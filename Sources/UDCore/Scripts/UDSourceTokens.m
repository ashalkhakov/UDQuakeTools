/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDSourceTokens.m — a decl's text as idLexer reads it, kept whole.
 */

#import "UDSourceTokens.h"
#import "UDDeclCodec.h"
#import "idLexer.h"
#import "idToken.h"
#import <objc/runtime.h>

@implementation UDSourceToken

+ (instancetype)tokenWithLeading:(NSString *)leading text:(NSString *)text value:(NSString *)value {
    UDSourceToken *token = [[self alloc] init];
    token->_leading = [leading copy];
    token->_text = [text copy];
    token->_value = [value copy];
    return token;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[UDSourceToken class]]) return NO;
    UDSourceToken *other = object;
    return [other.leading isEqualToString:self.leading] && [other.text isEqualToString:self.text];
}

- (NSUInteger)hash {
    return self.text.hash;
}

- (NSString *)description {
    return [self.leading stringByAppendingString:self.text];
}

@end

@implementation UDSourceTokens

+ (instancetype)tokensWithTokens:(NSArray<UDSourceToken *> *)tokens trailing:(NSString *)trailing {
    UDSourceTokens *result = [[self alloc] init];
    result->_tokens = [tokens copy];
    result->_trailing = [trailing copy];
    return result;
}

static NSString *UDBytesString(const char *start, const char *end) {
    if (start == NULL || end == NULL || end < start) return @"";
    return [[NSString alloc] initWithBytes:start length:(NSUInteger)(end - start) encoding:NSUTF8StringEncoding] ?:
           [[NSString alloc] initWithBytes:start length:(NSUInteger)(end - start) encoding:NSISOLatin1StringEncoding] ?: @"";
}

+ (instancetype)tokensOfText:(NSString *)text flags:(int)flags {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSMutableData *buffer = [data mutableCopy];
    [buffer appendBytes:"" length:1];
    idLexer *src = [[idLexer alloc] initWithFileSystem:nil];
    NSMutableArray<UDSourceToken *> *tokens = [NSMutableArray array];
    if (![src loadMemory:buffer.bytes length:(int)data.length name:@"" startLine:1 error:NULL]) {
        return [self tokensWithTokens:@[] trailing:text];
    }
    objc_setAssociatedObject(src, (__bridge const void *)src, buffer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [src setFlags:flags | LEXFL_NOERRORS | LEXFL_NOWARNINGS];

    const char *bytes = buffer.bytes;
    const char *end = bytes + data.length;
    const char *read = bytes;                       // the text taken so far
    idToken token;
    idToken_Init(&token);
    while ([src readToken:&token error:NULL]) {
        const char *after = [src scriptPointer];
        if (token.whiteSpaceStart_p != read || after > end) break;   // (never: one read after another)
        [tokens addObject:[UDSourceToken tokenWithLeading:UDBytesString(token.whiteSpaceStart_p, token.whiteSpaceEnd_p)
                                                     text:UDBytesString(token.whiteSpaceEnd_p, after)
                                                    value:UDTokenString(&token)]];
        read = after;
    }
    [src freeSource];
    return [self tokensWithTokens:tokens trailing:UDBytesString(read, end)];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[UDSourceTokens class]]) return NO;
    UDSourceTokens *other = object;
    return [other.tokens isEqualToArray:self.tokens] && [other.trailing isEqualToString:self.trailing];
}

- (NSUInteger)hash {
    return self.tokens.count;
}

- (NSString *)text {
    NSMutableString *out = [NSMutableString string];
    for (UDSourceToken *token in self.tokens) {
        [out appendString:token.leading];
        [out appendString:token.text];
    }
    [out appendString:self.trailing];
    return out;
}

- (NSArray<NSNumber *> *)byteOffsets {
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:self.tokens.count + 1];
    NSUInteger offset = 0;
    for (UDSourceToken *token in self.tokens) {
        [offsets addObject:@(offset)];
        offset += [token.leading lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        offset += [token.text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    }
    [offsets addObject:@(offset)];
    return offsets;
}

@end
