#import "UDToken.h"
#import "UDIdParser.h"

@interface UDIdParser ()
@property (nonatomic, strong) UDIdLexer *lexer;
@property (nullable, nonatomic, strong) UDIdToken *lookahead;
@property (nonatomic, copy) NSString *sourceText;
@property (nonatomic, assign) NSUInteger markerIndex;
@end

@implementation UDIdParser

- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) {
        _sourceText = [text copy] ?: @"";
        _lexer = [[UDIdLexer alloc] initWithText:text];
        _markerIndex = 0;
    }
    return self;
}

- (BOOL)readToken:(UDIdToken * _Nullable * _Nonnull)outToken {
    UDIdToken *token = [self readToken];
    if (outToken) {
        *outToken = token;
    }
    return token.kind != UDIdTokenKindEOF;
}

- (BOOL)expectTokenType:(UDIdTokenKind)kind token:(UDIdToken * _Nullable * _Nonnull)outToken {
    UDIdToken *token = [self readToken];
    if (outToken) {
        *outToken = token;
    }
    if (token.kind == kind) {
        return YES;
    }

    [self unreadToken:token];
    return NO;
}

- (BOOL)expectTokenString:(NSString *)tokenString token:(UDIdToken * _Nullable * _Nonnull)outToken {
    UDIdToken *token = [self readToken];
    if (outToken) {
        *outToken = token;
    }
    if (token.text && [token.text isEqualToString:tokenString]) {
        return YES;
    }

    [self unreadToken:token];
    return NO;
}

- (UDIdToken *)readToken {
    if (self.lookahead) {
        UDIdToken *token = self.lookahead;
        self.lookahead = nil;
        return token;
    }
    return [self.lexer nextToken];
}

- (UDIdToken *)peekToken {
    if (!self.lookahead) {
        self.lookahead = [self.lexer nextToken];
    }
    return self.lookahead;
}

- (void)unreadToken:(UDIdToken *)token {
    self.lookahead = token;
}

- (BOOL)expectPunctuation:(NSString *)punctuation {
    UDIdToken *token = [self readToken];
    if (token.kind == UDIdTokenKindPunctuation && [token.text isEqualToString:punctuation]) {
        return YES;
    }
    [self unreadToken:token];
    return NO;
}

- (void)skipUntilPunctuation:(NSString *)punctuation {
    while (YES) {
        UDIdToken *token = [self readToken];
        if (token.kind == UDIdTokenKindEOF) {
            return;
        }
        if (token.kind == UDIdTokenKindPunctuation && [token.text isEqualToString:punctuation]) {
            return;
        }
    }
}

- (void)setMarker {
    UDIdToken *next = [self peekToken];
    self.markerIndex = MIN(next.start, self.sourceText.length);
}

- (NSString *)getStringFromMarkerTrimLeadingWhitespace:(BOOL)trimLeadingWhitespace {
    UDIdToken *next = [self peekToken];
    NSUInteger end = MIN(next.start, self.sourceText.length);
    NSUInteger start = MIN(self.markerIndex, end);
    NSString *slice = [self.sourceText substringWithRange:NSMakeRange(start, end - start)];
    if (!trimLeadingWhitespace) {
        return slice;
    }
    return [slice stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (BOOL)parseBracedSectionExact:(NSString * _Nonnull * _Nonnull)outSection startingWithOpenBraceToken:(nullable UDIdToken *)openBraceToken {
    UDIdToken *openToken = openBraceToken;
    if (!openToken) {
        openToken = [self readToken];
    }

    if (openToken.kind != UDIdTokenKindPunctuation || ![openToken.text isEqualToString:@"{"]) {
        [self unreadToken:openToken];
        return NO;
    }

    NSInteger depth = 1;
    UDIdToken *endToken = openToken;
    while (depth > 0) {
        UDIdToken *token = [self readToken];
        if (token.kind == UDIdTokenKindEOF) {
            return NO;
        }
        endToken = token;

        if (token.kind == UDIdTokenKindPunctuation) {
            if ([token.text isEqualToString:@"{"]) {
                depth++;
            } else if ([token.text isEqualToString:@"}"]) {
                depth--;
            }
        }
    }

    if (outSection) {
        NSUInteger start = MIN(openToken.start, self.sourceText.length);
        NSUInteger end = MIN(endToken.end, self.sourceText.length);
        *outSection = [self.sourceText substringWithRange:NSMakeRange(start, end - start)];
    }
    return YES;
}

@end
