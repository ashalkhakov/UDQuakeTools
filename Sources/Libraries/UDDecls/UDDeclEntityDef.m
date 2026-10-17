/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclEntityDef.m — entityDefs and mapDefs (idDeclEntityDef).
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclEntityDef.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

#pragma mark - entityDef and mapDef

@implementation UDEntityKeyValue

+ (instancetype)keyValueWithKey:(NSString *)key value:(NSString *)value {
    UDEntityKeyValue *pair = [[self alloc] init];
    pair->_key = [key copy];
    pair->_value = [value copy];
    return pair;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] keyValueWithKey:_key value:_value];
}

- (void)setKey:(NSString *)key {
    UDEntityKeyValue *edited = [self copy];
    edited->_key = [key copy];
    if (![self ud_replaceInOwnerWith:edited]) {
        _key = [key copy];
    }
}

- (void)setValue:(NSString *)value {
    UDEntityKeyValue *edited = [self copy];
    edited->_value = [value copy];
    if (![self ud_replaceInOwnerWith:edited]) {
        _value = [value copy];
    }
}

// Both are quoted strings, and the decl lexer has no escapes in them: a
// '"' cannot be in one, nor a line break. A key is not empty.
static BOOL UDValidateQuotable(id *ioValue, NSString *what, BOOL mayBeEmpty, NSError **error) {
    NSString *text = *ioValue == nil ? @"" : [*ioValue isKindOfClass:[NSString class]] ? *ioValue : [*ioValue description];
    NSString *problem = nil;
    if (!mayBeEmpty && text.length == 0) {
        problem = [NSString stringWithFormat:@"A %@ is not empty.", what];
    } else if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"\r\n"]].location != NSNotFound) {
        problem = [NSString stringWithFormat:@"A %@ is a quoted string: no '\"' in it, and one line.", what];
    }
    if (problem == nil) {
        *ioValue = text;
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclElement" code:1 userInfo:@{NSLocalizedDescriptionKey: problem}];
    }
    return NO;
}

- (BOOL)validateKey:(id *)ioValue error:(NSError **)error {
    return UDValidateQuotable(ioValue, @"key", NO, error);
}

- (BOOL)validateValue:(id *)ioValue error:(NSError **)error {
    return UDValidateQuotable(ioValue, @"value", YES, error);
}

@end

@implementation UDInheritedKeyValue

- (instancetype)initWithKey:(NSString *)key value:(NSString *)value from:(NSString *)from {
    self = [super init];
    if (self) {
        _key = [key copy];
        _value = [value copy];
        _from = [from copy];
    }
    return self;
}

@end

@implementation UDDeclEntityDef

@dynamic keyValues;

UD_ELEMENT_ARRAY_SETTER(setKeyValues, @"keyValues")

// keyValues is transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSArray *keyValues = UDParsedSourceText(self)[@"keyValues"] ?: @[];
    [self setPrimitiveValue:keyValues forKey:@"keyValues"];
    UDAdoptElements(keyValues, self, @"keyValues");
}

// idDeclEntityDef::DefaultDefinition
+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"\"DEFAULTED\"\t\"1\"\n"
        @"}";
}

static NSUInteger UDIndexOfKey(NSArray<UDEntityKeyValue *> *pairs, NSString *key) {
    for (NSUInteger i = 0; i < pairs.count; i++) {
        if ([pairs[i].key caseInsensitiveCompare:key] == NSOrderedSame) return i;
    }
    return NSNotFound;
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingInherit {
    return [NSSet setWithObject:@"keyValues"];
}

- (NSString *)inherit {
    NSArray<UDEntityKeyValue *> *pairs = self.keyValues;
    NSUInteger index = UDIndexOfKey(pairs, @"inherit");
    return index == NSNotFound ? nil : pairs[index].value;
}

- (void)setInherit:(NSString *)inherit {
    NSMutableArray<UDEntityKeyValue *> *pairs = [self.keyValues mutableCopy] ?: [NSMutableArray array];
    NSUInteger index = UDIndexOfKey(pairs, @"inherit");
    if (inherit.length == 0) {
        if (index == NSNotFound) return;
        [pairs removeObjectAtIndex:index];
    } else if (index == NSNotFound) {
        [pairs insertObject:[UDEntityKeyValue keyValueWithKey:@"inherit" value:inherit] atIndex:0];
    } else if ([pairs[index].value isEqualToString:inherit]) {
        return;
    } else {
        pairs[index] = [UDEntityKeyValue keyValueWithKey:pairs[index].key value:inherit];
    }
    self.keyValues = pairs;
}

- (BOOL)validateInherit:(id *)ioValue error:(NSError **)error {
    return UDValidateQuotable(ioValue, @"name", YES, error);
}

/// The pairs, as idDict holds them: the last value of a key set twice.
static NSMutableDictionary<NSString *, NSString *> *UDDictOfPairs(NSArray<UDEntityKeyValue *> *pairs, NSMutableArray<NSString *> *order) {
    NSMutableDictionary<NSString *, NSString *> *dict = [NSMutableDictionary dictionary];
    for (UDEntityKeyValue *pair in pairs) {
        NSString *lower = pair.key.lowercaseString;
        if (dict[lower] == nil) [order addObject:pair.key];
        dict[lower] = pair.value ?: @"";
    }
    return dict;
}

/// idDeclEntityDef::Parse's merge: the decl's dict, its "inherit…" keys
/// taken out, each one's entityDef (resolved the same way) setting the
/// keys not yet set. @a from names where each inherited key came from.
- (NSMutableDictionary<NSString *, NSString *> *)ud_resolvedDictOrder:(NSMutableArray<NSString *> *)order
                                                                  from:(NSMutableDictionary<NSString *, NSString *> *)from
                                                               unknown:(NSMutableArray<NSString *> *)unknown
                                                               visited:(NSMutableSet<NSString *> *)visited {
    NSMutableDictionary<NSString *, NSString *> *dict = UDDictOfPairs(self.keyValues, order);
    NSMutableArray<NSString *> *parents = [NSMutableArray array];
    for (NSString *key in [order copy]) {
        if (![key.lowercaseString hasPrefix:@"inherit"]) continue;
        [parents addObject:dict[key.lowercaseString]];
        [dict removeObjectForKey:key.lowercaseString];
        [order removeObject:key];
    }
    for (NSString *parentName in parents) {
        UDDeclEntityDef *parent = [[self ud_store] ud_existingDeclOfTypeName:@"entityDef" named:parentName
                                                                    inContext:self.managedObjectContext];
        if (![parent isKindOfClass:[UDDeclEntityDef class]]) {
            [unknown addObject:parentName];
            continue;
        }
        if ([visited containsObject:parentName.lowercaseString]) continue;  // each is parsed once
        [visited addObject:parentName.lowercaseString];
        NSMutableArray<NSString *> *parentOrder = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSString *> *parentFrom = [NSMutableDictionary dictionary];
        NSMutableDictionary *parentDict = [parent ud_resolvedDictOrder:parentOrder from:parentFrom unknown:[NSMutableArray array] visited:visited];
        for (NSString *key in parentOrder) {
            NSString *lower = key.lowercaseString;
            if (dict[lower] != nil) continue;                       // SetDefaults
            dict[lower] = parentDict[lower];
            [order addObject:key];
            from[lower] = parentFrom[lower] ?: parent.name;
        }
    }
    return dict;
}

- (NSArray<UDInheritedKeyValue *> *)ud_inheritedKeyValuesUnknown:(NSArray<NSString *> **)unknown {
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *from = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *unknownNames = [NSMutableArray array];
    NSMutableDictionary *dict = [self ud_resolvedDictOrder:order from:from unknown:unknownNames
                                                    visited:[NSMutableSet setWithObject:self.name.lowercaseString ?: @""]];
    NSMutableArray<UDInheritedKeyValue *> *inherited = [NSMutableArray array];
    for (NSString *key in order) {
        NSString *source = from[key.lowercaseString];
        if (source == nil) continue;                                // its own
        [inherited addObject:[[UDInheritedKeyValue alloc] initWithKey:key value:dict[key.lowercaseString] from:source]];
    }
    if (unknown != NULL) *unknown = unknownNames;
    return inherited;
}

/// The resolved dict's values for keys with @a prefix, in order.
- (NSArray<NSString *> *)ud_valuesWithPrefix:(NSString *)prefix {
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary *dict = [self ud_resolvedDictOrder:order from:[NSMutableDictionary dictionary]
                                                    unknown:[NSMutableArray array]
                                                    visited:[NSMutableSet setWithObject:self.name.lowercaseString ?: @""]];
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSString *key in order) {
        if ([key.lowercaseString hasPrefix:prefix.lowercaseString]) [values addObject:dict[key.lowercaseString]];
    }
    return values;
}

// EClass_InitFromDict: "concatenate all editor usage comments".
- (NSString *)ud_usage {
    NSMutableString *text = [NSMutableString string];
    for (NSString *value in [self ud_valuesWithPrefix:@"editor_usage"]) {
        [text appendString:value];
        if (value.length == 0 || ![text hasSuffix:@"\n"]) [text appendString:@"\n"];
    }
    return text.length > 0 ? [text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] : nil;
}

// EClass_InitFromDict's EvarPrefixes: a spawnArg's description, by its type.
/// The editor_* keys' types, in the order Radiant looks for them.
static NSArray<NSString *> *UDEditorKeyTypes(void) {
    return @[@"var", @"int", @"float", @"bool", @"color", @"mat", @"model", @"gui", @"snd"];
}

/// The first editor_<type> key's type and help, of the decl or what it
/// inherits, for @a key.
- (nullable NSString *)ud_editorKey:(NSString *)key type:(NSString * _Nullable * _Nullable)type {
    NSMutableDictionary *dict = [self ud_resolvedDictOrder:[NSMutableArray array] from:[NSMutableDictionary dictionary]
                                                    unknown:[NSMutableArray array]
                                                    visited:[NSMutableSet setWithObject:self.name.lowercaseString ?: @""]];
    for (NSString *kind in UDEditorKeyTypes()) {
        NSString *help = dict[[NSString stringWithFormat:@"editor_%@ %@", kind, key].lowercaseString];
        if (help != nil) {
            if (type != NULL) *type = kind;
            return help;
        }
    }
    return nil;
}

- (NSString *)ud_helpForKey:(NSString *)key {
    return [self ud_editorKey:key type:NULL];
}

- (NSString *)ud_editorTypeForKey:(NSString *)key {
    NSString *type = nil;
    [self ud_editorKey:key type:&type];
    return type;
}

// DialogEntityDefEditor::PopulateLists: idDeclEntityDef::Parse's reading of
// the pairs, which stops (as the editor did, where the engine made the decl
// a default) at what is not a quoted key.
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

    NSMutableArray<UDEntityKeyValue *> *pairs = [NSMutableArray array];
    while (1) {
        if (![src readToken:&token error:NULL]) {
            break;
        }
        if (!strcasecmp(token.text, "}")) {
            break;
        }
        if (token.type != TT_STRING) {
            [src warning:@"Expected quoted string, but found '%s'", token.text];
            break;
        }
        if (![src readToken:&token2 error:NULL]) {
            [src warning:@"Unexpected end of file"];
            break;
        }
        NSString *key = UDTokenString(&token);
        NSUInteger index = UDIndexOfKey(pairs, key);
        UDEntityKeyValue *pair = [UDEntityKeyValue keyValueWithKey:key value:UDTokenString(&token2)];
        if (index != NSNotFound) {
            [src warning:@"'%s' already defined", token.text];
            pairs[index] = pair;                                    // idDict::Set
        } else {
            [pairs addObject:pair];
        }
    }
    return @{ @"keyValues": pairs };
}

// DialogEntityDefEditor::BuildDeclText's layout, a pair a line.
+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"%@ %@\n{\n", [self ud_typeName], name];
    for (UDEntityKeyValue *pair in values[@"keyValues"]) {
        if (pair.key.length == 0) continue;
        [out appendFormat:@"\"%@\"\t\t\t\"%@\"\n", pair.key, pair.value ?: @""];
    }
    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSString *)ud_typeName {
    return @"entityDef";
}

@end

// A mapDef is an idDeclEntityDef too.
@implementation UDDeclMapDef

+ (NSString *)ud_typeName {
    return @"mapDef";
}

@end
