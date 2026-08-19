/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclManagedObjects.m
 *
 * The decl entity classes and their text codecs. The parse/unparse logic in
 * this file is ported from the former idDecl* subclasses (idDeclPDA.m,
 * idDeclTable.m, idDeclSkin.m, idDeclParticle.m), reworked to read/produce
 * codec value dictionaries instead of mutating typed decl objects.
 */

#import "UDDeclManagedObjects.h"

#import "UDDeclIncrementalStore.h"
#import "UDLexer.h"
#import "UDToken.h"

#pragma mark - Entity name convention

// NOTE: the naive capitalization here can differ from the real entity name
// for acronym entities ("pda" -> "DeclPda" vs the actual "DeclPDA"), and the
// reverse direction produces "pDA". Everything that matches these against
// real names must therefore compare case-insensitively (the model lookup in
// +ud_entityNameForDeclTypeName:inModel: and idDeclManager's
// declTypeFromName: both do).
NSString *UDDeclEntityNameForDeclTypeName(NSString *declTypeName) {
    if (declTypeName.length == 0) {
        return nil;
    }
    NSString *head = [[declTypeName substringToIndex:1] uppercaseString];
    return [NSString stringWithFormat:@"Decl%@%@", head, [declTypeName substringFromIndex:1]];
}

NSString *UDDeclTypeNameForDeclEntityName(NSString *entityName) {
    if (![entityName hasPrefix:@"Decl"] || entityName.length <= 4) {
        return nil;
    }
    NSString *rest = [entityName substringFromIndex:4];
    return [[[rest substringToIndex:1] lowercaseString] stringByAppendingString:[rest substringFromIndex:1]];
}

#pragma mark - Codec helpers

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

// Builds a lexer over raw decl text, positioned right after the opening
// brace of the decl body (the text may or may not carry a "type name"
// header in front of it).
static idLexer *UDDeclCodecLexerWithFlags(NSData *text, NSString *name, NSString *fileName, int lineNum,
                                          int flags, idFileSystem *fileSystem, NSError **error) {
    if (text == nil) {
        return nil;
    }

    // NUL-terminate a private copy so C-string oriented lexer internals are safe.
    NSMutableData *buffer = [text mutableCopy];
    [buffer appendBytes:"" length:1];

    idLexer *src = [[idLexer alloc] initWithFileSystem:fileSystem];
    if (![src loadMemory:buffer.bytes
                  length:(int)text.length
                    name:(fileName.length > 0 ? fileName : (name ?: @"decl"))
               startLine:(lineNum > 0 ? lineNum : 1)
                   error:error]) {
        return nil;
    }
    [src setFlags:flags];
    if (![src skipUntilString:@"{" error:error]) {
        return nil;
    }
    return src;
}

static idLexer *UDDeclCodecLexer(NSData *text, NSString *name, NSString *fileName, int lineNum,
                                 idFileSystem *fileSystem, NSError **error) {
    return UDDeclCodecLexerWithFlags(text, name, fileName, lineNum, DECL_LEXER_FLAGS, fileSystem, error);
}

static NSString *UDTokenString(const idToken *token) {
    return [NSString stringWithUTF8String:token->text] ?: @"";
}

// key "value" — quoted so values containing spaces survive a re-parse.
// Embedded double quotes are downgraded to single quotes since
// DECL_LEXER_FLAGS has no string escape characters.
static void UDAppendQuoted(NSMutableString *out, NSString *key, NSString *value) {
    NSString *safe = [(value ?: @"") stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    [out appendFormat:@"\t%@ \"%@\"\n", key, safe];
}

// Same, but for the email/audio/video codecs which parse with
// PDA_ITEM_LEXER_FLAGS (string escapes enabled): real newlines in the value
// are written back as literal \n escapes, since a raw newline inside a
// string token is a lexer error. This mirrors the way retail .pda files
// store multi-line info fields.
static void UDAppendQuotedEscaped(NSMutableString *out, NSString *key, NSString *value) {
    NSString *safe = [(value ?: @"") stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    safe = [safe stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    safe = [safe stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    safe = [safe stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    [out appendFormat:@"\t%@ \"%@\"\n", key, safe];
}

// The value accessors read through KVC so they work uniformly on codec value
// dictionaries and on plain model objects (UDParticleStage).
static NSString *UDStringValue(id values, NSString *key) {
    id value = [values valueForKey:key];
    if (value == nil || value == [NSNull null]) {
        return @"";
    }
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return [value description];
}

static float UDFloatValue(id values, NSString *key) {
    id value = [values valueForKey:key];
    return (value != nil && value != [NSNull null]) ? [value floatValue] : 0.0f;
}

static int UDIntValue(id values, NSString *key) {
    id value = [values valueForKey:key];
    return (value != nil && value != [NSNull null]) ? [value intValue] : 0;
}

static BOOL UDBoolValue(id values, NSString *key) {
    id value = [values valueForKey:key];
    return (value != nil && value != [NSNull null]) ? [value boolValue] : NO;
}

static NSString *UDFloatsToString(const float *v, int count) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [parts addObject:[NSString stringWithFormat:@"%g", v[i]]];
    }
    return [parts componentsJoinedByString:@" "];
}

static void UDStringToFloats(NSString *string, float *v, int count) {
    memset(v, 0, count * sizeof(*v));
    NSArray<NSString *> *parts = [string componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    int i = 0;
    for (NSString *part in parts) {
        if (part.length == 0) {
            continue;
        }
        if (i >= count) {
            break;
        }
        v[i++] = part.floatValue;
    }
}

#pragma mark - DeclFile / DeclType

@implementation UDDeclFile

@dynamic fileName;
@dynamic checksum;
@dynamic timestamp;

@end

@implementation UDDeclType

@dynamic name;
@dynamic type;

@end

#pragma mark - DeclBase

@implementation UDDeclBase

@dynamic name;
@dynamic sourceText;
@dynamic sourceFile;
@dynamic type;

+ (NSString *)ud_defaultDefinition {
    return @"{\n}\n";
}

+ (NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)text
                                                    name:(NSString *)name
                                                fileName:(NSString *)fileName
                                                 lineNum:(int)lineNum
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError **)error {
    return nil; // raw-text-only entity
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    return nil; // raw-text-only entity
}

+ (NSString *)ud_entityNameForDeclTypeName:(NSString *)declTypeName inModel:(NSManagedObjectModel *)model {
    NSString *wanted = UDDeclEntityNameForDeclTypeName(declTypeName);
    if (wanted == nil) {
        return nil;
    }
    // Match case-insensitively: entity names capitalize acronyms (DeclPDA)
    // while type names don't ("pda"), so a naive "Decl"+capitalized(typeName)
    // comparison would miss them.
    for (NSString *entityName in model.entitiesByName) {
        if ([entityName caseInsensitiveCompare:wanted] == NSOrderedSame) {
            return entityName;
        }
    }
    return nil;
}

+ (__kindof UDDeclBase *)ud_declWithTypeName:(NSString *)declTypeName
                                          name:(NSString *)name
                                     inContext:(NSManagedObjectContext *)context
                                         error:(NSError **)error {
    NSManagedObjectModel *model = context.persistentStoreCoordinator.managedObjectModel;
    NSString *entityName = [self ud_entityNameForDeclTypeName:declTypeName inModel:model];
    if (entityName == nil || name.length == 0) {
        return nil;
    }

    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entityName];
    request.predicate = [NSPredicate predicateWithFormat:@"name ==[c] %@", name];

    NSArray *results = [context executeFetchRequest:request error:error];
    return results.firstObject;
}

// Property-level validation, invoked by Core Data during
// -validateForInsert: / -validateForUpdate:, i.e. when the context saves —
// so a nameless decl is rejected before the incremental store ever sees the
// save request. The model can't express this itself: `name` is non-optional
// but its default of @"" satisfies the non-null check.
- (BOOL)validateName:(id *)valueRef error:(NSError **)error {
    NSString *name = (valueRef != NULL) ? *valueRef : nil;
    NSString *trimmed = [name isKindOfClass:[NSString class]]
        ? [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : nil;

    if (trimmed.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                          code:NSValidationMissingMandatoryPropertyError
                                      userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"A %@ needs a non-empty decl name", self.entity.name],
                NSValidationObjectErrorKey: self,
                NSValidationKeyErrorKey: @"name",
            }];
        }
        return NO;
    }
    return YES;
}

// sourceText is transient, so Core Data never faults it in through the
// store's -newValuesForObjectWithID:withContext:error:. Populate it here
// instead, straight from the manager's raw decl text, so readers can rely
// on it after a fetch without each caller having to know to ask the store.
- (void)awakeFromFetch {
    [super awakeFromFetch];

    UDDeclIncrementalStore *store = (UDDeclIncrementalStore *)self.objectID.persistentStore;
    if (![store isKindOfClass:[UDDeclIncrementalStore class]]) {
        return;
    }

    NSData *text = [store ud_currentSourceTextForObjectID:self.objectID error:NULL];
    if (text != nil) {
        [self setPrimitiveValue:text forKey:@"sourceText"];
    }
}

@end

#pragma mark - DeclMaterial (raw text only)

@implementation UDDeclMaterial

+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"{\n"
        @"\t\t"        @"blend\tblend\n"
        @"\t\t"        @"map\t\t_default\n"
        @"\t"    @"}\n"
        @"}";
}

@end

#pragma mark - DeclTable

@implementation UDDeclTable

@dynamic clamp;
@dynamic snap;
@dynamic values;

+ (NSString *)ud_defaultDefinition {
    return @"{ { 0 } }";
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

    BOOL snap = NO;
    BOOL clamp = NO;
    NSMutableArray<NSString *> *numbers = [NSMutableArray array];

    // Tolerant scanner over the table body. The game data is not uniform
    // here: most tables wrap their values in an inner brace pair, some list
    // values directly, and some lists are empty. Track brace depth and
    // collect numbers wherever they appear; anything unrecognized is skipped
    // with a warning instead of aborting the whole table.
    int depth = 1; // the codec lexer already consumed the opening brace
    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "{")) {
            depth++;
            continue;
        }
        if (!strcmp(token.text, "}")) {
            if (--depth == 0) {
                break;
            }
            continue;
        }
        if (!strcmp(token.text, ",")) {
            continue;
        }
        if (!strcasecmp(token.text, "snap")) {
            snap = YES;
            continue;
        }
        if (!strcasecmp(token.text, "clamp")) {
            clamp = YES;
            continue;
        }

        if (!strcmp(token.text, "-")) {
            if ([src readToken:&token error:error]) {
                idToken_StripQuotes(&token);
                [numbers addObject:[NSString stringWithFormat:@"%g", -atof(token.text)]];
            }
            continue;
        }

        idToken_StripQuotes(&token);
        const char first = token.text[0];
        if ((first >= '0' && first <= '9') || first == '.' || first == '+') {
            [numbers addObject:[NSString stringWithFormat:@"%g", atof(token.text)]];
            continue;
        }

        [src warning:@"table '%@': unknown token '%s'", name, token.text];
    }

    return @{
        @"snap": @(snap),
        @"clamp": @(clamp),
        @"values": [numbers componentsJoinedByString:@", "],
    };
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"table %@ {\n", name];
    if (UDBoolValue(values, @"snap")) {
        [out appendString:@"\tsnap\n"];
    }
    if (UDBoolValue(values, @"clamp")) {
        [out appendString:@"\tclamp\n"];
    }

    NSMutableArray<NSString *> *numbers = [NSMutableArray array];
    for (NSString *part in [UDStringValue(values, @"values") componentsSeparatedByString:@","]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [numbers addObject:[NSString stringWithFormat:@"%g", trimmed.floatValue]];
        }
    }
    [out appendFormat:@"\t{ %@ }\n", [numbers componentsJoinedByString:@", "]];
    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end

#pragma mark - DeclSkin

@implementation UDDeclSkin

@dynamic mappings;
@dynamic associatedModels;

+ (NSString *)ud_defaultDefinition {
    return
    @"{\n"
    @"\t"    @"\"*\"\t\"_default\"\n"
    @"}";
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

    idToken token, token2;
    idToken_Init(&token);
    idToken_Init(&token2);

    NSMutableArray<NSString *> *mappingLines = [NSMutableArray array];
    NSMutableArray<NSString *> *modelLines = [NSMutableArray array];

    while (1) {
        if (![src readToken:&token error:error]) {
            break;
        }
        if (!strcasecmp(token.text, "}")) {
            break;
        }
        if (![src readToken:&token2 error:error]) {
            [src warning:@"skin '%@': unexpected end of file", name];
            break;
        }

        if (!strcasecmp(token.text, "model")) {
            [modelLines addObject:UDTokenString(&token2)];
            continue;
        }

        NSString *from = !strcasecmp(token.text, "*") ? @"*" : UDTokenString(&token);
        [mappingLines addObject:[NSString stringWithFormat:@"%@ %@", from, UDTokenString(&token2)]];
    }

    return @{
        @"mappings": [mappingLines componentsJoinedByString:@"\n"],
        @"associatedModels": [modelLines componentsJoinedByString:@"\n"],
    };
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"skin %@ {\n", name];

    for (NSString *line in [UDStringValue(values, @"associatedModels") componentsSeparatedByString:@"\n"]) {
        NSString *model = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (model.length > 0) {
            [out appendFormat:@"\tmodel %@\n", model];
        }
    }

    for (NSString *line in [UDStringValue(values, @"mappings") componentsSeparatedByString:@"\n"]) {
        NSString *mapping = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (mapping.length > 0) {
            [out appendFormat:@"\t%@\n", mapping];
        }
    }

    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end

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

#pragma mark - DeclParticle

// keyword tables ported from idDeclParticle.m
typedef struct UDParticleParmDesc {
    const char *name;
    int count;
} UDParticleParmDesc_t;

static const UDParticleParmDesc_t UDParticleDistributionDesc[] = {
    { "rect", 3 },
    { "cylinder", 4 },
    { "sphere", 3 },
};

static const UDParticleParmDesc_t UDParticleDirectionDesc[] = {
    { "cone", 1 },
    { "outward", 1 },
};

static const UDParticleParmDesc_t UDParticleOrientationDesc[] = {
    { "view", 0 },
    { "aimed", 2 },
    { "x", 0 },
    { "y", 0 },
    { "z", 0 },
};

static const UDParticleParmDesc_t UDParticleCustomDesc[] = {
    { "standard", 0 },
    { "helix", 5 },
    { "flies", 3 },
    { "orbit", 2 },
    { "drip", 2 },
};

#define UDParticleDescCount(table) ((int)(sizeof(table) / sizeof((table)[0])))

static int UDParticleDescIndex(const UDParticleParmDesc_t *table, int tableCount, const char *keyword) {
    for (int i = 0; i < tableCount; i++) {
        if (strcasecmp(table[i].name, keyword) == 0) {
            return i;
        }
    }
    return -1;
}

@implementation UDParticleStage

// The defaults the old idParticleStage's -defaults installed before parsing
// a stage; keywords the decl text doesn't mention keep these values.
- (instancetype)init {
    self = [super init];
    if (self) {
        _material = @"_default";
        _totalParticles = 100;
        _cycles = 0.0f;
        _spawnBunching = 1.0f;
        _particleLife = 1.5f;
        _timeOffset = 0.0f;
        _deadTime = 0.0f;
        _distributionType = 0; // rect
        _distributionParms = @"8 8 8 0";
        _directionType = 0; // cone
        _directionParms = @"90 0 0 0";
        _orientation = 0; // view
        _orientationParms = @"0 0 0 0";
        _customPathType = 0; // standard
        _customPathParms = @"0 0 0 0 0 0 0 0";
        _speedFrom = 150.0f;
        _speedTo = 150.0f;
        _rotationFrom = 0.0f;
        _rotationTo = 0.0f;
        _sizeFrom = 4.0f;
        _sizeTo = 4.0f;
        _aspectFrom = 1.0f;
        _aspectTo = 1.0f;
        _gravity = 1.0f;
        _worldGravity = NO;
        _randomDistribution = YES;
        _entityColor = NO;
        _offset = @"0 0 0";
        _animationFrames = 0;
        _animationRate = 0.0f;
        _initialAngle = 0.0f;
        _color = @"1 1 1 1";
        _fadeColor = @"0 0 0 0";
        _fadeInFraction = 0.1f;
        _fadeOutFraction = 0.25f;
        _fadeIndexFraction = 0.0f;
        _boundsExpansion = 0.0f;
        _softeningRadius = -2.0f;
        _hidden = NO;
    }
    return self;
}

@end

// Reads the remaining float parameters on the current line. Stops at (and
// unreads) the first token that is not a number: real .prt files sometimes
// put the stage's closing brace or the next keyword on the same line, and
// consuming it here desynchronizes the stage parser — which is exactly how
// spurious "unknown token depthHack" errors appear.
static int UDParticleParseParms(idLexer *src, float *parms, int maxParms, NSError **error) {
    memset(parms, 0, maxParms * sizeof(*parms));

    idToken token;
    idToken_Init(&token);

    int count = 0;
    while ([src readTokenOnLine:&token error:error]) {
        if (!strcmp(token.text, "-")) {
            if (![src readTokenOnLine:&token error:error]) {
                break;
            }
            idToken_StripQuotes(&token);
            if (count < maxParms) {
                parms[count] = -atof(token.text);
            }
            count++;
            continue;
        }

        // peek inside quotes for the numeric check, but unread the token
        // untouched if it turns out not to be a parameter
        char first = token.text[0];
        if (first == '"' || first == '\'') {
            first = token.text[1];
        }
        const BOOL numeric = (first >= '0' && first <= '9') || first == '.' || first == '+';
        if (!numeric) {
            [src unreadToken:&token error:error];
            break;
        }

        idToken_StripQuotes(&token);
        if (count < maxParms) {
            parms[count] = atof(token.text);
        }
        count++;
    }
    return count < maxParms ? count : maxParms;
}

// Parses `<table>` or `<from> [to <to>]` into <prefix>Table / <prefix>From /
// <prefix>To keys. Numbers are often quoted in .prt files written by the
// particle editor, so quotes are stripped before classification.
static BOOL UDParticleParseParametric(idLexer *src, UDParticleStage *stage, NSString *prefix, NSError **error) {
    idToken token;
    idToken_Init(&token);

    if (![src readToken:&token error:error]) {
        return NO;
    }
    idToken_StripQuotes(&token);

    const char first = token.text[0];
    const BOOL numeric = (first >= '0' && first <= '9') || first == '-' || first == '+' || first == '.';

    NSString *tableKey = [prefix stringByAppendingString:@"Table"];
    NSString *fromKey = [prefix stringByAppendingString:@"From"];
    NSString *toKey = [prefix stringByAppendingString:@"To"];

    if (!numeric) {
        [stage setValue:UDTokenString(&token) forKey:tableKey];
        return YES;
    }

    float from = atof(token.text);
    float to = from;
    if ([src readToken:&token error:error]) {
        if (!strcasecmp(token.text, "to")) {
            if (![src readToken:&token error:error]) {
                return NO;
            }
            idToken_StripQuotes(&token);
            to = atof(token.text);
        } else {
            [src unreadToken:&token error:error];
        }
    }
    [stage setValue:nil forKey:tableKey];
    [stage setValue:@(from) forKey:fromKey];
    [stage setValue:@(to) forKey:toKey];
    return YES;
}

static UDParticleStage *UDParticleParseStage(idLexer *src, NSString *name, NSError **error) {
    UDParticleStage *stage = [[UDParticleStage alloc] init];

    idToken token;
    idToken_Init(&token);

    float parms[8];

    while (1) {
        if ([src hadError]) {
            break;
        }
        if (![src readToken:&token error:error]) {
            break;
        }
        if (!strcasecmp(token.text, "}")) {
            break;
        }

        if (!strcasecmp(token.text, "material")) {
            if (![src readToken:&token error:error]) {
                return nil;
            }
            stage.material = UDTokenString(&token);
            continue;
        }
        if (!strcasecmp(token.text, "count")) {
            int i = 0;
            if (![src parseInt:&i error:error]) {
                return nil;
            }
            stage.totalParticles = i;
            continue;
        }

        static const struct { const char *keyword; const char *key; } floatFields[] = {
            { "time", "particleLife" },
            { "cycles", "cycles" },
            { "timeOffset", "timeOffset" },
            { "deadTime", "deadTime" },
            { "bunching", "spawnBunching" },
            { "angle", "initialAngle" },
            { "fadeIn", "fadeInFraction" },
            { "fadeOut", "fadeOutFraction" },
            { "fadeIndex", "fadeIndexFraction" },
            { "animationRate", "animationRate" },
            { "boundsExpansion", "boundsExpansion" },
            { "softeningRadius", "softeningRadius" },
        };
        BOOL matched = NO;
        for (size_t i = 0; i < sizeof(floatFields) / sizeof(floatFields[0]); i++) {
            if (!strcasecmp(token.text, floatFields[i].keyword)) {
                float f = 0.0f;
                if (![src parseFloat:&f error:error]) {
                    return nil;
                }
                [stage setValue:@(f) forKey:[NSString stringWithUTF8String:floatFields[i].key]];
                matched = YES;
                break;
            }
        }
        if (matched) {
            continue;
        }

        if (!strcasecmp(token.text, "animationFrames")) {
            int i = 0;
            if (![src parseInt:&i error:error]) {
                return nil;
            }
            stage.animationFrames = i;
            continue;
        }
        if (!strcasecmp(token.text, "randomDistribution")) {
            BOOL b = NO;
            if (![src parseBool:&b error:error]) {
                return nil;
            }
            stage.randomDistribution = b;
            continue;
        }
        if (!strcasecmp(token.text, "entityColor")) {
            BOOL b = NO;
            if (![src parseBool:&b error:error]) {
                return nil;
            }
            stage.entityColor = b;
            continue;
        }

        if (!strcasecmp(token.text, "distribution")) {
            if (![src readToken:&token error:error]) {
                return nil;
            }
            int index = UDParticleDescIndex(UDParticleDistributionDesc, UDParticleDescCount(UDParticleDistributionDesc), token.text);
            if (index < 0) {
                [src warning:@"particle '%@': bad distribution type: %s", name, token.text];
                index = 0;
            }
            stage.distributionType = index;
            UDParticleParseParms(src, parms, 4, error);
            stage.distributionParms = UDFloatsToString(parms, 4);
            continue;
        }
        if (!strcasecmp(token.text, "direction")) {
            if (![src readToken:&token error:error]) {
                return nil;
            }
            int index = UDParticleDescIndex(UDParticleDirectionDesc, UDParticleDescCount(UDParticleDirectionDesc), token.text);
            if (index < 0) {
                [src warning:@"particle '%@': bad direction type: %s", name, token.text];
                index = 0;
            }
            stage.directionType = index;
            UDParticleParseParms(src, parms, 4, error);
            stage.directionParms = UDFloatsToString(parms, 4);
            continue;
        }
        if (!strcasecmp(token.text, "orientation")) {
            if (![src readToken:&token error:error]) {
                return nil;
            }
            int index = UDParticleDescIndex(UDParticleOrientationDesc, UDParticleDescCount(UDParticleOrientationDesc), token.text);
            if (index < 0) {
                [src warning:@"particle '%@': bad orientation type: %s", name, token.text];
                index = 0;
            }
            stage.orientation = index;
            UDParticleParseParms(src, parms, 4, error);
            stage.orientationParms = UDFloatsToString(parms, 4);
            continue;
        }
        if (!strcasecmp(token.text, "customPath")) {
            if (![src readToken:&token error:error]) {
                return nil;
            }
            int index = UDParticleDescIndex(UDParticleCustomDesc, UDParticleDescCount(UDParticleCustomDesc), token.text);
            if (index < 0 && !strcasecmp(token.text, "spherical")) {
                index = 3; // orbit; legacy keyword
            }
            if (index < 0) {
                [src warning:@"particle '%@': bad path type: %s", name, token.text];
                index = 0;
            }
            stage.customPathType = index;
            UDParticleParseParms(src, parms, 8, error);
            stage.customPathParms = UDFloatsToString(parms, 8);
            continue;
        }

        if (!strcasecmp(token.text, "speed")) {
            if (!UDParticleParseParametric(src, stage, @"speed", error)) {
                return nil;
            }
            continue;
        }
        if (!strcasecmp(token.text, "rotation")) {
            if (!UDParticleParseParametric(src, stage, @"rotation", error)) {
                return nil;
            }
            continue;
        }
        if (!strcasecmp(token.text, "size")) {
            if (!UDParticleParseParametric(src, stage, @"size", error)) {
                return nil;
            }
            continue;
        }
        if (!strcasecmp(token.text, "aspect")) {
            if (!UDParticleParseParametric(src, stage, @"aspect", error)) {
                return nil;
            }
            continue;
        }

        if (!strcasecmp(token.text, "color") || !strcasecmp(token.text, "fadeColor")) {
            NSString *key = !strcasecmp(token.text, "color") ? @"color" : @"fadeColor";
            float c[4] = { 0, 0, 0, 0 };
            for (int i = 0; i < 4; i++) {
                if (![src parseFloat:&c[i] error:error]) {
                    return nil;
                }
            }
            [stage setValue:UDFloatsToString(c, 4) forKey:key];
            continue;
        }
        if (!strcasecmp(token.text, "offset")) {
            float o[3] = { 0, 0, 0 };
            for (int i = 0; i < 3; i++) {
                if (![src parseFloat:&o[i] error:error]) {
                    return nil;
                }
            }
            stage.offset = UDFloatsToString(o, 3);
            continue;
        }
        if (!strcasecmp(token.text, "gravity")) {
            if (![src readToken:&token error:error]) {
                return nil;
            }
            if (!strcasecmp(token.text, "world")) {
                stage.worldGravity = YES;
            } else {
                [src unreadToken:&token error:error];
            }
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return nil;
            }
            stage.gravity = f;
            continue;
        }

        [src warning:@"particle '%@': unknown token %s (skipping rest of line)", name, token.text];
        [src skipRestOfLine:error];
    }

    return stage;
}

static void UDParticleWriteParametric(NSMutableString *out, UDParticleStage *stage, NSString *keyword, NSString *prefix) {
    NSString *table = UDStringValue(stage, [prefix stringByAppendingString:@"Table"]);
    float from = UDFloatValue(stage, [prefix stringByAppendingString:@"From"]);
    float to = UDFloatValue(stage, [prefix stringByAppendingString:@"To"]);

    [out appendFormat:@"\t\t%@\t\t\t\t ", keyword];
    if (table.length > 0) {
        [out appendFormat:@"%@\n", table];
    } else if (from == to) {
        [out appendFormat:@"\"%.3f\" \n", from];
    } else {
        [out appendFormat:@"\"%.3f\"  to \"%.3f\"\n", from, to];
    }
}

static void UDParticleWriteStage(NSMutableString *out, UDParticleStage *stage) {
    [out appendString:@"\t{\n"];
    [out appendFormat:@"\t\tcount\t\t\t\t%i\n", UDIntValue(stage, @"totalParticles")];
    [out appendFormat:@"\t\tmaterial\t\t\t%@\n", UDStringValue(stage, @"material")];
    if (UDIntValue(stage, @"animationFrames")) {
        [out appendFormat:@"\t\tanimationFrames \t%i\n", UDIntValue(stage, @"animationFrames")];
    }
    if (UDFloatValue(stage, @"animationRate")) {
        [out appendFormat:@"\t\tanimationRate \t\t%.3f\n", UDFloatValue(stage, @"animationRate")];
    }
    [out appendFormat:@"\t\ttime\t\t\t\t%.3f\n", UDFloatValue(stage, @"particleLife")];
    [out appendFormat:@"\t\tcycles\t\t\t\t%.3f\n", UDFloatValue(stage, @"cycles")];
    if (UDFloatValue(stage, @"timeOffset")) {
        [out appendFormat:@"\t\ttimeOffset\t\t\t%.3f\n", UDFloatValue(stage, @"timeOffset")];
    }
    if (UDFloatValue(stage, @"deadTime")) {
        [out appendFormat:@"\t\tdeadTime\t\t\t%.3f\n", UDFloatValue(stage, @"deadTime")];
    }
    [out appendFormat:@"\t\tbunching\t\t\t%.3f\n", UDFloatValue(stage, @"spawnBunching")];

    float parms[8];

    int distribution = UDIntValue(stage, @"distributionType");
    if (distribution < 0 || distribution >= UDParticleDescCount(UDParticleDistributionDesc)) {
        distribution = 0;
    }
    UDStringToFloats(UDStringValue(stage, @"distributionParms"), parms, 8);
    [out appendFormat:@"\t\tdistribution\t\t%s ", UDParticleDistributionDesc[distribution].name];
    for (int i = 0; i < UDParticleDistributionDesc[distribution].count; i++) {
        [out appendFormat:@"%.3f ", parms[i]];
    }
    [out appendString:@"\n"];

    int direction = UDIntValue(stage, @"directionType");
    if (direction < 0 || direction >= UDParticleDescCount(UDParticleDirectionDesc)) {
        direction = 0;
    }
    UDStringToFloats(UDStringValue(stage, @"directionParms"), parms, 8);
    [out appendFormat:@"\t\tdirection\t\t\t%s ", UDParticleDirectionDesc[direction].name];
    for (int i = 0; i < UDParticleDirectionDesc[direction].count; i++) {
        [out appendFormat:@"\"%.3f\" ", parms[i]];
    }
    [out appendString:@"\n"];

    int orientation = UDIntValue(stage, @"orientation");
    if (orientation < 0 || orientation >= UDParticleDescCount(UDParticleOrientationDesc)) {
        orientation = 0;
    }
    UDStringToFloats(UDStringValue(stage, @"orientationParms"), parms, 8);
    [out appendFormat:@"\t\torientation\t\t\t%s ", UDParticleOrientationDesc[orientation].name];
    for (int i = 0; i < UDParticleOrientationDesc[orientation].count; i++) {
        [out appendFormat:@"%.3f ", parms[i]];
    }
    [out appendString:@"\n"];

    int customPath = UDIntValue(stage, @"customPathType");
    if (customPath < 0 || customPath >= UDParticleDescCount(UDParticleCustomDesc)) {
        customPath = 0;
    }
    if (customPath != 0) {
        UDStringToFloats(UDStringValue(stage, @"customPathParms"), parms, 8);
        [out appendFormat:@"\t\tcustomPath %s ", UDParticleCustomDesc[customPath].name];
        for (int i = 0; i < UDParticleCustomDesc[customPath].count; i++) {
            [out appendFormat:@"%.3f ", parms[i]];
        }
        [out appendString:@"\n"];
    }

    if (UDBoolValue(stage, @"entityColor")) {
        [out appendString:@"\t\tentityColor\t\t\t1\n"];
    }

    UDParticleWriteParametric(out, stage, @"speed", @"speed");
    UDParticleWriteParametric(out, stage, @"size", @"size");
    UDParticleWriteParametric(out, stage, @"aspect", @"aspect");

    if (UDStringValue(stage, @"rotationTable").length > 0 || UDFloatValue(stage, @"rotationFrom")) {
        UDParticleWriteParametric(out, stage, @"rotation", @"rotation");
    }

    if (UDFloatValue(stage, @"initialAngle")) {
        [out appendFormat:@"\t\tangle\t\t\t\t%.3f\n", UDFloatValue(stage, @"initialAngle")];
    }

    [out appendFormat:@"\t\trandomDistribution\t\t\t\t%i\n", UDBoolValue(stage, @"randomDistribution") ? 1 : 0];
    [out appendFormat:@"\t\tboundsExpansion\t\t\t\t%.3f\n", UDFloatValue(stage, @"boundsExpansion")];

    [out appendFormat:@"\t\tfadeIn\t\t\t\t%.3f\n", UDFloatValue(stage, @"fadeInFraction")];
    [out appendFormat:@"\t\tfadeOut\t\t\t\t%.3f\n", UDFloatValue(stage, @"fadeOutFraction")];
    [out appendFormat:@"\t\tfadeIndex\t\t\t\t%.3f\n", UDFloatValue(stage, @"fadeIndexFraction")];

    float c[4];
    UDStringToFloats(UDStringValue(stage, @"color"), c, 4);
    [out appendFormat:@"\t\tcolor \t\t\t\t%.3f %.3f %.3f %.3f\n", c[0], c[1], c[2], c[3]];
    UDStringToFloats(UDStringValue(stage, @"fadeColor"), c, 4);
    [out appendFormat:@"\t\tfadeColor \t\t\t%.3f %.3f %.3f %.3f\n", c[0], c[1], c[2], c[3]];

    float o[3];
    UDStringToFloats(UDStringValue(stage, @"offset"), o, 3);
    [out appendFormat:@"\t\toffset \t\t\t\t%.3f %.3f %.3f\n", o[0], o[1], o[2]];

    [out appendString:@"\t\tgravity \t\t\t"];
    if (UDBoolValue(stage, @"worldGravity")) {
        [out appendString:@"world "];
    }
    [out appendFormat:@"%.3f\n", UDFloatValue(stage, @"gravity")];
    [out appendString:@"\t}\n"];
}

@implementation UDDeclParticle

@dynamic depthHack;
@dynamic stages;

// stages is transient, so the store never faults it in; build it here from
// the freshly populated sourceText (same pattern as sourceText itself in
// UDDeclBase).
- (void)awakeFromFetch {
    [super awakeFromFetch];

    NSData *text = [self primitiveValueForKey:@"sourceText"];
    if (text == nil) {
        return;
    }
    NSDictionary *parsed = [[self class] ud_parseValuesFromText:text
                                                           name:[self primitiveValueForKey:@"name"]
                                                       fileName:nil
                                                        lineNum:1
                                                     fileSystem:nil
                                                          error:NULL];
    [self setPrimitiveValue:(parsed[@"stages"] ?: @[]) forKey:@"stages"];
}

- (void)awakeFromInsert {
    [super awakeFromInsert];
    [self setPrimitiveValue:@[] forKey:@"stages"];
}

+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
    @"\t"    @"{\n"
    @"\t\t"        @"material\t_default\n"
    @"\t\t"        @"count\t20\n"
    @"\t\t"        @"time\t\t1.0\n"
    @"\t"    @"}\n"
        @"}";
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

    float depthHack = 0.0f;
    NSMutableArray<UDParticleStage *> *stages = [NSMutableArray array];

    while (1) {
        if (![src readToken:&token error:error]) {
            break;
        }
        if (!strcasecmp(token.text, "}")) {
            break;
        }

        if (!strcasecmp(token.text, "{")) {
            UDParticleStage *stage = UDParticleParseStage(src, name, error);
            if (stage == nil) {
                [src warning:@"particle '%@': stage parse failed", name];
                break;
            }
            [stages addObject:stage];
            continue;
        }

        if (!strcasecmp(token.text, "depthHack")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                break;
            }
            depthHack = f;
            continue;
        }

        [src warning:@"particle '%@': bad token %s (skipping rest of line)", name, token.text];
        [src skipRestOfLine:error];
    }

    return @{
        @"depthHack": @(depthHack),
        @"stages": stages,
    };
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"particle %@ {\n", name];

    float depthHack = UDFloatValue(values, @"depthHack");
    if (depthHack) {
        [out appendFormat:@"\tdepthHack\t%f\n", depthHack];
    }

    for (UDParticleStage *stage in values[@"stages"] ?: @[]) {
        UDParticleWriteStage(out, stage);
    }

    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end

