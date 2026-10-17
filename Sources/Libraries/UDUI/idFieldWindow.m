/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idFieldWindow.m — ui/FieldWindow.cpp, ported. See idFieldWindow.h.
 */

#import "idFieldWindow.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "UDDeclCodec.h"
#import "idDeviceContext.h"
#import "idDict.h"
#import "idParser.h"

@implementation idFieldWindow

- (void)fieldCommonInit {
    cursorPos = 0;
    lastTextLength = 0;
    lastCursorPos = 0;
    paintOffset = 0;
    showCursor = NO;
}

- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)g {
    self = [super initWithDC:d gui:g];
    if (self) {
        cursorVar = @"";
        dc = d;
        gui = g;
        [self fieldCommonInit];
    }
    return self;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)g {
    self = [super initWithGui:g];
    if (self) {
        cursorVar = @"";
        gui = g;
        [self fieldCommonInit];
    }
    return self;
}


- (BOOL)parseInternalVar:(NSString *)_name parser:(idParser *)src {
    if ([_name ud_iequals:@"cursorvar"]) {
        cursorVar = [self parseString:src] ?: cursorVar;
        return YES;
    }
    if ([_name ud_iequals:@"showcursor"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        showCursor = b;
        return YES;
    }
    return [super parseInternalVar:_name parser:src];
}


- (void)calcPaintOffset:(int)len {
    lastCursorPos = cursorPos;
    lastTextLength = len;
    paintOffset = 0;
    int tw = [dc textWidth:[text data] scale:textScale.data limit:-1];
    if (tw < textRect.w) {
        return;
    }
    while (tw > textRect.w && len > 0) {
        tw = [dc textWidth:[text data] scale:textScale.data limit:--len];
        paintOffset++;
    }
}


- (void)draw:(int)time x:(float)x y:(float)y {
    float scale = textScale.data;
    int len = [text length];
    cursorPos = [[gui state] getInt:cursorVar];
    if (len != lastTextLength || cursorPos != lastCursorPos) {
        [self calcPaintOffset:len];
    }
    idRectangle drawRectangle = textRect;
    if (paintOffset >= len) {
        paintOffset = 0;
    }
    if (cursorPos > len) {
        cursorPos = len;
    }
    [dc drawText:[[text data] substringFromIndex:paintOffset] textScale:scale textAlign:0 color:foreColor.data rectDraw:drawRectangle wrap:NO cursor:((flags & WIN_FOCUS) || showCursor) ? cursorPos - paintOffset : -1];
}

@end
