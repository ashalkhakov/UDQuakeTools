/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idSliderWindow.h — a sliderDef (ui/SliderWindow.h, SliderWindow.cpp),
 * ported; also the scroll bar of edit and list windows.
 */

#import "idWindow.h"

@class idCVar;

NS_ASSUME_NONNULL_BEGIN

@interface idSliderWindow : idWindow {
@public
    idWinFloat *        value;
    float               low;
    float               high;
    float               thumbWidth;
    float               thumbHeight;
    float               stepSize;
    float               lastValue;
    idRectangle         thumbRect;
    idMaterial *        thumbMat;
    BOOL                vertical;
    BOOL                verticalFlip;
    BOOL                scrollbar;
    __weak idWindow *   buddyWin;
    NSString *          thumbShader;

    idWinStr *          cvarStr;
    idCVar *_Nullable   cvar;
    BOOL                cvar_init;
    idWinBool *         liveUpdate;
    idWinStr *          cvarGroup;
}

- (void)initWithDefaults:(NSString *)_name rect:(idRectangle)_rect foreColor:(idVec4)_foreColor matColor:(idVec4)_matColor
              background:(NSString *)_background thumbShader:(NSString *)thumbShader vertical:(BOOL)_vertical scrollbar:(BOOL)_scrollbar;
- (void)setRange:(float)_low high:(float)_high step:(float)_step;
- (float)getLow;
- (float)getHigh;
- (void)setValue:(float)_value;
- (float)getValue;

@end

NS_ASSUME_NONNULL_END
