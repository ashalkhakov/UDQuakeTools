/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idGuiScript.m — ui/GuiScript.cpp, ported (its savegame parts left out).
 */

#import "idGuiScript.h"
#import "idWindow.h"
#import "idWinVar.h"
#import "idUserInterface.h"
#import "idDeviceContext.h"
#import "idParser.h"
#import "idToken.h"
#import "idDict.h"
#import "idStr.h"
#import "UDDeclCodec.h"

@implementation idGSWinVar
@end

static inline idWinStr *AsWinStr( idWinVar *var ) {
    return [var isKindOfClass:[idWinStr class]] ? (idWinStr *)var : nil;
}

static inline idWinVec4 *AsWinVec4( idWinVar *var ) {
    return [var isKindOfClass:[idWinVec4 class]] ? (idWinVec4 *)var : nil;
}

/*
=========================
Script_Set
=========================
*/
static void Script_Set( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    idWinStr *dest = AsWinStr( src[0]->var );
    if (dest) {
        if ([[dest data] ud_iequals:@"cmd"]) {
            dest = AsWinStr( src[1]->var );
            NSUInteger parmCount = src.count;
            if (parmCount > 2) {
                NSMutableString *val = [NSMutableString stringWithString:[dest string]];
                NSUInteger i = 2;
                while (i < parmCount) {
                    [val appendString:@" \""];
                    [val appendString:[src[i]->var string]];
                    [val appendString:@"\""];
                    i++;
                }
                [window addCommand:val];
            } else {
                [window addCommand:[dest data]];
            }
            return;
        }
    }
    [src[0]->var set:[src[1]->var string]];
    [src[0]->var setEval:NO];
}

/*
=========================
Script_SetFocus
=========================
*/
static void Script_SetFocus( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    idWinStr *parm = AsWinStr( src[0]->var );
    if (parm) {
        idDrawWin *win = [[[window getGui] getDesktop] findChildByName:[parm data]];
        if (win && win.win) {
            [window setFocus:win.win];
        }
    }
}

/*
=========================
Script_ShowCursor
=========================
*/
static void Script_ShowCursor( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    idWinStr *parm = AsWinStr( src[0]->var );
    if ( parm ) {
        if ( atoi( [parm data].UTF8String ) ) {
            [[[window getGui] getDesktop] clearFlag:WIN_NOCURSOR];
        } else {
            [[[window getGui] getDesktop] setFlag:WIN_NOCURSOR];
        }
    }
}

/*
=========================
Script_RunScript

 run scripts must come after any set cmd set's in the script
=========================
*/
static void Script_RunScript( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    idWinStr *parm = AsWinStr( src[0]->var );
    if (parm) {
        [window->cmd appendString:@" ; runScript "];
        [window->cmd appendString:[parm string]];
    }
}

/*
=========================
Script_LocalSound
=========================
*/
static void Script_LocalSound( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    idWinStr *parm = AsWinStr( src[0]->var );
    if (parm) {
        [[[window getGui] manager] playShaderDirectly:[parm data]];
    }
}

/*
=========================
Script_EvalRegs
=========================
*/
static void Script_EvalRegs( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    [window evalRegs:-1 force:YES];
}

/*
=========================
Script_EndGame
=========================
*/
static void Script_EndGame( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    idUserInterfaceManager *manager = [[window getGui] manager];
    [manager.cvars setBool:@"g_nightmare" value:YES];
    [manager.bufferedCommands addObject:@"disconnect\n"];
}

/*
=========================
Script_ResetTime
=========================
*/
static void Script_ResetTime( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    idWinStr *parm = AsWinStr( src[0]->var );
    idDrawWin *win = nil;
    if (parm && src.count > 1) {
        win = [[[window getGui] getDesktop] findChildByName:[parm data]];
        parm = AsWinStr( src[1]->var );
    }
    if (win && win.win) {
        [win.win resetTime:atoi([parm data].UTF8String)];
        [win.win evalRegs:-1 force:YES];
    } else {
        [window resetTime:atoi([parm data].UTF8String)];
        [window evalRegs:-1 force:YES];
    }
}

/*
=========================
Script_ResetCinematics
=========================
*/
static void Script_ResetCinematics( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    [window resetCinematics];
}

/*
=========================
Script_Transition
=========================
*/
static void Script_Transition( idWindow *window, NSMutableArray<idGSWinVar *> *src ) {
    // transitions always affect rect or vec4 vars
    if (src.count >= 4) {
        idWinRectangle *rect = nil;
        idWinVec4 *vec4 = AsWinVec4( src[0]->var );
        //
        //  added float variable
        idWinFloat* val = nil;
        //
        if (vec4 == nil) {
            rect = [src[0]->var isKindOfClass:[idWinRectangle class]] ? (idWinRectangle *)src[0]->var : nil;
            //
            //  added float variable
            if ( nil == rect ) {
                val = [src[0]->var isKindOfClass:[idWinFloat class]] ? (idWinFloat *)src[0]->var : nil;
            }
            //
        }
        idWinVec4 *from = AsWinVec4( src[1]->var );
        idWinVec4 *to = AsWinVec4( src[2]->var );
        idWinStr *timeStr = AsWinStr( src[3]->var );
        //
        //  added float variable
        if (!((vec4 || rect || val) && from && to && timeStr)) {
            //
            [[[window getGui] manager] uiWarning:[NSString stringWithFormat:@"Bad transition in gui %@ in window %@", [[window getGui] getSourceFile], [window getName]]];
            return;
        }
        int time = atoi([timeStr data].UTF8String);
        float ac = 0.0f;
        float dc = 0.0f;
        if (src.count > 4) {
            idWinStr *acv = AsWinStr( src[4]->var );
            idWinStr *dcv = src.count > 5 ? AsWinStr( src[5]->var ) : nil;
            assert(acv && dcv);
            ac = atof([acv data].UTF8String);
            dc = atof([dcv data].UTF8String);
        }

        if (vec4) {
            [vec4 setEval:NO];
            [window addTransition:vec4 from:[from data] to:[to data] time:time accelTime:ac decelTime:dc];
            //
            //  added float variable
        } else if ( val ) {
            [val setEval:NO];
            [window addTransition:val from:[from data] to:[to data] time:time accelTime:ac decelTime:dc];
            //
        } else {
            [rect setEval:NO];
            [window addTransition:rect from:[from data] to:[to data] time:time accelTime:ac decelTime:dc];
        }
        [window startTransition];
    }
}

typedef struct {
    const char *name;
    idGuiScriptHandler handler;
    int mMinParms;
    int mMaxParms;
} guiCommandDef_t;

static const guiCommandDef_t commandList[] = {
    { "set", Script_Set, 2, 999 },
    { "setFocus", Script_SetFocus, 1, 1 },
    { "endGame", Script_EndGame, 0, 0 },
    { "resetTime", Script_ResetTime, 0, 2 },
    { "showCursor", Script_ShowCursor, 1, 1 },
    { "resetCinematics", Script_ResetCinematics, 0, 2 },
    { "transition", Script_Transition, 4, 6 },
    { "localSound", Script_LocalSound, 1, 1 },
    { "runScript", Script_RunScript, 1, 1 },
    { "evalRegs", Script_EvalRegs, 0, 0 }
};

static const int scriptCommandCount = sizeof(commandList) / sizeof(guiCommandDef_t);

@implementation idGuiScript

/*
=========================
idGuiScript::idGuiScript
=========================
*/
- (instancetype)init {
    self = [super init];
    if (self) {
        ifList = nil;
        elseList = nil;
        conditionReg = -1;
        handler = NULL;
        parms = [NSMutableArray array];
    }
    return self;
}

- (void)execute:(idWindow *)win {
    if (handler) {
        handler(win, parms);
    }
}

- (NSString *)commandName {
    for ( int i = 0; i < scriptCommandCount; i++ ) {
        if ( handler == commandList[i].handler ) {
            return [NSString stringWithUTF8String:commandList[i].name];
        }
    }
    return nil;
}

/*
=========================
idGuiScript::Parse
=========================
*/
- (BOOL)parse:(idParser *)src {
    int i;

    // first token should be function call
    // then a potentially variable set of parms
    // ended with a ;
    idToken token;
    idToken_Init( &token );
    if ( ![src readToken:&token error:NULL] ) {
        [src error:NULL format:@"Unexpected end of file"];
        return NO;
    }

    handler = NULL;

    for ( i = 0; i < scriptCommandCount ; i++ ) {
        if ( UDTokenIcmp( &token, commandList[i].name ) ) {
            handler = commandList[i].handler;
            break;
        }
    }

    if (handler == NULL) {
        [src error:NULL format:@"Unknown script call %s", token.text];
    }
    // now read parms til ;
    // all parms are read as idWinStr's but will be fixed up later
    // to be proper types
    while (1) {
        if ( ![src readToken:&token error:NULL] ) {
            [src error:NULL format:@"Unexpected end of file"];
            return NO;
        }

        if ( UDTokenIcmp( &token, ";" ) ) {
            break;
        }

        if ( UDTokenIcmp( &token, "}" ) ) {
            [src unreadToken:&token];
            break;
        }

        idWinStr *str = [[idWinStr alloc] init];
        [str setData:UDTokenLatin1String( &token )];
        idGSWinVar *wv = [[idGSWinVar alloc] init];
        wv->own = YES;
        wv->var = str;
        [parms addObject:wv];
    }

    //
    //  verify min/max params
    if ( handler && ((int)parms.count < commandList[i].mMinParms || (int)parms.count > commandList[i].mMaxParms ) ) {
        [src error:NULL format:@"incorrect number of parameters for script %s", commandList[i].name];
    }
    //

    return YES;
}

/*
=========================
idGuiScriptList::FixupParms
=========================
*/
- (void)fixupParms:(idWindow *)win {
    idUserInterfaceManager *manager = [[win getGui] manager];
    if (handler == &Script_Set) {
        BOOL precacheBackground = NO;
        BOOL precacheSounds = NO;
        idWinStr *str = AsWinStr( parms[0]->var );
        assert(str);
        idWinVar *dest = [win getWinVarByName:[str data] fixup:YES owner:NULL];
        if (dest) {
            parms[0]->var = dest;
            parms[0]->own = NO;

            if ( [dest isKindOfClass:[idWinBackground class]] ) {
                precacheBackground = YES;
            }
        } else if ( [[str string] ud_iequals:@"cmd"] ) {
            precacheSounds = YES;
        }
        NSUInteger parmCount = parms.count;
        for (NSUInteger i = 1; i < parmCount; i++) {
            idWinStr *parm = AsWinStr( parms[i]->var );
            if ([[parm data] ud_icmpn:@"gui::" length:5] == 0) {

                //  always use a string here, no point using a float if it is one
                //  FIXME: This creates duplicate variables, while not technically a problem since they
                //  are all bound to the same guiDict, it does consume extra memory and is generally a bad thing
                idWinStr* defvar = [[idWinStr alloc] init];
                [defvar winVarInit:[parm data] window:win];
                [win addDefinedVar:defvar];
                parms[i]->var = defvar;
                parms[i]->own = NO;

                //dest = win->GetWinVarByName(*str, true);
                //if (dest) {
                //  delete parms[i].var;
                //  parms[i].var = dest;
                //  parms[i].own = false;
                //}
                //
            } else if ([[parm data] hasPrefix:@"$"]) {
                //
                //  dont include the $ when asking for variable
                dest = [[[win getGui] getDesktop] getWinVarByName:[[parm data] substringFromIndex:1] fixup:YES owner:NULL];
                //
                if (dest) {
                    parms[i]->var = dest;
                    parms[i]->own = NO;
                }
            } else if ( [[parm string] ud_cmpn:STRTABLE_ID length:STRTABLE_ID_LENGTH] == 0 ) {
                [parm set:[manager.languageDict getString:[parm string]]];
            } else if ( precacheBackground ) {
                idMaterial *mat = [manager findMaterial:[parm string]];
                [mat setSort:SS_GUI];
            } else if ( precacheSounds ) {
                // Search for "play <...>": declManager->FindSound, which
                // only loads the sound
            }
        }
    } else if (handler == &Script_Transition) {
        if (parms.count < 4) {
            [manager uiWarning:[NSString stringWithFormat:@"Window %@ in gui %@ has a bad transition definition", [win getName], [[win getGui] getSourceFile]]];
        }
        idWinStr *str = AsWinStr( parms[0]->var );
        assert(str);

        //
        idDrawWin *destowner = nil;
        idWinVar *dest = [win getWinVarByName:[str data] fixup:YES owner:&destowner];
        //

        if (dest) {
            parms[0]->var = dest;
            parms[0]->own = NO;
        } else {
            [manager uiWarning:[NSString stringWithFormat:@"Window %@ in gui %@: a transition does not have a valid destination var %@", [win getName], [[win getGui] getSourceFile], [str string]]];
        }

        //
        //  support variables as parameters
        for ( NSUInteger c = 1; c < 3 && c < parms.count; c ++ ) {
            str = AsWinStr( parms[c]->var );

            idWinVec4 *v4 = [[idWinVec4 alloc] init];
            parms[c]->var = v4;
            parms[c]->own = YES;

            idDrawWin* owner = nil;

            if ( [[str data] hasPrefix:@"$"] ) {
                dest = [win getWinVarByName:[[str data] substringFromIndex:1] fixup:YES owner:&owner];
            } else {
                dest = nil;
            }

            if ( dest ) {
                idWindow* ownerparent;
                idWindow* destparent;
                if ( owner ) {
                    ownerparent = owner.simp ? [owner.simp getParent] : [owner.win getParent];
                    destparent  = destowner.simp ? [destowner.simp getParent] : [destowner.win getParent];

                    // If its the rectangle they are referencing then adjust it
                    if ( ownerparent && destparent &&
                        (dest == (owner.simp ? [owner.simp getWinVarByName:@"rect"] : [owner.win getWinVarByName:@"rect"] ) ) )
                    {
                        idRectangle rect;
                        rect = [(idWinRectangle *)dest data];
                        [ownerparent clientToScreen:&rect];
                        [destparent screenToClient:&rect];
                        [v4 setData:idRectangle_ToVec4( &rect )];
                    } else {
                        [v4 set:[dest string]];
                    }
                } else {
                    [v4 set:[dest string]];
                }
            } else {
                [v4 set:[str data]];
            }
        }
        //

    } else {
        for ( idGSWinVar *parm in parms ) {
            [parm->var winVarInit:[parm->var string] window:win];
        }
    }
}

@end

@implementation idGuiScriptList

- (instancetype)init {
    self = [super init];
    if (self) {
        _list = [NSMutableArray array];
    }
    return self;
}

- (void)append:(idGuiScript *)gs {
    [self.list addObject:gs];
}

/*
=========================
idGuiScriptList::Execute
=========================
*/
- (void)execute:(idWindow *)win {
    // the list as it is now: a script may change the window's scripts
    NSArray<idGuiScript *> *list = [self.list copy];
    for ( idGuiScript *gs in list ) {
        assert(gs);
        if (gs->conditionReg >= 0) {
            if ([win hasOps]) {
                float f = [win evalRegs:gs->conditionReg force:NO];
                if (f) {
                    if (gs->ifList) {
                        [win runScriptList:gs->ifList];
                    }
                } else if (gs->elseList) {
                    [win runScriptList:gs->elseList];
                }
            }
        }
        [gs execute:win];
    }
}

/*
=========================
idGuiScriptList::FixupParms
=========================
*/
- (void)fixupParms:(idWindow *)win {
    for ( idGuiScript *gs in self.list ) {
        [gs fixupParms:win];
        if (gs->ifList) {
            [gs->ifList fixupParms:win];
        }
        if (gs->elseList) {
            [gs->elseList fixupParms:win];
        }
    }
}

@end
