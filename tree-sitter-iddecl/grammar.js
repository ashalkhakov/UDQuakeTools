/**
 * Doom 3's decl files, as idDeclFile::LoadAndParse reads them
 * (neo/framework/DeclManager.cpp): a decl is an optional type name, the
 * decl's name, and a braced section the decl's own parser reads later. The
 * tokens are idLexer's with DECL_LEXER_FLAGS: names may be path names, '\'
 * does not escape inside strings. What is inside a decl's braces is left to
 * its type's parser; here it is only tokens and nested braces.
 */

module.exports = grammar({
  name: 'iddecl',

  // A file may end in a NUL, where the lexer stops (materials/patd.mtr).
  extras: $ => [/[\s\x00]/, $.comment],

  // Whether a name is a type or a stray takes the tokens after it to tell.
  conflicts: $ => [[$.decl, $._token]],

  rules: {
    source_file: $ => repeat(choice($.decl, $.block, $._token)),

    // "[type] <name> {": without a type, the name is the file's default
    // type's. A token left over (a stray, or a type with nothing after it)
    // is warned about and skipped, as LoadAndParse does.
    decl: $ => prec.dynamic(1, choice(
      seq(field('type', $.name), field('name', $._decl_name), field('body', $.block)),
      seq(field('name', $._decl_name), field('body', $.block)),
    )),

    _decl_name: $ => prec(2, choice($.name, $.string, $.number)),

    block: $ => seq('{', repeat(choice($.block, $._token)), '}'),

    _token: $ => choice($.name, $.string, $.number, $.punctuation),

    comment: $ => token(prec(1, choice(
      seq('//', /[^\n]*/),
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/'),
    ))),

    // ReadName: a letter or '_', or with LEXFL_ALLOWPATHNAMES '/', '\' or
    // '.'; then letters, digits, '_' and the path name characters.
    name: $ => /[A-Za-z_\/\\.][A-Za-z0-9_\/\\:.]*/,

    // ReadString: no escapes (LEXFL_NOSTRINGESCAPECHARS); a literal in
    // single quotes may be several characters (LEXFL_ALLOWMULTICHARLITERALS).
    string: $ => token(choice(/"[^"\n]*"/, /'[^'\n]*'/)),

    // ReadNumber: hexadecimal, binary, octal and decimal integers, and
    // floats, which may start with '.'; a sign is punctuation.
    number: $ => token(prec(1, choice(
      /0[xX][0-9a-fA-F]+/,
      /0[bB][01]+/,
      /[0-9]+(\.[0-9]*)?([eE][+-]?[0-9]+)?/,
      /\.[0-9]+([eE][+-]?[0-9]+)?/,
    ))),

    punctuation: $ => /[^\sA-Za-z0-9_\/\\."'{}]/,
  },
});
