//
//  UDScriptExpression.m
//  udscript-dap
//

#import "UDScriptExpression.h"

// A parsed expression: a tree of nodes, each an array whose first element
// says what it is: @[@"n", number], @[@"s", string], @[@"v", name],
// @[@"!", operand], @[@"-", operand] (negation), @[@".", operand, member]
// (a vector's x, y or z), @[op, left, right].

@interface UDScriptExpression ()
@property (nonatomic, copy, readwrite) NSString *text;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *names;
@property (nonatomic, strong) NSArray *tree;
@end

@interface UDScriptExpressionParser : NSObject {
@public
    NSArray<NSString *> *tokens;
    NSUInteger at;
    NSString *error;
    NSMutableSet<NSString *> *names;
}
@end

@implementation UDScriptExpressionParser

static BOOL UDIsNameStart(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static BOOL UDIsNameCharacter(unichar c) {
    return UDIsNameStart(c) || (c >= '0' && c <= '9');
}

/// The tokens of @a text: names (a "$" one an entity), numbers, strings
/// (with their quotes), operators ("." a member's).
static NSArray<NSString *> *UDTokens(NSString *text, NSString **error) {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSUInteger length = text.length, i = 0;
    NSArray<NSString *> *operators = @[@"||", @"&&", @"==", @"!=", @"<=", @">=", @"<", @">", @"!", @"+", @"-", @"*", @"/",
                                       @"%", @"(", @")", @"."];
    while (i < length) {
        unichar c = [text characterAtIndex:i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { i++; continue; }
        NSUInteger start = i;
        if (UDIsNameStart(c) || (c == '$' && i + 1 < length)) {
            i++;
            while (i < length && UDIsNameCharacter([text characterAtIndex:i])) i++;
        } else if ((c >= '0' && c <= '9') || (c == '.' && i + 1 < length && [text characterAtIndex:i + 1] >= '0' && [text characterAtIndex:i + 1] <= '9')) {
            while (i < length && (([text characterAtIndex:i] >= '0' && [text characterAtIndex:i] <= '9') || [text characterAtIndex:i] == '.')) i++;
        } else if (c == '"') {
            i++;
            while (i < length && [text characterAtIndex:i] != '"') i++;
            if (i >= length) {
                if (error) *error = @"A string is not closed";
                return nil;
            }
            i++;
        } else {
            NSString *found = nil;
            for (NSString *op in operators) {
                if ([text compare:op options:0 range:NSMakeRange(i, MIN(op.length, length - i))] == NSOrderedSame) {
                    found = op;
                    break;
                }
            }
            if (found == nil) {
                if (error) *error = [NSString stringWithFormat:@"'%C' is no operator", c];
                return nil;
            }
            i += found.length;
        }
        [tokens addObject:[text substringWithRange:NSMakeRange(start, i - start)]];
    }
    return tokens;
}

- (NSString *)peek {
    return at < tokens.count ? tokens[at] : nil;
}

- (BOOL)take:(NSString *)token {
    if ([[self peek] isEqualToString:token]) {
        at++;
        return YES;
    }
    return NO;
}

/// Binary operators, the lowest precedence first (C's, as idScript's).
static NSArray<NSArray<NSString *> *> *UDLevels(void) {
    return @[@[@"||"], @[@"&&"], @[@"==", @"!="], @[@"<", @"<=", @">", @">="], @[@"+", @"-"], @[@"*", @"/", @"%"]];
}

- (NSArray *)level:(NSUInteger)level {
    if (level >= UDLevels().count) return [self unary];
    NSArray *left = [self level:level + 1];
    while (left != nil) {
        NSString *op = nil;
        for (NSString *candidate in UDLevels()[level]) {
            if ([self take:candidate]) { op = candidate; break; }
        }
        if (op == nil) break;
        NSArray *right = [self level:level + 1];
        if (right == nil) return nil;
        left = @[op, left, right];
    }
    return left;
}

- (NSArray *)unary {
    if ([self take:@"!"]) {
        NSArray *operand = [self unary];
        return operand ? @[@"!", operand] : nil;
    }
    if ([self take:@"-"]) {
        NSArray *operand = [self unary];
        return operand ? @[@"-", operand] : nil;
    }
    NSArray *operand = [self primary];
    // a member: a vector's component
    while (operand != nil && [self take:@"."]) {
        NSString *member = [self peek];
        if (![member isEqualToString:@"x"] && ![member isEqualToString:@"y"] && ![member isEqualToString:@"z"]) {
            error = member != nil ? [NSString stringWithFormat:@"'%@' is no vector's member (x, y, z)", member]
                                  : @"The expression ends too soon";
            return nil;
        }
        at++;
        operand = @[@".", operand, member];
    }
    return operand;
}

- (NSArray *)primary {
    NSString *token = [self peek];
    if (token == nil) {
        error = @"The expression ends too soon";
        return nil;
    }
    at++;
    if ([token isEqualToString:@"("]) {
        NSArray *inner = [self level:0];
        if (inner == nil) return nil;
        if (![self take:@")"]) {
            error = @"A '(' is not closed";
            return nil;
        }
        return inner;
    }
    unichar c = [token characterAtIndex:0];
    if (c == '"') return @[@"s", [token substringWithRange:NSMakeRange(1, token.length - 2)]];
    if (c == '$') return @[@"s", token];
    if ((c >= '0' && c <= '9') || c == '.') return @[@"n", @(token.doubleValue)];
    if (UDIsNameStart(c)) {
        // self.field: the field, which a method reads by its name
        if ([token isEqualToString:@"self"] && [[self peek] isEqualToString:@"."] && at + 1 < tokens.count
            && UDIsNameStart([tokens[at + 1] characterAtIndex:0])) {
            token = tokens[at + 1];
            at += 2;
        }
        [names addObject:token];
        return @[@"v", token];
    }
    error = [NSString stringWithFormat:@"'%@' is not expected here", token];
    return nil;
}

@end

@implementation UDScriptExpression

+ (instancetype)expressionWithText:(NSString *)text error:(NSString **)error {
    NSString *why = nil;
    NSArray<NSString *> *tokens = UDTokens(text, &why);
    UDScriptExpressionParser *parser = [[UDScriptExpressionParser alloc] init];
    parser->tokens = tokens ?: @[];
    parser->names = [NSMutableSet set];
    NSArray *tree = tokens.count > 0 ? [parser level:0] : nil;
    if (tree != nil && parser->at < tokens.count) {
        parser->error = [NSString stringWithFormat:@"'%@' is not expected here", tokens[parser->at]];
        tree = nil;
    }
    if (tree == nil) {
        if (error) *error = why ?: parser->error ?: @"The expression is empty";
        return nil;
    }
    UDScriptExpression *expression = [[UDScriptExpression alloc] init];
    expression.text = text;
    expression.names = parser->names;
    expression.tree = tree;
    return expression;
}

/// The game's text for a variable as a value: a number, else a string (its
/// quotes taken off).
static id UDValueOfVariable(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length >= 2 && [trimmed hasPrefix:@"\""] && [trimmed hasSuffix:@"\""]) {
        return [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
    }
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    double number = 0;
    if (trimmed.length > 0 && [scanner scanDouble:&number] && scanner.isAtEnd) return @(number);
    return trimmed;
}

static BOOL UDIsNumber(id value) {
    return [value isKindOfClass:[NSNumber class]];
}

- (id)_evaluate:(NSArray *)node variables:(NSDictionary<NSString *, NSString *> *)values error:(NSString **)error {
    NSString *kind = node[0];
    if ([kind isEqualToString:@"n"] || [kind isEqualToString:@"s"]) return node[1];
    if ([kind isEqualToString:@"v"]) {
        NSString *value = values[node[1]];
        if (value == nil || [value isEqualToString:@"???"]) {
            if (error) *error = [NSString stringWithFormat:@"%@ is not a variable here", node[1]];
            return nil;
        }
        return UDValueOfVariable(value);
    }
    if ([kind isEqualToString:@"."]) {
        id vector = [self _evaluate:node[1] variables:values error:error];
        if (vector == nil) return nil;
        NSArray<NSString *> *components = [UDIsNumber(vector) ? @"" : vector componentsSeparatedByString:@","];
        if (components.count != 3) {
            if (error) *error = [NSString stringWithFormat:@".%@ takes a vector", node[2]];
            return nil;
        }
        return @([components[[@[@"x", @"y", @"z"] indexOfObject:node[2]]] doubleValue]);
    }
    if (node.count == 2) {
        id operand = [self _evaluate:node[1] variables:values error:error];
        if (operand == nil) return nil;
        if ([kind isEqualToString:@"!"]) return @(![UDScriptExpression isTrue:operand]);
        if (!UDIsNumber(operand)) {
            if (error) *error = @"Only a number is negated";
            return nil;
        }
        return @(-[operand doubleValue]);
    }
    id left = [self _evaluate:node[1] variables:values error:error];
    if (left == nil) return nil;
    // && and || look at their right only as C does
    if ([kind isEqualToString:@"&&"] && ![UDScriptExpression isTrue:left]) return @NO;
    if ([kind isEqualToString:@"||"] && [UDScriptExpression isTrue:left]) return @YES;
    id right = [self _evaluate:node[2] variables:values error:error];
    if (right == nil) return nil;
    if ([kind isEqualToString:@"&&"] || [kind isEqualToString:@"||"]) return @([UDScriptExpression isTrue:right]);
    BOOL numbers = UDIsNumber(left) && UDIsNumber(right);
    if ([kind isEqualToString:@"=="] || [kind isEqualToString:@"!="]) {
        BOOL equal = numbers ? [left doubleValue] == [right doubleValue]
                             : [[UDScriptExpression textOf:left] isEqualToString:[UDScriptExpression textOf:right]];
        return @([kind isEqualToString:@"=="] ? equal : !equal);
    }
    if ([kind isEqualToString:@"+"] && !numbers) {
        return [[UDScriptExpression textOf:left] stringByAppendingString:[UDScriptExpression textOf:right]];
    }
    if (!numbers) {
        if (error) *error = [NSString stringWithFormat:@"%@ takes numbers", kind];
        return nil;
    }
    double a = [left doubleValue], b = [right doubleValue];
    if ([kind isEqualToString:@"<"]) return @(a < b);
    if ([kind isEqualToString:@"<="]) return @(a <= b);
    if ([kind isEqualToString:@">"]) return @(a > b);
    if ([kind isEqualToString:@">="]) return @(a >= b);
    if ([kind isEqualToString:@"+"]) return @(a + b);
    if ([kind isEqualToString:@"-"]) return @(a - b);
    if ([kind isEqualToString:@"*"]) return @(a * b);
    if ([kind isEqualToString:@"/"]) return b != 0 ? @(a / b) : @0;
    if ([kind isEqualToString:@"%"]) return (long long)b != 0 ? @((long long)a % (long long)b) : @0;
    if (error) *error = [NSString stringWithFormat:@"'%@' is no operator", kind];
    return nil;
}

- (id)valueWithVariables:(NSDictionary<NSString *, NSString *> *)values error:(NSString **)error {
    return [self _evaluate:self.tree variables:values error:error];
}

+ (BOOL)isTrue:(id)value {
    if (UDIsNumber(value)) return [value doubleValue] != 0;
    return [value length] > 0;
}

+ (NSString *)textOf:(id)value {
    if (UDIsNumber(value)) return [NSString stringWithFormat:@"%g", [value doubleValue]];
    return value;
}

+ (NSString *)displayOf:(id)value {
    if (UDIsNumber(value)) return [self textOf:value];
    NSString *text = value;
    // an entity, a vector: as the game writes them; a string quoted
    if ([text hasPrefix:@"$"] || [text componentsSeparatedByString:@","].count == 3) return text;
    return [NSString stringWithFormat:@"\"%@\"", text];
}

- (BOOL)isVariable {
    return [self.tree[0] isEqualToString:@"v"];
}

+ (NSArray *)partsOfMessage:(NSString *)message error:(NSString **)error {
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableString *literal = [NSMutableString string];
    NSUInteger i = 0, length = message.length;
    while (i < length) {
        unichar c = [message characterAtIndex:i];
        if ((c == '{' || c == '}') && i + 1 < length && [message characterAtIndex:i + 1] == c) {
            [literal appendFormat:@"%C", c];
            i += 2;
            continue;
        }
        if (c == '{') {
            NSRange close = [message rangeOfString:@"}" options:0 range:NSMakeRange(i + 1, length - i - 1)];
            if (close.location == NSNotFound) {
                if (error) *error = @"A '{' is not closed";
                return nil;
            }
            UDScriptExpression *expression = [self expressionWithText:[message substringWithRange:NSMakeRange(i + 1, close.location - i - 1)] error:error];
            if (expression == nil) return nil;
            if (literal.length > 0) [parts addObject:[literal copy]];
            [literal setString:@""];
            [parts addObject:expression];
            i = close.location + 1;
            continue;
        }
        [literal appendFormat:@"%C", c];
        i++;
    }
    if (literal.length > 0) [parts addObject:[literal copy]];
    return parts;
}

+ (BOOL)hitCount:(NSInteger)hits passes:(NSString *)condition error:(NSString **)error {
    NSString *text = [condition stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *op = @"==";
    for (NSString *candidate in @[@"==", @">=", @"<=", @">", @"<", @"%"]) {
        if ([text hasPrefix:candidate]) {
            op = candidate;
            text = [[text substringFromIndex:candidate.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            break;
        }
    }
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSInteger count = 0;
    if (text.length == 0 || ![scanner scanInteger:&count] || !scanner.isAtEnd) {
        if (error) *error = [NSString stringWithFormat:@"'%@' is no hit count (\"5\", \">= 5\", \"%% 5\")", condition];
        return NO;
    }
    if ([op isEqualToString:@"=="]) return hits == count;
    if ([op isEqualToString:@">="]) return hits >= count;
    if ([op isEqualToString:@"<="]) return hits <= count;
    if ([op isEqualToString:@">"]) return hits > count;
    if ([op isEqualToString:@"<"]) return hits < count;
    return count > 0 && hits % count == 0;
}

@end
