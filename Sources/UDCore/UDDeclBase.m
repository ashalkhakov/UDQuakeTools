/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclBase.m — the decl entities' base class, and DeclFile and DeclType.
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclBase.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

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
