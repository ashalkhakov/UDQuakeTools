/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclTable.m — tables (idDeclTable).
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclTable.h"
#import "idDeclManager.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

@implementation UDTableValue

+ (instancetype)valueWithNumber:(float)number {
    UDTableValue *value = [[self alloc] init];
    value->_number = number;
    return value;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] valueWithNumber:_number];
}

- (void)setNumber:(float)number {
    UDTableValue *edited = [self copy];
    edited->_number = number;
    if (![self ud_replaceInOwnerWith:edited]) {
        _number = number;
    }
}

/// A number, or text that is all of one ("0.25"); anything else is refused.
- (BOOL)validateNumber:(id *)ioValue error:(NSError **)error {
    if ([*ioValue isKindOfClass:[NSNumber class]]) {
        return YES;
    }
    NSScanner *scanner = [NSScanner scannerWithString:[*ioValue description] ?: @""];
    float number;
    if ([scanner scanFloat:&number] && scanner.isAtEnd) {
        *ioValue = @(number);
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclElement" code:2
                                 userInfo:@{ NSLocalizedDescriptionKey: @"A table's value is a number." }];
    }
    return NO;
}

@end

@implementation UDDeclTable

@dynamic clamp;
@dynamic snap;

@dynamic values;

UD_ELEMENT_ARRAY_SETTER(setValues, @"values")

// values is transient: read from the text here, as particle stages are.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSArray *values = UDParsedSourceText(self)[@"values"] ?: @[];
    [self setPrimitiveValue:values forKey:@"values"];
    UDAdoptElements(values, self, @"values");
}

+ (NSString *)ud_defaultDefinition {
    return @"{ { 0 } }";
}

/// What idDeclTable::MakeDefault leaves: the default definition, { { 0 } }.
static NSDictionary<NSString *, id> *UDDefaultTableValues(void) {
    return @{ @"snap": @NO, @"clamp": @NO, @"values": @[[UDTableValue valueWithNumber:0]] };
}

// A port of idDeclTable::Parse (neo/framework/DeclTable.cpp). Where it calls
// MakeDefault(), the values are the default definition's, as the engine's
// are. The copy of the 0 element it appends, for lerping, is not the decl's
// text and is not kept.
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
    float v;

    BOOL snap = NO;
    BOOL clamp = NO;
    NSMutableArray<UDTableValue *> *values = [NSMutableArray array];

    while (1) {
        if (![src readToken:&token error:NULL]) {
            break;
        }

        if (!strcmp(token.text, "}")) {
            break;
        }

        if (!strcasecmp(token.text, "snap")) {
            snap = YES;
        } else if (!strcasecmp(token.text, "clamp")) {
            clamp = YES;
        } else if (!strcasecmp(token.text, "{")) {

            while (1) {
                if (![src parseFloat:&v error:NULL]) {
                    // we got something non-numeric
                    return UDDefaultTableValues();
                }

                [values addObject:[UDTableValue valueWithNumber:v]];

                [src readToken:&token error:NULL];
                if (!strcmp(token.text, "}")) {
                    break;
                }
                if (!strcmp(token.text, ",")) {
                    continue;
                }
                [src warning:@"expected comma or brace"];
                return UDDefaultTableValues();
            }

        } else {
            [src warning:@"unknown token '%s'", token.text];
            return UDDefaultTableValues();
        }
    }

    return @{
        @"snap": @(snap),
        @"clamp": @(clamp),
        @"values": values,
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
    for (UDTableValue *value in values[@"values"]) {
        [numbers addObject:[NSString stringWithFormat:@"%g", value.number]];
    }
    [out appendFormat:@"\t{ %@ }\n", [numbers componentsJoinedByString:@", "]];
    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

/*
===================
idDeclTable::TableLookup
===================
*/
+ (float)ud_lookup:(float)index inTableNamed:(NSString *)name declManager:(idDeclManager *)declManager {
    NSDictionary *parsed = nil;
    idDeclBase *base = [declManager findDeclWithoutParsing:DECL_TABLE name:name makeDefault:NO];
    if ( base != nil ) {
        NSMutableData *buffer = [NSMutableData data];
        [base text:buffer];
        if ( buffer.length > 0 ) [buffer setLength:buffer.length - 1];
        parsed = [self ud_parseValuesFromText:buffer name:name fileName:nil lineNum:1 fileSystem:nil error:NULL];
    }
    NSArray *read = [parsed[@"values"] valueForKey:@"number"] ?: @[];
    BOOL clamp = [parsed[@"clamp"] boolValue];
    BOOL snap = [parsed[@"snap"] boolValue];
    // copy the 0 element to the end, so lerping doesn't
    // need to worry about the wrap case (idDeclTable::Parse)
    NSMutableArray<NSNumber *> *values = [read mutableCopy];
    if ( values.count > 0 ) [values addObject:values[0]];

    int iIndex;
    float iFrac;

    int domain = (int)values.count - 1;

    if ( domain <= 1 ) {
        return 1.0f;
    }

    if ( clamp ) {
        index *= (domain-1);
        if ( index >= domain - 1 ) {
            return values[domain - 1].floatValue;
        } else if ( index <= 0 ) {
            return values[0].floatValue;
        }
        iIndex = (int)index;                                       // idMath::Ftoi
        iFrac = index - iIndex;
    } else {
        index *= domain;

        if ( index < 0 ) {
            index += domain * ceilf( -index / domain );
        }

        iIndex = (int)floorf( index );                              // idMath::FtoiFast( idMath::Floor( index ) )
        iFrac = index - iIndex;
        iIndex = iIndex % domain;
    }

    if ( !snap ) {
        // we duplicated the 0 index at the end at creation time, so we
        // don't need to worry about wrapping the filter
        return values[iIndex].floatValue * ( 1.0f - iFrac ) + values[iIndex + 1].floatValue * iFrac;
    }

    return values[iIndex].floatValue;
}

@end
