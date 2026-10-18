//
//  UDScriptExpression.h
//  udscript-dap
//
//  A breakpoint's condition, or an expression in a logpoint's message, as
//  the adapter evaluates it: the game reads a variable by name and nothing
//  more, so the variables an expression names are read, and the expression
//  is evaluated here. idScript's operators (|| && ! == != < <= > >= + - * /
//  % and parentheses) over numbers, strings ("text"), entities ($name) and
//  variables, whose values are as the game formats them: a float "%g", a
//  vector "x,y,z", a boolean 1 or 0, a string quoted, an entity "$name".
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDScriptExpression : NSObject

/// The expression @a text is; nil, with @a error saying why, for what does
/// not read as one.
+ (nullable instancetype)expressionWithText:(NSString *)text error:(NSString * _Nullable * _Nullable)error;

@property (nonatomic, copy, readonly) NSString *text;
/// The variables it reads.
@property (nonatomic, copy, readonly) NSSet<NSString *> *names;

/// Its value (an NSNumber, or an NSString), the variables' as the game gave
/// them (a name missing: no such variable, an error).
- (nullable id)valueWithVariables:(NSDictionary<NSString *, NSString *> *)values error:(NSString * _Nullable * _Nullable)error;

/// A value as a condition takes it: a number not 0, a string not empty.
+ (BOOL)isTrue:(id)value;
/// A value as a logpoint prints it.
+ (NSString *)textOf:(id)value;

/// A logpoint's message in pieces: its text (NSString) and, for each
/// {expression} in it, the expression (UDScriptExpression); nil, with
/// @a error, where one does not read. "{{" and "}}" are braces.
+ (nullable NSArray *)partsOfMessage:(NSString *)message error:(NSString * _Nullable * _Nullable)error;

/// A hit count condition, as VS Code's: "5" or "== 5", ">= 5", "> 5", "< 5",
/// "<= 5", "% 5" (each fifth); whether @a hits passes it. NO, with @a error,
/// for what is none.
+ (BOOL)hitCount:(NSInteger)hits passes:(NSString *)condition error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
