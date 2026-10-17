/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idSimpleWindow.m — ui/SimpleWindow.cpp, ported (its savegame parts left
 * out). See idWindow.h.
 */

#import "idWindow.h"
#import "idUserInterface.h"
#import "idDeviceContext.h"
#import "idDict.h"
#import "idStr.h"

@implementation idSimpleWindow

- (instancetype)initWithWindow:(idWindow *)win {
    self = [super init];
    if (self) {
        text = [[idWinStr alloc] init];
        visible = [[idWinBool alloc] init];
        rect = [[idWinRectangle alloc] init];
        backColor = [[idWinVec4 alloc] init];
        matColor = [[idWinVec4 alloc] init];
        foreColor = [[idWinVec4 alloc] init];
        borderColor = [[idWinVec4 alloc] init];
        textScale = [[idWinFloat alloc] init];
        rotate = [[idWinFloat alloc] init];
        shear = [[idWinVec2 alloc] init];
        backGroundName = [[idWinBackground alloc] init];
        hideCursor = [[idWinBool alloc] init];
        cstAnchor = [[idWinInt alloc] init];
        cstAnchorTo = [[idWinInt alloc] init];
        cstAnchorFactor = [[idWinFloat alloc] init];

        gui = [win getGui];
        dc = win->dc;
        drawRect = win->drawRect;
        clientRect = win->clientRect;
        textRect = win->textRect;
        origin = win->origin;
        fontNum = win->fontNum;
        name = [win->name copy];
        matScalex = win->matScalex;
        matScaley = win->matScaley;
        borderSize = win->borderSize;
        textAlign = win->textAlign;
        textAlignx = win->textAlignx;
        textAligny = win->textAligny;
        background = win->background;
        flags = win->flags;
        textShadow = win->textShadow;

        [visible assign:win->visible];
        [text assign:win->text];
        [rect assign:win->rect];
        [backColor assign:win->backColor];
        [matColor assign:win->matColor];
        [foreColor assign:win->foreColor];
        [borderColor assign:win->borderColor];
        [textScale assign:win->textScale];
        [rotate assign:win->rotate];
        // shear = win->shear: an idVec2 assigned to an idWinVec2 (its operator=)
        [shear setData:win->shear];
        [backGroundName assign:win->backGroundName];
        if ([backGroundName length]) {
            background = [[gui manager] findMaterial:[backGroundName data]];
            [background setSort:SS_GUI];
            [background setImageClassifications:1];   // just for resource tracking
        }
        [backGroundName setMaterialPtr:self];
//
//  added parent
        mParent = [win getParent];
//
        [hideCursor assign:win->hideCursor];
        //#modified-fva; BEGIN
        [cstAnchor assign:win->cstAnchor];
        [cstAnchorTo assign:win->cstAnchorTo];
        [cstAnchorFactor assign:win->cstAnchorFactor];
        cstNoClipBackground = win->cstNoClipBackground;
        //#modified-fva; END

        idWindow *parent = [win getParent];
        if (parent) {
            if ([text needsUpdate]) {
                [parent addUpdateVar:text];
            }
            if ([visible needsUpdate]) {
                [parent addUpdateVar:visible];
            }
            if ([rect needsUpdate]) {
                [parent addUpdateVar:rect];
            }
            if ([backColor needsUpdate]) {
                [parent addUpdateVar:backColor];
            }
            if ([matColor needsUpdate]) {
                [parent addUpdateVar:matColor];
            }
            if ([foreColor needsUpdate]) {
                [parent addUpdateVar:foreColor];
            }
            if ([borderColor needsUpdate]) {
                [parent addUpdateVar:borderColor];
            }
            if ([textScale needsUpdate]) {
                [parent addUpdateVar:textScale];
            }
            if ([rotate needsUpdate]) {
                [parent addUpdateVar:rotate];
            }
            if ([shear needsUpdate]) {
                [parent addUpdateVar:shear];
            }
            if ([backGroundName needsUpdate]) {
                [parent addUpdateVar:backGroundName];
            }
            //#modified-fva; BEGIN
            if ([cstAnchor needsUpdate]) {
                [parent addUpdateVar:cstAnchor];
            }
            if ([cstAnchorTo needsUpdate]) {
                [parent addUpdateVar:cstAnchorTo];
            }
            if ([cstAnchorFactor needsUpdate]) {
                [parent addUpdateVar:cstAnchorFactor];
            }
            //#modified-fva; END
        }
    }
    return self;
}

- (idWindow *)getParent {
    return mParent;
}

// (*mat) = …, through idWinBackground's material pointer
- (void)setBackgroundMaterialNamed:(NSString *)materialName {
    background = materialName ? [[gui manager] findMaterial:materialName] : nil;
}

- (void)stateChanged:(BOOL)redraw {
    if ( redraw && background && [background cinematicLength] ) {
        [background updateCinematic:[gui getTime]];
    }
}

- (void)setupTransforms:(float)x y:(float)y {
    static idMat3 trans;
    static idVec3 org;

    idMat3_Identity( &trans );
    org = idVec3_Make( origin.x + x, origin.y + y, 0 );

    if ( rotate.data ) {
        static idVec3 vec = { 0, 0, 1 };
        trans = idRotation_ToMat3( vec, rotate.data );
    }

    static idMat3 smat;
    idMat3_Identity( &smat );
    if ([shear x] || [shear y]) {
        smat.mat[0].y = [shear x];
        smat.mat[1].x = [shear y];
        idMat3_MultiplySelf( &trans, &smat );
    }

    if ( !idMat3_IsIdentity( &trans ) ) {
        [dc setTransformInfo:org mat:trans];
    }
}

- (void)drawBackground:(idRectangle)drawRectangle {
    if ([backColor w] > 0) {
        [dc drawFilledRect:drawRectangle.x y:drawRectangle.y width:drawRectangle.w height:drawRectangle.h color:backColor.data];
    }

    if (background) {
        if ([matColor w] > 0) {
            float scalex, scaley;
            if ( flags & WIN_NATURALMAT ) {
                scalex = drawRectangle.w / [background getImageWidth];
                scaley = drawRectangle.h / [background getImageHeight];
            } else {
                scalex = matScalex;
                scaley = matScaley;
            }
            [dc drawMaterial:drawRectangle.x y:drawRectangle.y w:drawRectangle.w h:drawRectangle.h mat:background color:matColor.data scalex:scalex scaley:scaley];
        }
    }
}

- (void)drawBorderAndCaption:(idRectangle)drawRectangle {
    if (flags & WIN_BORDER) {
        if (borderSize) {
            [dc drawRect:drawRectangle.x y:drawRectangle.y width:drawRectangle.w height:drawRectangle.h size:borderSize color:borderColor.data];
        }
    }
}

- (void)calcClientRect:(float)xofs yofs:(float)yofs {

    drawRect = rect.data;

    if ( flags & WIN_INVERTRECT ) {
        drawRect.x = [rect x] - [rect w];
        drawRect.y = [rect y] - [rect h];
    }

    drawRect.x += xofs;
    drawRect.y += yofs;

    clientRect = drawRect;
    if ([rect h] > 0.0 && [rect w] > 0.0) {

        if (flags & WIN_BORDER && borderSize != 0.0) {
            clientRect.x += borderSize;
            clientRect.y += borderSize;
            clientRect.w -= borderSize;
            clientRect.h -= borderSize;
        }

        textRect = clientRect;
        textRect.x += 2.0;
        textRect.w -= 2.0;
        textRect.y += 2.0;
        textRect.h -= 2.0;
        textRect.x += textAlignx;
        textRect.y += textAligny;

    }
    origin = idVec2_Make( [rect x] + ( [rect w] / 2 ), [rect y] + ( [rect h] / 2 ) );

}

- (void)redraw:(float)x y:(float)y {

    if (!visible.data) {
        return;
    }

    [self calcClientRect:0 yofs:0];
    [dc setFont:fontNum];
    //#modified-fva; BEGIN
    idWindow *parent = mParent;
    if (parent && parent->cstAnchor.data != CST_ANCHOR_NONE) {
        [cstAnchor setData:parent->cstAnchor.data];
        [cstAnchorTo setData:parent->cstAnchorTo.data];
        [cstAnchorFactor setData:parent->cstAnchorFactor.data];
    }
    if (![[gui manager].cvars getBool:@"cst_hudAdjustAspect"] || cstAnchor.data == CST_ANCHOR_NONE) {
        if (parent) {
            [dc setSize:parent->forceAspectWidth height:parent->forceAspectHeight];
        } else {
            [dc setSize:VIRTUAL_WIDTH height:VIRTUAL_HEIGHT];
        }
    } else {
        [dc cstSetSize:cstAnchor.data anchorTo:cstAnchorTo.data factor:cstAnchorFactor.data];
    }
    //#modified-fva; END
    idRectangle_Offset( &drawRect, x, y );
    idRectangle_Offset( &clientRect, x, y );
    idRectangle_Offset( &textRect, x, y );
    [self setupTransforms:x y:y];
    // fva's cst: added cstNoClipBackground
    if ((flags & WIN_NOCLIP) || cstNoClipBackground) {
        [dc enableClipping:NO];
    }
    [self drawBackground:drawRect];
    //#modified-fva; BEGIN
    if (!(flags & WIN_NOCLIP) && cstNoClipBackground) {
        [dc enableClipping:YES];
    }
    //#modified-fva; END
    [self drawBorderAndCaption:drawRect];
    if ( textShadow ) {
        NSString *shadowText = [[text data] ud_stringByRemovingColors];
        idRectangle shadowRect = textRect;

        shadowRect.x += textShadow;
        shadowRect.y += textShadow;

        [dc drawText:shadowText textScale:textScale.data textAlign:textAlign color:idDeviceContext_colorBlack rectDraw:shadowRect wrap:!( flags & WIN_NOWRAP ) cursor:-1];
    }
    [dc drawText:[text data] textScale:textScale.data textAlign:textAlign color:foreColor.data rectDraw:textRect wrap:!( flags & WIN_NOWRAP ) cursor:-1];
    [dc setTransformInfo:vec3_origin mat:mat3_identity];
    if ( flags & WIN_NOCLIP ) {
        [dc enableClipping:YES];
    }
    idRectangle_Offset( &drawRect, -x, -y );
    idRectangle_Offset( &clientRect, -x, -y );
    idRectangle_Offset( &textRect, -x, -y );
}

- (idWinVar *)getWinVarByName:(NSString *)_name {
    idWinVar *retVar = nil;
    if ([_name ud_iequals:@"background"]) {
        retVar = backGroundName;
    }
    if ([_name ud_iequals:@"visible"]) {
        retVar = visible;
    }
    if ([_name ud_iequals:@"rect"]) {
        retVar = rect;
    }
    if ([_name ud_iequals:@"backColor"]) {
        retVar = backColor;
    }
    if ([_name ud_iequals:@"matColor"]) {
        retVar = matColor;
    }
    if ([_name ud_iequals:@"foreColor"]) {
        retVar = foreColor;
    }
    if ([_name ud_iequals:@"borderColor"]) {
        retVar = borderColor;
    }
    if ([_name ud_iequals:@"textScale"]) {
        retVar = textScale;
    }
    if ([_name ud_iequals:@"rotate"]) {
        retVar = rotate;
    }
    if ([_name ud_iequals:@"shear"]) {
        retVar = shear;
    }
    if ([_name ud_iequals:@"text"]) {
        retVar = text;
    }
    //#modified-fva; BEGIN
    if ([_name ud_iequals:@"cstAnchor"]) {
        retVar = cstAnchor;
    } else if ([_name ud_iequals:@"cstAnchorTo"]) {
        retVar = cstAnchorTo;
    } else if ([_name ud_iequals:@"cstAnchorFactor"]) {
        retVar = cstAnchorFactor;
    }
    //#modified-fva; END
    return retVar;
}

@end
