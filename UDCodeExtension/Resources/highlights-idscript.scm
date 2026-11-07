; idScript highlights, in the capture names TreeSitterTheme styles.

(comment) @comment
(preproc) @keyword
(string) @string
(vector) @constant
(number) @number

(primitive_type) @type.builtin
(type_identifier) @type

[
  "scriptEvent" "namespace" "object" "int" "thread"
] @keyword

[
  "if" "else" "while" "for" "do" "return" "break" "continue"
] @keyword.control

(macro_statement macro: (identifier) @keyword.control)

(entity) @variable.builtin
(entity name: (identifier) @variable.builtin)

(object_definition name: (identifier) @type)
(method_definition object: (identifier) @type)
(scoped_identifier namespace: (identifier) @namespace)
(namespace_definition name: (identifier) @namespace)

(function_definition name: (identifier) @function)
(method_definition name: (identifier) @function)
(method_declaration name: (identifier) @function.method)
(event_declaration name: (identifier) @function)
(call_expression function: (identifier) @function.call)
(call_expression function: (scoped_identifier name: (identifier) @function.call))
(call_expression function: (field_expression field: (identifier) @function.method))

(parameter name: (identifier) @variable.parameter)
(field_declaration name: (identifier) @property)

[
  "=" "+=" "-=" "*=" "/=" "%=" "&=" "|="
  "==" "!=" "<" ">" "<=" ">=" "&&" "||"
  "+" "-" "*" "/" "%" "&" "|" "!" "~" "++" "--" "::" "$"
] @operator

["(" ")" "{" "}"] @punctuation.bracket
[";" "," "." ":"] @punctuation
