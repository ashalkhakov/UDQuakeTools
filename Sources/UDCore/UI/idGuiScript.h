/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idGuiScript.h — GUI script commands (ui/GuiScript.h, GuiScript.cpp),
 * ported: set, setFocus, endGame, resetTime, showCursor, resetCinematics,
 * transition, localSound, runScript, evalRegs, and if/else.
 */

#import <Foundation/Foundation.h>

@class idParser, idWindow, idWinVar, idGuiScriptList;

NS_ASSUME_NONNULL_BEGIN

@interface idGSWinVar : NSObject {
@public
    idWinVar *_Nullable var;
    BOOL own;
}
@end

typedef void (*idGuiScriptHandler)( idWindow *window, NSMutableArray<idGSWinVar *> *src );

@interface idGuiScript : NSObject {
@public
    int conditionReg;
    idGuiScriptList *_Nullable ifList;
    idGuiScriptList *_Nullable elseList;
    NSMutableArray<idGSWinVar *> *parms;
    idGuiScriptHandler _Nullable handler;
}
- (BOOL)parse:(idParser *)src;
- (void)execute:(idWindow *)win;
- (void)fixupParms:(idWindow *)win;
/// The command's name, as commandList has it (nil for an unknown one).
- (nullable NSString *)commandName;
@end

@interface idGuiScriptList : NSObject
@property (nonatomic, strong, readonly) NSMutableArray<idGuiScript *> *list;
- (void)execute:(idWindow *)win;
- (void)append:(idGuiScript *)gs;
- (void)fixupParms:(idWindow *)win;
@end

NS_ASSUME_NONNULL_END
