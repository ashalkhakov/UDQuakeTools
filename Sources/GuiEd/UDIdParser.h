//
//  UDIdParser.h
//  PakManager
//
//  Created by artyom on 8/20/26.
//

#import "UDToken.h"
#import "UDidLexer.h"

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
