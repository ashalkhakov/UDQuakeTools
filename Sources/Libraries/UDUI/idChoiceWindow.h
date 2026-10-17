/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idChoiceWindow.h — a choiceDef (ui/ChoiceWindow.h, ChoiceWindow.cpp), ported.
 */

#import "idWindow.h"

@class idCVar;

NS_ASSUME_NONNULL_BEGIN

@interface idChoiceWindow : idWindow {
@public
    int                 currentChoice;
    int                 choiceType;
    NSString *          latchedChoices;
    idWinStr *          choicesStr;
    NSString *          latchedVals;
    idWinStr *          choiceVals;
    NSMutableArray<NSString *> *choices;    // idStrList, Latin-1
    NSMutableArray<NSString *> *values;
    idWinStr *          guiStr;
    idWinStr *          cvarStr;
    idCVar *_Nullable   cvar;
    idMultiWinVar *     updateStr;
    idWinBool *         liveUpdate;
    idWinStr *          updateGroup;
}
@end

/// R_GetVidModeListString, R_GetVidModeValsString (renderer/RenderSystem_init.cpp)
NSString *R_GetVidModeListString( BOOL addCustom );
NSString *R_GetVidModeValsString( BOOL addCustom );

NS_ASSUME_NONNULL_END
