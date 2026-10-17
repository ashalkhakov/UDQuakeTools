/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idEditWindow.h — an editDef (ui/EditWindow.h, EditWindow.cpp), ported.
 */

#import "idWindow.h"

@class idSliderWindow, idCVar;

NS_ASSUME_NONNULL_BEGIN

#define MAX_EDITFIELD   4096

@interface idEditWindow : idWindow {
@public
    int                 maxChars;
    int                 paintOffset;
    int                 cursorPos;
    int                 cursorLine;
    int                 cvarMax;
    BOOL                wrap;
    BOOL                readonly;
    BOOL                numeric;
    NSString *          sourceFile;
    idSliderWindow *    scroller;
    NSMutableArray<NSNumber *> *breaks;
    float               sizeBias;
    int                 textIndex;
    int                 lastTextLength;
    BOOL                forceScroll;
    idWinBool *         password;
    idWinStr *          cvarStr;
    idCVar *_Nullable   cvar;
    idWinBool *         liveUpdate;
    idWinStr *          cvarGroup;
}
@end

NS_ASSUME_NONNULL_END
