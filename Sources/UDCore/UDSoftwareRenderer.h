/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDSoftwareRenderer.h — surfaces drawn as the engine's ambient pass draws
 * them (RB_STD_T_RenderShaderPasses' stages, ported), into a picture: GL's
 * part, its texturing, texture environment and blending, done in software.
 */

#import <Foundation/Foundation.h>
#import "UDParticleModel.h"

@class idDeclManager, idFileSystem, UDImage;

NS_ASSUME_NONNULL_BEGIN

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

/// The picture cleared to @a color.
- (void)clearToColor:(const float [_Nonnull 4])color;

/// @a surfaces drawn, sorted as the engine sorts them (by their materials'
/// sort, in order otherwise), their materials' registers at @a time
/// seconds with each surface's entity's shader parms.
- (void)drawSurfaces:(NSArray<UDParticleSurface *> *)surfaces time:(float)time;

/// The picture, the top row first.
- (UDImage *)image;

@end

NS_ASSUME_NONNULL_END
