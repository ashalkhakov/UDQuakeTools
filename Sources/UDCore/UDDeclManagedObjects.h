/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclManagedObjects.h — NSManagedObject subclasses backing DeclModel.xcdatamodeld.
 *
 * These are the one and only structured representation of decls: the entity
 * classes own the type-specific parse/unparse logic (ported from the old
 * idDecl* subclasses), while idDeclManager stays a dumb text repository.
 * UDDeclIncrementalStore drives the codecs from the managed object model —
 * it derives everything (attributes, child-decl relationships, owned
 * sub-entities like particle stages) from NSEntityDescription introspection.
 *
 * Entity naming convention: the entity for decl type name "x" is named
 * "Decl" + capitalized("x") — material → DeclMaterial, pda → DeclPDA,
 * entityDef → DeclEntityDef.
 *
 * Codec value dictionaries use these shapes:
 *   attribute name                   -> NSString / NSNumber
 *   transient structured attribute   -> whatever the entity defines (e.g.
 *                                       DeclParticle.stages holds
 *                                       NSArray<UDParticleStage *>)
 *   to-many relationship to a decl   -> NSArray<NSString *> of decl names
 */

#import <CoreData/CoreData.h>

#import "idDeclManager.h"

@class idFileSystem;
@class UDDeclTextProblem;

NS_ASSUME_NONNULL_BEGIN

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

@interface UDDeclMaterial : UDDeclBase
@end

// Edited as text until their editors arrive; each new one starts from its
// engine class's DefaultDefinition.

@interface UDDeclFX : UDDeclBase
@end
@interface UDDeclAF : UDDeclBase
@end
@interface UDDeclModel : UDDeclBase
@end
@interface UDDeclExport : UDDeclBase
@end

// ---------------------------------------------------------------------------
// A table's values and a skin's mappings and models: like particle stages,
// plain KVO-compliant objects in transient attributes of their decl, read
// from its text on fetch and written back on save. An element belongs to its
// decl: setting a property of one asks the decl to put an edited copy in its
// place, in a new array, so a bound cell's edit is the decl's (undoable, the
// decl updated) and undo brings the element back as it was.
// ---------------------------------------------------------------------------

@interface UDDeclElement : NSObject <NSCopying>
/// The decl and its attribute holding this element; nil until it is in one.
@property (nonatomic, weak, nullable) UDDeclBase *ud_owner;
@property (nonatomic, copy, nullable) NSString *ud_ownerKey;
@end

/// One of a table's values.
@interface UDTableValue : UDDeclElement
@property (nonatomic) float number;
+ (instancetype)valueWithNumber:(float)number;
@end

/// One of a skin's mappings: from a material ("*" for all) to another.
@interface UDSkinMapping : UDDeclElement
@property (nonatomic, copy) NSString *from;
@property (nonatomic, copy) NSString *to;
+ (instancetype)mappingFrom:(NSString *)from to:(NSString *)to;
@end

/// One of the models a skin goes with.
@interface UDSkinModel : UDDeclElement
@property (nonatomic, copy) NSString *path;
+ (instancetype)modelWithPath:(NSString *)path;
@end

@interface UDDeclTable : UDDeclBase

@property (nonatomic) BOOL clamp;
@property (nonatomic) BOOL snap;
/// The values, in order. TRANSIENT: read from the decl text on fetch and
/// written back on save; a new array marks the decl updated.
@property (nonatomic, copy, nullable) NSArray<UDTableValue *> *values;

@end

@interface UDDeclSkin : UDDeclBase

/// The mappings and the associated models, in order. TRANSIENT, as a
/// table's values are.
@property (nonatomic, copy, nullable) NSArray<UDSkinMapping *> *mappings;
@property (nonatomic, copy, nullable) NSArray<UDSkinModel *> *associatedModels;

@end

/// One of an entityDef's key/value pairs (a spawnArg).
@interface UDEntityKeyValue : UDDeclElement
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *value;
+ (instancetype)keyValueWithKey:(NSString *)key value:(NSString *)value;
@end

/// An inherited pair: the key/value, and the entityDef it comes from.
@interface UDInheritedKeyValue : NSObject
@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly, copy) NSString *value;
@property (nonatomic, readonly, copy) NSString *from;
@end

/// An entityDef (and a mapDef, which the engine parses as one): its own
/// key/value pairs, in order, as idDeclEntityDef::Parse reads them before it
/// merges in what it inherits. TRANSIENT, as a table's values are.
@interface UDDeclEntityDef : UDDeclBase
@property (nonatomic, copy, nullable) NSArray<UDEntityKeyValue *> *keyValues;

/// The "inherit" pair's value, or nil; setting it sets, adds (first) or,
/// with nil or "", removes that pair.
@property (nonatomic, copy, nullable) NSString *inherit;

/// What it inherits and does not set itself, as idDeclEntityDef::Parse
/// merges it (each "inherit…" key's entityDef, its own inheritance
/// resolved, filling in the keys not yet set), from the decls in its
/// context. @a unknown gets the inherited names no entityDef has.
- (NSArray<UDInheritedKeyValue *> *)ud_inheritedKeyValuesUnknown:(NSArray<NSString *> * _Nullable * _Nullable)unknown;

/// The spawnArgs' help, from the editor_* keys of the decl and what it
/// inherits, as Radiant's EClass_InitFromDict reads them: the entity's
/// editor_usage, and each key's editor_var (editor_int, editor_bool, ...).
- (nullable NSString *)ud_usage;
- (nullable NSString *)ud_helpForKey:(NSString *)key;
@end

@interface UDDeclMapDef : UDDeclEntityDef
@end

/// One of a sound shader's samples or leadins: a .wav or .ogg path.
@interface UDSoundSample : UDDeclElement
@property (nonatomic, copy) NSString *path;
+ (instancetype)sampleWithPath:(NSString *)path;
@end

/// A sound shader, as idSoundShader::ParseShader reads it. A parameter it
/// does not set is nil (the engine's default then); the flags are its
/// SSF_* keywords and speaker masks. ordered, plain, onDemand and reverb are
/// no longer supported by the engine, kept so that an edit does not drop
/// them. samples and leadins are TRANSIENT, as a table's values are.
@interface UDDeclSound : UDDeclBase
@property (nonatomic, copy, nullable) NSString *soundDescription;
@property (nonatomic, copy, nullable) NSNumber *minSamples;
@property (nonatomic, copy, nullable) NSNumber *minDistance;
@property (nonatomic, copy, nullable) NSNumber *maxDistance;
@property (nonatomic, copy, nullable) NSNumber *volume;
@property (nonatomic, copy, nullable) NSNumber *leadinVolume;
@property (nonatomic, copy, nullable) NSNumber *shakes;
@property (nonatomic, copy, nullable) NSNumber *soundClass;
@property (nonatomic, copy, nullable) NSString *altSound;
@property (nonatomic, copy, nullable) NSString *reverb;
@property (nonatomic) BOOL noDups, noFlicker, looping, noOcclusion, privateSound, antiPrivate,
                           playOnce, global, unclamped, omnidirectional;
@property (nonatomic) BOOL maskCenter, maskLeft, maskRight, maskBackLeft, maskBackRight, maskLFE;
@property (nonatomic) BOOL ordered, plain, onDemand;
@property (nonatomic, copy, nullable) NSArray<UDSoundSample *> *samples;
@property (nonatomic, copy, nullable) NSArray<UDSoundSample *> *leadins;
@end

@interface UDDeclPDA : UDDeclBase

@property (nonatomic, copy, nullable) NSString *pdaName;
@property (nonatomic, copy, nullable) NSString *fullName;
@property (nonatomic, copy, nullable) NSString *icon;
@property (nonatomic, copy, nullable) NSString *ident;
@property (nonatomic, copy, nullable) NSString *post;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *security;

@property (nonatomic, strong, nullable) NSSet<__kindof UDDeclBase *> *audios;
@property (nonatomic, strong, nullable) NSSet<__kindof UDDeclBase *> *emails;
@property (nonatomic, strong, nullable) NSSet<__kindof UDDeclBase *> *videos;

@end

@interface UDDeclEmail : UDDeclBase

@property (nonatomic, copy, nullable) NSString *from;
@property (nonatomic, copy, nullable) NSString *to;
@property (nonatomic, copy, nullable) NSString *subject;
@property (nonatomic, copy, nullable) NSString *date;
@property (nonatomic, copy, nullable) NSString *body;
@property (nonatomic, copy, nullable) NSString *image;

@property (nonatomic, strong, nullable) UDDeclPDA *pda;

@end

@interface UDDeclAudio : UDDeclBase

@property (nonatomic, copy, nullable) NSString *audioName;
@property (nonatomic, copy, nullable) NSString *audio;
@property (nonatomic, copy, nullable) NSString *info;
@property (nonatomic, copy, nullable) NSString *preview;

@property (nonatomic, strong, nullable) UDDeclPDA *pda;

@end

@interface UDDeclVideo : UDDeclBase

@property (nonatomic, copy, nullable) NSString *videoName;
@property (nonatomic, copy, nullable) NSString *video;
@property (nonatomic, copy, nullable) NSString *audio;
@property (nonatomic, copy, nullable) NSString *info;
@property (nonatomic, copy, nullable) NSString *preview;

@property (nonatomic, strong, nullable) UDDeclPDA *pda;

@end

// ---------------------------------------------------------------------------
// UDParticleStage — a single particle stage. Deliberately NOT a Core Data
// entity: a stage has no identity outside its owning particle, so it lives
// as an element of DeclParticle's transient `stages` attribute (array order
// == stage order in the decl text): a value set through KVC (a binding's
// edit) puts an edited copy in its place, as a table's values do.
// Vector-ish values are stored as space-separated float strings ("x y z w");
// parametric values (speed/rotation/size/aspect) are a table decl name plus
// from/to floats. -init installs the engine's parse-time stage defaults.
// ---------------------------------------------------------------------------

@interface UDParticleStage : UDDeclElement

@property (nonatomic, copy, nullable) NSString *material;
@property (nonatomic) int32_t totalParticles;
@property (nonatomic) float cycles;
@property (nonatomic) float spawnBunching;
@property (nonatomic) float particleLife;
@property (nonatomic) float timeOffset;
@property (nonatomic) float deadTime;

@property (nonatomic) int32_t distributionType;
@property (nonatomic, copy, nullable) NSString *distributionParms;
@property (nonatomic) int32_t directionType;
@property (nonatomic, copy, nullable) NSString *directionParms;
@property (nonatomic) int32_t orientation;
@property (nonatomic, copy, nullable) NSString *orientationParms;
@property (nonatomic) int32_t customPathType;
@property (nonatomic, copy, nullable) NSString *customPathParms;

@property (nonatomic, copy, nullable) NSString *speedTable;
@property (nonatomic) float speedFrom;
@property (nonatomic) float speedTo;
@property (nonatomic, copy, nullable) NSString *rotationTable;
@property (nonatomic) float rotationFrom;
@property (nonatomic) float rotationTo;
@property (nonatomic, copy, nullable) NSString *sizeTable;
@property (nonatomic) float sizeFrom;
@property (nonatomic) float sizeTo;
@property (nonatomic, copy, nullable) NSString *aspectTable;
@property (nonatomic) float aspectFrom;
@property (nonatomic) float aspectTo;

@property (nonatomic) float gravity;
@property (nonatomic) BOOL worldGravity;
@property (nonatomic) BOOL randomDistribution;
@property (nonatomic) BOOL entityColor;

@property (nonatomic, copy, nullable) NSString *offset;
@property (nonatomic) int32_t animationFrames;
@property (nonatomic) float animationRate;
@property (nonatomic) float initialAngle;

@property (nonatomic, copy, nullable) NSString *color;
@property (nonatomic, copy, nullable) NSString *fadeColor;
@property (nonatomic) float fadeInFraction;
@property (nonatomic) float fadeOutFraction;
@property (nonatomic) float fadeIndexFraction;

@property (nonatomic) float boundsExpansion;
@property (nonatomic) float softeningRadius;
@property (nonatomic) BOOL hidden;

@end

@interface UDDeclParticle : UDDeclBase

@property (nonatomic) float depthHack;

/// The particle's stages, in decl-text order. This is a TRANSIENT modeled
/// attribute: it is populated from the decl text on fetch and unparsed back
/// on save. A stage's value set through KVC is an edit of the particle;
/// set as a property (as the parser does) it is not.
@property (nonatomic, copy, nullable) NSArray<UDParticleStage *> *stages;

@end

NS_ASSUME_NONNULL_END
