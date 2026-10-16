; Decl highlights, in the capture names TreeSitterTheme styles: the decl's
; type and name, and the lexer's tokens. What a type's parser makes of the
; names inside the braces is its own.

(comment) @comment
(string) @string
(number) @number

(decl type: (name) @keyword)
(decl name: (_) @type)

["{" "}"] @punctuation.bracket
(punctuation) @punctuation
