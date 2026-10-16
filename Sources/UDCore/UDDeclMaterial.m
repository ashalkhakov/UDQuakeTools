/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclMaterial.m — materials (idMaterial), kept as their tokens.
 */

// AppKit (UDWorkspace.h) before Core Data: GNUstep's NSPredicateEditorRowTemplate.h
// defines Core Data's attribute types when Core Data is not yet in.
#import "UDWorkspace.h"
#import "UDDeclMaterial.h"
#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "UDMaterialParser.h"
#import "UDSourceTokens.h"
#import "idDeclManager.h"
#import "idFileSystem.h"
#import <objc/runtime.h>

static NSString *const UDMaterialKeywordLeading = @"\n\t";
static NSString *const UDStageKeywordLeading = @"\n\t\t";

#pragma mark - Keys

// What a key is: a value (its keyword's, as the parse read it), a flag (its
// keyword there or not), or one of (the first of its keywords there).
typedef NS_ENUM(NSInteger, UDMaterialKeyKind) {
    UDMaterialKeyValue,
    UDMaterialKeyQuotedValue,
    UDMaterialKeyFlag,
    UDMaterialKeyOneOf,
};

@interface UDMaterialKey : NSObject
@property (nonatomic) UDMaterialKeyKind kind;
@property (nonatomic, copy) NSArray<NSString *> *keywords;
@end

@implementation UDMaterialKey
@end

static UDMaterialKey *UDKey(UDMaterialKeyKind kind, NSArray<NSString *> *keywords) {
    UDMaterialKey *key = [[UDMaterialKey alloc] init];
    key.kind = kind;
    key.keywords = keywords;
    return key;
}

// ParseMaterial's keywords.
static NSDictionary<NSString *, UDMaterialKey *> *UDMaterialKeys(void) {
    static NSDictionary *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *table = [NSMutableDictionary dictionary];
        table[@"materialDescription"] = UDKey(UDMaterialKeyQuotedValue, @[@"description"]);
        table[@"qerEditorImage"] = UDKey(UDMaterialKeyValue, @[@"qer_editorimage"]);
        for (NSString *keyword in @[@"sort", @"deform", @"decalInfo", @"renderbump", @"guisurf", @"spectrum", @"lightFalloffImage"]) {
            table[keyword] = UDKey(UDMaterialKeyValue, @[keyword]);
        }
        table[@"surfaceType"] = UDKey(UDMaterialKeyOneOf, @[@"metal", @"stone", @"flesh", @"wood", @"cardboard", @"liquid",
                                                             @"glass", @"plastic", @"ricochet", @"surftype10", @"surftype11",
                                                             @"surftype12", @"surftype13", @"surftype14", @"surftype15"]);
        table[@"clampMode"] = UDKey(UDMaterialKeyOneOf, @[@"clamp", @"zeroclamp", @"alphazeroclamp"]);
        NSDictionary<NSString *, NSString *> *flags = @{
            @"noShadows": @"noShadows", @"noSelfShadow": @"noSelfShadow", @"forceShadows": @"forceShadows",
            @"twoSided": @"twoSided", @"backSided": @"backSided", @"translucent": @"translucent",
            @"forceOpaque": @"forceOpaque", @"forceOverlays": @"forceOverlays", @"noOverlays": @"noOverlays",
            @"noFog": @"noFog", @"noPortalFog": @"noPortalFog", @"fogLight": @"fogLight", @"blendLight": @"blendLight",
            @"ambientLight": @"ambientLight", @"mirror": @"mirror", @"unsmoothedTangents": @"unsmoothedTangents",
            @"suppressInSubview": @"suppressInSubview", @"portalSky": @"portalSky", @"polygonOffset": @"polygonOffset",
            @"decalMacro": @"DECAL_MACRO",
            // CheckSurfaceParm's infoParms, but the surface types
            @"solid": @"solid", @"water": @"water", @"playerclip": @"playerclip", @"monsterclip": @"monsterclip",
            @"moveableclip": @"moveableclip", @"ikclip": @"ikclip", @"blood": @"blood", @"trigger": @"trigger",
            @"aassolid": @"aassolid", @"aasobstacle": @"aasobstacle", @"flashlightTrigger": @"flashlight_trigger",
            @"nonsolid": @"nonsolid", @"nullNormal": @"nullNormal", @"areaportal": @"areaportal",
            @"qerNoCarve": @"qer_nocarve", @"discrete": @"discrete", @"noFragment": @"noFragment", @"slick": @"slick",
            @"collision": @"collision", @"noimpact": @"noimpact", @"nodamage": @"nodamage", @"ladder": @"ladder",
            @"nosteps": @"nosteps"};
        for (NSString *key in flags) table[key] = UDKey(UDMaterialKeyFlag, @[flags[key]]);
        keys = table;
    });
    return keys;
}

// ParseStage's keywords.
static NSDictionary<NSString *, UDMaterialKey *> *UDStageKeys(void) {
    static NSDictionary *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *table = [NSMutableDictionary dictionary];
        table[@"name"] = UDKey(UDMaterialKeyQuotedValue, @[@"name"]);
        table[@"condition"] = UDKey(UDMaterialKeyValue, @[@"if"]);
        for (NSString *keyword in @[@"blend", @"map", @"cubeMap", @"cameraCubeMap", @"videomap", @"soundmap",
                                    @"remoteRenderMap", @"mirrorRenderMap", @"xrayRenderMap", @"texGen", @"scroll",
                                    @"translate", @"scale", @"centerScale", @"shear", @"rotate", @"color", @"red",
                                    @"green", @"blue", @"alpha", @"rgb", @"rgba", @"alphaTest", @"program",
                                    @"vertexProgram", @"fragmentProgram", @"megaTexture"]) {
            table[keyword] = UDKey(UDMaterialKeyValue, @[keyword]);
        }
        table[@"filter"] = UDKey(UDMaterialKeyOneOf, @[@"nearest", @"linear"]);
        table[@"clampMode"] = UDKey(UDMaterialKeyOneOf, @[@"clamp", @"noclamp", @"zeroclamp", @"alphazeroclamp"]);
        for (NSString *keyword in @[@"ignoreAlphaTest", @"vertexColor", @"inverseVertexColor", @"colored", @"maskRed",
                                    @"maskGreen", @"maskBlue", @"maskAlpha", @"maskColor", @"maskDepth", @"ignoreDepth",
                                    @"uncompressed", @"highquality", @"forceHighQuality", @"nopicmip", @"screen",
                                    @"screen2", @"glassWarp", @"privatePolygonOffset"]) {
            table[keyword] = UDKey(UDMaterialKeyFlag, @[keyword]);
        }
        keys = table;
    });
    return keys;
}

static BOOL UDIsShortcutKeyword(NSString *keyword) {
    return keyword != nil && ([keyword caseInsensitiveCompare:@"diffusemap"] == NSOrderedSame ||
                              [keyword caseInsensitiveCompare:@"specularmap"] == NSOrderedSame ||
                              [keyword caseInsensitiveCompare:@"bumpmap"] == NSOrderedSame);
}

/// @a text as tokens, the first one's leading @a leading.
static NSArray<UDSourceToken *> *UDTokensOf(NSString *text) {
    return [UDSourceTokens tokensOfText:text flags:DECL_LEXER_FLAGS].tokens;
}

#pragma mark - What the parse says is where

/// A keyword the parse read: its tokens, [start, end), and what it read.
@interface UDMaterialItem : NSObject
@property (nonatomic, copy, nullable) NSString *keyword;
@property (nonatomic, copy, nullable) NSString *value;
@property (nonatomic) NSUInteger start;
@property (nonatomic) NSUInteger end;
@property (nonatomic) BOOL unparsed;
@end

@implementation UDMaterialItem
@end

/// A stage: its tokens, [start, end); its close brace's (NSNotFound when the
/// parse gave up in it); its keywords; or the shortcut keyword it is.
@interface UDMaterialStageRange : NSObject
@property (nonatomic) NSUInteger start;
@property (nonatomic) NSUInteger end;
@property (nonatomic) NSUInteger closeIndex;
@property (nonatomic, copy) NSArray<UDMaterialItem *> *items;
@property (nonatomic, strong, nullable) UDMaterialItem *shortcut;
@end

@implementation UDMaterialStageRange
@end

@interface UDMaterialStructure : NSObject
@property (nonatomic, copy) NSArray<UDMaterialItem *> *items;
@property (nonatomic, copy) NSArray<UDMaterialStageRange *> *stages;
/// The material's close brace's token (its tokens' count when it has none).
@property (nonatomic) NSUInteger closeIndex;
@end

@implementation UDMaterialStructure
@end

/// What idMaterial::Parse makes of @a tokens: which of them are which
/// keyword and stage.
static UDMaterialStructure *UDStructureOf(UDSourceTokens *tokens, NSString *name, idDeclManager *declManager) {
    UDMaterialParser *parser = [[UDMaterialParser alloc] initWithText:tokens.text name:name ?: @"" declManager:declManager];
    NSArray<NSNumber *> *offsets = tokens.byteOffsets;
    NSMutableDictionary<NSNumber *, NSNumber *> *indexOfOffset = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < tokens.tokens.count; i++) indexOfOffset[offsets[i]] = @(i);
    NSUInteger count = tokens.tokens.count;
    NSUInteger closeIndex = count > 0 && [tokens.tokens.lastObject.value isEqualToString:@"}"] ? count - 1 : count;

    NSUInteger (^indexOf)(NSInteger) = ^NSUInteger(NSInteger offset) {
        NSNumber *index = indexOfOffset[@(offset)];
        return index != nil ? index.unsignedIntegerValue : NSNotFound;
    };
    NSMutableArray<UDMaterialItem *> *items = [NSMutableArray array];
    NSMutableArray<UDMaterialStageRange *> *stages = [NSMutableArray array];
    NSArray<UDMaterialTextNode *> *body = parser.body;
    for (NSUInteger n = 0; n < body.count; n++) {
        UDMaterialTextNode *node = body[n];
        NSUInteger start = indexOf(node.leadingStart);
        NSUInteger end = n + 1 < body.count ? indexOf(body[n + 1].leadingStart) : closeIndex;
        if (start == NSNotFound || end == NSNotFound) continue;
        if (node.kind == UDMaterialTextStage) {
            UDMaterialStageRange *stage = [[UDMaterialStageRange alloc] init];
            stage.start = start;
            stage.closeIndex = node.closed ? indexOf(node.closingStart) : NSNotFound;
            stage.end = stage.closeIndex != NSNotFound ? stage.closeIndex + 1 : end;
            NSUInteger childrenEnd = stage.closeIndex != NSNotFound ? stage.closeIndex : end;
            NSMutableArray<UDMaterialItem *> *children = [NSMutableArray array];
            for (NSUInteger c = 0; c < node.children.count; c++) {
                UDMaterialTextNode *child = node.children[c];
                UDMaterialItem *item = [[UDMaterialItem alloc] init];
                item.keyword = child.keyword;
                item.value = child.value;
                item.unparsed = child.kind == UDMaterialTextUnparsed;
                item.start = indexOf(child.leadingStart);
                item.end = c + 1 < node.children.count ? indexOf(node.children[c + 1].leadingStart) : childrenEnd;
                if (item.start != NSNotFound && item.end != NSNotFound) [children addObject:item];
            }
            stage.items = children;
            [stages addObject:stage];
            continue;
        }
        UDMaterialItem *item = [[UDMaterialItem alloc] init];
        item.keyword = node.keyword;
        item.value = node.value;
        item.unparsed = node.kind == UDMaterialTextUnparsed;
        item.start = start;
        item.end = end;
        if (!item.unparsed && UDIsShortcutKeyword(item.keyword)) {
            UDMaterialStageRange *stage = [[UDMaterialStageRange alloc] init];
            stage.start = start;
            stage.end = end;
            stage.closeIndex = NSNotFound;
            stage.items = @[];
            stage.shortcut = item;
            [stages addObject:stage];
        } else {
            [items addObject:item];
        }
    }
    UDMaterialStructure *structure = [[UDMaterialStructure alloc] init];
    structure.items = items;
    structure.stages = stages;
    structure.closeIndex = closeIndex;
    return structure;
}

static BOOL UDItemIs(UDMaterialItem *item, NSString *keyword) {
    return !item.unparsed && item.keyword != nil && [item.keyword caseInsensitiveCompare:keyword] == NSOrderedSame;
}

/// @a key's value in @a items.
static id UDKeyValue(UDMaterialKey *key, NSArray<UDMaterialItem *> *items) {
    switch (key.kind) {
        case UDMaterialKeyValue:
        case UDMaterialKeyQuotedValue:
            for (UDMaterialItem *item in items) {
                if (UDItemIs(item, key.keywords[0])) return item.value ?: @"";
            }
            return nil;
        case UDMaterialKeyFlag:
            for (UDMaterialItem *item in items) {
                if (UDItemIs(item, key.keywords[0])) return @YES;
            }
            return @NO;
        case UDMaterialKeyOneOf:
            for (UDMaterialItem *item in items) {
                for (NSString *keyword in key.keywords) {
                    if (UDItemIs(item, keyword)) return keyword;
                }
            }
            return nil;
    }
    return nil;
}

/// @a tokens with @a key set to @a value among @a items: its first
/// keyword's value tokens changed, its keyword put in (at @a insertAt, after
/// @a leading) or taken out; for a flag or a one-of, its other keywords
/// taken out. A value's later keywords are their own (a second scroll
/// multiplies the first).
static NSArray<UDSourceToken *> *UDTokensSettingKey(UDMaterialKey *key, id value, NSArray<UDMaterialItem *> *items,
                                                   NSArray<UDSourceToken *> *tokens, NSUInteger insertAt, NSString *leading) {
    if (value == [NSNull null]) value = nil;
    NSString *newKeyword = nil, *newValue = nil;
    switch (key.kind) {
        case UDMaterialKeyValue:
        case UDMaterialKeyQuotedValue: {
            NSString *text = [[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (text.length > 0) {
                newKeyword = key.keywords[0];
                newValue = key.kind == UDMaterialKeyQuotedValue ? [NSString stringWithFormat:@"\"%@\"", text] : text;
            }
            break;
        }
        case UDMaterialKeyFlag:
            if ([value boolValue]) newKeyword = key.keywords[0];
            break;
        case UDMaterialKeyOneOf: {
            NSString *text = [value description];
            for (NSString *keyword in key.keywords) {
                if (text != nil && [keyword caseInsensitiveCompare:text] == NSOrderedSame) newKeyword = keyword;
            }
            break;
        }
    }
    BOOL isValue = key.kind == UDMaterialKeyValue || key.kind == UDMaterialKeyQuotedValue;

    NSMutableArray<UDMaterialItem *> *matching = [NSMutableArray array];
    for (UDMaterialItem *item in items) {
        for (NSString *keyword in key.keywords) {
            if (UDItemIs(item, keyword)) {
                [matching addObject:item];
                break;
            }
        }
    }
    NSMutableArray<UDSourceToken *> *result = [tokens mutableCopy];
    // The others first, from the back: the indexes before them stay.
    if (!isValue) {
        for (NSUInteger i = matching.count; i > 1; i--) {
            UDMaterialItem *other = matching[i - 1];
            [result removeObjectsInRange:NSMakeRange(other.start, other.end - other.start)];
        }
    }
    UDMaterialItem *first = matching.firstObject;
    if (first != nil) {
        if (newKeyword == nil) {
            [result removeObjectsInRange:NSMakeRange(first.start, first.end - first.start)];
        } else if (key.kind == UDMaterialKeyOneOf) {
            UDSourceToken *old = result[first.start];
            if (![old.value isEqualToString:newKeyword]) {
                result[first.start] = [UDSourceToken tokenWithLeading:old.leading text:newKeyword value:newKeyword];
            }
        } else if (isValue) {
            // The keyword as written; its value's tokens new.
            NSArray<UDSourceToken *> *valueTokens = UDTokensOf([@"\t" stringByAppendingString:newValue]);
            NSRange old = NSMakeRange(first.start + 1, first.end - first.start - 1);
            if (![[result subarrayWithRange:old] isEqualToArray:valueTokens] && ![first.value isEqualToString:[[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]) {
                [result replaceObjectsInRange:old withObjectsFromArray:valueTokens];
            }
        }
    } else if (newKeyword != nil) {
        NSString *text = newValue != nil ? [NSString stringWithFormat:@"%@%@\t%@", leading, newKeyword, newValue]
                                         : [leading stringByAppendingString:newKeyword];
        [result replaceObjectsInRange:NSMakeRange(MIN(insertAt, result.count), 0) withObjectsFromArray:UDTokensOf(text)];
    }
    return result;
}

#pragma mark - UDMaterialStage

@interface UDMaterialStage ()
+ (instancetype)stageOfMaterial:(UDDeclMaterial *)material index:(NSUInteger)index;
@end

@interface UDDeclMaterial (UDStructure)
- (UDMaterialStructure *)ud_structure;
- (void)ud_setTokenArray:(NSArray<UDSourceToken *> *)tokens;
- (id)ud_valueOfStage:(NSUInteger)index forKey:(NSString *)key;
- (void)ud_setValue:(id)value ofStage:(NSUInteger)index forKey:(NSString *)key;
- (NSString *)ud_textOfStage:(NSUInteger)index;
@end

@implementation UDMaterialStage

+ (instancetype)stageOfMaterial:(UDDeclMaterial *)material index:(NSUInteger)index {
    UDMaterialStage *stage = [[self alloc] init];
    stage->_material = material;
    stage->_index = index;
    return stage;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[UDMaterialStage class]]) return NO;
    UDMaterialStage *other = object;
    return other.material == self.material && other.index == self.index;
}

- (NSUInteger)hash {
    return self.index;
}

- (NSString *)shortcut {
    UDMaterialStructure *structure = [self.material ud_structure];
    return self.index < structure.stages.count ? structure.stages[self.index].shortcut.keyword : nil;
}

- (NSString *)text {
    return [self.material ud_textOfStage:self.index];
}

- (id)valueForKey:(NSString *)key {
    if (UDStageKeys()[key] != nil) return [self.material ud_valueOfStage:self.index forKey:key];
    return [super valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
    if (UDStageKeys()[key] != nil) {
        [self.material ud_setValue:value ofStage:self.index forKey:key];
        return;
    }
    [super setValue:value forKey:key];
}

@end

#pragma mark - UDDeclMaterial

@implementation UDDeclMaterial

@dynamic tokens;

static const void *UDStructureKey = &UDStructureKey;

+ (NSArray<NSString *> *)ud_materialValueKeys {
    return UDMaterialKeys().allKeys;
}

+ (NSArray<NSString *> *)ud_stageValueKeys {
    return UDStageKeys().allKeys;
}

// Its tokens set: its stages and every value of it change with them.
- (void)setTokens:(UDSourceTokens *)tokens {
    NSArray<NSString *> *keys = UDMaterialKeys().allKeys;
    for (NSString *key in keys) [self willChangeValueForKey:key];
    [self willChangeValueForKey:@"stages"];
    [self willChangeValueForKey:@"tokens"];
    [self setPrimitiveValue:tokens forKey:@"tokens"];
    [self didChangeValueForKey:@"tokens"];
    [self didChangeValueForKey:@"stages"];
    for (NSString *key in keys.reverseObjectEnumerator) [self didChangeValueForKey:key];
}

- (void)awakeFromFetch {
    [super awakeFromFetch];
    [self setPrimitiveValue:UDParsedSourceText(self)[@"tokens"] forKey:@"tokens"];
}

- (idDeclManager *)ud_declManager {
    return [self ud_store].declManager;
}

/// What the parse makes of its tokens as they are now.
- (UDMaterialStructure *)ud_structure {
    UDSourceTokens *tokens = self.tokens ?: [UDSourceTokens tokensWithTokens:@[] trailing:@""];
    NSArray *cached = objc_getAssociatedObject(self, UDStructureKey);
    if (cached != nil && cached[0] == tokens) return cached[1];
    UDMaterialStructure *structure = UDStructureOf(tokens, self.name, [self ud_declManager]);
    objc_setAssociatedObject(self, UDStructureKey, @[tokens, structure], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return structure;
}

- (void)ud_setTokenArray:(NSArray<UDSourceToken *> *)tokens {
    UDSourceTokens *current = self.tokens;
    if ([current.tokens isEqualToArray:tokens]) return;
    self.tokens = [UDSourceTokens tokensWithTokens:tokens trailing:current.trailing ?: @""];
}

- (NSArray<UDMaterialStage *> *)stages {
    NSUInteger count = [self ud_structure].stages.count;
    NSMutableArray<UDMaterialStage *> *stages = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [stages addObject:[UDMaterialStage stageOfMaterial:self index:i]];
    return stages;
}

- (id)valueForKey:(NSString *)key {
    UDMaterialKey *materialKey = UDMaterialKeys()[key];
    if (materialKey != nil) return UDKeyValue(materialKey, [self ud_structure].items);
    return [super valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
    UDMaterialKey *materialKey = UDMaterialKeys()[key];
    if (materialKey == nil) {
        [super setValue:value forKey:key];
        return;
    }
    UDMaterialStructure *structure = [self ud_structure];
    // A new keyword goes after the material's own before its first stage,
    // or after its open brace.
    NSUInteger firstStage = structure.stages.count > 0 ? structure.stages[0].start : structure.closeIndex;
    NSUInteger insertAt = 1;
    for (UDMaterialItem *item in structure.items) {
        if (item.start < firstStage && !item.unparsed) insertAt = item.end;
    }
    [self ud_setTokenArray:UDTokensSettingKey(materialKey, value, structure.items, self.tokens.tokens ?: @[],
                                              insertAt, UDMaterialKeywordLeading)];
}

#pragma mark - Stages

- (id)ud_valueOfStage:(NSUInteger)index forKey:(NSString *)key {
    UDMaterialStructure *structure = [self ud_structure];
    if (index >= structure.stages.count) return nil;
    UDMaterialStageRange *stage = structure.stages[index];
    if (stage.shortcut != nil) {
        // ParseMaterial's: "blend <its keyword>", "map <its image>".
        if ([key isEqualToString:@"blend"]) return stage.shortcut.keyword.lowercaseString;
        if ([key isEqualToString:@"map"]) return stage.shortcut.value;
        return UDStageKeys()[key].kind == UDMaterialKeyFlag ? @NO : nil;
    }
    return UDKeyValue(UDStageKeys()[key], stage.items);
}

- (void)ud_setValue:(id)value ofStage:(NSUInteger)index forKey:(NSString *)key {
    UDMaterialStructure *structure = [self ud_structure];
    if (index >= structure.stages.count) return;
    UDMaterialStageRange *stage = structure.stages[index];
    NSArray<UDSourceToken *> *tokens = self.tokens.tokens;
    if (stage.shortcut != nil) {
        if ([key isEqualToString:@"map"] && [[value description] length] > 0) {
            // Still a shortcut: its image's tokens.
            UDMaterialKey *mapKey = UDKey(UDMaterialKeyValue, @[stage.shortcut.keyword]);
            [self ud_setTokenArray:UDTokensSettingKey(mapKey, value, @[stage.shortcut], tokens, NSNotFound, @"")];
            return;
        }
        if ([key isEqualToString:@"blend"] && [[value description] caseInsensitiveCompare:stage.shortcut.keyword] == NSOrderedSame) {
            return;
        }
        // No longer one: the stage it stands for, as a stage, then the edit.
        UDSourceToken *first = tokens[stage.start];
        NSString *text = [NSString stringWithFormat:@"%@{%@blend\t%@%@map\t%@%@}", first.leading, UDStageKeywordLeading,
                          stage.shortcut.keyword.lowercaseString, UDStageKeywordLeading, stage.shortcut.value ?: @"",
                          UDMaterialKeywordLeading];
        NSMutableArray<UDSourceToken *> *expanded = [tokens mutableCopy];
        [expanded replaceObjectsInRange:NSMakeRange(stage.start, stage.end - stage.start) withObjectsFromArray:UDTokensOf(text)];
        [self ud_setTokenArray:expanded];
        [self ud_setValue:value ofStage:index forKey:key];
        return;
    }
    NSUInteger insertAt = stage.closeIndex != NSNotFound ? stage.closeIndex : stage.end;
    [self ud_setTokenArray:UDTokensSettingKey(UDStageKeys()[key], value, stage.items, tokens, insertAt, UDStageKeywordLeading)];
}

- (NSString *)ud_textOfStage:(NSUInteger)index {
    UDMaterialStructure *structure = [self ud_structure];
    if (index >= structure.stages.count) return @"";
    UDMaterialStageRange *stage = structure.stages[index];
    NSMutableString *text = [NSMutableString string];
    NSArray<UDSourceToken *> *tokens = self.tokens.tokens;
    for (NSUInteger i = stage.start; i < stage.end; i++) {
        if (i > stage.start) [text appendString:tokens[i].leading];
        [text appendString:tokens[i].text];
    }
    return text;
}

- (void)ud_insertStageText:(NSString *)text atIndex:(NSUInteger)index {
    UDMaterialStructure *structure = [self ud_structure];
    NSUInteger at = index < structure.stages.count ? structure.stages[index].start : structure.closeIndex;
    NSMutableArray<UDSourceToken *> *tokens = [self.tokens.tokens mutableCopy] ?: [NSMutableArray array];
    [tokens replaceObjectsInRange:NSMakeRange(MIN(at, tokens.count), 0)
             withObjectsFromArray:UDTokensOf([UDMaterialKeywordLeading stringByAppendingString:text])];
    [self ud_setTokenArray:tokens];
}

- (void)ud_removeStageAtIndex:(NSUInteger)index {
    UDMaterialStructure *structure = [self ud_structure];
    if (index >= structure.stages.count) return;
    UDMaterialStageRange *stage = structure.stages[index];
    NSMutableArray<UDSourceToken *> *tokens = [self.tokens.tokens mutableCopy];
    [tokens removeObjectsInRange:NSMakeRange(stage.start, stage.end - stage.start)];
    [self ud_setTokenArray:tokens];
}

- (void)ud_exchangeStageAtIndex:(NSUInteger)index withStageAtIndex:(NSUInteger)otherIndex {
    UDMaterialStructure *structure = [self ud_structure];
    if (index >= structure.stages.count || otherIndex >= structure.stages.count || index == otherIndex) return;
    UDMaterialStageRange *a = structure.stages[MIN(index, otherIndex)];
    UDMaterialStageRange *b = structure.stages[MAX(index, otherIndex)];
    NSArray<UDSourceToken *> *tokens = self.tokens.tokens;
    NSMutableArray<UDSourceToken *> *result = [NSMutableArray arrayWithCapacity:tokens.count];
    [result addObjectsFromArray:[tokens subarrayWithRange:NSMakeRange(0, a.start)]];
    [result addObjectsFromArray:[tokens subarrayWithRange:NSMakeRange(b.start, b.end - b.start)]];
    [result addObjectsFromArray:[tokens subarrayWithRange:NSMakeRange(a.end, b.start - a.end)]];
    [result addObjectsFromArray:[tokens subarrayWithRange:NSMakeRange(a.start, a.end - a.start)]];
    [result addObjectsFromArray:[tokens subarrayWithRange:NSMakeRange(b.end, tokens.count - b.end)]];
    [self ud_setTokenArray:result];
}

#pragma mark - The codec

// idMaterial::DefaultDefinition
+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"{\n"
        @"\t\t"        @"blend\tblend\n"
        @"\t\t"        @"map\t\t_default\n"
        @"\t"    @"}\n"
        @"}";
}

// Its body's tokens, from its open brace: the decl manager keeps the header
// as the file has it.
+ (NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)data
                                                    name:(NSString *)name
                                                fileName:(NSString *)fileName
                                                 lineNum:(int)lineNum
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError **)error {
    // The lexer finds the body's brace (and says what it finds wrong).
    if (UDDeclCodecLexer(data, name, fileName, lineNum, fileSystem, error) == nil) {
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?:
                     [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] ?: @"";
    UDSourceTokens *all = [UDSourceTokens tokensOfText:text flags:DECL_LEXER_FLAGS];
    NSUInteger brace = NSNotFound;
    for (NSUInteger i = 0; i < all.tokens.count; i++) {
        if ([all.tokens[i].value isEqualToString:@"{"]) {
            brace = i;
            break;
        }
    }
    if (brace == NSNotFound) return nil;
    NSMutableArray<UDSourceToken *> *body = [[all.tokens subarrayWithRange:NSMakeRange(brace, all.tokens.count - brace)] mutableCopy];
    body[0] = [UDSourceToken tokenWithLeading:@"" text:body[0].text value:body[0].value];
    return @{@"tokens": [UDSourceTokens tokensWithTokens:body trailing:all.trailing]};
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    UDSourceTokens *tokens = values[@"tokens"];
    NSString *text = tokens != nil ? tokens.text : [self ud_defaultDefinition];
    // The decl's text ends with its close brace.
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSArray<UDDeclTextProblem *> *)ud_problemsParsingText:(NSString *)text name:(NSString *)name declManager:(idDeclManager *)declManager {
    return [[UDMaterialParser alloc] initWithText:text name:name declManager:declManager].problems;
}

+ (NSArray<UDDeclTextProblem *> *)ud_problemsParsingText:(NSString *)text name:(NSString *)name fileSystem:(idFileSystem *)fileSystem {
    return [self ud_problemsParsingText:text name:name declManager:fileSystem.workspace.declManager];
}

@end
