/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idRenderWindow.h — a renderDef (ui/RenderWindow.h, RenderWindow.cpp),
 * ported but for its 3D view: the window's vars, its parse, and the view
 * Draw makes; the scene itself is the render world's, which a running
 * engine draws (the roadmap's bridge). Here it is not drawn.
 */

#import "idWindow.h"

NS_ASSUME_NONNULL_BEGIN

/// renderView_t, as Draw sets it up.
typedef struct {
    int     x, y, width, height;
    float   fov_x, fov_y;
    idVec3  vieworg;
    idMat3  viewaxis;
    float   shaderParms[12];
    int     time;
} idGuiRenderView;

@interface idRenderWindow : idWindow {
@public
    idGuiRenderView refdef;
    idWinStr *modelName;
    idWinStr *animName;
    NSString *animClass;
    idWinVec4 *lightOrigin;
    idWinVec4 *lightColor;
    idWinVec4 *modelOrigin;
    idWinVec4 *modelRotate;
    idWinVec4 *viewOffset;
    idWinBool *needsRender;
    int animLength;
    int animEndTime;
    BOOL updateAnimation;
}
@end

NS_ASSUME_NONNULL_END
