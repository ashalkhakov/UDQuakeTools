/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclParser.h — Decl parsing interfaces and id-style token helpers.
 */

#import <Foundation/Foundation.h>

#import "UDDeclModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclParser : NSObject

- (NSArray<UDDeclDefinition *> *)parseDefinitionsFromText:(NSString *)text
                                         sourceVirtualPath:(NSString *)sourceVirtualPath
                                                     error:(NSError **)error;

- (NSString *)serializeDefinitions:(NSArray<UDDeclDefinition *> *)definitions;

@end

typedef NS_ENUM(NSInteger, UDIdTokenKind) {
    UDIdTokenKindEOF = 0,
    UDIdTokenKindIdentifier,
    UDIdTokenKindString,
    UDIdTokenKindPunctuation,
};

@interface UDIdToken : NSObject

@property (nonatomic, assign) UDIdTokenKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) NSUInteger start;
@property (nonatomic, assign) NSUInteger end;

@end

@interface UDIdLexer : NSObject

- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (UDIdToken *)nextToken;

@end

@interface UDIdParser : NSObject

- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (UDIdToken *)peekToken;
- (UDIdToken *)readToken;
- (void)unreadToken:(UDIdToken *)token;
- (BOOL)readToken:(UDIdToken * _Nullable * _Nonnull)outToken;
- (BOOL)expectTokenType:(UDIdTokenKind)kind token:(UDIdToken * _Nullable * _Nonnull)outToken;
- (BOOL)expectTokenString:(NSString *)tokenString token:(UDIdToken * _Nullable * _Nonnull)outToken;
- (BOOL)expectPunctuation:(NSString *)punctuation;
- (void)skipUntilPunctuation:(NSString *)punctuation;
- (void)setMarker;
- (NSString *)getStringFromMarkerTrimLeadingWhitespace:(BOOL)trimLeadingWhitespace;
- (BOOL)parseBracedSectionExact:(NSString * _Nonnull * _Nonnull)outSection startingWithOpenBraceToken:(nullable UDIdToken *)openBraceToken;

@end

NS_ASSUME_NONNULL_END
