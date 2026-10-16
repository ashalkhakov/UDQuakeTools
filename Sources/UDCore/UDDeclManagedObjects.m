/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclManagedObjects.m
 *
 * The decl entity classes and their text codecs. The parse/unparse logic in
 * this file is ported from the former idDecl* subclasses (idDeclPDA.m,
 * idDeclTable.m, idDeclSkin.m, idDeclParticle.m), reworked to read/produce
 * codec value dictionaries instead of mutating typed decl objects.
 */

#import "UDDeclManagedObjects.h"
#import <objc/runtime.h>

#import "UDDeclIncrementalStore.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"
#import "UDDeclTextChecker.h"

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

@interface UDDeclBase (UDStore)
- (nullable UDDeclIncrementalStore *)ud_store;
@end

static void UDAdoptElements(NSArray *elements, UDDeclBase *owner, NSString *key);

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

// While a parse is tested, the diagnostics its lexers collect into.
static NSString *const UDDeclCodecDiagnosticsKey = @"UDDeclCodecDiagnostics";

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

@synthesize ud_sourceTextEdited = _ud_sourceTextEdited;

// Handwritten so a public assignment (the text editor's save path) can be
// told apart from -awakeFromFetch's setPrimitiveValue: population, which
// FreeCoreData also surfaces in -changedValues. Equivalent to the
// generated setter otherwise (Apple's documented accessor pattern).
- (void)setSourceText:(NSData *)sourceText {
    [self willChangeValueForKey:@"sourceText"];
    [self setPrimitiveValue:[sourceText copy] forKey:@"sourceText"];
    [self didChangeValueForKey:@"sourceText"];
    self.ud_sourceTextEdited = YES;
}

- (void)didSave {
    [super didSave];
    self.ud_sourceTextEdited = NO;
}

// A new decl is its type's DefaultDefinition, as idDeclManager::CreateNewDecl
// makes one: what its parser reads of it. (Its lists, empty without one.)
- (void)awakeFromInsert {
    [super awakeFromInsert];
    NSData *text = [[[self class] ud_defaultDefinition] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *values = [[self class] ud_parseValuesFromText:text name:@"" fileName:nil lineNum:1 fileSystem:nil error:NULL];
    for (NSAttributeDescription *attribute in self.entity.attributesByName.allValues) {
        if ([attribute.name isEqualToString:@"name"] || [attribute.name isEqualToString:@"sourceText"]) continue;
        id value = values[attribute.name];
        if (value == [NSNull null]) value = nil;
        if (value == nil && attribute.isTransient) value = @[];
        if (value == nil) continue;
        [self setPrimitiveValue:value forKey:attribute.name];
        if ([value isKindOfClass:[NSArray class]]) UDAdoptElements(value, self, attribute.name);
    }
}

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

- (UDDeclIncrementalStore *)ud_store {
    id store = self.objectID.persistentStore ?: self.managedObjectContext.persistentStoreCoordinator.persistentStores.firstObject;
    return [store isKindOfClass:[UDDeclIncrementalStore class]] ? store : nil;
}

- (NSData *)ud_currentText:(NSError **)error {
    return [[self ud_store] ud_textForDeclObject:self error:error];
}

- (BOOL)ud_applyText:(NSData *)text error:(NSError **)error {
    UDDeclIncrementalStore *store = [self ud_store];
    return store != nil && [store ud_applyText:text toDeclObject:self error:error];
}

+ (NSArray<UDDeclTextProblem *> *)ud_problemsParsingText:(NSString *)text
                                                    name:(NSString *)name
                                              fileSystem:(idFileSystem *)fileSystem {
    NSMutableArray<NSDictionary *> *diagnostics = [NSMutableArray array];
    NSMutableDictionary *threadDictionary = [NSThread currentThread].threadDictionary;
    threadDictionary[UDDeclCodecDiagnosticsKey] = diagnostics;
    NSError *error = nil;
    NSDictionary *values = [self ud_parseValuesFromText:[text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]
                                                   name:name fileName:nil lineNum:1
                                             fileSystem:fileSystem error:&error];
    [threadDictionary removeObjectForKey:UDDeclCodecDiagnosticsKey];

    NSMutableArray<UDDeclTextProblem *> *problems = [NSMutableArray array];
    for (NSDictionary *diagnostic in diagnostics) {
        [problems addObject:[[UDDeclTextProblem alloc] initWithLine:[diagnostic[@"line"] integerValue]
                                                            message:diagnostic[@"message"]
                                                            isError:[diagnostic[@"error"] boolValue]]];
    }
    // A parser's own failure, when its lexer said nothing of it.
    if (values == nil && error != nil && diagnostics.count == 0) {
        [problems addObject:[[UDDeclTextProblem alloc] initWithLine:1 message:error.localizedDescription isError:YES]];
    }
    return problems;
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
    self.ud_sourceTextEdited = NO;
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

#pragma mark - Raw text only, until their editors arrive



// idDeclAF::DefaultDefinition
@implementation UDDeclAF

+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"settings {\n"
        @"\t\t"        @"model \"\"\n"
        @"\t\t"        @"skin \"\"\n"
        @"\t\t"        @"friction 0.01, 0.01, 0.8, 0.5\n"
        @"\t\t"        @"suspendSpeed 20, 30, 40, 60\n"
        @"\t\t"        @"noMoveTime 1\n"
        @"\t\t"        @"noMoveTranslation 10\n"
        @"\t\t"        @"noMoveRotation 10\n"
        @"\t\t"        @"minMoveTime -1\n"
        @"\t\t"        @"maxMoveTime -1\n"
        @"\t\t"        @"totalMass -1\n"
        @"\t\t"        @"contents corpse\n"
        @"\t\t"        @"clipMask solid, corpse\n"
        @"\t\t"        @"selfCollision 1\n"
        @"\t"    @"}\n"
        @"\t"    @"body \"body\" {\n"
        @"\t\t"        @"joint \"origin\"\n"
        @"\t\t"        @"mod orientation\n"
        @"\t\t"        @"model box( ( -10, -10, -10 ), ( 10, 10, 10 ) )\n"
        @"\t\t"        @"origin ( 0, 0, 0 )\n"
        @"\t\t"        @"density 0.2\n"
        @"\t\t"        @"friction 0.01, 0.01, 0.8\n"
        @"\t\t"        @"contents corpse\n"
        @"\t\t"        @"clipMask solid, corpse\n"
        @"\t\t"        @"selfCollision 1\n"
        @"\t\t"        @"containedJoints \"*origin\"\n"
        @"\t"    @"}\n"
        @"}\n";
}

@end

// idDeclModelDef::DefaultDefinition
@implementation UDDeclModel

+ (NSString *)ud_defaultDefinition {
    return @"{ }";
}

@end

// An export is a plain idDecl: idDeclLocal::DefaultDefinition.
@implementation UDDeclExport

+ (NSString *)ud_defaultDefinition {
    return @"{ }";
}

@end

#pragma mark - DeclTable

#pragma mark - Elements

/// Each element of @a elements is @a owner's, under @a key.
static void UDAdoptElements(NSArray *elements, UDDeclBase *owner, NSString *key) {
    for (UDDeclElement *element in elements) {
        if ([element isKindOfClass:[UDDeclElement class]]) {
            element.ud_owner = owner;
            element.ud_ownerKey = key;
        }
    }
}

/// A name a decl can hold: one token, not empty.
static BOOL UDValidateName(id *ioValue, NSString *what, NSError **error) {
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

@implementation UDDeclElement

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] init];
}

/// Its decl puts @a edited in this element's place, in a new array; NO when
/// it is in none.
- (BOOL)ud_replaceInOwnerWith:(UDDeclElement *)edited {
    UDDeclBase *owner = self.ud_owner;
    NSString *key = self.ud_ownerKey;
    if (owner == nil || key == nil) {
        return NO;
    }
    NSMutableArray *elements = [[owner valueForKey:key] mutableCopy];
    NSUInteger index = [elements indexOfObjectIdenticalTo:self];
    if (index == NSNotFound) {
        return NO;
    }
    elements[index] = edited;
    [owner setValue:elements forKey:key];
    return YES;
}

@end

@implementation UDDeclPropertyElement

/// Its values: its class's declared properties.
+ (NSArray<NSString *> *)ud_valueKeys {
    static NSMutableDictionary<NSString *, NSArray<NSString *> *> *keysByClass;
    @synchronized ([UDDeclPropertyElement class]) {
        if (keysByClass == nil) keysByClass = [NSMutableDictionary dictionary];
        NSString *className = NSStringFromClass(self);
        NSArray<NSString *> *keys = keysByClass[className];
        if (keys == nil) {
            NSMutableArray<NSString *> *names = [NSMutableArray array];
            unsigned int count = 0;
            objc_property_t *properties = class_copyPropertyList(self, &count);
            for (unsigned int i = 0; i < count; i++) {
                [names addObject:[NSString stringWithUTF8String:property_getName(properties[i])]];
            }
            free(properties);
            keys = keysByClass[className] = [names copy];
        }
        return keys;
    }
}

+ (NSSet<NSString *> *)ud_numberKeys {
    return [NSSet set];
}

- (id)copyWithZone:(NSZone *)zone {
    UDParticleStage *copy = [[[self class] alloc] init];
    for (NSString *key in [[self class] ud_valueKeys]) {
        [copy ud_setValue:[self valueForKey:key] forKey:key];
    }
    return copy;
}

- (void)ud_setValue:(id)value forKey:(NSString *)key {
    [super setValue:value forKey:key];
}

// A binding's edit: an edited copy in its place, so that it is its decl's
// (undoable, the decl updated).
- (void)setValue:(id)value forKey:(NSString *)key {
    if (self.ud_owner == nil || ![[[self class] ud_valueKeys] containsObject:key]) {
        [super setValue:value forKey:key];
        return;
    }
    UDParticleStage *edited = [self copy];
    [edited ud_setValue:value forKey:key];
    if (![self ud_replaceInOwnerWith:edited]) {
        [super setValue:value forKey:key];
    }
}

// A number typed in: a number, not text that KVC would make 0.
- (BOOL)validateValue:(id *)ioValue forKey:(NSString *)key error:(NSError **)error {
    objc_property_t property = class_getProperty([self class], key.UTF8String);
    const char *type = property != NULL ? property_getAttributes(property) : NULL;
    BOOL scalar = type != NULL && (type[1] == 'f' || type[1] == 'i');
    if ([[[self class] ud_numberKeys] containsObject:key] && [*ioValue isKindOfClass:[NSString class]] &&
        [[*ioValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
        *ioValue = nil;                                             // none
        return YES;
    }
    BOOL number = scalar || [[[self class] ud_numberKeys] containsObject:key];
    if (!number || ![*ioValue isKindOfClass:[NSString class]]) {
        return [super validateValue:ioValue forKey:key error:error];
    }
    NSScanner *scanner = [NSScanner scannerWithString:[*ioValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    double d = 0;
    int i = 0;
    BOOL integer = scalar && type[1] == 'i';
    BOOL scanned = integer ? [scanner scanInt:&i] : [scanner scanDouble:&d];
    if (scanned && scanner.isAtEnd) {
        *ioValue = integer ? @(i) : @((float)d);
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclElement" code:1 userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"%@ is a %@number.", key, integer ? @"whole " : @""]}];
    }
    return NO;
}

@end

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

/// A transient element array's setter, after the particle stages': it marks
/// the decl updated (and registers with undo) and adopts the elements.
#define UD_ELEMENT_ARRAY_SETTER(Setter, key) \
- (void)Setter:(NSArray *)elements { \
    [self willChangeValueForKey:key]; \
    [self setPrimitiveValue:[elements copy] forKey:key]; \
    [self didChangeValueForKey:key]; \
    UDAdoptElements(elements, self, key); \
}

/// The values @a object's codec reads from its text, for -awakeFromFetch.
static NSDictionary *UDParsedSourceText(UDDeclBase *object) {
    NSData *text = [object primitiveValueForKey:@"sourceText"];
    if (text == nil) {
        return nil;
    }
    return [[object class] ud_parseValuesFromText:text name:[object primitiveValueForKey:@"name"]
                                         fileName:nil lineNum:1 fileSystem:nil error:NULL];
}

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
    return [pairs indexOfObjectPassingTest:^BOOL(UDEntityKeyValue *pair, NSUInteger i, BOOL *stop) {
        return [pair.key caseInsensitiveCompare:key] == NSOrderedSame;
    }];
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
- (NSString *)ud_helpForKey:(NSString *)key {
    static NSString *const prefixes[] = {
        @"editor_var ", @"editor_int ", @"editor_float ", @"editor_bool ", @"editor_color ",
        @"editor_mat ", @"editor_model ", @"editor_gui ", @"editor_snd ",
    };
    NSMutableDictionary *dict = [self ud_resolvedDictOrder:[NSMutableArray array] from:[NSMutableDictionary dictionary]
                                                    unknown:[NSMutableArray array]
                                                    visited:[NSMutableSet setWithObject:self.name.lowercaseString ?: @""]];
    for (size_t i = 0; i < sizeof(prefixes) / sizeof(prefixes[0]); i++) {
        NSString *help = dict[[prefixes[i] stringByAppendingString:key].lowercaseString];
        if (help != nil) return help;
    }
    return nil;
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

#pragma mark - Sound shaders

@implementation UDSoundSample

+ (instancetype)sampleWithPath:(NSString *)path {
    UDSoundSample *sample = [[self alloc] init];
    sample->_path = [path copy];
    return sample;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] sampleWithPath:_path];
}

- (void)setPath:(NSString *)path {
    UDSoundSample *edited = [self copy];
    edited->_path = [path copy];
    if (![self ud_replaceInOwnerWith:edited]) {
        _path = [path copy];
    }
}

- (BOOL)validatePath:(id *)ioValue error:(NSError **)error {
    return UDValidateName(ioValue, @"sample", error);
}

@end

// The flags' keywords, ParseShader's, by the attribute each sets.
static NSArray<NSArray<NSString *> *> *UDSoundFlagKeywords(void) {
    return @[
        @[@"noDups", @"no_dups"], @[@"noFlicker", @"no_flicker"], @[@"looping", @"looping"],
        @[@"noOcclusion", @"no_occlusion"], @[@"privateSound", @"private"], @[@"antiPrivate", @"antiPrivate"],
        @[@"playOnce", @"playonce"], @[@"global", @"global"], @[@"unclamped", @"unclamped"],
        @[@"omnidirectional", @"omnidirectional"],
        @[@"maskCenter", @"mask_center"], @[@"maskLeft", @"mask_left"], @[@"maskRight", @"mask_right"],
        @[@"maskBackRight", @"mask_backright"], @[@"maskBackLeft", @"mask_backleft"], @[@"maskLFE", @"mask_lfe"],
        @[@"ordered", @"ordered"], @[@"plain", @"plain"], @[@"onDemand", @"onDemand"],
    ];
}

@implementation UDDeclSound

@dynamic soundDescription, minSamples, minDistance, maxDistance, volume, leadinVolume, shakes, soundClass, altSound, reverb;
@dynamic noDups, noFlicker, looping, noOcclusion, privateSound, antiPrivate, playOnce, global, unclamped, omnidirectional;
@dynamic maskCenter, maskLeft, maskRight, maskBackLeft, maskBackRight, maskLFE, ordered, plain, onDemand;
@dynamic samples, leadins;

UD_ELEMENT_ARRAY_SETTER(setSamples, @"samples")
UD_ELEMENT_ARRAY_SETTER(setLeadins, @"leadins")

// samples and leadins are transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSDictionary *parsed = UDParsedSourceText(self);
    for (NSString *key in @[@"samples", @"leadins"]) {
        NSArray *elements = parsed[key] ?: @[];
        [self setPrimitiveValue:elements forKey:key];
        UDAdoptElements(elements, self, key);
    }
}

/// A parameter typed in: a number (a whole one for @a integer), or nothing,
/// which leaves it unset.
static BOOL UDValidateParameter(id *ioValue, BOOL integer, NSString *what, NSError **error) {
    id value = *ioValue;
    if (value == nil || value == [NSNull null]) {
        *ioValue = nil;
        return YES;
    }
    NSString *text = [[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (text.length == 0) {
        *ioValue = nil;
        return YES;
    }
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double d = 0;
    int i = 0;
    BOOL scanned = integer ? [scanner scanInt:&i] : [scanner scanDouble:&d];
    if (scanned && scanner.isAtEnd) {
        *ioValue = integer ? @(i) : @((float)d);
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclSound" code:1 userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"%@ is a %@number, or nothing for the engine's default.", what, integer ? @"whole " : @""]}];
    }
    return NO;
}

- (BOOL)validateMinDistance:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Min distance", error); }
- (BOOL)validateMaxDistance:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Max distance", error); }
- (BOOL)validateVolume:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Volume", error); }
- (BOOL)validateLeadinVolume:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Leadin volume", error); }
- (BOOL)validateShakes:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Shakes", error); }
- (BOOL)validateMinSamples:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, YES, @"Min samples", error); }

- (BOOL)validateSoundClass:(id *)ioValue error:(NSError **)error {
    if (!UDValidateParameter(ioValue, YES, @"Sound class", error)) return NO;
    // SOUND_MAX_CLASSES: "SoundClass out of range" past it.
    if (*ioValue == nil || ([*ioValue integerValue] >= 0 && [*ioValue integerValue] < 4)) return YES;
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclSound" code:1 userInfo:@{NSLocalizedDescriptionKey: @"A sound class is 0 to 3."}];
    }
    return NO;
}

// idSoundShader::DefaultDefinition
+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"_default.wav\n"
        @"}";
}

/// MakeDefault()'s shader: the default definition's one sample.
static NSDictionary<NSString *, id> *UDDefaultSoundValues(void) {
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *flag in UDSoundFlagKeywords()) values[flag[0]] = @NO;
    values[@"samples"] = @[[UDSoundSample sampleWithPath:@"_default.wav"]];
    values[@"leadins"] = @[];
    return values;
}

// A port of idSoundShader::ParseShader (neo/sound/snd_shader.cpp), keeping
// the keywords' values rather than the sound system's parms (so minSamples
// is what it says, not clamped; the samples are their names, not found in
// the sound cache, with no sys_lang voice-over substitution). Where it
// returns false, idSoundShader::Parse calls MakeDefault(): the values are
// the default definition's.
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
    NSMutableArray<UDSoundSample *> *samples = [NSMutableArray array];
    NSMutableArray<UDSoundSample *> *leadins = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *flags = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *flag in UDSoundFlagKeywords()) {
        flags[flag[1].lowercaseString] = flag[0];
        values[flag[0]] = @NO;
    }

    while (1) {
        if (![src expectAnyToken:&token error:NULL]) {
            return UDDefaultSoundValues();
        }
        // end of definition
        else if (!strcmp(token.text, "}")) {
            break;
        }
        NSString *keyword = UDTokenString(&token);
        // minimum number of sounds
        if (!strcasecmp(token.text, "minSamples")) {
            int v = 0;
            [src parseInt:&v error:NULL];
            values[@"minSamples"] = @(v);
        }
        // description
        else if (!strcasecmp(token.text, "description")) {
            [src readTokenOnLine:&token error:NULL];
            values[@"soundDescription"] = UDTokenString(&token);
        }
        // mindistance, maxdistance, volume, leadinVolume
        else if (!strcasecmp(token.text, "mindistance") || !strcasecmp(token.text, "maxdistance") ||
                 !strcasecmp(token.text, "volume") || !strcasecmp(token.text, "leadinVolume")) {
            float f = 0;
            [src parseFloat:&f error:NULL];
            NSString *key = !strcasecmp(token.text, "mindistance") ? @"minDistance"
                          : !strcasecmp(token.text, "maxdistance") ? @"maxDistance"
                          : !strcasecmp(token.text, "volume") ? @"volume" : @"leadinVolume";
            values[key] = @(f);
        }
        // shakes screen
        else if (!strcasecmp(token.text, "shakes")) {
            [src expectAnyToken:&token error:NULL];
            if (token.type == TT_NUMBER) {
                values[@"shakes"] = @(idToken_FloatValue(&token));
            } else {
                [src unreadToken:&token error:NULL];
                values[@"shakes"] = @1.0f;
            }
        }
        // reverb, no longer supported: kept
        else if (!strcasecmp(token.text, "reverb")) {
            float a = 0, b = 0;
            [src parseFloat:&a error:NULL];
            if (![src expectTokenString:@"," error:NULL]) {
                [src freeSource];
                return UDDefaultSoundValues();
            }
            [src parseFloat:&b error:NULL];
            values[@"reverb"] = [NSString stringWithFormat:@"%g, %g", a, b];
        }
        // soundClass
        else if (!strcasecmp(token.text, "soundClass")) {
            int v = 0;
            [src parseInt:&v error:NULL];
            if (v < 0 || v >= 4) {                          // SOUND_MAX_CLASSES
                [src warning:@"SoundClass out of range"];
                return UDDefaultSoundValues();
            }
            values[@"soundClass"] = @(v);
        }
        // altSound
        else if (!strcasecmp(token.text, "altSound")) {
            if (![src expectAnyToken:&token error:NULL]) {
                return UDDefaultSoundValues();
            }
            values[@"altSound"] = UDTokenString(&token);
        }
        // the flags and speaker masks (ordered, plain and onDemand no longer supported: kept)
        else if (flags[keyword.lowercaseString] != nil) {
            values[flags[keyword.lowercaseString]] = @YES;
        }
        // the wave files
        else if (!strcasecmp(token.text, "leadin")) {
            // add to the leadin list
            if (![src readToken:&token error:NULL]) {
                [src warning:@"Expected sound after leadin"];
                return UDDefaultSoundValues();
            }
            [leadins addObject:[UDSoundSample sampleWithPath:UDTokenString(&token)]];
        } else if ([keyword rangeOfString:@".wav" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                   [keyword rangeOfString:@".ogg" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            // add to the wav list
            [samples addObject:[UDSoundSample sampleWithPath:[keyword stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]]];
        } else {
            [src warning:@"unknown token '%s'", token.text];
            return UDDefaultSoundValues();
        }
    }
    values[@"samples"] = samples;
    values[@"leadins"] = leadins;
    return values;
}

static NSString *UDFloatText(NSNumber *number) {
    return [NSString stringWithFormat:@"%g", number.doubleValue];
}

// What ParseShader reads, a keyword a line: the parameters set, the flags,
// then the leadins and the samples.
+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString stringWithFormat:@"sound %@\n{\n", name];
    NSString *description = values[@"soundDescription"];
    if (description.length > 0) [out appendFormat:@"\tdescription\t\t\"%@\"\n", description];
    if (values[@"minSamples"] != nil) [out appendFormat:@"\tminSamples\t\t%ld\n", (long)[values[@"minSamples"] integerValue]];
    for (NSArray<NSString *> *parameter in @[@[@"minDistance", @"minDistance"], @[@"maxDistance", @"maxDistance"],
                                             @[@"volume", @"volume"], @[@"leadinVolume", @"leadinVolume"], @[@"shakes", @"shakes"]]) {
        NSNumber *value = values[parameter[0]];
        if (value != nil) [out appendFormat:@"\t%@\t\t%@\n", parameter[1], UDFloatText(value)];
    }
    if (values[@"soundClass"] != nil) [out appendFormat:@"\tsoundClass\t\t%ld\n", (long)[values[@"soundClass"] integerValue]];
    NSString *altSound = values[@"altSound"];
    if (altSound.length > 0) [out appendFormat:@"\taltSound\t\t%@\n", altSound];
    NSString *reverb = values[@"reverb"];
    if (reverb.length > 0) [out appendFormat:@"\treverb\t\t\t%@\n", reverb];
    for (NSArray<NSString *> *flag in UDSoundFlagKeywords()) {
        if ([values[flag[0]] boolValue]) [out appendFormat:@"\t%@\n", flag[1]];
    }
    for (UDSoundSample *leadin in values[@"leadins"]) {
        if (leadin.path.length > 0) [out appendFormat:@"\tleadin %@\n", leadin.path];
    }
    for (UDSoundSample *sample in values[@"samples"]) {
        if (sample.path.length > 0) [out appendFormat:@"\t%@\n", sample.path];
    }
    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end

#pragma mark - FX

@implementation UDFXAction

+ (NSSet<NSString *> *)ud_numberKeys {
    return [NSSet setWithArray:@[@"delay", @"duration", @"restart", @"size", @"fadeIn", @"fadeOut", @"rotate",
                                 @"random1", @"random2", @"lightRadius", @"shakeTime", @"shakeAmplitude",
                                 @"shakeDistance", @"shakeImpulse"]];
}

@end

/// The numbers of a "x, y, z" (ParseFloat and ExpectTokenString( "," ) in
/// turn), as a value's "x y z".
static NSString *UDFXParseCommaFloats(idLexer *src, int count) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        if (i > 0) [src expectTokenString:@"," error:NULL];
        float f = 0.0f;
        [src parseFloat:&f error:NULL];
        [values addObject:[NSString stringWithFormat:@"%g", f]];
    }
    return [values componentsJoinedByString:@" "];
}

static NSNumber *UDFXParseFloat(idLexer *src) {
    float f = 0.0f;
    [src parseFloat:&f error:NULL];
    return @(f);
}

// A port of idDeclFX::ParseSingleFXAction (neo/framework/DeclFX.cpp),
// keeping the keywords' values as written rather than the game's (an axis
// normalized into a matrix, a sibling found by name, the media precached).
static UDFXAction *UDFXParseSingleAction(idLexer *src) {
    idToken token;
    idToken_Init(&token);
    UDFXAction *action = [[UDFXAction alloc] init];

    while (1) {
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcasecmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcasecmp( token.text, "shake" ) ) {
            action.kind = @"shake";
            action.shakeTime = UDFXParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            action.shakeAmplitude = UDFXParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            action.shakeDistance = UDFXParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            BOOL falloff = NO;
            [src parseBool:&falloff error:NULL];
            action.shakeFalloff = falloff;
            [src expectTokenString:@"," error:NULL];
            action.shakeImpulse = UDFXParseFloat( src );
            continue;
        }
        if ( !strcasecmp( token.text, "noshadows" ) ) {
            action.noshadows = YES;
            continue;
        }
        if ( !strcasecmp( token.text, "name" ) ) {
            [src readToken:&token error:NULL];
            action.name = UDTokenString( &token );
            continue;
        }
        if ( !strcasecmp( token.text, "fire" ) ) {
            [src readToken:&token error:NULL];
            action.fire = UDTokenString( &token );
            continue;
        }
        if ( !strcasecmp( token.text, "random" ) ) {
            action.random1 = UDFXParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            action.random2 = UDFXParseFloat( src );
            action.delay = nil;                                     // check random
            continue;
        }
        static const struct { const char *keyword; const char *key; } floats[] = {
            { "delay", "delay" }, { "rotate", "rotate" }, { "duration", "duration" }, { "restart", "restart" },
            { "fadeIn", "fadeIn" }, { "fadeOut", "fadeOut" }, { "size", "size" },
        };
        BOOL matched = NO;
        for ( size_t i = 0; i < sizeof( floats ) / sizeof( floats[0] ); i++ ) {
            if ( !strcasecmp( token.text, floats[i].keyword ) ) {
                [action setValue:UDFXParseFloat( src ) forKey:[NSString stringWithUTF8String:floats[i].key]];
                matched = YES;
                break;
            }
        }
        if ( matched ) {
            continue;
        }
        if ( !strcasecmp( token.text, "trackorigin" ) ) {
            BOOL b = NO;
            [src parseBool:&b error:NULL];
            action.trackOrigin = b;
            continue;
        }
        if ( !strcasecmp( token.text, "offset" ) ) {
            action.offset = UDFXParseCommaFloats( src, 3 );
            continue;
        }
        if ( !strcasecmp( token.text, "axis" ) ) {
            action.axis = UDFXParseCommaFloats( src, 3 );
            continue;
        }
        if ( !strcasecmp( token.text, "angle" ) ) {
            action.angle = UDFXParseCommaFloats( src, 3 );
            continue;
        }
        if ( !strcasecmp( token.text, "light" ) ) {
            [src readToken:&token error:NULL];
            action.data = UDTokenString( &token );
            [src expectTokenString:@"," error:NULL];
            action.lightColor = UDFXParseCommaFloats( src, 3 );
            [src expectTokenString:@"," error:NULL];
            action.lightRadius = UDFXParseFloat( src );
            action.kind = @"light";
            continue;
        }
        // The keywords that name what the action uses, and are its kind.
        static const char *const named[] = {
            "uselight", "attachlight", "attachentity", "launch", "useModel", "model", "particle", "decal", "sound", "shockwave",
        };
        for ( size_t i = 0; i < sizeof( named ) / sizeof( named[0] ); i++ ) {
            if ( !strcasecmp( token.text, named[i] ) ) {
                NSString *kind = [NSString stringWithUTF8String:named[i]].lowercaseString;
                [src readToken:&token error:NULL];
                action.data = UDTokenString( &token );
                action.kind = kind;
                matched = YES;
                break;
            }
        }
        if ( matched ) {
            continue;
        }
        if ( !strcasecmp( token.text, "particleTrackVelocity" ) ) {
            action.particleTrackVelocity = YES;
            continue;
        }
        if ( !strcasecmp( token.text, "ignoreMaster" ) ) {
            action.ignoreMaster = YES;
            continue;
        }
        [src warning:@"FX File: bad token"];
        continue;
    }
    return action;
}

@implementation UDDeclFX

@dynamic bindTo, actions;

UD_ELEMENT_ARRAY_SETTER(setActions, @"actions")

// actions is transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSArray *actions = UDParsedSourceText(self)[@"actions"] ?: @[];
    [self setPrimitiveValue:actions forKey:@"actions"];
    UDAdoptElements(actions, self, @"actions");
}

// idDeclFX::DefaultDefinition
+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"{\n"
        @"\t\t"        @"duration\t5\n"
        @"\t\t"        @"model\t\t_default\n"
        @"\t"    @"}\n"
        @"}";
}

// A port of idDeclFX::Parse. A parse error is warned about and the actions
// read are kept: idDeclLocal::ParseLocal makes no default of an FX that
// failed.
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
    NSMutableArray<UDFXAction *> *actions = [NSMutableArray array];

    // scan through, identifying each individual parameter
    while( 1 ) {
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcasecmp( token.text, "bindto" ) ) {
            [src readToken:&token error:NULL];
            values[@"bindTo"] = UDTokenString( &token );
            continue;
        }
        if ( !strcasecmp( token.text, "{" ) ) {
            [actions addObject:UDFXParseSingleAction( src )];
            continue;
        }
    }
    if ( [src hadError] ) {
        [src warning:@"FX decl '%@' had a parse error", name];
    }
    values[@"actions"] = actions;
    return values;
}

static void UDFXWriteNumber(NSMutableString *out, NSString *keyword, NSNumber *value) {
    if (value != nil) [out appendFormat:@"\t\t%@ %g\n", keyword, value.doubleValue];
}

/// A value's "x y z" as the decl's "x, y, z".
static NSString *UDFXCommaList(NSString *spaced) {
    NSArray<NSString *> *numbers = [[spaced componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                                    filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    return numbers.count > 0 ? [numbers componentsJoinedByString:@", "] : @"0, 0, 0";
}

// What ParseSingleFXAction reads, a keyword a line, as the retail .fx files
// have them: the timing, what the action does, then its other keywords.
+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString stringWithFormat:@"fx %@\n{\n", name];
    NSString *bindTo = values[@"bindTo"];
    if (bindTo.length > 0) [out appendFormat:@"\tbindto \"%@\"\n", bindTo];
    for (UDFXAction *action in values[@"actions"]) {
        [out appendString:@"\t{\n"];
        if (action.name.length > 0) [out appendFormat:@"\t\tname \"%@\"\n", action.name];
        UDFXWriteNumber(out, @"delay", action.delay);
        if (action.random1 != nil || action.random2 != nil) {
            [out appendFormat:@"\t\trandom %g, %g\n", action.random1.doubleValue, action.random2.doubleValue];
        }
        UDFXWriteNumber(out, @"duration", action.duration);
        UDFXWriteNumber(out, @"restart", action.restart);
        NSString *kind = action.kind;
        if ([kind isEqualToString:@"light"]) {
            [out appendFormat:@"\t\tlight \"%@\", %@, %g\n", action.data ?: @"", UDFXCommaList(action.lightColor ?: @""),
                              action.lightRadius.doubleValue];
        } else if ([kind isEqualToString:@"shake"]) {
            [out appendFormat:@"\t\tshake %g, %g, %g, %d, %g\n", action.shakeTime.doubleValue, action.shakeAmplitude.doubleValue,
                              action.shakeDistance.doubleValue, action.shakeFalloff ? 1 : 0, action.shakeImpulse.doubleValue];
        } else if (kind.length > 0) {
            NSString *keyword = [kind isEqualToString:@"usemodel"] ? @"useModel" : [kind isEqualToString:@"uselight"] ? @"useLight" : kind;
            [out appendFormat:@"\t\t%@ \"%@\"\n", keyword, action.data ?: @""];
        }
        if (action.fire.length > 0) [out appendFormat:@"\t\tfire \"%@\"\n", action.fire];
        UDFXWriteNumber(out, @"size", action.size);
        UDFXWriteNumber(out, @"rotate", action.rotate);
        if (action.offset.length > 0) [out appendFormat:@"\t\toffset %@\n", UDFXCommaList(action.offset)];
        if (action.axis.length > 0) [out appendFormat:@"\t\taxis %@\n", UDFXCommaList(action.axis)];
        if (action.angle.length > 0) [out appendFormat:@"\t\tangle %@\n", UDFXCommaList(action.angle)];
        UDFXWriteNumber(out, @"fadeIn", action.fadeIn);
        UDFXWriteNumber(out, @"fadeOut", action.fadeOut);
        if (action.trackOrigin) [out appendString:@"\t\ttrackorigin 1\n"];
        if (action.noshadows) [out appendString:@"\t\tnoshadows\n"];
        if (action.particleTrackVelocity) [out appendString:@"\t\tparticleTrackVelocity\n"];
        if (action.ignoreMaster) [out appendString:@"\t\tignoreMaster\n"];
        [out appendString:@"\t}\n"];
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

/// The floats @a parms holds, as a stage's parameter string.
static NSString *UDParticleParmString(const float *parms, int count) {
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [values addObject:[NSString stringWithFormat:@"%g", parms[i]]];
    }
    return [values componentsJoinedByString:@" "];
}

// idDeclParticle::ParseParms: every token left on the line, as atof reads it.
static void UDParticleParseParms(idLexer *src, float *parms, int maxParms) {
    idToken token;
    idToken_Init(&token);
    memset( parms, 0, maxParms * sizeof( *parms ) );
    int count = 0;
    while( 1 ) {
        if ( ![src readTokenOnLine:&token error:NULL] ) {
            return;
        }
        if ( count == maxParms ) {
            [src error:NULL format:@"too many parms on line"];
            return;
        }
        idToken_StripQuotes( &token );
        parms[count] = atof( token.text );
        count++;
    }
}

// idDeclParticle::ParseParametric, into <prefix>Table / From / To.
static void UDParticleParseParametric(idLexer *src, UDParticleStage *stage, NSString *prefix) {
    idToken token;
    idToken_Init(&token);
    NSString *tableKey = [prefix stringByAppendingString:@"Table"];
    NSString *fromKey = [prefix stringByAppendingString:@"From"];
    NSString *toKey = [prefix stringByAppendingString:@"To"];

    [stage setValue:nil forKey:tableKey];
    [stage setValue:@0.0f forKey:fromKey];
    [stage setValue:@0.0f forKey:toKey];

    if ( ![src readToken:&token error:NULL] ) {
        [src error:NULL format:@"not enough parameters"];
        return;
    }

    if ( idStr_IsNumericCString( token.text ) ) {
        // can have a to + 2nd parm
        float from = atof( token.text );
        [stage setValue:@(from) forKey:fromKey];
        [stage setValue:@(from) forKey:toKey];
        if ( [src readToken:&token error:NULL] ) {
            if ( !strcasecmp( token.text, "to" ) ) {
                if ( ![src readToken:&token error:NULL] ) {
                    [src error:NULL format:@"missing second parameter"];
                    return;
                }
                [stage setValue:@((float)atof( token.text )) forKey:toKey];
            } else {
                [src unreadToken:&token error:NULL];
            }
        }
    } else {
        // table
        [stage setValue:UDTokenString(&token) forKey:tableKey];
    }
}

// idDeclParticle::ParseParticleStage. It always gives a stage: an error
// (an unknown token, a bad type) ends it with what it has read.
static UDParticleStage *UDParticleParseStage(idLexer *src, NSString *name) {
    idToken token;
    idToken_Init(&token);
    UDParticleStage *stage = [[UDParticleStage alloc] init];           // Default()
    float parms[8];

    while (1) {
        if ( [src hadError] ) {
            break;
        }
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcasecmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcasecmp( token.text, "material" ) ) {
            [src readToken:&token error:NULL];
            stage.material = UDTokenString(&token);
            continue;
        }
        if ( !strcasecmp( token.text, "count" ) ) {
            int i = 0;
            [src parseInt:&i error:NULL];
            stage.totalParticles = i;
            continue;
        }
        static const struct { const char *keyword; const char *key; } floats[] = {
            { "time", "particleLife" }, { "cycles", "cycles" }, { "timeOffset", "timeOffset" },
            { "deadTime", "deadTime" }, { "bunching", "spawnBunching" }, { "angle", "initialAngle" },
            { "fadeIn", "fadeInFraction" }, { "fadeOut", "fadeOutFraction" }, { "fadeIndex", "fadeIndexFraction" },
            { "animationRate", "animationRate" }, { "boundsExpansion", "boundsExpansion" },
        };
        BOOL matched = NO;
        for ( size_t i = 0; i < sizeof( floats ) / sizeof( floats[0] ); i++ ) {
            if ( !strcasecmp( token.text, floats[i].keyword ) ) {
                float f = 0.0f;
                [src parseFloat:&f error:NULL];
                [stage setValue:@(f) forKey:[NSString stringWithUTF8String:floats[i].key]];
                matched = YES;
                break;
            }
        }
        if ( matched ) {
            continue;
        }
        if ( !strcasecmp( token.text, "randomDistribution" ) ) {
            BOOL b = NO;
            [src parseBool:&b error:NULL];
            stage.randomDistribution = b;
            continue;
        }
        if ( !strcasecmp( token.text, "entityColor" ) ) {
            BOOL b = NO;
            [src parseBool:&b error:NULL];
            stage.entityColor = b;
            continue;
        }
        if ( !strcasecmp( token.text, "animationFrames" ) ) {
            int i = 0;
            [src parseInt:&i error:NULL];
            stage.animationFrames = i;
            continue;
        }
        if ( !strcasecmp( token.text, "distribution" ) ) {
            [src readToken:&token error:NULL];
            int type = UDParticleDescIndex( UDParticleDistributionDesc, UDParticleDescCount( UDParticleDistributionDesc ), token.text );
            if ( type >= 0 ) {
                stage.distributionType = type;
            } else {
                [src error:NULL format:@"bad distribution type: %s\n", token.text];
            }
            UDParticleParseParms( src, parms, 4 );
            stage.distributionParms = UDParticleParmString( parms, 4 );
            continue;
        }
        if ( !strcasecmp( token.text, "direction" ) ) {
            [src readToken:&token error:NULL];
            int type = UDParticleDescIndex( UDParticleDirectionDesc, UDParticleDescCount( UDParticleDirectionDesc ), token.text );
            if ( type >= 0 ) {
                stage.directionType = type;
            } else {
                [src error:NULL format:@"bad direction type: %s\n", token.text];
            }
            UDParticleParseParms( src, parms, 4 );
            stage.directionParms = UDParticleParmString( parms, 4 );
            continue;
        }
        if ( !strcasecmp( token.text, "orientation" ) ) {
            [src readToken:&token error:NULL];
            int type = UDParticleDescIndex( UDParticleOrientationDesc, UDParticleDescCount( UDParticleOrientationDesc ), token.text );
            if ( type >= 0 ) {
                stage.orientation = type;
            } else {
                [src error:NULL format:@"bad orientation type: %s\n", token.text];
            }
            UDParticleParseParms( src, parms, 4 );
            stage.orientationParms = UDParticleParmString( parms, 4 );
            continue;
        }
        if ( !strcasecmp( token.text, "customPath" ) ) {
            [src readToken:&token error:NULL];
            // The parser's names: "spherical" is PPATH_ORBIT (written as "orbit"), and no "drip".
            if ( !strcasecmp( token.text, "standard" ) ) {
                stage.customPathType = 0;
            } else if ( !strcasecmp( token.text, "helix" ) ) {
                stage.customPathType = 1;
            } else if ( !strcasecmp( token.text, "flies" ) ) {
                stage.customPathType = 2;
            } else if ( !strcasecmp( token.text, "spherical" ) ) {
                stage.customPathType = 3;
            } else {
                [src error:NULL format:@"bad path type: %s\n", token.text];
            }
            UDParticleParseParms( src, parms, 8 );
            stage.customPathParms = UDParticleParmString( parms, 8 );
            continue;
        }
        if ( !strcasecmp( token.text, "speed" ) ) {
            UDParticleParseParametric( src, stage, @"speed" );
            continue;
        }
        if ( !strcasecmp( token.text, "rotation" ) ) {
            UDParticleParseParametric( src, stage, @"rotation" );
            continue;
        }
        if ( !strcasecmp( token.text, "size" ) ) {
            UDParticleParseParametric( src, stage, @"size" );
            continue;
        }
        if ( !strcasecmp( token.text, "aspect" ) ) {
            UDParticleParseParametric( src, stage, @"aspect" );
            continue;
        }
        if ( !strcasecmp( token.text, "color" ) || !strcasecmp( token.text, "fadeColor" ) ) {
            float c[4] = { 0, 0, 0, 0 };
            for ( int i = 0; i < 4; i++ ) {
                [src parseFloat:&c[i] error:NULL];
            }
            [stage setValue:UDParticleParmString( c, 4 ) forKey:!strcasecmp( token.text, "color" ) ? @"color" : @"fadeColor"];
            continue;
        }
        if ( !strcasecmp( token.text, "offset" ) ) {
            float o[3] = { 0, 0, 0 };
            for ( int i = 0; i < 3; i++ ) {
                [src parseFloat:&o[i] error:NULL];
            }
            stage.offset = UDParticleParmString( o, 3 );
            continue;
        }
        if ( !strcasecmp( token.text, "gravity" ) ) {
            [src readToken:&token error:NULL];
            if ( !strcasecmp( token.text, "world" ) ) {
                stage.worldGravity = YES;
            } else {
                [src unreadToken:&token error:NULL];
            }
            float f = 0.0f;
            [src parseFloat:&f error:NULL];
            stage.gravity = f;
            continue;
        }
        if ( !strcasecmp( token.text, "softeningRadius" ) ) { // #3878 soft particles
            // dhewm3 warns and ignores it (its value is read next, as a keyword)
            [src warning:@"Particle %@ has stage with \"softeningRadius\" attribute, which is currently ignored (we soften all suitable particles)", name];
            continue;
        }
        [src error:NULL format:@"unknown token %s\n", token.text];
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

    // As WriteStage has it: only when rotationSpeed.from is not 0 (a
    // rotation by a table is not written).
    if (UDFloatValue(stage, @"rotationFrom")) {
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

UD_ELEMENT_ARRAY_SETTER(setStages, @"stages")

// stages is transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSArray *stages = UDParsedSourceText(self)[@"stages"] ?: @[];
    [self setPrimitiveValue:stages forKey:@"stages"];
    UDAdoptElements(stages, self, @"stages");
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

// idDeclParticle::Parse. Where it gives up, MakeDefault(): the values are
// the default definition's.
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
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcasecmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcasecmp( token.text, "{" ) ) {
            [stages addObject:UDParticleParseStage( src, name )];
            continue;
        }
        if ( !strcasecmp( token.text, "depthHack" ) ) {
            [src parseFloat:&depthHack error:NULL];
            continue;
        }
        [src warning:@"bad token %s", token.text];
        return [self ud_defaultValuesNamed:name];
    }
    return @{
        @"depthHack": @(depthHack),
        @"stages": stages,
    };
}

/// MakeDefault()'s values: the default definition, parsed.
+ (NSDictionary<NSString *, id> *)ud_defaultValuesNamed:(NSString *)name {
    NSData *text = [[self ud_defaultDefinition] dataUsingEncoding:NSUTF8StringEncoding];
    return [self ud_parseValuesFromText:text name:name fileName:nil lineNum:1 fileSystem:nil error:NULL];
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

