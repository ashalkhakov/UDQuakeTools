/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * id-style parser implementation helpers.
 */

#import "UDIdParser.h"
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
