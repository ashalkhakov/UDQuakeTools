/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * id-style parser implementation helpers.
 */

#import "UDDeclParser.h"

#import "UDDeclType.h"

static NSString *UDDefaultDeclTypeForSourceVirtualPath(NSString *sourceVirtualPath) {
    NSString *extension = sourceVirtualPath.pathExtension.lowercaseString;
    NSString *identifier = [UDDeclTypeRegistry defaultDeclIdentifierForFileExtension:extension];
    return identifier ?: @"decl";
}

static NSString *UDCanonicalDeclType(NSString *declType) {
    return [UDDeclTypeRegistry canonicalIdentifierForIdentifier:declType];
}

@interface UDIdParser ()
@property (nonatomic, strong) UDIdLexer *lexer;
@property (nullable, nonatomic, strong) UDIdToken *lookahead;
@property (nonatomic, copy) NSString *sourceText;
@property (nonatomic, assign) NSUInteger markerIndex;
@end

@implementation UDIdParser

- (instancetype)init {
    self = [self initWithText:@""];
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

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

@implementation UDDeclParser

- (NSArray<UDDeclDefinition *> *)parseDefinitionsFromText:(NSString *)text
                                         sourceVirtualPath:(NSString *)sourceVirtualPath
                                                     error:(NSError **)error {
    NSParameterAssert(text != nil);
    NSParameterAssert(sourceVirtualPath.length > 0);

    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray array];
    UDIdParser *parser = [[UDIdParser alloc] initWithText:text];

    while (YES) {
        UDIdToken *first = [parser readToken];
        if (first.kind == UDIdTokenKindEOF) {
            break;
        }

        if (first.kind != UDIdTokenKindIdentifier && first.kind != UDIdTokenKindString) {
            continue;
        }

        NSString *declType = first.text;
        NSString *declName = nil;

        UDIdToken *second = [parser readToken];
        if (second.kind == UDIdTokenKindPunctuation && [second.text isEqualToString:@"{"]) {
            // Single-token headers (e.g., many .mtr entries): token is the name.
            declName = declType;
            declType = UDDefaultDeclTypeForSourceVirtualPath(sourceVirtualPath);
        } else if (second.kind == UDIdTokenKindIdentifier || second.kind == UDIdTokenKindString) {
            declName = second.text;
            UDIdToken *third = [parser peekToken];
            if (third.kind == UDIdTokenKindPunctuation && [third.text isEqualToString:@"{"]) {
                [parser expectPunctuation:@"{"];
            } else {
                [parser skipUntilPunctuation:@"}"];
                continue;
            }
        } else {
            [parser skipUntilPunctuation:@"}"];
            continue;
        }

        NSInteger braceDepth = 1;
        UDIdToken *closingBrace = nil;
        while (braceDepth > 0) {
            UDIdToken *token = [parser readToken];
            if (token.kind == UDIdTokenKindEOF) {
                break;
            }

            if (token.kind == UDIdTokenKindPunctuation) {
                if ([token.text isEqualToString:@"{"]) {
                    braceDepth++;
                } else if ([token.text isEqualToString:@"}"]) {
                    braceDepth--;
                    if (braceDepth == 0) {
                        closingBrace = token;
                    }
                }
            }
        }

        if (!closingBrace) {
            // Preserve parser resilience: skip malformed trailing decl and keep already parsed entries.
            break;
        }

        NSUInteger sourceStart = first.start;
        NSUInteger sourceEnd = closingBrace.end;
        if (sourceEnd < sourceStart || sourceStart > text.length || sourceEnd > text.length) {
            continue;
        }

        NSString *body = [text substringWithRange:NSMakeRange(sourceStart, sourceEnd - sourceStart)];
        if (declType.length == 0 || declName.length == 0) {
            continue;
        }

        NSString *canonicalType = UDCanonicalDeclType(declType);
        UDDeclDefinition *definition = [[UDDeclDefinition alloc] initWithDeclType:canonicalType
                                                                          declName:declName
                                                                              body:body
                                                                 sourceVirtualPath:sourceVirtualPath];
        [definitions addObject:definition];
    }

    if (error) {
        *error = nil;
    }

    if (definitions.count == 0) {
        NSString *extension = sourceVirtualPath.pathExtension.lowercaseString;
        NSString *defaultDeclType = [UDDeclTypeRegistry defaultDeclIdentifierForFileExtension:extension];
        if (defaultDeclType.length > 0) {
            NSString *declName = sourceVirtualPath.lastPathComponent.stringByDeletingPathExtension;
            if (declName.length == 0) {
                declName = sourceVirtualPath;
            }

            UDDeclDefinition *definition = [[UDDeclDefinition alloc] initWithDeclType:UDCanonicalDeclType(defaultDeclType)
                                                                              declName:declName
                                                                                  body:text
                                                                     sourceVirtualPath:sourceVirtualPath];
            [definitions addObject:definition];
        }
    }

    return definitions;
}

- (NSString *)serializeDefinitions:(NSArray<UDDeclDefinition *> *)definitions {
    NSMutableString *text = [NSMutableString string];
    NSUInteger count = definitions.count;
    for (NSUInteger i = 0; i < count; i++) {
        UDDeclDefinition *definition = [definitions objectAtIndex:i];
        [text appendString:definition.body ?: @""];
        if (i + 1 < count) {
            [text appendString:@"\n\n"];
        }
    }
    return text;
}

@end
