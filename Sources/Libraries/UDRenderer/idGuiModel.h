/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idGuiModel.h — what a GUI draws into (renderer/GuiModel.cpp), ported: its
 * surfaces, a material and a color each, and their triangles; and the
 * render system's calls into it (RenderSystem.cpp's SetColor,
 * DrawStretchPic, DrawStretchTri). EmitFullScreen gives the surfaces, for
 * UDSoftwareRenderer to draw as the backend draws a 2D view.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"
#import "UDParticleModel.h"

/// A GUI's material, as the GUI model keeps it for its surfaces (the UI's
/// idMaterial adopts this): the material it is drawn with, by name.
@protocol idGuiMaterial <NSObject>
@property (nonatomic, copy, readonly) NSString *name;
@end

NS_ASSUME_NONNULL_BEGIN

@interface idGuiModel : NSObject

/// tr.defaultMaterial, the first surface's.
- (instancetype)initWithDefaultMaterial:(id<idGuiMaterial>)defaultMaterial;

/// Begins collecting draw commands into surfaces
- (void)clear;
- (void)setColor:(float)r g:(float)g b:(float)b a:(float)a;
- (void)drawStretchPic:(const UDDrawVert *)dverts indexes:(const int *)dindexes vertCount:(int)vertCount indexCount:(int)indexCount
              material:(nullable id<idGuiMaterial>)hShader clip:(BOOL)clip minX:(float)min_x minY:(float)min_y maxX:(float)max_x maxY:(float)max_y;
/// x/y/w/h are in the 0,0 to 640,480 range
- (void)drawStretchPic:(float)x y:(float)y w:(float)w h:(float)h s1:(float)s1 t1:(float)t1 s2:(float)s2 t2:(float)t2 material:(nullable id<idGuiMaterial>)hShader;
- (void)drawStretchTri:(idVec2)p1 p2:(idVec2)p2 p3:(idVec2)p3 t1:(idVec2)t1 t2:(idVec2)t2 t3:(idVec2)t3 material:(nullable id<idGuiMaterial>)material;

/// EmitFullScreen: the surfaces collected, in order, each with its color as
/// its entity's shader parms; none if the first is empty.
- (NSArray<UDParticleSurface *> *)emitFullScreen;

@end

NS_ASSUME_NONNULL_END
