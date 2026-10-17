/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclBase.h — the decl entities' base class, and DeclFile and DeclType.
 */

#import <CoreData/CoreData.h>

#import "idDeclManager.h"

NS_ASSUME_NONNULL_BEGIN

@class idFileSystem;
@class UDDeclTextProblem;


/// "material" → "DeclMaterial", "entityDef" → "DeclEntityDef"; nil for empty input.
NSString * _Nullable UDDeclEntityNameForDeclTypeName(NSString * _Nullable declTypeName);

/// "DeclMaterial" → "material"; nil if the name doesn't follow the convention.
NSString * _Nullable UDDeclTypeNameForDeclEntityName(NSString * _Nullable entityName);

// ---------------------------------------------------------------------------
// DeclFile / DeclType — read-mostly views over idDeclManager bookkeeping.
// ---------------------------------------------------------------------------

@interface UDDeclFile : NSManagedObject

@property (nonatomic, copy) NSString *fileName;
@property (nonatomic) int64_t checksum;
@property (nonatomic) int64_t timestamp;

@end

@interface UDDeclType : NSManagedObject

@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic) int32_t type;

@end

// ---------------------------------------------------------------------------
// DeclBase and concrete decl entities.
// ---------------------------------------------------------------------------

@class UDDeclPDA;

@interface UDDeclBase : NSManagedObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSData *sourceText;
@property (nonatomic, strong, nullable) UDDeclFile *sourceFile;
@property (nonatomic, strong, nullable) UDDeclType *type;

/// YES when sourceText was assigned through the public setter (a raw text
/// edit, e.g. from the text editor) since the last fetch/save. The store
/// uses this to decide whether the raw text wins over the structured
/// attributes on save. It cannot rely on -changedValues for that:
/// FreeCoreData records -awakeFromFetch's setPrimitiveValue: population of
/// this transient there, so "sourceText present in changedValues" does not
/// imply "edited". Not a modeled attribute.
@property (nonatomic) BOOL ud_sourceTextEdited;

/// The default decl body for a freshly created decl of this type (starts
/// with an open brace, ends with a close brace). Subclasses override.
/// These will eventually be replaced by the entities setting up default
/// attribute values on insert instead.
+ (NSString *)ud_defaultDefinition;

/// Parses raw decl text into a codec values dictionary (see header comment
/// for the shape). Returns nil when this entity has no structured codec and
/// is edited as raw text only (e.g. materials for now).
+ (nullable NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)text
                                                             name:(NSString *)name
                                                         fileName:(nullable NSString *)fileName
                                                          lineNum:(int)lineNum
                                                       fileSystem:(nullable idFileSystem *)fileSystem
                                                            error:(NSError * _Nullable * _Nullable)error;

/// The decl's text as it would be saved now, its unsaved edits in it; and
/// a text read back into the decl, as one edit of its context (NO, with the
/// parser's error, when it does not parse). A structured editor's source
/// view: UDDeclIncrementalStore's -ud_textForDeclObject:error: and
/// -ud_applyText:toDeclObject:error:.
- (nullable NSData *)ud_currentText:(NSError * _Nullable * _Nullable)error;
- (BOOL)ud_applyText:(NSData *)text error:(NSError * _Nullable * _Nullable)error;

/// What this entity's parser says of @a text (DialogDeclEditor's Test, which
/// has the decl parse its edited text): its lexer's errors and warnings, by
/// line from the text's first, and the parse's own error. None for a
/// raw-text-only entity, which has no parser.
+ (NSArray<UDDeclTextProblem *> *)ud_problemsParsingText:(NSString *)text
                                                    name:(NSString *)name
                                              fileSystem:(nullable idFileSystem *)fileSystem;
/// The same, for a parser that looks other decls up (a material's tables):
/// in @a declManager, its file system the one above.
+ (NSArray<UDDeclTextProblem *> *)ud_problemsParsingText:(NSString *)text
                                                    name:(NSString *)name
                                             declManager:(nullable idDeclManager *)declManager;

/// Produces the full decl text (including the "type name" header) from a
/// codec values dictionary. Returns nil when this entity has no structured
/// codec (the raw sourceText is authoritative then).
+ (nullable NSData *)ud_textByUnparsingName:(NSString *)name
                                     values:(NSDictionary<NSString *, id> *)values
                                      error:(NSError * _Nullable * _Nullable)error;

/// Fetches the managed decl identified by (declTypeName, name) from the given
/// context (which must be backed by UDDeclIncrementalStore). Returns nil if no
/// such decl exists.
+ (nullable __kindof UDDeclBase *)ud_declWithTypeName:(NSString *)declTypeName
                                                    name:(NSString *)name
                                               inContext:(NSManagedObjectContext *)context
                                                   error:(NSError * _Nullable * _Nullable)error;

/// The DeclModel entity name for the given idDeclManager type name, validated
/// against the model (returns nil when the model has no such entity).
+ (nullable NSString *)ud_entityNameForDeclTypeName:(NSString *)declTypeName
                                             inModel:(NSManagedObjectModel *)model;

@end

NS_ASSUME_NONNULL_END
