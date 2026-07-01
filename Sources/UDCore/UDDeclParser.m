/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * id-style parser implementation helpers.
 */

#import "UDAssetIndex.h"

@interface UDIdParser ()
@property (nonatomic, strong) UDIdLexer *lexer;
@property (nullable, nonatomic, strong) UDIdToken *lookahead;
@end

@implementation UDIdParser

- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) {
        _lexer = [[UDIdLexer alloc] initWithText:text];
    }
    return self;
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

@end
