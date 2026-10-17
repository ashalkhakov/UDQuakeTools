/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclCodec.m — the decl codecs' shared helpers.
 */

// AppKit (UDWorkspace.h) before Core Data: GNUstep's NSPredicateEditorRowTemplate.h
// defines Core Data's attribute types when Core Data is not yet in.
#include <strings.h>
#import "UDWorkspace.h"
#import "UDDeclManagedObjects.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

#pragma mark - Codec helpers

// While a parse is tested, the diagnostics its lexers collect into.
NSString *const UDDeclCodecDiagnosticsKey = @"UDDeclCodecDiagnostics";

// Builds a lexer over raw decl text, positioned right after the opening
// brace of the decl body (the text may or may not carry a "type name"
// header in front of it).
idLexer *UDDeclCodecLexerWithFlags(NSData *text, NSString *name, NSString *fileName, int lineNum,
                                          int flags, idFileSystem *fileSystem, NSError **error) {
    if (text == nil) {
        return nil;
    }

    // NUL-terminate a private copy so C-string oriented lexer internals are safe.
    NSMutableData *buffer = [text mutableCopy];
    [buffer appendBytes:"" length:1];

    idLexer *src = [[idLexer alloc] initWithFileSystem:fileSystem];
    // A Test of the text collects what the lexer says (+ud_problemsParsingText:...).
    src.diagnostics = [NSThread currentThread].threadDictionary[UDDeclCodecDiagnosticsKey];
    if (![src loadMemory:buffer.bytes
                  length:(int)text.length
                    name:(fileName.length > 0 ? fileName : (name ?: @"decl"))
               startLine:(lineNum > 0 ? lineNum : 1)
                   error:error]) {
        return nil;
    }
    // loadMemory BORROWS the pointer (idLexer keeps buffer.bytes without
    // copying), but `buffer` is a local that ARC releases when this helper
    // returns — leaving the lexer scanning freed memory. macOS's allocator
    // left the bytes intact so it appeared to work; glibc recycles the
    // chunk immediately, so on Linux every codec parse read garbage
    // ("unknown punctuation") and produced empty values. Tie the buffer's
    // lifetime to the lexer's.
    objc_setAssociatedObject(src, (__bridge const void *)src, buffer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [src setFlags:flags];
    if (![src skipUntilString:@"{" error:error]) {
        // SkipUntilString says nothing at the end of the text: a decl
        // without a body is not one its parser can read.
        if (error != NULL && *error == nil) {
            *error = [NSError errorWithDomain:@"org.underivable.udquaketools.lexer" code:1002 userInfo:
                      @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: no '{' opens the decl",
                                                    name.length > 0 ? name : @"decl"]}];
        }
        return nil;
    }
    return src;
}

idLexer *UDDeclCodecLexer(NSData *text, NSString *name, NSString *fileName, int lineNum,
                                 idFileSystem *fileSystem, NSError **error) {
    return UDDeclCodecLexerWithFlags(text, name, fileName, lineNum, DECL_LEXER_FLAGS, fileSystem, error);
}

NSString *UDTokenString(const idToken *token) {
    return [NSString stringWithUTF8String:token->text] ?: @"";
}

NSString *UDTokenLatin1String(const idToken *token) {
    return [NSString stringWithCString:token->text encoding:NSISOLatin1StringEncoding] ?: @"";
}

BOOL UDTokenIs(const idToken *token, const char *text) {
    return !strcmp(token->text, text);
}

BOOL UDTokenIcmp(const idToken *token, const char *text) {
    return !strcasecmp(token->text, text);
}

// key "value" — quoted so values containing spaces survive a re-parse.
// Embedded double quotes are downgraded to single quotes since
// DECL_LEXER_FLAGS has no string escape characters.
void UDAppendQuoted(NSMutableString *out, NSString *key, NSString *value) {
    NSString *safe = [(value ?: @"") stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    [out appendFormat:@"\t%@ \"%@\"\n", key, safe];
}

// Same, but for the email/audio/video codecs which parse with
// PDA_ITEM_LEXER_FLAGS (string escapes enabled): real newlines in the value
// are written back as literal \n escapes, since a raw newline inside a
// string token is a lexer error. This mirrors the way retail .pda files
// store multi-line info fields.
void UDAppendQuotedEscaped(NSMutableString *out, NSString *key, NSString *value) {
    NSString *safe = [(value ?: @"") stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    safe = [safe stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    safe = [safe stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    safe = [safe stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    [out appendFormat:@"\t%@ \"%@\"\n", key, safe];
}

// The value accessors read through KVC so they work uniformly on codec value
// dictionaries and on plain model objects (UDParticleStage).
NSString *UDStringValue(id values, NSString *key) {
    id value = [values valueForKey:key];
    if (value == nil || value == [NSNull null]) {
        return @"";
    }
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return [value description];
}

float UDFloatValue(id values, NSString *key) {
    id value = [values valueForKey:key];
    return (value != nil && value != [NSNull null]) ? [value floatValue] : 0.0f;
}

int UDIntValue(id values, NSString *key) {
    id value = [values valueForKey:key];
    return (value != nil && value != [NSNull null]) ? [value intValue] : 0;
}

BOOL UDBoolValue(id values, NSString *key) {
    id value = [values valueForKey:key];
    return (value != nil && value != [NSNull null]) ? [value boolValue] : NO;
}

NSString *UDFloatsToString(const float *v, int count) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [parts addObject:[NSString stringWithFormat:@"%g", v[i]]];
    }
    return [parts componentsJoinedByString:@" "];
}

void UDStringToFloats(NSString *string, float *v, int count) {
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

#pragma mark - Elements

/// Each element of @a elements is @a owner's, under @a key.
void UDAdoptElements(NSArray *elements, UDDeclBase *owner, NSString *key) {
    for (UDDeclElement *element in elements) {
        if ([element isKindOfClass:[UDDeclElement class]]) {
            element.ud_owner = owner;
            element.ud_ownerKey = key;
        }
    }
}

/// A name a decl can hold: one token, not empty.
BOOL UDValidateName(id *ioValue, NSString *what, NSError **error) {
    NSString *name = [*ioValue isKindOfClass:[NSString class]] ? *ioValue : [*ioValue description];
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length > 0 && [name rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound) {
        *ioValue = name;
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclElement" code:1 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"A %@ is one name, with no spaces.", what] }];
    }
    return NO;
}

/// The values @a object's codec reads from its text, for -awakeFromFetch.
NSDictionary *UDParsedSourceText(UDDeclBase *object) {
    NSData *text = [object primitiveValueForKey:@"sourceText"];
    if (text == nil) {
        return nil;
    }
    // The store's file system: a material's parse looks its tables up.
    return [[object class] ud_parseValuesFromText:text name:[object primitiveValueForKey:@"name"]
                                         fileName:nil lineNum:1 fileSystem:[object ud_store].declManager.workspace.fileSystem
                                            error:NULL];
}
