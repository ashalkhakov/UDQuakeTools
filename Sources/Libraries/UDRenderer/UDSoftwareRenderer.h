/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDSoftwareRenderer.h — surfaces drawn as the engine's ambient pass draws
 * them (RB_STD_T_RenderShaderPasses' stages, ported), into a picture: GL's
 * part, its texturing, texture environment and blending, done in software.
 */

#import <Foundation/Foundation.h>
#import "UDParticleModel.h"

@class idDeclManager, idFileSystem, UDImage, UDMaterialParser;

NS_ASSUME_NONNULL_BEGIN

/// A point light, as R_DeriveLightData has one: its origin, its radius, its
/// material (lights/defaultPointLight for none), its shader parms
/// (SHADERPARM_RED… : its color, MAX_ENTITY_SHADER_PARMS of them).
@interface UDPointLight : NSObject
@property (nonatomic, copy, nullable) NSString *material;
@property (nonatomic, readonly) float *origin;          // 3
@property (nonatomic, readonly) float *radius;          // 3
@property (nonatomic, readonly) float *shaderParms;     // 12
@end

/// A vertex in the picture, as the triangles' setup leaves it for the
/// rasterizer.
typedef struct {
    float x, y;          // in the picture, its top row first
    float invW;          // 1 / the view's depth
    float s, t;          // texture coordinates, over the depth
    float r, g, b, a;    // vertex color 0–1, over the depth
} UDScreenVert;

/// A triangle the ambient pass draws: its vertices in the picture, the
/// texels it reads (RGBA, the top row first) and how (0 GL_REPEAT, else a
/// clamp: 3 TR_CLAMP_TO_ZERO, 4 TR_CLAMP_TO_ZERO_ALPHA, the others to the
/// edge), the second texture unit's constant color (GL_MODULATE) and its
/// stage's drawStateBits (GLS_SRCBLEND_*, GLS_DSTBLEND_*, the color mask).
typedef struct {
    UDScreenVert v[3];
    const uint8_t *texels;
    int texWidth, texHeight;
    int repeat;
    float constant[4];
    int drawStateBits;
} UDTriangleCommand;

/// The triangles surfaces are drawn with, in the order they are drawn, and
/// the images they read (kept while the list is).
@interface UDTriangleList : NSObject
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) const UDTriangleCommand *triangles;
- (UDImage *)imageOfTriangle:(NSUInteger)index;
@end

@interface UDSoftwareRenderer : NSObject

/// A picture of @a width × @a height, cleared to @a clearColor (RGBA, 0–1).
- (instancetype)initWithWidth:(int)width height:(int)height
                  declManager:(nullable idDeclManager *)declManager
                   fileSystem:(nullable idFileSystem *)fileSystem;

@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;

/// The view: its origin, its axis (renderView_t's viewaxis: forward, left,
/// up), and its horizontal field of view in degrees (the vertical one the
/// picture's aspect's).
- (void)setViewOrigin:(const float [_Nonnull 3])origin axis:(const float [_Nonnull 3][3])axis fovX:(float)fovX;

/// The picture resized (cleared); the view's field of view kept.
- (void)resizeToWidth:(int)width height:(int)height;

/// The view idGuiModel::EmitFullScreen makes: the 640 x 480 virtual screen
/// (qglOrtho( 0, 640, 480, 0, 0, 1 )) over the picture, no depth.
- (void)setGuiView;

/// idMaterial::SetSort on the material @a name (the GUIs' SS_GUI).
- (void)setSort:(float)sort forMaterial:(NSString *)name;

/// The material @a name, as declManager->FindMaterial gives it: its decl
/// parsed, or SetDefaultText's for a name no decl defines. @a name is
/// canonical (lowercase, its extension off).
- (UDMaterialParser *)materialNamed:(NSString *)name;
/// The image @a name, as ImageFromFile loads it; nil for none.
- (nullable UDImage *)imageNamed:(NSString *)name;
/// idImage::UploadScratch: @a image is the image @a name from now on.
- (void)setImage:(UDImage *)image forName:(NSString *)name;

/// The material @a name read from @a text instead of its decl's (an
/// editor's text, not saved yet).
- (void)setMaterialText:(NSString *)text forName:(NSString *)name;

/// The picture cleared to @a color.
- (void)clearToColor:(const float [_Nonnull 4])color;

/// @a surfaces drawn, sorted as the engine sorts them (by their materials'
/// sort, in order otherwise), their materials' registers at @a time
/// seconds with each surface's entity's shader parms.
- (void)drawSurfaces:(NSArray<UDParticleSurface *> *)surfaces time:(float)time;
/// What -drawSurfaces:time: draws, as triangles in the picture, not drawn:
/// the stages' registers evaluated, the vertices projected, the texture
/// matrices applied (for a renderer of another kind: GL's).
- (UDTriangleList *)trianglesOfSurfaces:(NSArray<UDParticleSurface *> *)surfaces time:(float)time;
/// @a list drawn into the picture.
- (void)drawTriangles:(UDTriangleList *)list;

/// @a surfaces lit by @a light, as the ARB2 interaction pass lights them
/// (RB_CreateSingleDrawInteractions, RB_ARB2_DrawInteraction, ported),
/// glprogs/interaction.vfp from the game's files run for each vertex and
/// pixel; their materials' and the light's registers at @a time seconds.
/// Nothing is drawn when the program is not there or does not run.
- (void)drawInteractionsOfSurfaces:(NSArray<UDParticleSurface *> *)surfaces light:(UDPointLight *)light time:(float)time;
/// Why the interactions are not drawn, if they are not.
@property (nonatomic, copy, readonly, nullable) NSString *interactionProblem;

/// The picture, the top row first.
- (UDImage *)image;

@end

NS_ASSUME_NONNULL_END
