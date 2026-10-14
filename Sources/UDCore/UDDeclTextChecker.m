#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idDeclManager.h"

@interface UDDeclTextProblem ()
- (instancetype)initWithLine:(NSInteger)line message:(NSString *)message isError:(BOOL)isError;
@end

@implementation UDDeclTextProblem
- (instancetype)initWithLine:(NSInteger)line message:(NSString *)message isError:(BOOL)isError {
    self = [super init];
    if (self) {
        _line = line;
        _message = [message copy];
        _isError = isError;
    }
    return self;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"%@ line %ld: %@", self.isError ? @"error" : @"warning", (long)self.line, self.message];
}
@end

static BOOL UDTokenIs(const idToken *token, const char *text) {
    return token->type == TT_PUNCTUATION && strcmp(token->text, text) == 0;
}

@implementation UDDeclTextChecker

+ (NSArray<UDDeclTextProblem *> *)problemsInDeclText:(NSString *)text fileSystem:(idFileSystem *)fileSystem {
    NSMutableArray<UDDeclTextProblem *> *problems = [NSMutableArray array];
    // NUL-terminated, as idLexer expects (its whitespace and comment loops
    // stop at the '\0', as Doom 3's did), like the decl manager's buffers.
    NSMutableData *bytes = [[text dataUsingEncoding:NSUTF8StringEncoding] mutableCopy] ?: [NSMutableData data];
    NSUInteger length = bytes.length;
    [bytes appendBytes:"" length:1];

    // The decl manager's flags, kept quiet: what it would say is collected.
    idLexer *lexer = [[idLexer alloc] initWithFlags:DECL_LEXER_FLAGS | LEXFL_NOERRORS | LEXFL_NOWARNINGS
                                         fileSystem:fileSystem];
    lexer.diagnostics = [NSMutableArray array];
    if (![lexer loadMemory:bytes.bytes length:(int)length name:@"decl" startLine:1 error:NULL]) {
        return problems;
    }

    idToken token;
    idToken_Init(&token);

    // Header: "{" at once (a body), or one or two names ("[type] name") then "{".
    int headerTokens = 0;
    int lastLine = 1;
    BOOL opened = NO;
    while ([lexer readToken:&token error:NULL]) {
        lastLine = token.line;
        if (UDTokenIs(&token, "{")) {
            opened = YES;
            break;
        }
        headerTokens++;
        if (headerTokens > 2) {
            [problems addObject:[[UDDeclTextProblem alloc] initWithLine:token.line
                                                                message:[NSString stringWithFormat:@"expected '{' after the decl's name, found '%s'", token.text]
                                                                isError:YES]];
            break;
        }
    }
    if (!opened) {
        if (problems.count == 0) {
            [problems addObject:[[UDDeclTextProblem alloc] initWithLine:lastLine
                                                                message:@"missing '{': a decl is [type] name { … }"
                                                                isError:YES]];
        }
    } else {
        // Body: balance the braces, remembering where each open one was.
        NSMutableArray<NSNumber *> *openLines = [NSMutableArray arrayWithObject:@(token.line)];
        BOOL reportedTrailing = NO;
        while ([lexer readToken:&token error:NULL]) {
            if (openLines.count == 0) {
                if (!reportedTrailing) {
                    [problems addObject:[[UDDeclTextProblem alloc] initWithLine:token.line
                                                                        message:[NSString stringWithFormat:@"'%s' after the decl's closing brace", token.text]
                                                                        isError:YES]];
                    reportedTrailing = YES;
                }
                continue;
            }
            if (UDTokenIs(&token, "{")) {
                [openLines addObject:@(token.line)];
            } else if (UDTokenIs(&token, "}")) {
                [openLines removeLastObject];
            }
        }
        for (NSNumber *line in openLines) {
            [problems addObject:[[UDDeclTextProblem alloc] initWithLine:line.integerValue
                                                                message:@"this '{' is never closed"
                                                                isError:YES]];
        }
    }

    for (NSDictionary *diagnostic in lexer.diagnostics) {
        [problems addObject:[[UDDeclTextProblem alloc] initWithLine:[diagnostic[@"line"] integerValue]
                                                            message:diagnostic[@"message"]
                                                            isError:[diagnostic[@"error"] boolValue]]];
    }

    [problems sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(UDDeclTextProblem *a, UDDeclTextProblem *b) {
        return a.line < b.line ? NSOrderedAscending : a.line > b.line ? NSOrderedDescending : NSOrderedSame;
    }];
    return problems;
}

@end
