/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclPDA.m — PDAs, emails, audio logs and videos (idDeclPDA and its kin).
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclPDA.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

// The lexer flags idDeclEmail::Parse, idDeclAudio::Parse and
// idDeclVideo::Parse use in the original engine (DeclPDA.cpp): identical to
// DECL_LEXER_FLAGS except that LEXFL_NOSTRINGESCAPECHARS is NOT set, so the
// lexer itself turns "\n" escapes inside quoted strings into real newlines.
// This is how email bodies and audio/video info get their line breaks —
// there is no post-processing anywhere else in the engine or its editors.
#define PDA_ITEM_LEXER_FLAGS    (LEXFL_NOSTRINGCONCAT | \
                                LEXFL_ALLOWPATHNAMES | \
                                LEXFL_ALLOWMULTICHARLITERALS | \
                                LEXFL_ALLOWBACKSLASHSTRINGCONCAT | \
                                LEXFL_NOFATALERRORS)

#pragma mark - PDA family

@implementation UDDeclPDA

@dynamic pdaName;
@dynamic fullName;
@dynamic icon;
@dynamic ident;
@dynamic post;
@dynamic title;
@dynamic security;
@dynamic audios;
@dynamic emails;
@dynamic videos;

+ (NSString *)ud_defaultDefinition {
    return @"{\n\tname  \"default pda\"\n}";
}

+ (NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)text
                                                    name:(NSString *)name
                                                fileName:(NSString *)fileName
                                                 lineNum:(int)lineNum
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError **)error {
    idLexer *src = UDDeclCodecLexer(text, name, fileName, lineNum, fileSystem, error);
    if (src == nil) {
        return nil;
    }

    idToken token;
    idToken_Init(&token);

    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *emails = [NSMutableArray array];
    NSMutableArray<NSString *> *audios = [NSMutableArray array];
    NSMutableArray<NSString *> *videos = [NSMutableArray array];

    static NSDictionary<NSString *, NSString *> *fieldKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fieldKeys = @{
            @"name": @"pdaName",
            @"fullname": @"fullName",
            @"icon": @"icon",
            @"id": @"ident",
            @"post": @"post",
            @"title": @"title",
            @"security": @"security",
        };
    });

    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "}")) {
            break;
        }

        NSString *keyword = [UDTokenString(&token) lowercaseString];
        NSString *fieldKey = fieldKeys[keyword];
        if (fieldKey != nil) {
            if (![src readToken:&token error:error]) {
                break;
            }
            values[fieldKey] = UDTokenString(&token);
            continue;
        }

        NSMutableArray<NSString *> *list = nil;
        if ([keyword isEqualToString:@"pda_email"]) {
            list = emails;
        } else if ([keyword isEqualToString:@"pda_audio"]) {
            list = audios;
        } else if ([keyword isEqualToString:@"pda_video"]) {
            list = videos;
        }
        if (list != nil) {
            if (![src readToken:&token error:error]) {
                break;
            }
            [list addObject:UDTokenString(&token)];
            continue;
        }
    }

    values[@"emails"] = emails;
    values[@"audios"] = audios;
    values[@"videos"] = videos;
    return values;
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"pda %@ {\n", name];

    UDAppendQuoted(out, @"name", UDStringValue(values, @"pdaName"));
    UDAppendQuoted(out, @"fullname", UDStringValue(values, @"fullName"));
    UDAppendQuoted(out, @"icon", UDStringValue(values, @"icon"));
    UDAppendQuoted(out, @"id", UDStringValue(values, @"ident"));
    UDAppendQuoted(out, @"post", UDStringValue(values, @"post"));
    UDAppendQuoted(out, @"title", UDStringValue(values, @"title"));
    UDAppendQuoted(out, @"security", UDStringValue(values, @"security"));

    for (NSString *email in values[@"emails"] ?: @[]) {
        UDAppendQuoted(out, @"pda_email", email);
    }
    for (NSString *audio in values[@"audios"] ?: @[]) {
        UDAppendQuoted(out, @"pda_audio", audio);
    }
    for (NSString *video in values[@"videos"] ?: @[]) {
        UDAppendQuoted(out, @"pda_video", video);
    }

    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end

@implementation UDDeclEmail

@dynamic from;
@dynamic to;
@dynamic subject;
@dynamic date;
@dynamic body;
@dynamic image;
@dynamic pda;

+ (NSString *)ud_defaultDefinition {
    return @"{\n\t{\n\t\tto\t5Mail recipient\n\t\tsubject\t5Nothing\n\t\tfrom\t5No one\n\t}\n}";
}

+ (NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)text
                                                    name:(NSString *)name
                                                fileName:(NSString *)fileName
                                                 lineNum:(int)lineNum
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError **)error {
    // PDA_ITEM_LEXER_FLAGS (not DECL_LEXER_FLAGS): idDeclEmail::Parse enables
    // string escapes, so "\n" inside quoted strings becomes a real newline.
    idLexer *src = UDDeclCodecLexerWithFlags(text, name, fileName, lineNum,
                                             PDA_ITEM_LEXER_FLAGS, fileSystem, error);
    if (src == nil) {
        return nil;
    }

    idToken token;
    idToken_Init(&token);

    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    NSMutableString *body = [NSMutableString string];

    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "}")) {
            break;
        }

        if (!strcasecmp(token.text, "text")) {
            if (![src readToken:&token error:error] || strcmp(token.text, "{")) {
                [src warning:@"email '%@': expected '{' after text", name];
                break;
            }
            while ([src readToken:&token error:error] && strcmp(token.text, "}")) {
                [body appendString:UDTokenString(&token)];
            }
            continue;
        }

        static const char *fields[] = { "subject", "to", "from", "date", "image" };
        BOOL matched = NO;
        for (size_t i = 0; i < sizeof(fields) / sizeof(fields[0]); i++) {
            if (!strcasecmp(token.text, fields[i])) {
                NSString *key = [NSString stringWithUTF8String:fields[i]];
                if (![src readToken:&token error:error]) {
                    return values;
                }
                values[key] = UDTokenString(&token);
                matched = YES;
                break;
            }
        }
        (void)matched;
    }

    values[@"body"] = body;
    return values;
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"email %@ {\n", name];

    UDAppendQuotedEscaped(out, @"subject", UDStringValue(values, @"subject"));
    UDAppendQuotedEscaped(out, @"to", UDStringValue(values, @"to"));
    UDAppendQuotedEscaped(out, @"from", UDStringValue(values, @"from"));
    UDAppendQuotedEscaped(out, @"date", UDStringValue(values, @"date"));

    // The parser expects the body as a `text { "..." }` block whose string
    // tokens it concatenates. Newlines cannot appear inside string tokens,
    // so multi-line bodies are written one line per token with a literal \n
    // escape (as in the retail .pda files, where the PDA gui interprets it).
    [out appendString:@"\ttext {\n"];
    NSArray<NSString *> *lines = [UDStringValue(values, @"body") componentsSeparatedByString:@"\n"];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = [lines[i] stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
        [out appendFormat:@"\t\t\"%@%@\"\n", line, (i + 1 < lines.count) ? @"\\n" : @""];
    }
    [out appendString:@"\t}\n"];

    UDAppendQuotedEscaped(out, @"image", UDStringValue(values, @"image"));

    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end

@implementation UDDeclAudio

@dynamic audioName;
@dynamic audio;
@dynamic info;
@dynamic preview;
@dynamic pda;

+ (NSString *)ud_defaultDefinition {
    return @"{\n\t{\n\t\tname\t5Default Audio\n\t}\n}";
}

+ (NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)text
                                                    name:(NSString *)name
                                                fileName:(NSString *)fileName
                                                 lineNum:(int)lineNum
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError **)error {
    // PDA_ITEM_LEXER_FLAGS: idDeclAudio::Parse enables string escapes, which
    // is how multi-line info fields get their real newlines.
    idLexer *src = UDDeclCodecLexerWithFlags(text, name, fileName, lineNum,
                                             PDA_ITEM_LEXER_FLAGS, fileSystem, error);
    if (src == nil) {
        return nil;
    }

    idToken token;
    idToken_Init(&token);

    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];

    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "}")) {
            break;
        }

        NSString *key = nil;
        if (!strcasecmp(token.text, "name")) {
            key = @"audioName";
        } else if (!strcasecmp(token.text, "audio")) {
            key = @"audio";
        } else if (!strcasecmp(token.text, "info")) {
            key = @"info";
        } else if (!strcasecmp(token.text, "preview")) {
            key = @"preview";
        }
        if (key != nil) {
            if (![src readToken:&token error:error]) {
                break;
            }
            values[key] = UDTokenString(&token);
        }
    }

    return values;
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"audio %@ {\n", name];

    UDAppendQuotedEscaped(out, @"name", UDStringValue(values, @"audioName"));
    UDAppendQuotedEscaped(out, @"audio", UDStringValue(values, @"audio"));
    UDAppendQuotedEscaped(out, @"info", UDStringValue(values, @"info"));
    UDAppendQuotedEscaped(out, @"preview", UDStringValue(values, @"preview"));

    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end

@implementation UDDeclVideo

@dynamic videoName;
@dynamic video;
@dynamic audio;
@dynamic info;
@dynamic preview;
@dynamic pda;

+ (NSString *)ud_defaultDefinition {
    return @"{\n\t{\n\t\tname\t5Default Video\n\t}\n}";
}

+ (NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)text
                                                    name:(NSString *)name
                                                fileName:(NSString *)fileName
                                                 lineNum:(int)lineNum
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError **)error {
    // PDA_ITEM_LEXER_FLAGS: idDeclVideo::Parse enables string escapes, which
    // is how multi-line info fields get their real newlines.
    idLexer *src = UDDeclCodecLexerWithFlags(text, name, fileName, lineNum,
                                             PDA_ITEM_LEXER_FLAGS, fileSystem, error);
    if (src == nil) {
        return nil;
    }

    idToken token;
    idToken_Init(&token);

    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];

    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "}")) {
            break;
        }

        NSString *key = nil;
        if (!strcasecmp(token.text, "name")) {
            key = @"videoName";
        } else if (!strcasecmp(token.text, "video")) {
            key = @"video";
        } else if (!strcasecmp(token.text, "audio")) {
            key = @"audio";
        } else if (!strcasecmp(token.text, "info")) {
            key = @"info";
        } else if (!strcasecmp(token.text, "preview")) {
            key = @"preview";
        }
        if (key != nil) {
            if (![src readToken:&token error:error]) {
                break;
            }
            values[key] = UDTokenString(&token);
        }
    }

    return values;
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"video %@ {\n", name];

    UDAppendQuotedEscaped(out, @"name", UDStringValue(values, @"videoName"));
    UDAppendQuotedEscaped(out, @"preview", UDStringValue(values, @"preview"));
    UDAppendQuotedEscaped(out, @"video", UDStringValue(values, @"video"));
    UDAppendQuotedEscaped(out, @"info", UDStringValue(values, @"info"));
    UDAppendQuotedEscaped(out, @"audio", UDStringValue(values, @"audio"));

    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end
