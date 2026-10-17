/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclParticle.h — particles (idDeclParticle).
 */

#import "UDDeclElement.h"

NS_ASSUME_NONNULL_BEGIN

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

@interface UDParticleStage : UDDeclPropertyElement

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
