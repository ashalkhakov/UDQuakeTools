/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDSourceTokens.h — a decl's text as idLexer reads it, kept whole: each
 * token as written, and the whitespace and comments before it.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A token as idLexer::ReadToken reads it: its text as written (its quotes,
/// if a string's), what the lexer makes of it, and what ReadWhiteSpace skipped
/// before it (whitespace and comments).
@interface UDSourceToken : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *leading;
@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, copy, readonly) NSString *value;
+ (instancetype)tokenWithLeading:(NSString *)leading text:(NSString *)text value:(NSString *)value;
@end

/// A text as tokens, and what follows the last (whitespace, comments, or
/// what the lexer could not read): put back together, the text as it was.
@interface UDSourceTokens : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSArray<UDSourceToken *> *tokens;
@property (nonatomic, copy, readonly) NSString *trailing;

/// @a text read by an idLexer with @a flags, to its end or to what it cannot
/// read.
+ (instancetype)tokensOfText:(NSString *)text flags:(int)flags;
+ (instancetype)tokensWithTokens:(NSArray<UDSourceToken *> *)tokens trailing:(NSString *)trailing;

/// The text: each token's leading and text, then the trailing.
- (NSString *)text;
/// Where each token's leading begins in -text's UTF-8 bytes, and (the last
/// number) where the trailing does.
- (NSArray<NSNumber *> *)byteOffsets;
@end

NS_ASSUME_NONNULL_END
