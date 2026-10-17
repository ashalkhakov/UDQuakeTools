/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclCodec.h — what the decl entities' codecs share: their lexer, token and element helpers. Private to UDCore.
 */

#import "UDDeclElement.h"

@class idLexer, UDDeclIncrementalStore;
#import "idToken.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclBase (UDStore)
- (nullable UDDeclIncrementalStore *)ud_store;
@end

@interface UDDeclElement (UDOwner)
/// Its decl puts @a edited in this element's place, in a new array; NO when
/// it is in none.
- (BOOL)ud_replaceInOwnerWith:(UDDeclElement *)edited;
@end

/// While a parse is tested, the diagnostics its lexers collect into.
extern NSString *const UDDeclCodecDiagnosticsKey;

/// A lexer over a decl's text (with or without its "type name" header),
/// just past its opening brace; nil, and an error, when there is none.
idLexer * _Nullable UDDeclCodecLexerWithFlags(NSData * _Nullable text, NSString * _Nullable name, NSString * _Nullable fileName,
                                             int lineNum, int flags, idFileSystem * _Nullable fileSystem,
                                             NSError * _Nullable * _Nullable error);
idLexer * _Nullable UDDeclCodecLexer(NSData * _Nullable text, NSString * _Nullable name, NSString * _Nullable fileName,
                                    int lineNum, idFileSystem * _Nullable fileSystem, NSError * _Nullable * _Nullable error);

NSString *UDTokenString(const idToken *token);
/// The token's bytes as the engine's Latin-1 text (a GUI's strings).
NSString *UDTokenLatin1String(const idToken *token);
/// token == text, token.Icmp( text ) == 0
BOOL UDTokenIs(const idToken *token, const char *text);
BOOL UDTokenIcmp(const idToken *token, const char *text);
void UDAppendQuoted(NSMutableString *out, NSString *key, NSString * _Nullable value);
void UDAppendQuotedEscaped(NSMutableString *out, NSString *key, NSString * _Nullable value);
NSString * _Nullable UDStringValue(id _Nullable values, NSString *key);
float UDFloatValue(id _Nullable values, NSString *key);
int UDIntValue(id _Nullable values, NSString *key);
BOOL UDBoolValue(id _Nullable values, NSString *key);
NSString *UDFloatsToString(const float *v, int count);
void UDStringToFloats(NSString * _Nullable string, float *v, int count);

/// Each element of @a elements is @a owner's, under @a key.
void UDAdoptElements(NSArray * _Nullable elements, UDDeclBase *owner, NSString *key);
BOOL UDValidateName(id _Nullable * _Nonnull ioValue, NSString *what, NSError * _Nullable * _Nullable error);
/// The values @a object's codec reads from its text, for -awakeFromFetch.
NSDictionary * _Nullable UDParsedSourceText(UDDeclBase *object);

NS_ASSUME_NONNULL_END

/// A transient element array's setter, after the particle stages': it marks
/// the decl updated (and registers with undo) and adopts the elements.
#define UD_ELEMENT_ARRAY_SETTER(Setter, key) \
- (void)Setter:(NSArray *)elements { \
    [self willChangeValueForKey:key]; \
    [self setPrimitiveValue:[elements copy] forKey:key]; \
    [self didChangeValueForKey:key]; \
    UDAdoptElements(elements, self, key); \
}
