/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idSliderWindow.m — ui/SliderWindow.cpp, ported. See idSliderWindow.h.
 */

#import "idSliderWindow.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "UDDeclCodec.h"
#import "idDeviceContext.h"
#import "idCVarSystem.h"
#import "idDict.h"
#import "idParser.h"

@implementation idSliderWindow

/*
============
idSliderWindow::CommonInit
============
*/
- (void)sliderCommonInit {
    [value setData:0.0];
    low = 0.0;
    high = 100.0;
    stepSize = 1.0;
    thumbMat = [[gui manager] findMaterial:@"_default"];
    buddyWin = nil;

    cvar = nil;
    cvar_init = NO;
    [liveUpdate setData:YES];

    vertical = NO;
    scrollbar = NO;

    verticalFlip = NO;
}

- (void)constructSliderMembers {
    value = [[idWinFloat alloc] init];
    thumbShader = @"";
    cvarStr = [[idWinStr alloc] init];
    liveUpdate = [[idWinBool alloc] init];
    cvarGroup = [[idWinStr alloc] init];
}

- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)g {
    self = [super initWithDC:d gui:g];
    if (self) {
        [self constructSliderMembers];
        dc = d;
        gui = g;
        [self sliderCommonInit];
    }
    return self;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)g {
    self = [super initWithGui:g];
    if (self) {
        [self constructSliderMembers];
        gui = g;
        [self sliderCommonInit];
    }
    return self;
}


- (BOOL)parseInternalVar:(NSString *)_name parser:(idParser *)src {
    if ([_name ud_iequals:@"stepsize"] || [_name ud_iequals:@"step"]) {
        float f = 0.0f;
        [src parseFloat:&f error:NULL];
        stepSize = f;
        return YES;
    }
    if ([_name ud_iequals:@"low"]) {
        float f = 0.0f;
        [src parseFloat:&f error:NULL];
        low = f;
        return YES;
    }
    if ([_name ud_iequals:@"high"]) {
        float f = 0.0f;
        [src parseFloat:&f error:NULL];
        high = f;
        return YES;
    }
    if ([_name ud_iequals:@"vertical"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        vertical = b;
        return YES;
    }
    if ([_name ud_iequals:@"verticalflip"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        verticalFlip = b;
        return YES;
    }
    if ([_name ud_iequals:@"scrollbar"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        scrollbar = b;
        return YES;
    }
    if ([_name ud_iequals:@"thumbshader"]) {
        thumbShader = [self parseString:src] ?: thumbShader;
        [[gui manager] findMaterial:thumbShader];
        return YES;
    }
    return [super parseInternalVar:_name parser:src];
}

- (idWinVar *)getWinVarByName:(NSString *)_name fixup:(BOOL)fixup owner:(idDrawWin **)owner {

    if ([_name ud_iequals:@"value"]) {
        return value;
    }
    if ([_name ud_iequals:@"cvar"]) {
        return cvarStr;
    }
    if ( [_name ud_iequals:@"liveUpdate"] ) {
        return liveUpdate;
    }
    if ( [_name ud_iequals:@"cvarGroup"] ) {
        return cvarGroup;
    }

    return [super getWinVarByName:_name fixup:fixup owner:owner];
}

- (NSString *)handleEvent:(const sysEvent_t *)event updateVisuals:(BOOL *)updateVisuals {

    if (!(event->evType == SE_KEY && event->evValue2)) {
        return @"";
    }

    int key = event->evValue;

    if ( event->evValue2 && key == K_MOUSE1 ) {
        [self setCapture:self];
        [self routeMouseCoords:0.0f yd:0.0f];
        return @"";
    }

    if ( key == K_RIGHTARROW || key == K_KP_RIGHTARROW || ( key == K_MOUSE2 && [gui cursorY] > thumbRect.y ) )  {
        [value setData:value.data + stepSize];
    }

    if ( key == K_LEFTARROW || key == K_KP_LEFTARROW || ( key == K_MOUSE2 && [gui cursorY] < thumbRect.y ) ) {
        [value setData:value.data - stepSize];
    }

    idWindow *buddy = buddyWin;
    if (buddy) {
        [buddy handleBuddyUpdate:self];
    } else {
        [gui setStateFloat:[cvarStr string] value:value.data];
        [self updateCvar:NO force:NO];
    }

    return @"";
}


- (void)setBuddy:(idWindow *)buddy {
    buddyWin = buddy;
}

- (void)postParse {
    [super postParse];
    [value setData:0.0];
    thumbMat = [[gui manager] findMaterial:thumbShader];
    [thumbMat setSort:SS_GUI];
    thumbWidth = [thumbMat getImageWidth];
    thumbHeight = [thumbMat getImageHeight];
    //vertical = state.GetBool("vertical");
    //scrollbar = state.GetBool("scrollbar");
    flags |= (WIN_HOLDCAPTURE | WIN_CANFOCUS);
    [self initCvar];
}

- (void)initWithDefaults:(NSString *)_name rect:(idRectangle)_rect foreColor:(idVec4)_foreColor matColor:(idVec4)_matColor
              background:(NSString *)_background thumbShader:(NSString *)_thumbShader vertical:(BOOL)_vertical scrollbar:(BOOL)_scrollbar {
    [self setInitialState:_name];
    [rect setData:_rect];
    [foreColor setData:_foreColor];
    [matColor setData:_matColor];
    thumbMat = [[gui manager] findMaterial:_thumbShader];
    [thumbMat setSort:SS_GUI];
    thumbWidth = [thumbMat getImageWidth];
    thumbHeight = [thumbMat getImageHeight];
    background = [[gui manager] findMaterial:_background];
    [background setSort:SS_GUI];
    vertical = _vertical;
    scrollbar = _scrollbar;
    flags |= WIN_HOLDCAPTURE;
}

- (void)setRange:(float)_low high:(float)_high step:(float)_step {
    low = _low;
    high = _high;
    stepSize = _step;
}

- (float)getLow { return low; }
- (float)getHigh { return high; }

- (void)setValue:(float)_value {
    [value setData:_value];
}

- (float)getValue {
    return value.data;
}

- (void)draw:(int)time x:(float)x y:(float)y {
    idVec4 color = foreColor.data;

    if ( !cvar && !buddyWin ) {
        return;
    }

    if ( !thumbWidth || !thumbHeight ) {
        thumbWidth = [thumbMat getImageWidth];
        thumbHeight = [thumbMat getImageHeight];
    }

    [self updateCvar:YES force:NO];
    if ( value.data > high ) {
        [value setData:high];
    } else if ( value.data < low ) {
        [value setData:low];
    }

    float range = high - low;

    if ( range <= 0.0f ) {
        return;
    }

    float thumbPos = (range) ? (value.data - low) / range : 0.0;
    if (vertical) {
        if ( verticalFlip ) {
            thumbPos = 1.f - thumbPos;
        }
        thumbPos *= drawRect.h - thumbHeight;
        thumbPos += drawRect.y;
        thumbRect.y = thumbPos;
        thumbRect.x = drawRect.x;
    } else {
        thumbPos *= drawRect.w - thumbWidth;
        thumbPos += drawRect.x;
        thumbRect.x = thumbPos;
        thumbRect.y = drawRect.y;
    }
    thumbRect.w = thumbWidth;
    thumbRect.h = thumbHeight;

    if ( hover && !noEvents.data && [self contains:[gui cursorX] y:[gui cursorY]] ) {
        color = hoverColor.data;
    } else {
        hover = NO;
    }
    if ( flags & WIN_CAPTURE ) {
        color = hoverColor.data;
        hover = YES;
    }

    [dc drawMaterial:thumbRect.x y:thumbRect.y w:thumbRect.w h:thumbRect.h mat:thumbMat color:color];
    if ( flags & WIN_FOCUS ) {
        [dc drawRect:thumbRect.x+1.0f y:thumbRect.y+1.0f width:thumbRect.w-2.0f height:thumbRect.h-2.0f size:1.0f color:color];
    }
}


- (void)drawBackground:(idRectangle)_drawRect {
    if ( !cvar && !buddyWin ) {
        return;
    }

    if ( high - low <= 0.0f ) {
        return;
    }

    idRectangle r = _drawRect;
    if (!scrollbar) {
        if ( vertical ) {
            r.y += thumbHeight / 2.f;
            r.h -= thumbHeight;
        } else {
            r.x += thumbWidth / 2.0;
            r.w -= thumbWidth;
        }
    }
    [super drawBackground:r];
}

- (NSString *)routeMouseCoords:(float)xd yd:(float)yd {
    float pct;

    if (!(flags & WIN_CAPTURE)) {
        return @"";
    }

    idRectangle r = drawRect;
    r.x = actualX;
    r.y = actualY;
    r.x += thumbWidth / 2.0;
    r.w -= thumbWidth;
    if (vertical) {
        r.y += thumbHeight / 2;
        r.h -= thumbHeight;
        if ([gui cursorY] >= r.y && [gui cursorY] <= idRectangle_Bottom( &r )) {
            pct = ([gui cursorY] - r.y) / r.h;
            if ( verticalFlip ) {
                pct = 1.f - pct;
            }
            [value setData:low + (high - low) * pct];
        } else if ([gui cursorY] < r.y) {
            if ( verticalFlip ) {
                [value setData:high];
            } else {
                [value setData:low];
            }
        } else {
            if ( verticalFlip ) {
                [value setData:low];
            } else {
                [value setData:high];
            }
        }
    } else {
        r.x += thumbWidth / 2;
        r.w -= thumbWidth;
        if ([gui cursorX] >= r.x && [gui cursorX] <= idRectangle_Right( &r )) {
            pct = ([gui cursorX] - r.x) / r.w;
            [value setData:low + (high - low) * pct];
        } else if ([gui cursorX] < r.x) {
            [value setData:low];
        } else {
            [value setData:high];
        }
    }

    idWindow *buddy = buddyWin;
    if (buddy) {
        [buddy handleBuddyUpdate:self];
    } else {
        [gui setStateFloat:[cvarStr string] value:value.data];
    }
    [self updateCvar:NO force:NO];

    return @"";
}


- (void)activate:(BOOL)activate act:(NSMutableString *)act {
    [super activate:activate act:act];
    if ( activate ) {
        [self updateCvar:YES force:YES];
    }
}

/*
============
idSliderWindow::InitCvar
============
*/
- (void)initCvar {
    if ( [cvarStr string].length == 0 ) {
        if ( !buddyWin ) {
            [[gui manager] uiWarning:[NSString stringWithFormat:@"idSliderWindow::InitCvar: gui '%@' window '%@' has an empty cvar string", [gui getSourceFile], name]];
        }
        cvar_init = YES;
        cvar = nil;
        return;
    }

    cvar = [[gui manager].cvars find:[cvarStr string]];
    if ( !cvar ) {
        [[gui manager] uiWarning:[NSString stringWithFormat:@"idSliderWindow::InitCvar: gui '%@' window '%@' references undefined cvar '%@'", [gui getSourceFile], name, [cvarStr string]]];
        cvar_init = YES;
        return;
    }
}

/*
============
idSliderWindow::UpdateCvar
============
*/
- (void)updateCvar:(BOOL)read force:(BOOL)force {
    if ( buddyWin || !cvar ) {
        return;
    }
    if ( force || liveUpdate.data ) {
        [value setData:[cvar getFloat]];
        if ( value.data != [[gui state] getFloat:[cvarStr string]] ) {
            if ( read ) {
                [gui setStateFloat:[cvarStr string] value:value.data];
            } else {
                [value setData:[[gui state] getFloat:[cvarStr string]]];
                [cvar setFloat:value.data];
            }
        }
    }
}

/*
============
idSliderWindow::RunNamedEvent
============
*/
- (void)runNamedEvent:(NSString *)eventName {
    if ( ![eventName ud_cmpn:@"cvar read " length:10] ) {
        NSString *group = [eventName substringFromIndex:10];
        if ( [group isEqualToString:[cvarGroup string]] ) {
            [self updateCvar:YES force:YES];
        }
    } else if ( ![eventName ud_cmpn:@"cvar write " length:11] ) {
        NSString *group = [eventName substringFromIndex:11];
        if ( [group isEqualToString:[cvarGroup string]] ) {
            [self updateCvar:NO force:YES];
        }
    }
}

@end
