/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idRenderWindow.m — ui/RenderWindow.cpp, ported but for the render world
 * (see idRenderWindow.h).
 */

#import "idRenderWindow.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "UDDeclCodec.h"
#import "idDeviceContext.h"
#import "idParser.h"

@implementation idRenderWindow

- (void)renderCommonInit {
    // world = renderSystem->AllocRenderWorld(): no render world here
    [needsRender setData:YES];
    [lightOrigin setData:idVec4_Make(-128.0f, 0.0f, 0.0f, 1.0f)];
    [lightColor setData:idVec4_Make(1.0f, 1.0f, 1.0f, 1.0f)];
    [modelOrigin zero];
    [viewOffset setData:idVec4_Make(-128.0f, 0.0f, 0.0f, 1.0f)];
    animLength = 0;
    animEndTime = -1;
    updateAnimation = YES;
}

- (void)constructRenderMembers {
    modelName = [[idWinStr alloc] init];
    animName = [[idWinStr alloc] init];
    animClass = @"";
    lightOrigin = [[idWinVec4 alloc] init];
    lightColor = [[idWinVec4 alloc] init];
    modelOrigin = [[idWinVec4 alloc] init];
    modelRotate = [[idWinVec4 alloc] init];
    viewOffset = [[idWinVec4 alloc] init];
    needsRender = [[idWinBool alloc] init];
}

- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)g {
    self = [super initWithDC:d gui:g];
    if (self) {
        [self constructRenderMembers];
        dc = d;
        gui = g;
        [self renderCommonInit];
    }
    return self;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)g {
    self = [super initWithGui:g];
    if (self) {
        [self constructRenderMembers];
        gui = g;
        [self renderCommonInit];
    }
    return self;
}


/*
 PreRender: the light and the model spawned into the render world
 (gameEdit->ParseSpawnArgsToRenderLight, …ToRenderEntity) once needsRender.
*/
- (void)preRender {
    if (needsRender.data) {
        if ( ![modelName string].length ) {
            [[gui manager] uiWarning:[NSString stringWithFormat:@"Window '%@' in gui '%@': no model set", [self getName], [[self getGui] getSourceFile]]];
        }
        [needsRender setData:NO];
    }
}

- (void)draw:(int)time x:(float)x_ y:(float)y_ {
    [self preRender];
    // Render( time ): the light and model updated in the render world

    memset( &refdef, 0, sizeof( refdef ) );
    refdef.vieworg = [viewOffset toVec3];
    //refdef.vieworg.Set(-128, 0, 0);

    idMat3_Identity( &refdef.viewaxis );
    refdef.shaderParms[0] = 1;
    refdef.shaderParms[1] = 1;
    refdef.shaderParms[2] = 1;
    refdef.shaderParms[3] = 1;

    // DG: for scaling menus to 4:3 (like that spinning mars globe in the main menu)
    float x = drawRect.x;
    float y = drawRect.y;
    float w = drawRect.w;
    float h = drawRect.h;
    if([dc isMenuScaleFixActive]) {
        [dc adjustCoords:&x y:&y w:&w h:&h];
    }

    refdef.x = x;
    refdef.y = y;
    refdef.width = w;
    refdef.height = h;
    // DG end
    refdef.fov_x = 90;
    refdef.fov_y = 2 * atanf((float)drawRect.h / drawRect.w) * ( 180.0f / (float)M_PI );

    refdef.time = time;
    // world->RenderScene( &refdef ): not drawn here
}

- (void)postParse {
    [super postParse];
}

//
//
- (idWinVar *)getWinVarByName:(NSString *)_name fixup:(BOOL)fixup owner:(idDrawWin **)owner {
//
    if ([_name ud_iequals:@"model"]) {
        return modelName;
    }
    if ([_name ud_iequals:@"anim"]) {
        return animName;
    }
    if ([_name ud_iequals:@"lightOrigin"]) {
        return lightOrigin;
    }
    if ([_name ud_iequals:@"lightColor"]) {
        return lightColor;
    }
    if ([_name ud_iequals:@"modelOrigin"]) {
        return modelOrigin;
    }
    if ([_name ud_iequals:@"modelRotate"]) {
        return modelRotate;
    }
    if ([_name ud_iequals:@"viewOffset"]) {
        return viewOffset;
    }
    if ([_name ud_iequals:@"needsRender"]) {
        return needsRender;
    }

//
//
    return [super getWinVarByName:_name fixup:fixup owner:owner];
//
}

- (BOOL)parseInternalVar:(NSString *)_name parser:(idParser *)src {
    if ([_name ud_iequals:@"animClass"]) {
        animClass = [self parseString:src] ?: animClass;
        return YES;
    }
    return [super parseInternalVar:_name parser:src];
}

@end
