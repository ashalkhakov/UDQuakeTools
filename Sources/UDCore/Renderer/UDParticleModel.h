/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDParticleModel.h — a particle system's quads at a time, as the engine
 * makes them: idRenderModelPrt::InstantiateDynamicModel and idParticleStage's
 * CreateParticle (DeclParticle.cpp, Model_prt.cpp), ported.
 */

#import <Foundation/Foundation.h>

@class idDeclManager, UDParticleStage;

NS_ASSUME_NONNULL_BEGIN

/// idDrawVert: its place, its texture coordinates, its normal and tangents
/// (a lit surface's; a particle's are 0), its color.
typedef struct {
    float   xyz[3];
    float   st[2];
    float   normal[3];
    float   tangents[2][3];
    uint8_t color[4];
} UDDrawVert;

/// A stage's surface at a time: its material, and its quads' vertexes (four
/// to a quad, in the order 0 1 / 2 3; drawn as 0 2 3, 0 3 1).
@interface UDParticleSurface : NSObject
@property (nonatomic, copy, readonly) NSString *material;
@property (nonatomic, readonly) NSInteger stageIndex;
@property (nonatomic, readonly) int numVerts;
@property (nonatomic, readonly) const UDDrawVert *verts;
/// Its entity's shader parms (MAX_ENTITY_SHADER_PARMS of them).
@property (nonatomic, readonly) const float *shaderParms;
/// A surface of @a numVerts @a verts (quads), its material @a material, its
/// entity's @a shaderParms.
+ (instancetype)surfaceWithMaterial:(NSString *)material verts:(const UDDrawVert *)verts numVerts:(int)numVerts
                        shaderParms:(const float *)shaderParms;
/// A surface of triangles: @a numIndexes @a indexes into @a verts, three to
/// a triangle (srfTriangles_t's).
+ (instancetype)surfaceWithMaterial:(NSString *)material verts:(const UDDrawVert *)verts numVerts:(int)numVerts
                            indexes:(const int *)indexes numIndexes:(int)numIndexes
                        shaderParms:(const float *)shaderParms;
/// Its triangles' indexes; NULL, 0 for quads.
@property (nonatomic, readonly, nullable) const int *indexes;
@property (nonatomic, readonly) int numIndexes;
@end

@interface UDParticleModel : NSObject

/// A model of @a stages (UDDeclParticle's), its tables looked up in
/// @a declManager.
- (instancetype)initWithStages:(NSArray<UDParticleStage *> *)stages declManager:(nullable idDeclManager *)declManager;

/// The surfaces at @a msec, seen along @a viewAxis (renderView_t's: forward,
/// left, up), the entity at the origin, unrotated, its shader parms 1 for
/// color and 0 for the rest.
- (NSArray<UDParticleSurface *> *)surfacesAtTime:(int)msec viewAxis:(const float [_Nonnull 3][3])viewAxis;
/// The same, for an entity with @a shaderParms (MAX_ENTITY_SHADER_PARMS),
/// at @a origin with @a axis: its quads in the world (the renderer's
/// model-to-world, origin + v * axis).
- (NSArray<UDParticleSurface *> *)surfacesAtTime:(int)msec viewAxis:(const float [_Nonnull 3][3])viewAxis
                                     shaderParms:(const float *)shaderParms
                                          origin:(const float [_Nonnull 3])origin
                                            axis:(const float [_Nonnull 3][3])axis;

/// idDeclParticle::GetStageBounds of every shown stage, together: min x y z,
/// max x y z.
- (void)getBounds:(float [_Nonnull 6])bounds;

@end

NS_ASSUME_NONNULL_END
