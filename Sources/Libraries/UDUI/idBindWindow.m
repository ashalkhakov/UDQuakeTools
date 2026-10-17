/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idBindWindow.m — ui/BindWindow.cpp, ported. See idBindWindow.h.
 */

#import "idBindWindow.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "UDDeclCodec.h"
#import "idDeviceContext.h"

@implementation idBindWindow

- (void)bindCommonInit {
    [bindName setData:@""];
    waitingOnKey = NO;
}

- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)g {
    self = [super initWithDC:d gui:g];
    if (self) {
        bindName = [[idWinStr alloc] init];
        dc = d;
        gui = g;
        [self bindCommonInit];
    }
    return self;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)g {
    self = [super initWithGui:g];
    if (self) {
        bindName = [[idWinStr alloc] init];
        gui = g;
        [self bindCommonInit];
    }
    return self;
}

- (NSString *)handleEvent:(const sysEvent_t *)event updateVisuals:(BOOL *)updateVisuals {
    if (!(event->evType == SE_KEY && event->evValue2)) {
        return @"";
    }

    int key = event->evValue;

    if (waitingOnKey) {
        waitingOnKey = NO;
        if (key == K_ESCAPE) {
            return [NSString stringWithFormat:@"clearbind \"%@\"", [bindName getName]];
        } else {
            return [NSString stringWithFormat:@"bind %i \"%@\"", key, [bindName getName]];
        }
    } else {
        if (key == K_MOUSE1) {
            waitingOnKey = YES;
            [gui setBindHandler:self];
            return @"";
        }
    }

    return @"";
}

- (idWinVar *)getWinVarByName:(NSString *)_name fixup:(BOOL)fixup owner:(idDrawWin **)owner {

    if ([_name ud_iequals:@"bind"]) {
        return bindName;
    }

    return [super getWinVarByName:_name fixup:fixup owner:owner];
}

- (void)postParse {
    [super postParse];
    [bindName setGuiInfo:[gui getStateDict] name:[bindName data]];
    [bindName update];
    //bindName = state.GetString("bind");
    flags |= (WIN_HOLDCAPTURE | WIN_CANFOCUS);
}

- (void)draw:(int)time x:(float)x y:(float)y {
    idVec4 color = foreColor.data;
    idLangDict *languageDict = [gui manager].languageDict;

    NSString *str;
    if ( waitingOnKey ) {
        str = [languageDict getString:@"#str_07000"];
    } else if ( [bindName length] ) {
        str = [bindName string];
    } else {
        str = [languageDict getString:@"#str_07001"];
    }

    if ( waitingOnKey || ( hover && !noEvents.data && [self contains:[gui cursorX] y:[gui cursorY]] ) ) {
        color = hoverColor.data;
    } else {
        hover = NO;
    }

    [dc drawText:str textScale:textScale.data textAlign:textAlign color:color rectDraw:textRect wrap:NO cursor:-1];
}

- (void)activate:(BOOL)activate act:(NSMutableString *)act {
    [super activate:activate act:act];
    [bindName update];
}

@end
