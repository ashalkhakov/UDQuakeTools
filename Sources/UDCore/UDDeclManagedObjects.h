/*
 * SPDX-License-Identifier: GPL-2.0-or-later
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

@interface UDDeclTable : UDDeclBase

@property (nonatomic) BOOL clamp;
@property (nonatomic) BOOL snap;
/// The table values as comma-separated floats, e.g. @"0, 0.5, 1".
@property (nonatomic, copy, nullable) NSString *values;

@end

@interface UDDeclSkin : UDDeclBase

/// One mapping per line: "<fromMaterial> <toMaterial>", with "*" as the
/// wildcard from-material.
@property (nonatomic, copy, nullable) NSString *mappings;
/// Associated model asset paths, one per line (preview aid for editors).
@property (nonatomic, copy, nullable) NSString *associatedModels;

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
// as a plain KVC/KVO-compliant object inside DeclParticle's transient
// `stages` attribute (array order == stage order in the decl text).
// Vector-ish values are stored as space-separated float strings ("x y z w");
// parametric values (speed/rotation/size/aspect) are a table decl name plus
// from/to floats. -init installs the engine's parse-time stage defaults.
// ---------------------------------------------------------------------------

@interface UDParticleStage : NSObject

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
/// on save. Replace the array wholesale when editing (assigning a new array
/// marks the object updated and registers with undo); mutating a
/// UDParticleStage in place does not mark the decl dirty by itself.
@property (nonatomic, copy, nullable) NSArray<UDParticleStage *> *stages;

@end

NS_ASSUME_NONNULL_END
