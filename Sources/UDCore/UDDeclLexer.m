/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * id-style lexer/parser primitives for decl parsing.
 */

#import "UDDeclParser.h"

static BOOL UDDeclLexerIsTokenCharacter(unichar character) {
    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:character]) {
        return YES;
    }

    switch (character) {
        case '_':
        case '/':
        case '.':
        case ':':
        case '-':
        case '*':
        case '$':
        case '@':
            return YES;
        default:
            return NO;
    }
}

@implementation UDIdToken
@end

@interface UDIdLexer ()
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) NSUInteger index;
@end

@implementation UDIdLexer

- (instancetype)init {
    self = [self initWithText:@""];
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) {
        _text = [text copy];
        _index = 0;
    }
    return self;
}

- (void)_skipWhitespaceAndComments {
    NSUInteger length = self.text.length;
    while (self.index < length) {
        unichar ch = [self.text characterAtIndex:self.index];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:ch]) {
            self.index++;
            continue;
        }

        if (ch == '/' && (self.index + 1) < length) {
            unichar next = [self.text characterAtIndex:(self.index + 1)];
            if (next == '/') {
                self.index += 2;
                while (self.index < length && [self.text characterAtIndex:self.index] != '\n') {
                    self.index++;
                }
                continue;
            }
            if (next == '*') {
                self.index += 2;
                while ((self.index + 1) < length) {
                    if ([self.text characterAtIndex:self.index] == '*' && [self.text characterAtIndex:(self.index + 1)] == '/') {
                        self.index += 2;
                        break;
                    }
                    self.index++;
                }
                continue;
            }
        }

        break;
    }
}

- (UDIdToken *)_makeTokenWithKind:(UDIdTokenKind)kind text:(NSString *)text start:(NSUInteger)start end:(NSUInteger)end {
    UDIdToken *token = [[UDIdToken alloc] init];
    token.kind = kind;
    token.text = text ?: @"";
    token.start = start;
    token.end = end;
    return token;
}

- (UDIdToken *)nextToken {
    [self _skipWhitespaceAndComments];

    NSUInteger length = self.text.length;
    if (self.index >= length) {
        return [self _makeTokenWithKind:UDIdTokenKindEOF text:@"" start:length end:length];
    }

    NSUInteger start = self.index;
    unichar ch = [self.text characterAtIndex:self.index];

    if (ch == '"') {
        self.index++;
        NSMutableString *value = [NSMutableString string];
        while (self.index < length) {
            unichar c = [self.text characterAtIndex:self.index];
            if (c == '\\' && (self.index + 1) < length) {
                unichar escaped = [self.text characterAtIndex:(self.index + 1)];
                [value appendFormat:@"%C", escaped];
                self.index += 2;
                continue;
            }
            if (c == '"') {
                self.index++;
                break;
            }
            [value appendFormat:@"%C", c];
            self.index++;
        }
        return [self _makeTokenWithKind:UDIdTokenKindString text:[value copy] start:start end:self.index];
    }

    if (UDDeclLexerIsTokenCharacter(ch)) {
        self.index++;
        while (self.index < length && UDDeclLexerIsTokenCharacter([self.text characterAtIndex:self.index])) {
            self.index++;
        }
        NSString *tokenText = [self.text substringWithRange:NSMakeRange(start, self.index - start)];
        return [self _makeTokenWithKind:UDIdTokenKindIdentifier text:tokenText start:start end:self.index];
    }

    self.index++;
    NSString *punctuation = [NSString stringWithCharacters:&ch length:1];
    return [self _makeTokenWithKind:UDIdTokenKindPunctuation text:punctuation start:start end:self.index];
}

@end

