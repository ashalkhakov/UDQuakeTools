/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclSkin.m — skins (idDeclSkin).
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclSkin.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

@implementation UDSkinMapping

+ (instancetype)mappingFrom:(NSString *)from to:(NSString *)to {
    UDSkinMapping *mapping = [[self alloc] init];
    mapping->_from = [from copy];
    mapping->_to = [to copy];
    return mapping;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] mappingFrom:_from to:_to];
}

- (void)setFrom:(NSString *)from {
    UDSkinMapping *edited = [self copy];
    edited->_from = [from copy];
    if (![self ud_replaceInOwnerWith:edited]) {
        _from = [from copy];
    }
}

- (void)setTo:(NSString *)to {
    UDSkinMapping *edited = [self copy];
    edited->_to = [to copy];
    if (![self ud_replaceInOwnerWith:edited]) {
        _to = [to copy];
    }
}

- (BOOL)validateFrom:(id *)ioValue error:(NSError **)error {
    return UDValidateName(ioValue, @"material", error);
}

- (BOOL)validateTo:(id *)ioValue error:(NSError **)error {
    return UDValidateName(ioValue, @"material", error);
}

@end

@implementation UDSkinModel

+ (instancetype)modelWithPath:(NSString *)path {
    UDSkinModel *model = [[self alloc] init];
    model->_path = [path copy];
    return model;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] modelWithPath:_path];
}

- (void)setPath:(NSString *)path {
    UDSkinModel *edited = [self copy];
    edited->_path = [path copy];
    if (![self ud_replaceInOwnerWith:edited]) {
        _path = [path copy];
    }
}

- (BOOL)validatePath:(id *)ioValue error:(NSError **)error {
    return UDValidateName(ioValue, @"model path", error);
}

@end

#pragma mark - DeclSkin

@implementation UDDeclSkin

@dynamic mappings;
@dynamic associatedModels;

UD_ELEMENT_ARRAY_SETTER(setMappings, @"mappings")
UD_ELEMENT_ARRAY_SETTER(setAssociatedModels, @"associatedModels")

// mappings and associatedModels are transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSDictionary *parsed = UDParsedSourceText(self);
    NSArray *mappings = parsed[@"mappings"] ?: @[];
    NSArray *models = parsed[@"associatedModels"] ?: @[];
    [self setPrimitiveValue:mappings forKey:@"mappings"];
    [self setPrimitiveValue:models forKey:@"associatedModels"];
    UDAdoptElements(mappings, self, @"mappings");
    UDAdoptElements(models, self, @"associatedModels");
}

+ (NSString *)ud_defaultDefinition {
    return
    @"{\n"
    @"\t"    @"\"*\"\t\"_default\"\n"
    @"}";
}

// A port of idDeclSkin::Parse (neo/framework/DeclSkin.cpp): the mappings,
// "from to" a line ("*" the wildcard from), and the associated models. Where
// it calls MakeDefault(), the values are the default definition's.
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

    NSMutableArray<UDSkinMapping *> *mappings = [NSMutableArray array];
    NSMutableArray<UDSkinModel *> *associatedModels = [NSMutableArray array];

    while (1) {
        if (![src readToken:&token error:NULL]) {
            break;
        }

        if (!strcasecmp(token.text, "}")) {
            break;
        }
        if (![src readToken:&token2 error:NULL]) {
            [src warning:@"Unexpected end of file"];
            return @{ @"mappings": @[[UDSkinMapping mappingFrom:@"*" to:@"_default"]], @"associatedModels": @[] };
        }

        if (!strcasecmp(token.text, "model")) {
            [associatedModels addObject:[UDSkinModel modelWithPath:UDTokenString(&token2)]];
            continue;
        }

        NSString *from = !strcasecmp(token.text, "*") ? @"*" /* wildcard */ : UDTokenString(&token);
        [mappings addObject:[UDSkinMapping mappingFrom:from to:UDTokenString(&token2)]];
    }

    return @{
        @"mappings": mappings,
        @"associatedModels": associatedModels,
    };
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"skin %@ {\n", name];

    for (UDSkinModel *model in values[@"associatedModels"]) {
        if (model.path.length > 0) {
            [out appendFormat:@"\tmodel %@\n", model.path];
        }
    }

    for (UDSkinMapping *mapping in values[@"mappings"]) {
        if (mapping.from.length > 0 && mapping.to.length > 0) {
            [out appendFormat:@"\t%@ %@\n", mapping.from, mapping.to];
        }
    }

    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end
