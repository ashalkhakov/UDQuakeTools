/**
 * idScript, Doom 3's script language, as idCompiler parses it
 * (neo/game/script/Script_Compiler.cpp): each rule names the function it
 * follows. The preprocessor (#include, #define, ...) runs before the
 * compiler, in idParser, so its lines are extras here, like comments.
 */

// GetExpression's priorities, lowest binding first: && and || (7), then
// assignments (6, right associative), comparisons (5), + and - (4), then
// *, /, %, & and | together (3).
const PREC = {
  logical: 1,
  assign: 2,
  compare: 3,
  add: 4,
  multiply: 5,
  call: 6,     // FUNCTION_PRIORITY
  postfix: 7,  // ++, --, and . (priority 1)
};

const commaSep1 = (rule) => seq(rule, repeat(seq(',', rule)));
const commaSep = (rule) => optional(commaSep1(rule));

module.exports = grammar({
  name: 'idscript',

  extras: $ => [/\s/, $.comment, $.preproc],

  word: $ => $.identifier,

  rules: {
    // CompileFile -> ParseNamespace(def_namespace)
    source_file: $ => repeat($._definition),

    // ParseDefs
    _definition: $ => choice(
      ';',
      $.event_declaration,
      $.namespace_definition,
      $.object_definition,
      $.method_definition,
      $.function_definition,
      $.variable_declaration,
    ),

    // ParseEventDef: scriptEvent <type> <name>( <type> <name>, ... );
    event_declaration: $ => seq(
      'scriptEvent', field('type', $._type), field('name', $.identifier),
      field('parameters', $.parameter_list), ';',
    ),

    // ParseNamespace
    namespace_definition: $ => seq(
      'namespace', field('name', $.identifier),
      '{', repeat($._definition), '}',
    ),

    // ParseObjectDef: object <name> [: <parent>] { <fields> };
    // In ParseDefs the type object and a name always begin one.
    object_definition: $ => prec(1, seq(
      'object', field('name', $.identifier),
      optional(seq(':', field('parent', $._type))),
      '{', repeat(choice(';', $.field_declaration, $.method_declaration)), '}', ';',
    )),

    field_declaration: $ => seq(field('type', $._type), field('name', $.identifier), ';'),

    // A field with parameters goes to ParseFunctionDef: a prototype, or the
    // method's definition with its body
    method_declaration: $ => seq(
      field('type', $._type), field('name', $.identifier),
      field('parameters', $.parameter_list), choice(field('body', $.block), ';'),
    ),

    // ParseDefs, <type> <object>::<name>( ... ) -> ParseFunctionDef
    method_definition: $ => seq(
      field('type', $._type), field('object', $.identifier), '::', field('name', $.identifier),
      field('parameters', $.parameter_list), choice(field('body', $.block), ';'),
    ),

    // ParseFunctionDef: a prototype, or a definition with its body
    function_definition: $ => seq(
      field('type', $._type), field('name', $.identifier),
      field('parameters', $.parameter_list), choice(field('body', $.block), ';'),
    ),

    // ParseFunction
    parameter_list: $ => seq('(', commaSep($.parameter), ')'),

    parameter: $ => seq(field('type', $._type), field('name', $.identifier)),

    // ParseDefs -> ParseVariableDef, then more names after commas
    variable_declaration: $ => seq(
      field('type', $._type), commaSep1($.variable_declarator), ';',
    ),

    variable_declarator: $ => seq(
      field('name', $.identifier), optional(seq('=', field('value', $._expression))),
    ),

    // CheckType: the built-in types, or the name of an object type
    _type: $ => choice($.primitive_type, alias($.identifier, $.type_identifier)),

    primitive_type: _ => choice(
      'float', 'vector', 'entity', 'string', 'void', 'object', 'boolean',
    ),

    // ParseStatement
    _statement: $ => choice(
      ';',
      $.block,
      $.return_statement,
      $.while_statement,
      $.for_statement,
      $.do_statement,
      $.break_statement,
      $.continue_statement,
      $.variable_declaration,
      $.function_definition,
      $.if_statement,
      $.macro_statement,
      $.expression_statement,
    ),

    block: $ => seq('{', repeat($._statement), '}'),

    // ParseReturnStatement
    return_statement: $ => seq('return', optional($._expression), ';'),

    // ParseWhileStatement
    while_statement: $ => seq(
      'while', '(', field('condition', $._expression), ')', field('body', $._statement),
    ),

    // ParseForStatement: initialisers and increments are lists; the condition is not
    for_statement: $ => seq(
      'for', '(',
      field('initializer', commaSep($._expression)), ';',
      field('condition', $._expression), ';',
      field('update', commaSep($._expression)), ')',
      field('body', $._statement),
    ),

    // ParseDoWhileStatement
    do_statement: $ => seq(
      'do', field('body', $._statement),
      'while', '(', field('condition', $._expression), ')', ';',
    ),

    break_statement: _ => seq('break', ';'),

    continue_statement: _ => seq('continue', ';'),

    // ParseIfStatement
    if_statement: $ => prec.right(seq(
      'if', '(', field('condition', $._expression), ')',
      field('consequence', $._statement),
      optional(seq('else', field('alternative', $._statement))),
    )),

    expression_statement: $ => seq($._expression, ';'),

    // Not the compiler's, which sees macros expanded: a macro that stands
    // for a loop's head, as the scripts' eachFrame does
    // (#define eachFrame for( 0; 1; waitFrame() )), followed by its body.
    macro_statement: $ => seq(field('macro', $.identifier), field('body', $.block)),

    // GetExpression
    _expression: $ => choice(
      $.binary_expression,
      $.assignment_expression,
      $.unary_expression,
      $.update_expression,
      $.call_expression,
      $.field_expression,
      $.thread_expression,
      $.int_expression,
      $._primary,
    ),

    binary_expression: $ => {
      const table = [
        [PREC.logical, choice('&&', '||')],
        [PREC.compare, choice('==', '!=', '<', '>', '<=', '>=')],
        [PREC.add, choice('+', '-')],
        [PREC.multiply, choice('*', '/', '%', '&', '|')],
      ];
      return choice(...table.map(([p, op]) => prec.left(p, seq(
        field('left', $._expression), field('operator', op), field('right', $._expression),
      ))));
    },

    assignment_expression: $ => prec.right(PREC.assign, seq(
      field('left', $._expression),
      field('operator', choice('=', '+=', '-=', '*=', '/=', '%=', '&=', '|=')),
      field('right', $._expression),
    )),

    // GetTerm: ~, ! and - take what GetExpression(NOT_PRIORITY) parses,
    // which is a comparison: !a == b is !(a == b)
    unary_expression: $ => prec.right(PREC.compare, seq(
      field('operator', choice('!', '~', '-')), field('argument', $._expression),
    )),

    // ++ and -- act on the operand to their left
    update_expression: $ => prec.left(PREC.postfix, seq(
      field('argument', $._expression), field('operator', choice('++', '--')),
    )),

    // ParseFunctionCall, ParseObjectCall, ParseEventCall, ParseSysObjectCall
    call_expression: $ => prec.left(PREC.call, seq(
      field('function', $._expression), field('arguments', $.argument_list),
    )),

    argument_list: $ => seq('(', commaSep($._expression), ')'),

    field_expression: $ => prec.left(PREC.postfix, seq(
      field('object', $._expression), '.', field('field', $.identifier),
    )),

    // GetTerm: thread <call>
    thread_expression: $ => prec.right(PREC.call, seq('thread', $._expression)),

    // GetTerm: int( <expression> )
    int_expression: $ => seq('int', '(', $._expression, ')'),

    _primary: $ => choice(
      $.identifier,
      $.scoped_identifier,
      $.entity,
      $.number,
      $.string,
      $.vector,
      $.parenthesized_expression,
    ),

    parenthesized_expression: $ => seq('(', $._expression, ')'),

    // ParseValue: a namespace's member, namespace::name
    scoped_identifier: $ => seq(
      field('namespace', $.identifier), '::',
      field('name', choice($.identifier, $.scoped_identifier)),
    ),

    // NextToken: $ and the token after it name an entity
    entity: $ => seq('$', field('name', $.identifier)),

    identifier: _ => /[A-Za-z_][A-Za-z0-9_]*/,

    // idLexer's numbers: decimal, with a fraction or exponent and a float
    // suffix, or hexadecimal
    number: _ => token(choice(
      /0[xX][0-9a-fA-F]+/,
      /\d+\.\d*([eE][+-]?\d+)?[fF]?/,
      /\.\d+([eE][+-]?\d+)?[fF]?/,
      /\d+([eE][+-]?\d+)?[fF]?/,
    )),

    string: _ => token(seq('"', repeat(choice(/[^"\\\n]+/, /\\./)), '"')),

    // NextToken: a quoted literal is a vector, 'x y z'
    vector: _ => token(seq("'", /[^'\n]*/, "'")),

    comment: _ => token(choice(
      seq('//', /[^\n]*/),
      seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/'),
    )),

    // idParser's directives, to the end of the line, continued with a backslash
    preproc: _ => token(seq('#', /([^\\\n]|\\\r?\n|\\.)*/)),
  },
});
