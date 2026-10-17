/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idWindow.m — ui/Window.cpp, ported (its demo and savegame parts, and the
 * GUI editor's wrapper hooks, left out). See idWindow.h.
 */

#import "idWindow.h"
#import "rvGEWindowWrapper.h"
#import "idLexer.h"
#import "idUserInterface.h"
#import "idDeviceContext.h"
#import "idDict.h"
#import "idParser.h"
#import "idToken.h"
#import "idLexer.h"
#import "idDeclManager.h"
#import "UDDeclTable.h"
#import "UDDeclCodec.h"
#import "idStr.h"
#import "idEditWindow.h"
#import "idChoiceWindow.h"
#import "idSliderWindow.h"
#import "idBindWindow.h"
#import "idListWindow.h"
#import "idRenderWindow.h"
#import "idMarkerWindow.h"
#import "idFieldWindow.h"

@implementation idDrawWin
@end

@implementation idTimeLineEvent
- (instancetype)init {
    self = [super init];
    if (self) {
        event = [[idGuiScriptList alloc] init];
    }
    return self;
}
@end

@implementation rvNamedEvent
- (instancetype)initWithName:(NSString *)aName {
    self = [super init];
    if (self) {
        mEvent = [[idGuiScriptList alloc] init];
        mName = [aName copy];
    }
    return self;
}
@end

@implementation idTransitionData
- (instancetype)init {
    self = [super init];
    if (self) {
        idInterpolateAccelDecelLinear_Construct( &interp );
    }
    return self;
}
@end

static BOOL registerIsTemporary[MAX_EXPRESSION_REGISTERS];     // statics to assist during parsing

//  made RegisterVars a member of idWindow
const idRegEntry idWindow_RegisterVars[] = {
    { @"forecolor", REG_VEC4 },
    { @"hovercolor", REG_VEC4 },
    { @"backcolor", REG_VEC4 },
    { @"bordercolor", REG_VEC4 },
    { @"rect", REG_RECTANGLE },
    { @"matcolor", REG_VEC4 },
    { @"scale", REG_VEC2 },
    { @"translate", REG_VEC2 },
    { @"rotate", REG_FLOAT },
    { @"textscale", REG_FLOAT },
    { @"visible", REG_BOOL },
    { @"noevents", REG_BOOL },
    { @"text", REG_STRING },
    { @"background", REG_STRING },
    { @"runscript", REG_STRING },
    { @"varbackground", REG_STRING },
    { @"cvar", REG_STRING },
    { @"choices", REG_STRING },
    { @"choiceVar", REG_STRING },
    { @"bind", REG_STRING },
    //#modified-fva; BEGIN - FIXME: why not at the end of the list?
    { @"cstLayer", REG_INT },
    { @"cstPseudoBit", REG_INT },
    { @"cstResetScrollbar", REG_BOOL },
    { @"cstWriteTop", REG_BOOL },
    { @"cstAnchor", REG_INT },
    { @"cstAnchorTo", REG_INT },
    { @"cstAnchorFactor", REG_FLOAT },
    //#modified-fva; END
    { @"modelRotate", REG_VEC4 },
    { @"modelOrigin", REG_VEC4 },
    { @"lightOrigin", REG_VEC4 },
    { @"lightColor", REG_VEC4 },
    { @"viewOffset", REG_VEC4 },
    { @"hideCursor", REG_BOOL}
};

const int idWindow_NumRegisterVars = sizeof(idWindow_RegisterVars) / sizeof(idRegEntry);

NSString *_Nonnull const idWindow_ScriptNames[SCRIPT_COUNT] = {
    @"onMouseEnter",
    @"onMouseExit",
    @"onAction",
    @"onActivate",
    @"onDeactivate",
    @"onESC",
    @"onEvent",
    @"onTrigger",
    @"onActionRelease",
    @"onEnter",
    @"onEnterRelease"
};

#define TokenIs UDTokenIs

static float ParserParseFloat( idParser *src ) {
    float f = 0.0f;
    [src parseFloat:&f error:NULL];
    return f;
}

static int ParserParseInt( idParser *src ) {
    int i = 0;
    [src parseInt:&i error:NULL];
    return i;
}

static BOOL ParserParseBool( idParser *src ) {
    BOOL b = NO;
    [src parseBool:&b error:NULL];
    return b;
}

@implementation idWindow

/*
================
idWindow::CommonInit
================
*/
- (void)windowCommonInit {
    childID = 0;
    flags = 0;
    lastTimeRun = 0;
    origin = idVec2_Make( 0, 0 );
    fontNum = 0;
    timeLine = -1;
    xOffset = yOffset = 0.0;
    cursor = 0;
    forceAspectWidth = 640;
    forceAspectHeight = 480;
    matScalex = 1;
    matScaley = 1;
    borderSize = 0;
    [noTime setData:NO];
    [visible setData:YES];
    textAlign = 0;
    textAlignx = 0;
    textAligny = 0;
    [noEvents setData:NO];
    [rotate setData:0];
    shear = idVec2_Make( 0, 0 );
    [textScale setData:0.35f];
    [backColor zero];
    [foreColor setData:idVec4_Make(1, 1, 1, 1)];
    [hoverColor setData:idVec4_Make(1, 1, 1, 1)];
    [matColor setData:idVec4_Make(1, 1, 1, 1)];
    [borderColor zero];
    background = nil;
    [backGroundName setData:@""];
    focusedChild = nil;
    captureChild = nil;
    overChild = nil;
    parent = nil;
    timeLine = -1;
    textShadow = 0;
    hover = NO;

    for (int i = 0; i < SCRIPT_COUNT; i++) {
        scripts[i] = nil;
    }

    [hideCursor setData:NO];

    //#modified-fva; BEGIN
    [cstAnchor setData:CST_ANCHOR_NONE];
    [cstAnchorTo setData:CST_ANCHOR_NONE];
    [cstAnchorFactor setData:0.0f];
    cstNoClipBackground = NO;
    //#modified-fva; END
}

// the members' constructors
- (void)constructMembers {
    cmd = [NSMutableString string];
    name = @"";
    comment = @"";
    noTime = [[idWinBool alloc] init];
    visible = [[idWinBool alloc] init];
    noEvents = [[idWinBool alloc] init];
    rect = [[idWinRectangle alloc] init];
    backColor = [[idWinVec4 alloc] init];
    matColor = [[idWinVec4 alloc] init];
    foreColor = [[idWinVec4 alloc] init];
    hoverColor = [[idWinVec4 alloc] init];
    borderColor = [[idWinVec4 alloc] init];
    textScale = [[idWinFloat alloc] init];
    rotate = [[idWinFloat alloc] init];
    text = [[idWinStr alloc] init];
    backGroundName = [[idWinBackground alloc] init];
    definedVars = [NSMutableArray array];
    updateVars = [NSMutableArray array];
    children = [NSMutableArray array];
    drawWindows = [NSMutableArray array];
    timeLineEvents = [NSMutableArray array];
    transitions = [NSMutableArray array];
    namedEvents = [NSMutableArray array];
    regList = [[idRegisterList alloc] init];
    hideCursor = [[idWinBool alloc] init];
    cstAnchor = [[idWinInt alloc] init];
    cstAnchorTo = [[idWinInt alloc] init];
    cstAnchorFactor = [[idWinFloat alloc] init];
    tables = [NSMutableArray array];
}

/*
================
idWindow::idWindow
================
*/
- (instancetype)initWithGui:(idUserInterfaceLocal *)ui {
    self = [super init];
    if (self) {
        [self constructMembers];
        dc = nil;
        gui = ui;
        [self windowCommonInit];
    }
    return self;
}

/*
================
idWindow::idWindow
================
*/
- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)ui {
    self = [super init];
    if (self) {
        [self constructMembers];
        dc = d;
        gui = ui;
        [self windowCommonInit];
    }
    return self;
}

- (void)freeOps {
    // the names of the vars not found yet (FixupParms frees the rest)
    for ( int i = 0; i < numOps; i++ ) {
        if ( ops[i].b == -2 ) {
            CFRelease( (CFTypeRef)ops[i].a );
        }
    }
    numOps = 0;
}

- (void)dealloc {
    [self freeOps];
    free( ops );
    free( expressionRegisters );
    free( saveTemps );
}

/*
================
idWindow::CleanUp
================
*/
- (void)cleanUp {
    // ensure the register list gets cleaned up
    [regList reset];

    // Cleanup the named events
    [namedEvents removeAllObjects];

    // Cleanup the operations and update vars
    // (if it is not fixed, orphane register references are possible)
    [self freeOps];
    [updateVars removeAllObjects];

    [drawWindows removeAllObjects];
    [children removeAllObjects];
    [definedVars removeAllObjects];
    [timeLineEvents removeAllObjects];
    for (int i = 0; i < SCRIPT_COUNT; i++) {
        scripts[i] = nil;
    }
    [self windowCommonInit];
}

/*
================
idWindow::Move
================
*/
- (void)move:(float)x y:(float)y {
    idRectangle rct = rect.data;
    rct.x = x;
    rct.y = y;
    idRegister *reg = [[self regList] findReg:@"rect"];
    if (reg) {
        [reg enable:NO];
    }
    [rect setData:rct];
}

/*
================
idWindow::SetFont
================
*/
- (void)setFont {
    [dc setFont:fontNum];
}

/*
================
idWindow::GetMaxCharHeight
================
*/
- (float)getMaxCharHeight {
    [self setFont];
    return [dc maxCharHeight:textScale.data];
}

/*
================
idWindow::GetMaxCharWidth
================
*/
- (float)getMaxCharWidth {
    [self setFont];
    return [dc maxCharWidth:textScale.data];
}

/*
================
idWindow::Draw
================
*/
- (void)draw:(int)time x:(float)x y:(float)y {
    if ( [text length] == 0 ) {
        return;
    }
    if ( textShadow ) {
        NSString *shadowText = [[text data] ud_stringByRemovingColors];
        idRectangle shadowRect = textRect;

        shadowRect.x += textShadow;
        shadowRect.y += textShadow;

        [dc drawText:shadowText textScale:textScale.data textAlign:textAlign color:idDeviceContext_colorBlack rectDraw:shadowRect wrap:!( flags & WIN_NOWRAP ) cursor:-1];
    }
    [dc drawText:[text data] textScale:textScale.data textAlign:textAlign color:foreColor.data rectDraw:textRect wrap:!( flags & WIN_NOWRAP ) cursor:-1];

    if ( [[gui manager].cvars getBool:@"gui_edit"] ) {
        [dc enableClipping:NO];
        [dc drawText:[NSString stringWithFormat:@"x: %i  y: %i", ( int )[rect x], ( int )[rect y]] textScale:0.25 textAlign:0 color:idDeviceContext_colorWhite rectDraw:idRectangle_Make( [rect x], [rect y] - 15, 100, 20 ) wrap:NO];
        [dc drawText:[NSString stringWithFormat:@"w: %i  h: %i", ( int )[rect w], ( int )[rect h]] textScale:0.25 textAlign:0 color:idDeviceContext_colorWhite rectDraw:idRectangle_Make( [rect x] + [rect w], [rect w] + [rect h] + 5, 100, 20 ) wrap:NO];
        [dc enableClipping:YES];
    }

}

/*
================
idWindow::BringToTop
================
*/
- (void)bringToTop:(idWindow *)w {

    if (w && !(w->flags & WIN_MODAL)) {
        return;
    }

    int c = (int)children.count;
    for (int i = 0; i < c; i++) {
        if (children[i] == w) {
            // this is it move from i - 1 to 0 to i to 1 then shove this one into 0
            for (int j = i+1; j < c; j++) {
                children[j-1] = children[j];
            }
            children[c-1] = w;
            break;
        }
    }
}

/*
================
idWindow::Size
================
*/
- (void)size:(float)x y:(float)y w:(float)w h:(float)h {
    idRectangle rct = rect.data;
    rct.x = x;
    rct.y = y;
    rct.w = w;
    rct.h = h;
    [rect setData:rct];
    [self calcClientRect:0 yofs:0];
}

/*
================
idWindow::MouseEnter
================
*/
- (void)mouseEnter {

    if (noEvents.data) {
        return;
    }

    [self runScript:ON_MOUSEENTER];
}

/*
================
idWindow::MouseExit
================
*/
- (void)mouseExit {

    if (noEvents.data) {
        return;
    }

    [self runScript:ON_MOUSEEXIT];
}


/*
================
idWindow::RouteMouseCoords
================
*/
- (NSString *)routeMouseCoords:(float)xd yd:(float)yd {
    if ([self getCaptureChild]) {
        //FIXME: unkludge this whole mechanism
        return [[self getCaptureChild] routeMouseCoords:xd yd:yd];
    }

    if (xd == -2000 || yd == -2000) {
        return @"";
    }

    int c = (int)children.count;
    while (c > 0) {
        idWindow *child = children[--c];
        if (child->visible.data && !child->noEvents.data && [child containsRect:child->drawRect x:[gui cursorX] y:[gui cursorY]]) {

            [dc setCursor:child->cursor];
            child->hover = YES;

            if (overChild != child) {
                if (overChild) {
                    idWindow *over = overChild;
                    [over mouseExit];
                    if (over->cmd.length) {
                        [[gui getDesktop] addCommand:[over->cmd copy]];
                        [over->cmd setString:@""];
                    }
                }
                overChild = child;
                [child mouseEnter];
                if (child->cmd.length) {
                    [[gui getDesktop] addCommand:[child->cmd copy]];
                    [child->cmd setString:@""];
                }
            } else {
                if (!(child->flags & WIN_HOLDCAPTURE)) {
                    [child routeMouseCoords:xd yd:yd];
                }
            }
            return @"";
        }
    }
    if (overChild) {
        idWindow *over = overChild;
        [over mouseExit];
        if (over->cmd.length) {
            [[gui getDesktop] addCommand:[over->cmd copy]];
            [over->cmd setString:@""];
        }
        overChild = nil;
    }
    return @"";
}

/*
================
idWindow::Activate
================
*/
- (void)activate:(BOOL)activate act:(NSMutableString *)act {

    int n = (activate) ? ON_ACTIVATE : ON_DEACTIVATE;

    //  make sure win vars are updated before activation
    [self updateWinVars];

    [self runScript:n];
    for (idWindow *child in [children copy]) {
        [child activate:activate act:act];
    }

    if ( act.length ) {
        [act appendString:@" ; "];
    }
}

/*
================
idWindow::Trigger
================
*/
- (void)trigger {
    [self runScript:ON_TRIGGER];
    for (idWindow *child in [children copy]) {
        [child trigger];
    }
    [self stateChanged:YES];
}

/*
================
idWindow::StateChanged
================
*/
- (void)stateChanged:(BOOL)redraw {

    [self updateWinVars];

    if (numExpressionRegisters && numOps) {
        [self evalRegs];
    }

    for ( NSUInteger i = 0; i < drawWindows.count; i++ ) {
        idDrawWin *dw = drawWindows[i];
        if ( dw.win ) {
            [dw.win stateChanged:redraw];
        } else {
            [dw.simp stateChanged:redraw];
        }
    }

    if ( redraw ) {
        if ( flags & WIN_DESKTOP ) {
            [self redraw:0.0f y:0.0f];
        }
        if ( background && [background cinematicLength] ) {
            [background updateCinematic:[gui getTime]];
        }
    }
}

/*
================
idWindow::SetCapture
================
*/
- (idWindow *)setCapture:(idWindow *)w {
    // only one child can have the focus

    idWindow *last = nil;
    for (idWindow *child in children) {
        if ( child->flags & WIN_CAPTURE ) {
            last = child;
            //last->flags &= ~WIN_CAPTURE;
            [last loseCapture];
            break;
        }
    }

    w->flags |= WIN_CAPTURE;
    [w gainCapture];
    [gui getDesktop]->captureChild = w;
    return last;
}

/*
================
idWindow::AddUpdateVar
================
*/
- (void)addUpdateVar:(idWinVar *)var {
    if ( [updateVars indexOfObjectIdenticalTo:var] == NSNotFound ) {
        [updateVars addObject:var];
    }
}

/*
================
idWindow::UpdateWinVars
================
*/
- (void)updateWinVars {
    for (NSUInteger i = 0; i < updateVars.count; i++) {
        idWinVar *var = updateVars[i];
        [var update];
    }
}

/*
================
idWindow::RunTimeEvents
================
*/
- (BOOL)runTimeEvents:(int)time {

    if ( time - lastTimeRun < USERCMD_MSEC ) {
        //common->Printf("Skipping gui time events at %i\n", time);
        return NO;
    }

    lastTimeRun = time;

    [self updateWinVars];

    if (numExpressionRegisters && numOps) {
        [self evalRegs];
    }

    if ( flags & WIN_INTRANSITION ) {
        [self transition];
    }

    [self time];

    // renamed ON_EVENT to ON_FRAME
    [self runScript:ON_FRAME];

    for (NSUInteger i = 0; i < children.count; i++) {
        idWindow *child = children[i];
        [child runTimeEvents:time];
    }

    return YES;
}

/*
================
idWindow::RunNamedEvent
================
*/
- (void)runNamedEvent:(NSString *)eventName {
    // Find and run the event
    for ( rvNamedEvent *ev in [namedEvents copy] ) {
        if ( ![ev->mName ud_iequals:eventName] ) {
            continue;
        }

        [self updateWinVars];

        // Make sure we got all the current values for stuff
        if (numExpressionRegisters && numOps) {
            [self evalRegs:-1 force:YES];
        }

        [self runScriptList:ev->mEvent];

        break;
    }

    // Run the event in all the children as well
    for ( idWindow *child in [children copy] ) {
        [child runNamedEvent:eventName];
    }
}

/*
================
idWindow::Contains
================
*/
- (BOOL)containsRect:(idRectangle)sr x:(float)x y:(float)y {
    idRectangle r = sr;
    r.x += actualX - drawRect.x;
    r.y += actualY - drawRect.y;
    return idRectangle_Contains( &r, x, y );
}

/*
================
idWindow::Contains
================
*/
- (BOOL)contains:(float)x y:(float)y {
    idRectangle r = drawRect;
    r.x = actualX;
    r.y = actualY;
    return idRectangle_Contains( &r, x, y );
}

/*
================
idWindow::AddCommand
================
*/
- (void)addCommand:(NSString *)command {
    NSString *added = command;
    if (cmd.length) {
        [cmd appendString:@" ; "];
        [cmd appendString:added];
    } else {
        [cmd setString:added];
    }
}

/*
================
idWindow::HandleEvent
================
*/
- (NSString *)handleEvent:(const sysEvent_t *)event updateVisuals:(BOOL *)updateVisuals {
    static BOOL actionDownRun;
    static BOOL actionUpRun;
    idUserInterfaceManager *manager = [gui manager];
    BOOL gui_edit = [manager.cvars getBool:@"gui_edit"];

    [cmd setString:@""];

    if ( flags & WIN_DESKTOP ) {
        actionDownRun = NO;
        actionUpRun = NO;
        if (numExpressionRegisters && numOps) {
            [self evalRegs];
        }
        [self runTimeEvents:[gui getTime]];
        [self calcRects:0 y:0];
        [dc setCursor:CURSOR_ARROW];
    }

    if (visible.data && !noEvents.data) {

        if (event->evType == SE_KEY) {
            [self evalRegs:-1 force:YES];
            if (updateVisuals) {
                *updateVisuals = YES;
            }

            if (event->evValue == K_MOUSE1) {

                if (!event->evValue2 && [self getCaptureChild]) {
                    [[self getCaptureChild] loseCapture];
                    [gui getDesktop]->captureChild = nil;
                    return @"";
                }

                int c = (int)children.count;
                while (--c >= 0) {
                    if (c >= (int)children.count) {
                        continue;
                    }
                    if (children[c]->visible.data && [children[c] containsRect:children[c]->drawRect x:[gui cursorX] y:[gui cursorY]] && !(children[c]->noEvents.data)) {
                        idWindow *child = children[c];
                        if (event->evValue2) {
                            [self bringToTop:child];
                            [self setFocus:child];
                            if (child->flags & WIN_HOLDCAPTURE) {
                                [self setCapture:child];
                            }
                        }
                        if ([child containsRect:child->clientRect x:[gui cursorX] y:[gui cursorY]]) {
                            //if ((gui_edit.GetBool() && (child->flags & WIN_SELECTED)) || (!gui_edit.GetBool() && (child->flags & WIN_MOVABLE))) {
                            //  SetCapture(child);
                            //}
                            [self setFocus:child];
                            NSString *childRet = [child handleEvent:event updateVisuals:updateVisuals];
                            if (childRet.length) {
                                return childRet;
                            }
                            if (child->flags & WIN_MODAL) {
                                return @"";
                            }
                        } else {
                            if (event->evValue2) {
                                [self setFocus:child];
                                BOOL capture = YES;
                                if (capture && ((child->flags & WIN_MOVABLE) || gui_edit)) {
                                    [self setCapture:child];
                                }
                                return @"";
                            } else {
                            }
                        }
                    }
                }
                if (event->evValue2 && !actionDownRun) {
                    actionDownRun = [self runScript:ON_ACTION];
                } else if (!actionUpRun) {
                    actionUpRun = [self runScript:ON_ACTIONRELEASE];
                }
            } else if (event->evValue == K_MOUSE2) {

                if (!event->evValue2 && [self getCaptureChild]) {
                    [[self getCaptureChild] loseCapture];
                    [gui getDesktop]->captureChild = nil;
                    return @"";
                }

                int c = (int)children.count;
                while (--c >= 0) {
                    if (c >= (int)children.count) {
                        continue;
                    }
                    if (children[c]->visible.data && [children[c] containsRect:children[c]->drawRect x:[gui cursorX] y:[gui cursorY]] && !(children[c]->noEvents.data)) {
                        idWindow *child = children[c];
                        if (event->evValue2) {
                            [self bringToTop:child];
                            [self setFocus:child];
                        }
                        if ([child containsRect:child->clientRect x:[gui cursorX] y:[gui cursorY]] || [self getCaptureChild] == child) {
                            if ((gui_edit && (child->flags & WIN_SELECTED)) || (!gui_edit && (child->flags & WIN_MOVABLE))) {
                                [self setCapture:child];
                            }
                            NSString *childRet = [child handleEvent:event updateVisuals:updateVisuals];
                            if (childRet.length) {
                                return childRet;
                            }
                            if (child->flags & WIN_MODAL) {
                                return @"";
                            }
                        }
                    }
                }
            } else if (event->evValue == K_MOUSE3) {
                if (gui_edit) {
                    for (idWindow *child in children) {
                        if (idRectangle_Contains( &child->drawRect, [gui cursorX], [gui cursorY] )) {
                            if (event->evValue2) {
                                child->flags ^= WIN_SELECTED;
                                if (child->flags & WIN_SELECTED) {
                                    flags &= ~WIN_SELECTED;
                                    return @"childsel";
                                }
                            }
                        }
                    }
                }
            } else if (event->evValue == K_TAB && event->evValue2) {
                if ([self getFocusedChild]) {
                    NSString *childRet = [[self getFocusedChild] handleEvent:event updateVisuals:updateVisuals];
                    if (childRet.length) {
                        return childRet;
                    }

                    // If the window didn't handle the tab, then move the focus to the next window
                    // or the previous window if shift is held down

                    int direction = 1;
                    if ( [manager isKeyDown:K_SHIFT] ) {
                        direction = -1;
                    }

                    idWindow *currentFocus = [self getFocusedChild];
                    idWindow *child = [self getFocusedChild];
                    idWindow *parentWin = [child getParent];
                    while ( parentWin ) {
                        BOOL foundFocus = NO;
                        BOOL recurse = NO;
                        int index = 0;
                        if ( child ) {
                            index = [parentWin getChildIndex:child] + direction;
                        } else if ( direction < 0 ) {
                            index = [parentWin getChildCount] - 1;
                        }
                        while ( index < [parentWin getChildCount] && index >= 0) {
                            idWindow *testWindow = [parentWin getChild:index];
                            if ( testWindow == currentFocus ) {
                                // we managed to wrap around and get back to our starting window
                                foundFocus = YES;
                                break;
                            }
                            if ( testWindow && !testWindow->noEvents.data && testWindow->visible.data ) {
                                if ( testWindow->flags & WIN_CANFOCUS ) {
                                    [self setFocus:testWindow];
                                    foundFocus = YES;
                                    break;
                                } else if ( [testWindow getChildCount] > 0 ) {
                                    parentWin = testWindow;
                                    child = nil;
                                    recurse = YES;
                                    break;
                                }
                            }
                            index += direction;
                        }
                        if ( foundFocus ) {
                            // We found a child to focus on
                            break;
                        } else if ( recurse ) {
                            // We found a child with children
                            continue;
                        } else {
                            // We didn't find anything, so go back up to our parent
                            child = parentWin;
                            parentWin = [child getParent];
                            if ( parentWin == [gui getDesktop] ) {
                                // We got back to the desktop, so wrap around but don't actually go to the desktop
                                parentWin = nil;
                                child = nil;
                            }
                        }
                    }
                }
            } else if (event->evValue == K_ESCAPE && event->evValue2) {
                if ([self getFocusedChild]) {
                    NSString *childRet = [[self getFocusedChild] handleEvent:event updateVisuals:updateVisuals];
                    if (childRet.length) {
                        return childRet;
                    }
                }
                [self runScript:ON_ESC];
            } else if (event->evValue == K_ENTER ) {
                if ([self getFocusedChild]) {
                    NSString *childRet = [[self getFocusedChild] handleEvent:event updateVisuals:updateVisuals];
                    if (childRet.length) {
                        return childRet;
                    }
                }
                if ( flags & WIN_WANTENTER ) {
                    if ( event->evValue2 ) {
                        [self runScript:ON_ACTION];
                    } else {
                        [self runScript:ON_ACTIONRELEASE];
                    }
                }
            } else {
                if ([self getFocusedChild]) {
                    NSString *childRet = [[self getFocusedChild] handleEvent:event updateVisuals:updateVisuals];
                    if (childRet.length) {
                        return childRet;
                    }
                }
            }

        } else if (event->evType == SE_MOUSE || event->evType == SE_MOUSE_ABS) {
            if (updateVisuals) {
                *updateVisuals = YES;
            }
            NSString *mouseRet = [self routeMouseCoords:event->evValue yd:event->evValue2];
            if (mouseRet.length) {
                return mouseRet;
            }
        } else if (event->evType == SE_NONE) {
        } else if (event->evType == SE_CHAR) {
            if ([self getFocusedChild]) {
                NSString *childRet = [[self getFocusedChild] handleEvent:event updateVisuals:updateVisuals];
                if (childRet.length) {
                    return childRet;
                }
            }
        }
    }

    NSMutableString *returnCmd = [gui getReturnCmd];
    [returnCmd setString:cmd];
    if ( [gui getPendingCmd].length ) {
        [returnCmd appendString:@" ; "];
        [returnCmd appendString:[gui getPendingCmd]];
        [[gui getPendingCmd] setString:@""];
    }
    [cmd setString:@""];
    return [returnCmd copy];
}

/*
================
idWindow::DebugDraw
================
*/
- (void)debugDraw:(int)time x:(float)x y:(float)y {
    if (dc) {
        int gui_debug = [[gui manager].cvars getInt:@"gui_debug"];
        [dc enableClipping:NO];
        if (gui_debug == 1) {
            [dc drawRect:drawRect.x y:drawRect.y width:drawRect.w height:drawRect.h size:1 color:idDeviceContext_colorRed];
        } else if (gui_debug == 2) {
            NSMutableString *buff = [NSMutableString string];
            NSString *str = [text string];

            if (str.length) {
                [buff appendFormat:@"%@\n", str];
            }

            [buff appendFormat:@"Rect: %0.1f, %0.1f, %0.1f, %0.1f\n", [rect x], [rect y], [rect w], [rect h]];
            [buff appendFormat:@"Draw Rect: %0.1f, %0.1f, %0.1f, %0.1f\n", drawRect.x, drawRect.y, drawRect.w, drawRect.h];
            [buff appendFormat:@"Client Rect: %0.1f, %0.1f, %0.1f, %0.1f\n", clientRect.x, clientRect.y, clientRect.w, clientRect.h];
            [buff appendFormat:@"Cursor: %0.1f : %0.1f\n", [gui cursorX], [gui cursorY]];


            //idRectangle tempRect = textRect;
            //tempRect.x += offsetX;
            //drawRect.y += offsetY;
            [dc drawText:buff textScale:textScale.data textAlign:textAlign color:foreColor.data rectDraw:textRect wrap:YES];
        }
        [dc enableClipping:YES];
    }
}

/*
================
idWindow::Transition
================
*/
- (void)transition {
    BOOL clear = YES;

    for ( idTransitionData *data in transitions ) {
        idWinRectangle *r = nil;
        idWinVec4 *v4 = [data->data isKindOfClass:[idWinVec4 class]] ? (idWinVec4 *)data->data : nil;
        idWinFloat* val = nil;
        if (v4 == nil) {
            r = [data->data isKindOfClass:[idWinRectangle class]] ? (idWinRectangle *)data->data : nil;
            if ( !r ) {
                val = [data->data isKindOfClass:[idWinFloat class]] ? (idWinFloat *)data->data : nil;
            }
        }
        if ( idInterpolateAccelDecelLinear_IsDone( &data->interp, [gui getTime] ) && data->data) {
            if (v4) {
                [v4 setData:idInterpolateAccelDecelLinear_GetEndValue( &data->interp )];
            } else if ( val ) {
                [val setData:idInterpolateAccelDecelLinear_GetEndValue( &data->interp ).x];
            } else {
                [r setVec4:idInterpolateAccelDecelLinear_GetEndValue( &data->interp )];
            }
        } else {
            clear = NO;
            if (data->data) {
                if (v4) {
                    [v4 setData:idInterpolateAccelDecelLinear_GetCurrentValue( &data->interp, [gui getTime] )];
                } else if ( val ) {
                    [val setData:idInterpolateAccelDecelLinear_GetCurrentValue( &data->interp, [gui getTime] ).x];
                } else {
                    [r setVec4:idInterpolateAccelDecelLinear_GetCurrentValue( &data->interp, [gui getTime] )];
                }
            } else {
                [[gui manager] uiWarning:[NSString stringWithFormat:@"Invalid transitional data for window %@ in gui %@", [self getName], [gui getSourceFile]]];
            }
        }
    }

    if ( clear ) {
        [transitions removeAllObjects];
        flags &= ~WIN_INTRANSITION;
    }
}

/*
================
idWindow::Time
================
*/
- (void)time {

    if ( noTime.data ) {
        return;
    }

    if ( timeLine == -1 ) {
        timeLine = [gui getTime];
    }

    [cmd setString:@""];

    for ( NSUInteger i = 0; i < timeLineEvents.count; i++ ) {
        idTimeLineEvent *ev = timeLineEvents[i];
        if ( ev->pending && [gui getTime] - timeLine >= ev->time ) {
            ev->pending = NO;
            [self runScriptList:ev->event];
        }
    }
    if ( [gui active] ) {
        [[gui getPendingCmd] appendString:cmd];
    }
}

/*
================
idWindow::EvalRegs
================
*/
- (float)evalRegs:(int)test force:(BOOL)force {
    static float regs[MAX_EXPRESSION_REGISTERS];
    static __weak idWindow *lastEval = nil;

    if (!force && test >= 0 && test < MAX_EXPRESSION_REGISTERS && lastEval == self) {
        return regs[test];
    }

    lastEval = self;

    if (numExpressionRegisters) {
        [regList setToRegs:regs];
        [self evaluateRegisters:regs];
        [regList getFromRegs:regs];
    }

    if (test >= 0 && test < MAX_EXPRESSION_REGISTERS) {
        return regs[test];
    }

    return 0.0;
}

- (float)evalRegs {
    return [self evalRegs:-1 force:NO];
}

/*
================
idWindow::DrawBackground
================
*/
- (void)drawBackground:(idRectangle)drawRectangle {
    if ( [backColor w] ) {
        [dc drawFilledRect:drawRectangle.x y:drawRectangle.y width:drawRectangle.w height:drawRectangle.h color:backColor.data];
    }

    if ( background && [matColor w] ) {
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

/*
================
idWindow::DrawBorderAndCaption
================
*/
- (void)drawBorderAndCaption:(idRectangle)drawRectangle {
    if ( flags & WIN_BORDER && borderSize && [borderColor w] ) {
        [dc drawRect:drawRectangle.x y:drawRectangle.y width:drawRectangle.w height:drawRectangle.h size:borderSize color:borderColor.data];
    }
}

/*
================
idWindow::SetupTransforms
================
*/
- (void)setupTransforms:(float)x y:(float)y {
    static idMat3 trans;
    static idVec3 org;

    idMat3_Identity( &trans );
    org = idVec3_Make( origin.x + x, origin.y + y, 0 );

    if ( rotate.data ) {
        static idVec3 vec = { 0, 0, 1 };
        trans = idRotation_ToMat3( vec, rotate.data );
    }

    if ( shear.x || shear.y ) {
        static idMat3 smat;
        idMat3_Identity( &smat );
        smat.mat[0].y = shear.x;
        smat.mat[1].x = shear.y;
        idMat3_MultiplySelf( &trans, &smat );
    }

    if ( !idMat3_IsIdentity( &trans ) ) {
        [dc setTransformInfo:org mat:trans];
    }
}

/*
================
idWindow::CalcRects
================
*/
- (void)calcRects:(float)x y:(float)y {
    [self calcClientRect:0 yofs:0];
    idRectangle_Offset( &drawRect, x, y );
    idRectangle_Offset( &clientRect, x, y );
    actualX = drawRect.x;
    actualY = drawRect.y;
    for ( idDrawWin *dw in drawWindows ) {
        if (dw.win) {
            [dw.win calcRects:clientRect.x + xOffset y:clientRect.y + yOffset];
        }
    }
    idRectangle_Offset( &drawRect, -x, -y );
    idRectangle_Offset( &clientRect, -x, -y );
}

/*
================
idWindow::Redraw
================
*/
- (void)redraw:(float)x y:(float)y {
    idUserInterfaceManager *manager = [gui manager];
    int r_skipGuiShaders = [manager.cvars getInt:@"r_skipGuiShaders"];

    if (r_skipGuiShaders == 1 || dc == nil ) {
        return;
    }

    int time = [gui getTime];

    if ( flags & WIN_DESKTOP && r_skipGuiShaders != 3 ) {
        [self runTimeEvents:time];
    }

    if ( r_skipGuiShaders == 2 ) {
        return;
    }

    // DG: allow scaling menus to 4:3
    BOOL fixupFor43 = NO;
    if ( flags & WIN_DESKTOP ) {
        // only scale desktop windows (will automatically scale its sub-windows)
        // that EITHER have the scaleto43 flag set OR are fullscreen menus and r_scaleMenusTo43 is 1
        if( (flags & WIN_SCALETO43) ||
            ((flags & WIN_MENUGUI) && [manager.cvars getBool:@"r_scaleMenusTo43"]) )
        {
            fixupFor43 = YES;
            [dc setMenuScaleFix:YES];
        }
    }

    if ( flags & WIN_SHOWTIME ) {
        [dc drawText:[NSString stringWithFormat:@" %0.1f seconds\n%@", (float)(time - timeLine) / 1000, [[gui state] getString:@"name"]] textScale:0.35f textAlign:0 color:idDeviceContext_colorWhite rectDraw:idRectangle_Make(100, 0, 80, 80) wrap:NO];
    }

    if ( flags & WIN_SHOWCOORDS ) {
        [dc enableClipping:NO];
        [dc drawText:[NSString stringWithFormat:@"x: %i y: %i  cursorx: %i cursory: %i", (int)[rect x], (int)[rect y], (int)[gui cursorX], (int)[gui cursorY]] textScale:0.25f textAlign:0 color:idDeviceContext_colorWhite rectDraw:idRectangle_Make(0, 0, 100, 20) wrap:NO];
        [dc enableClipping:YES];
    }

    if (!visible.data) {
        if (fixupFor43) { // DG: gotta reset that before returning this function
            [dc setMenuScaleFix:NO];
        }
        return;
    }

    [self calcClientRect:0 yofs:0];

    [self setFont];

    //#modified-fva; BEGIN
    /*
    //if (flags & WIN_DESKTOP) {
        // see if this window forces a new aspect ratio
        dc->SetSize(forceAspectWidth, forceAspectHeight);
    //}
    */
    idWindow *parentWin = parent;
    if (parentWin && parentWin->cstAnchor.data != CST_ANCHOR_NONE) {
        [cstAnchor setData:parentWin->cstAnchor.data];
        [cstAnchorTo setData:parentWin->cstAnchorTo.data];
        [cstAnchorFactor setData:parentWin->cstAnchorFactor.data];
    }
    if (![manager.cvars getBool:@"cst_hudAdjustAspect"] || cstAnchor.data == CST_ANCHOR_NONE) {
        [dc setSize:forceAspectWidth height:forceAspectHeight];
    } else {
        // DG: if this Window uses anchors, it already is aspect-ratio-aware
        //     so a potentially active menuscalefix must be disabled
        //    (else it's "fixed" twice => wrong ratio in other direction)
        [dc setMenuScaleFix:NO];
        [dc cstSetSize:cstAnchor.data anchorTo:cstAnchorTo.data factor:cstAnchorFactor.data];
    }
    //#modified-fva; END

    //FIXME: go to screen coord tracking
    idRectangle_Offset( &drawRect, x, y );
    idRectangle_Offset( &clientRect, x, y );
    idRectangle_Offset( &textRect, x, y );
    actualX = drawRect.x;
    actualY = drawRect.y;

    idVec3  oldOrg;
    idMat3  oldTrans;

    [dc getTransformInfo:&oldOrg mat:&oldTrans];

    [self setupTransforms:x y:y];
    //#modified-fva; BEGIN
    if (cstNoClipBackground) {
        [dc enableClipping:NO];
    }
    //#modified-fva; END

    [self drawBackground:drawRect];

    //#modified-fva; BEGIN
    if (cstNoClipBackground) {
        [dc enableClipping:YES];
    }
    //#modified-fva; END
    [self drawBorderAndCaption:drawRect];

    if ( !( flags & WIN_NOCLIP) ) {
        [dc pushClipRect:clientRect];
    }

    if ( r_skipGuiShaders < 5 ) {
        [self draw:time x:x y:y];
    }

    if ( [manager.cvars getInt:@"gui_debug"] ) {
        [self debugDraw:time x:x y:y];
    }

    for ( NSUInteger i = 0; i < drawWindows.count; i++ ) {
        idDrawWin *dw = drawWindows[i];
        if ( dw.win ) {
            [dw.win redraw:clientRect.x + xOffset y:clientRect.y + yOffset];
        } else {
            [dw.simp redraw:clientRect.x + xOffset y:clientRect.y + yOffset];
        }
    }

    // Put transforms back to what they were before the children were processed
    [dc setTransformInfo:oldOrg mat:oldTrans];

    if ( ! ( flags & WIN_NOCLIP ) ) {
        [dc popClipRect];
    }

    if ([manager.cvars getBool:@"gui_edit"] || (flags & WIN_DESKTOP && !( flags & WIN_NOCURSOR )  && !hideCursor.data && ([gui active] || ( flags & WIN_MENUGUI ) ))) {
        [dc setTransformInfo:vec3_origin mat:mat3_identity];
        [gui drawCursor];
    }

    if ([manager.cvars getInt:@"gui_debug"] && flags & WIN_DESKTOP) {
        [dc enableClipping:NO];
        [dc drawText:[NSString stringWithFormat:@"x: %1.f y: %1.f",  [gui cursorX], [gui cursorY]] textScale:0.25 textAlign:0 color:idDeviceContext_colorWhite rectDraw:idRectangle_Make(0, 0, 100, 20) wrap:NO];
        [dc drawText:[gui getSourceFile] textScale:0.25 textAlign:0 color:idDeviceContext_colorWhite rectDraw:idRectangle_Make(0, 20, 300, 20) wrap:NO];
        [dc enableClipping:YES];
    }

    if (fixupFor43) { // DG: gotta reset that before returning this function
        [dc setMenuScaleFix:NO];
    }

    idRectangle_Offset( &drawRect, -x, -y );
    idRectangle_Offset( &clientRect, -x, -y );
    idRectangle_Offset( &textRect, -x, -y );
}

/*
================
idWindow::SetDC
================
*/
- (void)setDC:(idDeviceContext *)d {
    dc = d;
    //if (flags & WIN_DESKTOP) {
        [dc setSize:forceAspectWidth height:forceAspectHeight];
    //}

    //#modified-fva; BEGIN
    idWindow *parentWin = parent;
    if (parentWin && parentWin->cstAnchor.data != CST_ANCHOR_NONE) {
        [cstAnchor setData:parentWin->cstAnchor.data];
        [cstAnchorTo setData:parentWin->cstAnchorTo.data];
        [cstAnchorFactor setData:parentWin->cstAnchorFactor.data];
    }
    //#modified-fva; END

    for (idWindow *child in children) {
        [child setDC:d];
    }
}

- (idDeviceContext *)getDC {
    return dc;
}

/*
================
idWindow::ArchiveToDictionary
================
*/
- (void)archiveToDictionary:(idDict *)dict useNames:(BOOL)useNames {
    //FIXME: rewrite without state
    for (idWindow *child in children) {
        [child archiveToDictionary:dict useNames:YES];
    }
}

/*
================
idWindow::InitFromDictionary
================
*/
- (void)initFromDictionary:(idDict *)dict byName:(BOOL)byName {
    //FIXME: rewrite without state
    for (idWindow *child in children) {
        [child initFromDictionary:dict byName:YES];
    }
}

/*
================
idWindow::CalcClientRect
================
*/
- (void)calcClientRect:(float)xofs yofs:(float)yofs {
    drawRect = rect.data;

    if ( flags & WIN_INVERTRECT ) {
        drawRect.x = [rect x] - [rect w];
        drawRect.y = [rect y] - [rect h];
    }

    idWindow *parentWin = parent;
    if (flags & (WIN_HCENTER | WIN_VCENTER) && parentWin) {
        // in this case treat xofs and yofs as absolute top left coords
        // and ignore the original positioning
        if (flags & WIN_HCENTER) {
            drawRect.x = ([parentWin->rect w] - [rect w]) / 2;
        } else {
            drawRect.y = ([parentWin->rect h] - [rect h]) / 2;
        }
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
    origin = idVec2_Make( [rect x] + ([rect w] / 2 ), [rect y] + ( [rect h] / 2 ) );

}

/*
================
idWindow::SetupBackground
================
*/
- (void)setupBackground {
    if ([backGroundName length]) {
        background = [[gui manager] findMaterial:[backGroundName data]];
        [background setImageClassifications:1];   // just for resource tracking
        if ( background && ![background defaulted] ) {
            [background setSort:SS_GUI];
        }
    }
    [backGroundName setMaterialPtr:self];
}

// (*mat) = …, through idWinBackground's material pointer
- (void)setBackgroundMaterialNamed:(NSString *)materialName {
    background = materialName ? [[gui manager] findMaterial:materialName] : nil;
}

/*
================
idWindow::SetupFromState
================
*/
- (void)setupFromState {
    background = nil;

    [self setupBackground];

    if (borderSize) {
        flags |= WIN_BORDER;
    }

    if ([regList findReg:@"rotate"] || [regList findReg:@"shear"]) {
        flags |= WIN_TRANSFORM;
    }

    [self calcClientRect:0 yofs:0];
    if ( scripts[ ON_ACTION ] ) {
        cursor = CURSOR_HAND;
        flags |= WIN_CANFOCUS;
    }
}

/*
================
idWindow::Moved, Sized, GainFocus, LoseFocus, GainCapture
================
*/
- (void)moved {
}

- (void)sized {
}

- (void)gainFocus {
}

- (void)loseFocus {
}

- (void)gainCapture {
}

/*
================
idWindow::LoseCapture
================
*/
- (void)loseCapture {
    flags &= ~WIN_CAPTURE;
}

/*
================
idWindow::SetFlag
================
*/
- (void)setFlag:(unsigned int)f {
    flags |= f;
}

/*
================
idWindow::ClearFlag
================
*/
- (void)clearFlag:(unsigned int)f {
    flags &= ~f;
}

- (unsigned)getFlags {
    return flags;
}

/*
================
idWindow::SetParent
================
*/
- (void)setParent:(idWindow *)w {
    parent = w;
}

- (idWindow *)getParent {
    return parent;
}

- (idUserInterfaceLocal *)getGui {
    return gui;
}

- (NSString *)getName {
    return name;
}

- (NSString *)getComment {
    return comment;
}

- (void)setComment:(NSString *)p {
    comment = [p copy];
}

- (idRegisterList *)regList {
    return regList;
}

- (BOOL)hasOps {
    return (numOps > 0);
}

- (void)setBuddy:(idWindow *)buddy {
}

- (void)handleBuddyUpdate:(idWindow *)buddy {
}

/*
================
idWindow::GetCaptureChild
================
*/
- (idWindow *)getCaptureChild {
    if (flags & WIN_DESKTOP) {
        return [gui getDesktop]->captureChild;
    }
    return nil;
}

/*
================
idWindow::GetFocusedChild
================
*/
- (idWindow *)getFocusedChild {
    if (flags & WIN_DESKTOP) {
        return [gui getDesktop]->focusedChild;
    }
    return nil;
}


/*
================
idWindow::SetFocus
================
*/
- (idWindow *)setFocus:(idWindow *)w scripts:(BOOL)runScripts {
    // only one child can have the focus
    idWindow *lastFocus = nil;
    if (w->flags & WIN_CANFOCUS) {
        lastFocus = [gui getDesktop]->focusedChild;
        if ( lastFocus ) {
            lastFocus->flags &= ~WIN_FOCUS;
            [lastFocus loseFocus];
        }

        //  call on lose focus
        if ( runScripts && lastFocus ) {
            // calling this broke all sorts of guis
            // lastFocus->RunScript(ON_MOUSEEXIT);
        }
        //  call on gain focus
        if ( runScripts && w ) {
            // calling this broke all sorts of guis
            // w->RunScript(ON_MOUSEENTER);
        }

        w->flags |= WIN_FOCUS;
        [w gainFocus];
        [gui getDesktop]->focusedChild = w;
    }

    return lastFocus;
}

- (idWindow *)setFocus:(idWindow *)w {
    return [self setFocus:w scripts:YES];
}

/*
================
idWindow::ParseScript
================
*/
- (BOOL)parseScript:(idParser *)src list:(idGuiScriptList *)list timeParm:(int *)timeParm elseBlock:(BOOL)elseBlock {

    BOOL    ifElseBlock = NO;

    idToken token;
    idToken_Init( &token );

    // scripts start with { ( unless parm is YES ) and have ; separated command lists.. commands are command,
    // arg.. basically we want everything between the { } as it will be interpreted at
    // run time

    if ( elseBlock ) {
        [src readToken:&token error:NULL];

        if ( UDTokenIcmp( &token, "if" ) ) {
            ifElseBlock = YES;
        }

        [src unreadToken:&token];

        if ( !ifElseBlock && ![src expectTokenString:@"{" error:NULL] ) {
            return NO;
        }
    }
    else if ( ![src expectTokenString:@"{" error:NULL] ) {
        return NO;
    }

    int nest = 0;

    while (1) {
        if ( ![src readToken:&token error:NULL] ) {
            [src error:NULL format:@"Unexpected end of file"];
            return NO;
        }

        if ( TokenIs( &token, "{" ) ) {
            nest++;
        }

        if ( TokenIs( &token, "}" ) ) {
            if (nest-- <= 0) {
                return YES;
            }
        }

        idGuiScript *gs = [[idGuiScript alloc] init];
        if (UDTokenIcmp( &token, "if" )) {
            gs->conditionReg = (int)[self parseExpression:src];
            gs->ifList = [[idGuiScriptList alloc] init];
            [self parseScript:src list:gs->ifList timeParm:NULL elseBlock:NO];
            if ([src readToken:&token error:NULL]) {
                if (TokenIs( &token, "else" )) {
                    gs->elseList = [[idGuiScriptList alloc] init];
                    // pass YES to indicate we are parsing an else condition
                    [self parseScript:src list:gs->elseList timeParm:NULL elseBlock:YES];
                } else {
                    [src unreadToken:&token];
                }
            }

            [list append:gs];

            // if we are parsing an else if then return out so
            // the initial "if" parser can handle the rest of the tokens
            if ( ifElseBlock ) {
                return YES;
            }
            continue;
        } else {
            [src unreadToken:&token];
        }

        // empty { } is not allowed
        if ( TokenIs( &token, "{" ) ) {
             [src error:NULL format:@"Unexpected {"];
             return NO;
        }

        [gs parse:src];
        [list append:gs];
    }

}

/*
================
idWindow::SaveExpressionParseState
================
*/
- (void)saveExpressionParseState {
    free( saveTemps );
    saveTemps = (BOOL*)malloc(MAX_EXPRESSION_REGISTERS * sizeof(BOOL));
    memcpy(saveTemps, registerIsTemporary, MAX_EXPRESSION_REGISTERS * sizeof(BOOL));
}

/*
================
idWindow::RestoreExpressionParseState
================
*/
- (void)restoreExpressionParseState {
    memcpy(registerIsTemporary, saveTemps, MAX_EXPRESSION_REGISTERS * sizeof(BOOL));
    free(saveTemps);
    saveTemps = NULL;
}

/*
================
idWindow::ParseScriptEntry
================
*/
- (BOOL)parseScriptEntry:(NSString *)scriptName parser:(idParser *)src {
    for (int i = 0; i < SCRIPT_COUNT; i++) {
        if ([scriptName ud_iequals:idWindow_ScriptNames[i]]) {
            scripts[i] = [[idGuiScriptList alloc] init];
            return [self parseScript:src list:scripts[i] timeParm:NULL elseBlock:NO];
        }
    }
    return NO;
}

/*
================
idWindow::DisableRegister
================
*/
- (void)disableRegister:(NSString *)_name {
    idRegister *reg = [[self regList] findReg:_name];
    if (reg) {
        [reg enable:NO];
    }
}

/*
================
idWindow::PostParse
================
*/
- (void)postParse {
}

- (void)addDefinedVar:(idWinVar *)var {
    // definedVars.AddUnique( var )
    if ( [definedVars indexOfObjectIdenticalTo:var] == NSNotFound ) {
        [definedVars addObject:var];
    }
}

/*
================
idWindow::GetWinVarByName
================
*/
- (idWinVar *)getWinVarByName:(NSString *)_name fixup:(BOOL)fixup owner:(idDrawWin **)owner {
    idWinVar *retVar = nil;

    if ( owner ) {
        *owner = nil;
    }

    if ([_name ud_iequals:@"notime"]) {
        retVar = noTime;
    } // FIXME: why does all this code not use "else if"?!
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
    if ([_name ud_iequals:@"hoverColor"]) {
        retVar = hoverColor;
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
    if ([_name ud_iequals:@"noEvents"]) {
        retVar = noEvents;
    }
    if ([_name ud_iequals:@"text"]) {
        retVar = text;
    }
    if ([_name ud_iequals:@"backGroundName"]) {
        retVar = backGroundName;
    }
    if ([_name ud_iequals:@"hidecursor"]) {
        retVar = hideCursor;
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

    BOOL guiVar = ([_name rangeOfString:VAR_GUIPREFIX].location != NSNotFound);
    for (idWinVar *var in definedVars) {
        if ([_name ud_iequals:[var getName]]) {
            retVar = var;
            break;
        }
    }

    if (retVar) {
        if (fixup && ![_name hasPrefix:@"$"]) {
            [self disableRegister:_name];
        }

        idWindow *parentWin = parent;
        if ( owner && parentWin ) {
            *owner = [parentWin findChildByName:name];
        }

        return retVar;
    }

    NSUInteger len = _name.length;
    if ( len > 5 && guiVar ) {
        idWinVar *var = [[idWinStr alloc] init];
        [var winVarInit:_name window:self];
        [definedVars addObject:var];
        return var;
    } else if (fixup) {
        NSRange n = [_name rangeOfString:@"::"];
        if (n.location != NSNotFound && n.location > 0) {
            NSString *winName = [_name substringToIndex:n.location];
            NSString *var = [_name substringFromIndex:n.location + 2];
            idDrawWin *win = [[[self getGui] getDesktop] findChildByName:winName];
            if (win) {
                if (win.win) {
                    return [win.win getWinVarByName:var fixup:NO owner:owner];
                } else {
                    if ( owner ) {
                        *owner = win;
                    }
                    return [win.simp getWinVarByName:var];
                }
            }
        }
    }
    return nil;
}

- (idWinVar *)getWinVarByName:(NSString *)_name {
    return [self getWinVarByName:_name fixup:NO owner:NULL];
}

/*
================
idWindow::ParseString
================
*/
- (NSString *)parseString:(idParser *)src {
    idToken tok;
    idToken_Init( &tok );
    if ([src readToken:&tok error:NULL]) {
        return UDTokenLatin1String( &tok );
    }
    return nil;
}

/*
================
idWindow::ParseVec4
================
*/
- (void)parseVec4:(idParser *)src out:(idVec4 *)out {
    idToken tok;
    idToken_Init( &tok );
    [src readToken:&tok error:NULL];
    out->x = atof(tok.text);
    [src expectTokenString:@"," error:NULL];
    [src readToken:&tok error:NULL];
    out->y = atof(tok.text);
    [src expectTokenString:@"," error:NULL];
    [src readToken:&tok error:NULL];
    out->z = atof(tok.text);
    [src expectTokenString:@"," error:NULL];
    [src readToken:&tok error:NULL];
    out->w = atof(tok.text);
}

/*
================
idWindow::ParseInternalVar
================
*/
- (BOOL)parseInternalVar:(NSString *)_name parser:(idParser *)src {

    if ([_name ud_iequals:@"showtime"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_SHOWTIME;
        }
        return YES;
    }
    if ([_name ud_iequals:@"showcoords"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_SHOWCOORDS;
        }
        return YES;
    }
    // DG: added this window flag for Windows that should be scaled to 4:3
    //     (with "empty" bars left/right or above/below)
    if ([_name ud_iequals:@"scaleto43"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_SCALETO43;
        }
        return YES;
    }
    // DG end
    if ([_name ud_iequals:@"forceaspectwidth"]) {
        forceAspectWidth = ParserParseFloat( src );
        return YES;
    }
    if ([_name ud_iequals:@"forceaspectheight"]) {
        forceAspectHeight = ParserParseFloat( src );
        return YES;
    }
    if ([_name ud_iequals:@"matscalex"]) {
        matScalex = ParserParseFloat( src );
        return YES;
    }
    if ([_name ud_iequals:@"matscaley"]) {
        matScaley = ParserParseFloat( src );
        return YES;
    }
    if ([_name ud_iequals:@"bordersize"]) {
        borderSize = ParserParseFloat( src );
        return YES;
    }
    if ([_name ud_iequals:@"nowrap"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_NOWRAP;
        }
        return YES;
    }
    if ([_name ud_iequals:@"shadow"]) {
        textShadow = ParserParseInt( src );
        return YES;
    }
    if ([_name ud_iequals:@"textalign"]) {
        textAlign = ParserParseInt( src );
        return YES;
    }
    if ([_name ud_iequals:@"textalignx"]) {
        textAlignx = ParserParseFloat( src );
        return YES;
    }
    if ([_name ud_iequals:@"textaligny"]) {
        textAligny = ParserParseFloat( src );
        return YES;
    }
    if ([_name ud_iequals:@"shear"]) {
        shear.x = ParserParseFloat( src );
        idToken tok;
        idToken_Init( &tok );
        [src readToken:&tok error:NULL];
        if ( !UDTokenIcmp( &tok, "," ) ) {
            [src error:NULL format:@"Expected comma in shear definiation"];
            return NO;
        }
        shear.y = ParserParseFloat( src );
        return YES;
    }
    if ([_name ud_iequals:@"wantenter"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_WANTENTER;
        }
        return YES;
    }
    if ([_name ud_iequals:@"naturalmatscale"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_NATURALMAT;
        }
        return YES;
    }
    if ([_name ud_iequals:@"noclip"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_NOCLIP;
        }
        return YES;
    }
    if ([_name ud_iequals:@"nocursor"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_NOCURSOR;
        }
        return YES;
    }
    if ([_name ud_iequals:@"menugui"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_MENUGUI;
        }
        return YES;
    }
    if ([_name ud_iequals:@"modal"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_MODAL;
        }
        return YES;
    }
    if ([_name ud_iequals:@"invertrect"]) {
        if ( ParserParseBool( src ) ) {
            flags |= WIN_INVERTRECT;
        }
        return YES;
    }
    if ([_name ud_iequals:@"name"]) {
        name = [self parseString:src] ?: name;
        return YES;
    }
    if ([_name ud_iequals:@"play"]) {
        [[gui manager] uiWarning:@"play encountered during gui parse.. see Robert"];
        [self parseString:src];
        return YES;
    }
    if ([_name ud_iequals:@"comment"]) {
        comment = [self parseString:src] ?: comment;
        return YES;
    }
    if ( [_name ud_iequals:@"font"] ) {
        NSString *fontStr = [self parseString:src] ?: @"";
        fontNum = (unsigned char)[dc findFont:fontStr];
        return YES;
    }

    //#modified-fva; BEGIN
    if ([_name ud_iequals:@"cstNoClipBackground"]) {
        cstNoClipBackground = ParserParseBool( src );
        return YES;
    }
    //#modified-fva; END

    return NO;
}

/*
================
idWindow::ParseRegEntry
================
*/
- (BOOL)parseRegEntry:(NSString *)regName parser:(idParser *)src {
    NSString *work = [regName ud_lowercase];

    idWinVar *var = [self getWinVarByName:work fixup:NO owner:NULL];
    if ( var ) {
        for (int i = 0; i < idWindow_NumRegisterVars; i++) {
            if ([work ud_iequals:idWindow_RegisterVars[i].name]) {
                [regList addReg:work type:idWindow_RegisterVars[i].type parser:src window:self var:var];
                return YES;
            }
        }
    }

    // not predefined so just read the next token and add it to the state
    idToken tok;
    idToken_Init( &tok );
    idWinInt *vari;
    idWinFloat *varf;
    idWinStr *vars;
    if ([src readToken:&tok error:NULL]) {
        if (var) {
            [var set:UDTokenLatin1String( &tok )];
            return YES;
        }
        switch (tok.type) {
            case TT_NUMBER :
                if (tok.subtype & TT_INTEGER) {
                    vari = [[idWinInt alloc] init];
                    [vari setData:atoi(tok.text)];
                    [vari setName:work];
                    [definedVars addObject:vari];
                } else if (tok.subtype & TT_FLOAT) {
                    varf = [[idWinFloat alloc] init];
                    [varf setData:atof(tok.text)];
                    [varf setName:work];
                    [definedVars addObject:varf];
                } else {
                    vars = [[idWinStr alloc] init];
                    [vars setData:UDTokenLatin1String( &tok )];
                    [vars setName:work];
                    [definedVars addObject:vars];
                }
                break;
            default :
                vars = [[idWinStr alloc] init];
                [vars setData:UDTokenLatin1String( &tok )];
                [vars setName:work];
                [definedVars addObject:vars];
                break;
        }
    }

    return YES;
}

/*
================
idWindow::SetInitialState
================
*/
- (void)setInitialState:(NSString *)_name {
    name = [_name copy];
    matScalex = 1.0;
    matScaley = 1.0;
    forceAspectWidth = 640.0;
    forceAspectHeight = 480.0;
    [noTime setData:NO];
    [visible setData:YES];
    flags = 0;
}

/// A child of @a cls parsed as Parse parses an editDef's, a choiceDef's…
- (void)parseChild:(Class)cls parser:(idParser *)src rebuild:(BOOL)rebuild {
    idWindow *win = [[cls alloc] initWithDC:dc gui:gui];
    [self saveExpressionParseState];
    [win parse:src rebuild:rebuild];
    [self restoreExpressionParseState];
    [self addChild:win];
    [win setParent:self];
    idDrawWin *dwt = [[idDrawWin alloc] init];
    dwt.simp = nil;
    dwt.win = win;
    [drawWindows addObject:dwt];
}

/*
================
idWindow::Parse's GUI editor support: what was parsed since the parser's
marker, as the wrapper keeps it
================
*/
- (NSString *)editorTextFromMarkerOf:(idParser *)src clean:(BOOL)clean {
    NSMutableString *str = [NSMutableString string];
    [src stringFromMarker:str clean:clean error:NULL];
    return str;
}

/// A script since the marker, its braces' text: "Parse it one more time to
/// knock unwanted tabs out".
- (NSString *)editorScriptFromMarkerOf:(idParser *)src {
    // Grab the string from the last marker
    NSString *str = [self editorTextFromMarkerOf:src clean:NO];

    // Parse it one more time to knock unwanted tabs out
    NSData *bytes __attribute__((objc_precise_lifetime)) = [str ud_latin1Buffer];
    idLexer *src2 = [[idLexer alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:@"" flags:[src flags] fileSystem:nil error:NULL];
    NSMutableString *out = [NSMutableString string];
    [src2 parseBracedSectionExact:out tabs:1 skippingCommentsAndStrings:YES error:NULL];
    return out;
}

/*
================
idWindow::Parse
================
*/
- (BOOL)parse:(idParser *)src rebuild:(BOOL)rebuild {
    idToken token, token2;
    idToken_Init( &token );
    idToken_Init( &token2 );

    if (rebuild) {
        [self cleanUp];
    }

    [timeLineEvents removeAllObjects];
    [transitions removeAllObjects];

    [namedEvents removeAllObjects];

    [src expectTokenType:TT_NAME subtype:0 token:&token error:NULL];

    [self setInitialState:UDTokenLatin1String( &token )];

    [src expectTokenString:@"{" error:NULL];
    [src expectAnyToken:&token error:NULL];

    BOOL ret = YES;

    // attach a window wrapper to the window if the gui editor is running
    BOOL editing = [gui manager].editing;
    if ( editing ) {
        (void)[[rvGEWindowWrapper alloc] initWithWindow:self type:WT_NORMAL];
    }

    while( !TokenIs( &token, "}" ) ) {
        // track what was parsed so we can maintain it for the guieditor
        [src setMarker];

        if ( TokenIs( &token, "windowDef" ) || TokenIs( &token, "animationDef" ) ) {
            if (TokenIs( &token, "animationDef" )) {
                [visible setData:NO];
                [rect setData:idRectangle_Make(0,0,0,0)];
            }
            [src expectTokenType:TT_NAME subtype:0 token:&token error:NULL];
            idToken_AssignFromToken( &token2, &token );
            [src unreadToken:&token];
            idDrawWin *dw = [self findChildByName:UDTokenLatin1String( &token2 )];
            if (dw && dw.win) {
                [self saveExpressionParseState];
                [dw.win parse:src rebuild:rebuild];
                [self restoreExpressionParseState];
            } else {
                idWindow *win = [[idWindow alloc] initWithDC:dc gui:gui];
                [self saveExpressionParseState];
                [win parse:src rebuild:rebuild];
                [self restoreExpressionParseState];
                [win setParent:self];
                idDrawWin *dwt = [[idDrawWin alloc] init];
                dwt.simp = nil;
                dwt.win = nil;
                if ([win isSimple]) {
                    idSimpleWindow *simple = [[idSimpleWindow alloc] initWithWindow:win];
                    dwt.simp = simple;
                    [drawWindows addObject:dwt];
                } else {
                    [self addChild:win];
                    [self setFocus:win scripts:NO];
                    dwt.win = win;
                    [drawWindows addObject:dwt];
                }
            }
        }
        else if ( TokenIs( &token, "editDef" ) ) {
            [self parseChild:[idEditWindow class] parser:src rebuild:rebuild];
        }
        else if ( TokenIs( &token, "choiceDef" ) ) {
            [self parseChild:[idChoiceWindow class] parser:src rebuild:rebuild];
        }
        else if ( TokenIs( &token, "sliderDef" ) ) {
            [self parseChild:[idSliderWindow class] parser:src rebuild:rebuild];
        }
        else if ( TokenIs( &token, "markerDef" ) ) {
            [self parseChild:[idMarkerWindow class] parser:src rebuild:rebuild];
        }
        else if ( TokenIs( &token, "bindDef" ) ) {
            [self parseChild:[idBindWindow class] parser:src rebuild:rebuild];
        }
        else if ( TokenIs( &token, "listDef" ) ) {
            [self parseChild:[idListWindow class] parser:src rebuild:rebuild];
        }
        else if ( TokenIs( &token, "fieldDef" ) ) {
            [self parseChild:[idFieldWindow class] parser:src rebuild:rebuild];
        }
        else if ( TokenIs( &token, "renderDef" ) ) {
            [self parseChild:[idRenderWindow class] parser:src rebuild:rebuild];
        }
        else if ( TokenIs( &token, "gameSSDDef" ) || TokenIs( &token, "gameBearShootDef" ) || TokenIs( &token, "gameBustOutDef" ) ) {
            // the engine's arcade games (idGameSSDWindow, idGameBearShootWindow,
            // idGameBustOutWindow) are not ported: the game's own code, not the
            // GUI's. Their windows are read and drawn as windows.
            [self parseChild:[idWindow class] parser:src rebuild:rebuild];
        }
//
//  added new onEvent
        else if ( TokenIs( &token, "onNamedEvent" ) ) {
            // Read the event name
            if ( ![src readToken:&token error:NULL] ) {
                [src error:NULL format:@"Expected event name"];
                return NO;
            }

            NSString *eventName = UDTokenLatin1String( &token );
            rvNamedEvent* ev = [[rvNamedEvent alloc] initWithName:eventName];

            [src setMarker];

            if ( ![self parseScript:src list:ev->mEvent timeParm:NULL elseBlock:NO] ) {
                ret = NO;
                break;
            }

            // If we are in the gui editor then add the internal var to the
            // the wrapper
            if ( editing ) {
                // Save the script. (The engine's key is "onEvent name", which
                // its editor writes back as it is, and Parse does not read:
                // its keyword is onNamedEvent.)
                [guiedWrapper.scriptDict set:[NSString stringWithFormat:@"onNamedEvent %@", eventName] value:[self editorScriptFromMarkerOf:src]];
            }
            [namedEvents addObject:ev];
        }
        else if ( TokenIs( &token, "onTime" ) ) {
            idTimeLineEvent *ev = [[idTimeLineEvent alloc] init];

            if ( ![src readToken:&token error:NULL] ) {
                [src error:NULL format:@"Unexpected end of file"];
                return NO;
            }
            ev->time = atoi(token.text);

            // reset the mark since we dont want it to include the time
            [src setMarker];

            if (![self parseScript:src list:ev->event timeParm:&ev->time elseBlock:NO]) {
                ret = NO;
                break;
            }

            // add the script to the wrappers script list
            // If we are in the gui editor then add the internal var to the
            // the wrapper
            if ( editing ) {
                // Save the script
                [guiedWrapper.scriptDict set:[NSString stringWithFormat:@"onTime %d", ev->time] value:[self editorScriptFromMarkerOf:src]];
            }

            // this is a timeline event
            ev->pending = YES;
            [timeLineEvents addObject:ev];
        }
        else if ( TokenIs( &token, "definefloat" ) ) {
            [src readToken:&token error:NULL];
            NSString *work = [UDTokenLatin1String( &token ) ud_lowercase];
            idWinFloat *varf = [[idWinFloat alloc] init];
            [varf setName:work];
            [definedVars addObject:varf];

            // add the float to the editors wrapper dict
            // Set the marker after the float name
            [src setMarker];

            // Read in the float
            [regList addReg:work type:REG_FLOAT parser:src window:self var:varf];

            // If we are in the gui editor then add the float to the defines
            if ( editing ) {
                // Grab the string from the last marker and save it in the wrapper
                [guiedWrapper.variableDict set:[NSString stringWithFormat:@"definefloat\t\"%@\"", UDTokenLatin1String( &token )]
                                         value:[self editorTextFromMarkerOf:src clean:YES]];
            }
        }
        else if ( TokenIs( &token, "definevec4" ) ) {
            [src readToken:&token error:NULL];
            NSString *work = [UDTokenLatin1String( &token ) ud_lowercase];
            idWinVec4 *var = [[idWinVec4 alloc] init];
            [var setName:work];

            // set the marker so we can determine what was parsed
            // set the marker after the vec4 name
            [src setMarker];

            // FIXME: how about we add the var to the desktop instead of this window so it won't get deleted
            //        when this window is destoyed which even happens during parsing with simple windows ?
            //definedVars.Append(var);
            idWindow *desktop = [gui getDesktop];
            [desktop->definedVars addObject:var];
            [desktop->regList addReg:work type:REG_VEC4 parser:src window:desktop var:var];

            // store the original vec4 for the editor
            // If we are in the gui editor then add the float to the defines
            if ( editing ) {
                // Grab the string from the last marker and save it in the wrapper
                [guiedWrapper.variableDict set:[NSString stringWithFormat:@"definevec4\t\"%@\"", UDTokenLatin1String( &token )]
                                         value:[self editorTextFromMarkerOf:src clean:YES]];
            }
        }
        else if ( TokenIs( &token, "float" ) ) {
            [src readToken:&token error:NULL];
            NSString *work = [UDTokenLatin1String( &token ) ud_lowercase];
            idWinFloat *varf = [[idWinFloat alloc] init];
            [varf setName:work];
            [definedVars addObject:varf];

            // add the float to the editors wrapper dict
            // set the marker to after the float name
            [src setMarker];

            // Parse the float
            [regList addReg:work type:REG_FLOAT parser:src window:self var:varf];

            // If we are in the gui editor then add the float to the defines
            if ( editing ) {
                // Grab the string from the last marker and save it in the wrapper
                [guiedWrapper.variableDict set:[NSString stringWithFormat:@"float\t\"%@\"", UDTokenLatin1String( &token )]
                                         value:[self editorTextFromMarkerOf:src clean:YES]];
            }
        }
        else if ([self parseScriptEntry:UDTokenLatin1String( &token ) parser:src]) {
            // add the script to the wrappers script list
            // If we are in the gui editor then add the internal var to the
            // the wrapper
            if ( editing ) {
                // Save the script
                [guiedWrapper.scriptDict set:UDTokenLatin1String( &token ) value:[self editorScriptFromMarkerOf:src]];
            }
        } else if ([self parseInternalVar:UDTokenLatin1String( &token ) parser:src]) {
            // gui editor support
            // If we are in the gui editor then add the internal var to the
            // the wrapper
            if ( editing ) {
                [guiedWrapper setStateKey:UDTokenLatin1String( &token ) value:[self editorTextFromMarkerOf:src clean:NO] update:NO];
            }
        }
        else {
            [self parseRegEntry:UDTokenLatin1String( &token ) parser:src];
            // hook into the main window parsing for the gui editor
            // If we are in the gui editor then add the internal var to the
            // the wrapper
            if ( editing ) {
                [guiedWrapper setStateKey:UDTokenLatin1String( &token ) value:[self editorTextFromMarkerOf:src clean:NO] update:NO];
            }
        }
        if ( ![src readToken:&token error:NULL] ) {
            [src error:NULL format:@"Unexpected end of file"];
            ret = NO;
            break;
        }
    }

    if (ret) {
        [self evalRegs:-1 force:YES];
    }

    [self setupFromState];
    [self postParse];

    // hook into the main window parsing for the gui editor
    // If we are in the gui editor then add the internal var to the
    // the wrapper
    if ( editing ) {
        [guiedWrapper finish];
    }

    return ret;
}

/*
================
idWindow::FindSimpleWinByName
================
*/
- (idSimpleWindow *)findSimpleWinByName:(NSString *)_name {
    for ( idDrawWin *dw in drawWindows ) {
        if (dw.simp == nil) {
            continue;
        }
        if ( [dw.simp->name ud_iequals:_name] ) {
            return dw.simp;
        }
    }
    return nil;
}

/*
================
idWindow::FindChildByName
================
*/
- (idDrawWin *)findChildByName:(NSString *)_name {
    // (not the engine's: the GUI's index of this window's tree, while it
    // has them; see idUserInterfaceLocal's fixupParmsOf:)
    NSDictionary<NSString *, idDrawWin *> *index = [gui nameIndexOf:self];
    if (index != nil) {
        return index[[_name ud_foldedAZ]];
    }
    if ([name ud_iequals:_name]) {
        idDrawWin *dw = [[idDrawWin alloc] init];
        dw.simp = nil;
        dw.win = self;
        return dw;
    }
    for ( idDrawWin *dw in drawWindows ) {
        if (dw.win) {
            if ([dw.win->name ud_iequals:_name]) {
                return dw;
            }
            idDrawWin *win = [dw.win findChildByName:_name];
            if (win) {
                return win;
            }
        } else {
            if ([dw.simp->name ud_iequals:_name]) {
                return dw;
            }
        }
    }
    return nil;
}

/*
================
idWindow::AddTransition
================
*/
- (void)addTransition:(idWinVar *)dest from:(idVec4)from to:(idVec4)to time:(int)time accelTime:(float)accelTime decelTime:(float)decelTime {
    idTransitionData *data = [[idTransitionData alloc] init];
    data->data = dest;
    idInterpolateAccelDecelLinear_Init( &data->interp, [gui getTime], accelTime * time, decelTime * time, time, from, to );
    [transitions addObject:data];
}


/*
================
idWindow::StartTransition
================
*/
- (void)startTransition {
    flags |= WIN_INTRANSITION;
}

/*
================
idWindow::ResetCinematics
================
*/
- (void)resetCinematics {
    if ( background ) {
        [background resetCinematicTime:[gui getTime]];
    }
}

/*
================
idWindow::ResetTime
================
*/
- (void)resetTime:(int)t {

    timeLine = [gui getTime] - t;

    for ( idTimeLineEvent *ev in timeLineEvents ) {
        if ( ev->time >= t ) {
            ev->pending = YES;
        }
    }

    [noTime setData:NO];

    for ( NSInteger i = 0; i < (NSInteger)transitions.count; i++ ) {
        idTransitionData *data = transitions[i];
        if ( idInterpolateAccelDecelLinear_IsDone( &data->interp, [gui getTime] ) && data->data ) {
            [transitions removeObjectAtIndex:i];
            i--;
        }
    }

}


/*
================
idWindow::RunScriptList
================
*/
- (BOOL)runScriptList:(idGuiScriptList *)src {
    if (src == nil) {
        return NO;
    }
    [src execute:self];
    return YES;
}

/*
================
idWindow::RunScript
================
*/
- (BOOL)runScript:(int)n {
    if (n >= ON_MOUSEENTER && n < SCRIPT_COUNT) {
        return [self runScriptList:scripts[n]];
    }
    return NO;
}

- (int)appendExpressionRegister:(float)f {
    if ( numExpressionRegisters == maxExpressionRegisters ) {
        maxExpressionRegisters = maxExpressionRegisters ? maxExpressionRegisters * 2 : 16;
        expressionRegisters = realloc( expressionRegisters, sizeof( float ) * maxExpressionRegisters );
    }
    expressionRegisters[numExpressionRegisters] = f;
    return numExpressionRegisters++;
}

/*
================
idWindow::ExpressionConstant
================
*/
- (int)expressionConstant:(float)f {
    int     i;

    for ( i = WEXP_REG_NUM_PREDEFINED ; i < numExpressionRegisters ; i++ ) {
        if ( !registerIsTemporary[i] && expressionRegisters[i] == f ) {
            return i;
        }
    }
    if ( numExpressionRegisters == MAX_EXPRESSION_REGISTERS ) {
        [[gui manager] uiWarning:[NSString stringWithFormat:@"expressionConstant: gui %@ hit MAX_EXPRESSION_REGISTERS", [gui getSourceFile]]];
        return 0;
    }

    int c = numExpressionRegisters;
    if (i > c) {
        while (i > c) {
            [self appendExpressionRegister:-9999999];
            i--;
        }
    }

    i = [self appendExpressionRegister:f];
    registerIsTemporary[i] = NO;
    return i;
}

/*
================
idWindow::ExpressionTemporary
================
*/
- (int)expressionTemporary {
    if ( numExpressionRegisters == MAX_EXPRESSION_REGISTERS ) {
        [[gui manager] uiWarning:[NSString stringWithFormat:@"expressionTemporary: gui %@ hit MAX_EXPRESSION_REGISTERS", [gui getSourceFile]]];
        return 0;
    }
    int i = numExpressionRegisters;
    registerIsTemporary[i] = YES;
    i = [self appendExpressionRegister:0];
    return i;
}

/*
================
idWindow::ExpressionOp: its index (the engine returns a pointer into the
list, which the COND op keeps across more appends)
================
*/
- (int)expressionOp {
    if ( numOps == MAX_EXPRESSION_OPS ) {
        [[gui manager] uiWarning:[NSString stringWithFormat:@"expressionOp: gui %@ hit MAX_EXPRESSION_OPS", [gui getSourceFile]]];
        return 0;
    }
    if ( numOps == maxOps ) {
        maxOps = maxOps ? maxOps * 2 : 16;
        ops = realloc( ops, sizeof( wexpOp_t ) * maxOps );
    }
    memset( &ops[numOps], 0, sizeof( wexpOp_t ) );
    return numOps++;
}

/*
================
idWindow::EmitOp
================
*/
- (intptr_t)emitOp:(intptr_t)a b:(intptr_t)b opType:(wexpOpType_t)opType opp:(int *)opp {
    int op = [self expressionOp];

    ops[op].opType = opType;
    ops[op].a = a;
    ops[op].b = b;
    ops[op].c = [self expressionTemporary];

    if (opp) {
        *opp = op;
    }
    return ops[op].c;
}

/*
================
idWindow::ParseEmitOp
================
*/
- (intptr_t)parseEmitOp:(idParser *)src a:(intptr_t)a opType:(wexpOpType_t)opType priority:(int)priority opp:(int *)opp {
    intptr_t b = [self parseExpressionPriority:src priority:priority var:nil component:0];
    return [self emitOp:a b:b opType:opType opp:opp];
}


/*
================
idWindow::ParseTerm

Returns a register index
=================
*/
- (intptr_t)parseTerm:(idParser *)src var:(idWinVar *)var component:(intptr_t)component {
    idToken token;
    idToken_Init( &token );
    intptr_t a, b;

    [src readToken:&token error:NULL];

    if ( TokenIs( &token, "(" ) ) {
        a = [self parseExpression:src];
        [src expectTokenString:@")" error:NULL];
        return a;
    }

    if ( UDTokenIcmp( &token, "time" ) ) {
        return WEXP_REG_TIME;
    }

    // parse negative numbers
    if ( TokenIs( &token, "-" ) ) {
        [src readToken:&token error:NULL];
        if ( token.type == TT_NUMBER || TokenIs( &token, "." ) ) {
            return [self expressionConstant:-(float) idToken_FloatValue( &token )];
        }
        [src warning:@"Bad negative number '%s'", token.text];
        return 0;
    }

    if ( token.type == TT_NUMBER || TokenIs( &token, "." ) || TokenIs( &token, "-" ) ) {
        return [self expressionConstant:(float) idToken_FloatValue( &token )];
    }

    // see if it is a table name
    if ( [[gui manager] tableExists:UDTokenLatin1String( &token )] ) {
        NSString *tableName = UDTokenLatin1String( &token );
        NSUInteger index = [tables indexOfObject:tableName];
        if ( index == NSNotFound ) {
            index = tables.count;
            [tables addObject:tableName];
        }
        a = (intptr_t)index;
        // parse a table expression
        [src expectTokenString:@"[" error:NULL];
        b = [self parseExpression:src];
        [src expectTokenString:@"]" error:NULL];
        return [self emitOp:a b:b opType:WOP_TYPE_TABLE opp:NULL];
    }

    if (var == nil) {
        var = [self getWinVarByName:UDTokenLatin1String( &token ) fixup:YES owner:NULL];
    }
    if (var) {
        a = (intptr_t)(__bridge void *)var;
        //assert(dynamic_cast<idWinVec4*>(var));
        [var winVarInit:UDTokenLatin1String( &token ) window:self];
        b = component;
        if ([var isKindOfClass:[idWinVec4 class]]) {
            if ([src readToken:&token error:NULL]) {
                if (TokenIs( &token, "[" )) {
                    b = [self parseExpression:src];
                    [src expectTokenString:@"]" error:NULL];
                } else {
                    [src unreadToken:&token];
                }
            }
            return [self emitOp:a b:b opType:WOP_TYPE_VAR opp:NULL];
        } else if ([var isKindOfClass:[idWinFloat class]]) {
            return [self emitOp:a b:b opType:WOP_TYPE_VARF opp:NULL];
        } else if ([var isKindOfClass:[idWinInt class]]) {
            return [self emitOp:a b:b opType:WOP_TYPE_VARI opp:NULL];
        } else if ([var isKindOfClass:[idWinBool class]]) {
            return [self emitOp:a b:b opType:WOP_TYPE_VARB opp:NULL];
        } else if ([var isKindOfClass:[idWinStr class]]) {
            return [self emitOp:a b:b opType:WOP_TYPE_VARS opp:NULL];
        } else {
            [src warning:@"Var expression not vec4, float or int '%s'", token.text];
        }
        return 0;
    } else {
        // ugly but used for post parsing to fixup named vars
        a = (intptr_t)CFBridgingRetain( UDTokenLatin1String( &token ) );
        b = -2;
        return [self emitOp:a b:b opType:WOP_TYPE_VAR opp:NULL];
    }

}

/*
=================
idWindow::ParseExpressionPriority

Returns a register index
=================
*/
#define TOP_PRIORITY 4
- (intptr_t)parseExpressionPriority:(idParser *)src priority:(int)priority var:(idWinVar *)var component:(intptr_t)component {
    idToken token;
    idToken_Init( &token );
    intptr_t a;

    if ( priority == 0 ) {
        return [self parseTerm:src var:var component:component];
    }

    a = [self parseExpressionPriority:src priority:priority - 1 var:var component:component];

    if ( ![src readToken:&token error:NULL] ) {
        // we won't get EOF in a real file, but we can
        // when parsing from generated strings
        return a;
    }

    if ( priority == 1 && TokenIs( &token, "*" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_MULTIPLY priority:priority opp:NULL];
    }
    if ( priority == 1 && TokenIs( &token, "/" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_DIVIDE priority:priority opp:NULL];
    }
    if ( priority == 1 && TokenIs( &token, "%" ) ) {  // implied truncate both to integer
        return [self parseEmitOp:src a:a opType:WOP_TYPE_MOD priority:priority opp:NULL];
    }
    if ( priority == 2 && TokenIs( &token, "+" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_ADD priority:priority opp:NULL];
    }
    if ( priority == 2 && TokenIs( &token, "-" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_SUBTRACT priority:priority opp:NULL];
    }
    if ( priority == 3 && TokenIs( &token, ">" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_GT priority:priority opp:NULL];
    }
    if ( priority == 3 && TokenIs( &token, ">=" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_GE priority:priority opp:NULL];
    }
    if ( priority == 3 && TokenIs( &token, "<" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_LT priority:priority opp:NULL];
    }
    if ( priority == 3 && TokenIs( &token, "<=" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_LE priority:priority opp:NULL];
    }
    if ( priority == 3 && TokenIs( &token, "==" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_EQ priority:priority opp:NULL];
    }
    if ( priority == 3 && TokenIs( &token, "!=" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_NE priority:priority opp:NULL];
    }
    if ( priority == 4 && TokenIs( &token, "&&" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_AND priority:priority opp:NULL];
    }
    if ( priority == 4 && TokenIs( &token, "||" ) ) {
        return [self parseEmitOp:src a:a opType:WOP_TYPE_OR priority:priority opp:NULL];
    }
    if ( priority == 4 && TokenIs( &token, "?" ) ) {
        int oop = -1;
        intptr_t o = [self parseEmitOp:src a:a opType:WOP_TYPE_COND priority:priority opp:&oop];
        if ( ![src readToken:&token error:NULL] ) {
            return o;
        }
        if (TokenIs( &token, ":@" )) {
            a = [self parseExpressionPriority:src priority:priority - 1 var:var component:0];
            ops[oop].d = a;
        }
        return o;
    }

    // assume that anything else terminates the expression
    // not too robust error checking...

    [src unreadToken:&token];

    return a;
}

/*
================
idWindow::ParseExpression

Returns a register index
================
*/
- (intptr_t)parseExpression:(idParser *)src var:(idWinVar *)var component:(intptr_t)component {
    return [self parseExpressionPriority:src priority:TOP_PRIORITY var:var component:0];
}

- (intptr_t)parseExpression:(idParser *)src {
    return [self parseExpression:src var:nil component:0];
}

/*
================
idWindow::ParseBracedExpression
================
*/
- (void)parseBracedExpression:(idParser *)src {
    [src expectTokenString:@"{" error:NULL];
    [self parseExpression:src];
    [src expectTokenString:@"}" error:NULL];
}

/*
===============
idWindow::EvaluateRegisters

Parameters are taken from the localSpace and the renderView,
then all expressions are evaluated, leaving the shader registers
set to their apropriate values.
===============
*/
- (void)evaluateRegisters:(float *)registers {
    int     i, b;
    wexpOp_t    *op;

    int erc = numExpressionRegisters;
    int oc = numOps;
    // copy the constants
    for ( i = WEXP_REG_NUM_PREDEFINED ; i < erc ; i++ ) {
        registers[i] = expressionRegisters[i];
    }

    // copy the local and global parameters
    registers[WEXP_REG_TIME] = [gui getTime];

    for ( i = 0 ; i < oc ; i++ ) {
        op = &ops[i];
        if (op->b == -2) {
            continue;
        }
        switch( op->opType ) {
        case WOP_TYPE_ADD:
            registers[op->c] = registers[op->a] + registers[op->b];
            break;
        case WOP_TYPE_SUBTRACT:
            registers[op->c] = registers[op->a] - registers[op->b];
            break;
        case WOP_TYPE_MULTIPLY:
            registers[op->c] = registers[op->a] * registers[op->b];
            break;
        case WOP_TYPE_DIVIDE:
            if ( registers[op->b] == 0.0f ) {
                [[gui manager] uiWarning:[NSString stringWithFormat:@"Divide by zero in window '%@' in %@", [self getName], [gui getSourceFile]]];
                registers[op->c] = registers[op->a];
            } else {
                registers[op->c] = registers[op->a] / registers[op->b];
            }
            break;
        case WOP_TYPE_MOD:
            b = (int)registers[op->b];
            b = b != 0 ? b : 1;
            registers[op->c] = (int)registers[op->a] % b;
            break;
        case WOP_TYPE_TABLE:
            {
                registers[op->c] = [UDDeclTable ud_lookup:registers[op->b] inTableNamed:tables[op->a] declManager:[gui manager].declManager];
            }
            break;
        case WOP_TYPE_GT:
            registers[op->c] = registers[ op->a ] > registers[op->b];
            break;
        case WOP_TYPE_GE:
            registers[op->c] = registers[ op->a ] >= registers[op->b];
            break;
        case WOP_TYPE_LT:
            registers[op->c] = registers[ op->a ] < registers[op->b];
            break;
        case WOP_TYPE_LE:
            registers[op->c] = registers[ op->a ] <= registers[op->b];
            break;
        case WOP_TYPE_EQ:
            registers[op->c] = registers[ op->a ] == registers[op->b];
            break;
        case WOP_TYPE_NE:
            registers[op->c] = registers[ op->a ] != registers[op->b];
            break;
        case WOP_TYPE_COND:
            registers[op->c] = (registers[ op->a ]) ? registers[op->b] : registers[op->d];
            break;
        case WOP_TYPE_AND:
            registers[op->c] = registers[ op->a ] && registers[op->b];
            break;
        case WOP_TYPE_OR:
            registers[op->c] = registers[ op->a ] || registers[op->b];
            break;
        case WOP_TYPE_VAR:
            if ( !op->a ) {
                registers[op->c] = 0.0f;
                break;
            }
            if ( op->b >= 0 && registers[op->b] >= 0 && registers[op->b] < 4 ) {
                // grabs vector components: the engine's ((idVec4&)var)[i]
                // reads past the pointer it casts; the var's vector it means
                idWinVar *var = (__bridge idWinVar *)(void *)( op->a );
                if ( [var isKindOfClass:[idWinVec4 class]] ) {
                    idVec4 v = [(idWinVec4 *)var data];
                    registers[op->c] = idVec4_Ptr( &v )[(int)registers[op->b]];
                } else {
                    registers[op->c] = [var x];
                }
            } else {
                registers[op->c] = [(__bridge idWinVar *)(void *)(op->a) x];
            }
            break;
        case WOP_TYPE_VARS:
            if (op->a) {
                idWinStr *var = (__bridge idWinStr *)(void *)(op->a);
                registers[op->c] = atof([var string].UTF8String);
            } else {
                registers[op->c] = 0;
            }
            break;
        case WOP_TYPE_VARF:
            if (op->a) {
                idWinFloat *var = (__bridge idWinFloat *)(void *)(op->a);
                registers[op->c] = var.data;
            } else {
                registers[op->c] = 0;
            }
            break;
        case WOP_TYPE_VARI:
            if (op->a) {
                idWinInt *var = (__bridge idWinInt *)(void *)(op->a);
                registers[op->c] = var.data;
            } else {
                registers[op->c] = 0;
            }
            break;
        case WOP_TYPE_VARB:
            if (op->a) {
                idWinBool *var = (__bridge idWinBool *)(void *)(op->a);
                registers[op->c] = var.data;
            } else {
                registers[op->c] = 0;
            }
            break;
        default:
            // common->FatalError( "R_EvaluateExpression: bad opcode" );
            break;
        }
    }

}

/*
===============
idWindow::NumTransitions
===============
*/
- (int)numTransitions {
    int c = (int)transitions.count;
    for ( idWindow *child in children ) {
        c += [child numTransitions];
    }
    return c;
}

/*
===============
idWindow::AddChild
===============
*/
- (void)addChild:(idWindow *)win {
    [children addObject:win];
    win->childID = (int)children.count - 1;
}

/*
================
idWindow::FixupParms
================
*/
- (void)fixupParms {
    int i;
    for (idWindow *child in [children copy]) {
        [child fixupParms];
    }
    for (i = 0; i < SCRIPT_COUNT; i++) {
        if (scripts[i]) {
            [scripts[i] fixupParms:self];
        }
    }

    for (idTimeLineEvent *ev in [timeLineEvents copy]) {
        [ev->event fixupParms:self];
    }

    for (rvNamedEvent *ev in [namedEvents copy]) {
        [ev->mEvent fixupParms:self];
    }

    for (i = 0; i < numOps; i++) {
        if (ops[i].b == -2) {
            // need to fix this up
            NSString *p = CFBridgingRelease( (CFTypeRef)ops[i].a );
            idWinVar *var = [self getWinVarByName:p fixup:YES owner:NULL];
            ops[i].a = (intptr_t)(__bridge void *)var;
            ops[i].b = -1;
        }
    }


    if (flags & WIN_DESKTOP) {
        [self calcRects:0 y:0];
    }

}

/*
================
idWindow::IsSimple
================
*/
- (BOOL)isSimple {

    // dont do simple windows when in gui editor
    if ( [gui manager].editing ) {
        return NO;
    }

    if (numOps) {
        return NO;
    }
    if (flags & (WIN_HCENTER | WIN_VCENTER)) {
        return NO;
    }
    if (children.count || drawWindows.count) {
        return NO;
    }
    for (int i = 0; i < SCRIPT_COUNT; i++) {
        if (scripts[i]) {
            return NO;
        }
    }
    if (timeLineEvents.count) {
        return NO;
    }

    if ( namedEvents.count ) {
        return NO;
    }

    return YES;
}

/*
================
idWindow::ContainsStateVars
================
*/
- (BOOL)containsStateVars {
    if ( updateVars.count ) {
        return YES;
    }
    for (idWindow *child in children) {
        if ( [child containsStateVars] ) {
            return YES;
        }
    }
    return NO;
}

/*
================
idWindow::Interactive
================
*/
- (BOOL)interactive {
    if ( scripts[ ON_ACTION ] ) {
        return YES;
    }
    for (idWindow *child in children) {
        if ([child interactive]) {
            return YES;
        }
    }
    return NO;
}

/*
================
idWindow::SetChildWinVarVal
================
*/
- (void)setChildWinVarVal:(NSString *)childName var:(NSString *)var val:(NSString *)val {
    idDrawWin *dw = [self findChildByName:childName];
    idWinVar *wv = nil;
    if (dw && dw.simp) {
        wv = [dw.simp getWinVarByName:var];
    } else if (dw && dw.win) {
        wv = [dw.win getWinVarByName:var];
    }
    if (wv) {
        [wv set:val];
        [wv setEval:NO];
    }
}


/*
================
idWindow::FindChildByPoint

Finds the window under the given point
================
*/
- (idWindow *)findChildByPoint:(float)x y:(float)y belowPtr:(__strong idWindow **)below {
    // If we are looking for a window below this one then
    // the next window should be good, but this one wasnt it
    if ( *below == self ) {
        *below = nil;
        return nil;
    }

    if ( ![self containsRect:drawRect x:x y:y] ) {
        return nil;
    }

    for (NSInteger i = (NSInteger)children.count - 1; i >= 0 ; i-- ) {
        idWindow* found = [children[i] findChildByPoint:x y:y belowPtr:below];
        if ( found ) {
            if ( *below ) {
                continue;
            }

            return found;
        }
    }

    return self;
}

/*
================
idWindow::FindChildByPoint
================
*/
- (idWindow *)findChildByPoint:(float)x y:(float)y below:(idWindow *)below {
    idWindow *b = below;
    return [self findChildByPoint:x y:y belowPtr:&b];
}

/*
================
idWindow::GetChildCount

Returns the number of children
================
*/
- (int)getChildCount {
    return (int)drawWindows.count;
}

/*
================
idWindow::GetChild

Returns the child window at the given index
================
*/
- (idWindow *)getChild:(int)index {
    return drawWindows[index].win;
}

/*
================
idWindow::GetChildIndex

Returns the index of the given child window
================
*/
- (int)getChildIndex:(idWindow *)window {
    int find;
    for ( find = 0; find < (int)drawWindows.count; find ++ ) {
        if ( drawWindows[find].win == window ) {
            return find;
        }
    }
    return -1;
}

/*
================
idWindow::RemoveChild

Removes the child from the list of children.   Note that the child window being
removed must still be deallocated by the caller
================
*/
- (void)removeChild:(idWindow *)win {
    int find;

    // Remove the child window
    [children removeObjectIdenticalTo:win];

    for ( find = 0; find < (int)drawWindows.count; find ++ )
    {
        if ( drawWindows[find].win == win )
        {
            [drawWindows removeObjectAtIndex:find];
            break;
        }
    }
}

/*
================
idWindow::InsertChild

Inserts the given window as a child into the given location in the zorder.
================
*/
- (BOOL)insertChild:(idWindow *)win before:(idWindow *)before
{
    [self addChild:win];

    win->parent = self;

    idDrawWin *dwt = [[idDrawWin alloc] init];
    dwt.simp = nil;
    dwt.win = win;

    // If not inserting before anything then just add it at the end
    if ( before ) {
        int index;
        index = [self getChildIndex:before];
        if ( index != -1 ) {
            [drawWindows insertObject:dwt atIndex:index];
            return YES;
        }
    }

    [drawWindows addObject:dwt];
    return YES;
}

/*
================
idWindow::ScreenToClient
================
*/
- (void)screenToClient:(idRectangle *)r {
    int       x;
    int       y;
    idWindow* p;

    for ( p = self, x = 0, y = 0; p; p = p->parent ) {
        x += [p->rect x];
        y += [p->rect y];
    }

    r->x -= x;
    r->y -= y;
}

/*
================
idWindow::ClientToScreen
================
*/
- (void)clientToScreen:(idRectangle *)r {
    int       x;
    int       y;
    idWindow* p;

    for ( p = self, x = 0, y = 0; p; p = p->parent ) {
        x += [p->rect x];
        y += [p->rect y];
    }

    r->x += x;
    r->y += y;
}

/*
================
idWindow::SetDefaults

Set the window do a default window with no text, no background and
default colors, etc..
================
*/
- (void)setDefaults {
    forceAspectWidth = 640.0f;
    forceAspectHeight = 480.0f;
    matScalex = 1;
    matScaley = 1;
    borderSize = 0;
    [noTime setData:NO];
    [visible setData:YES];
    textAlign = 0;
    textAlignx = 0;
    textAligny = 0;
    [noEvents setData:NO];
    [rotate setData:0];
    shear = idVec2_Make( 0, 0 );
    [textScale setData:0.35f];
    [backColor zero];
    [foreColor setData:idVec4_Make(1, 1, 1, 1)];
    [hoverColor setData:idVec4_Make(1, 1, 1, 1)];
    [matColor setData:idVec4_Make(1, 1, 1, 1)];
    [borderColor zero];
    [text setData:@""];

    background = nil;
    [backGroundName setData:@""];
}

/*
================
idWindow::UpdateFromDictionary

The editor only has a dictionary to work with so the easiest way to push the
values of the dictionary onto the window is for the window to interpret the
dictionary as if were a file being parsed.
================
*/
- (BOOL)updateFromDictionary:(idDict *)dict {
    int i;

    [self setDefaults];

    // Clear all registers since they will get recreated
    [regList reset];
    numExpressionRegisters = 0;
    [self freeOps];

    for ( i = 0; i < [dict numKeyVals]; i ++ ) {
        NSString *key = [dict keyAtIndex:i];
        NSString *value = [dict valueAtIndex:i];

        // Special case name
        if ( [key ud_iequals:@"name"] ) {
            name = [value copy];
            continue;
        }

        NSData *bytes __attribute__((objc_precise_lifetime)) = [value ud_latin1Buffer];
        idParser *src = [[idParser alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:@""
                                                   flags:LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                                   error:NULL];
        if ( ![self parseInternalVar:key parser:src] ) {
            // Kill the old register since the parse reg entry will add a new one
            if ( ![self parseRegEntry:key parser:src] ) {
                continue;
            }
        }
    }

    [self evalRegs:-1 force:YES];

    [self setupFromState];
    [self postParse];

    return YES;
}

@end
