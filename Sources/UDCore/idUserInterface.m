/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idUserInterface.m — ui/UserInterface.cpp, ported (its demo and savegame
 * parts, and the gamepad's events, left out). See idUserInterface.h.
 */

#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "idUserInterface.h"
#import "idDeviceContext.h"
#import "idGuiModel.h"
#import "idDict.h"
#import "idParser.h"
#import "idToken.h"
#import "idLexer.h"
#import "idDeclManager.h"
#import "UDSoftwareRenderer.h"
#import "UDDeclCodec.h"
#import "idStr.h"

#pragma mark - idUserInterfaceManagerLocal

@interface idUserInterfaceManager ()
@property (nonatomic, readwrite) idRectangle screenRect;
@property (nonatomic, strong, readwrite) idDeviceContext *dc;
@property (nonatomic, strong, readwrite) idGuiModel *guiModel;
@property (nonatomic, strong, readwrite) UDSoftwareRenderer *renderer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, idMaterial *> *materials;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *keysDown;
@end

@interface idMaterial ()
- (instancetype)initWithName:(NSString *)name manager:(idUserInterfaceManager *)manager;
@end

@implementation idUserInterfaceManager

- (instancetype)initWithFileSystem:(idFileSystem *)fileSystem declManager:(idDeclManager *)declManager {
    self = [super init];
    if (self) {
        _fileSystem = fileSystem;
        _declManager = declManager;
        _guis = [NSMutableArray array];
        _languageDict = [[idLangDict alloc] init];
        _languageDict.warnings = self;
        _cvars = [[idCVarSystem alloc] init];
        _playedSounds = [NSMutableArray array];
        _warnings = [NSMutableArray array];
        _bufferedCommands = [NSMutableArray array];
        _materials = [NSMutableDictionary dictionary];
        _keysDown = [NSMutableSet set];
        _screenWidth = VIRTUAL_WIDTH;
        _screenHeight = VIRTUAL_HEIGHT;
        _renderer = [[UDSoftwareRenderer alloc] initWithWidth:VIRTUAL_WIDTH height:VIRTUAL_HEIGHT declManager:declManager fileSystem:fileSystem];
        [_renderer setGuiView];
        _guiModel = [[idGuiModel alloc] initWithDefaultMaterial:[self findMaterial:@"_default"]];
        _dc = [[idDeviceContext alloc] initWithManager:self];
    }
    return self;
}

- (void)managerInit {
    if ( self.fileSystem != nil ) {
        [self.languageDict initLanguage:[self.cvars getString:@"sys_lang"] fileSystem:self.fileSystem];
    }
    self.screenRect = idRectangle_Make(0, 0, 640, 480);
    [self.dc deviceInit];
}

- (void)shutdown {
    [self.guis removeAllObjects];
    [self.dc shutdown];
}

- (void)setSize:(float)width height:(float)height {
    [self.dc setSize:width height:height];
}

- (BOOL)checkGui:(NSString *)qpath {
    return [self.fileSystem readFile:qpath buffer:NULL timestamp:NULL error:NULL] >= 0;
}

- (idUserInterfaceLocal *)allocGui {
    return [[idUserInterfaceLocal alloc] initWithManager:self];
}

- (void)deAlloc:(idUserInterfaceLocal *)gui {
    if ( gui ) {
        [self.guis removeObjectIdenticalTo:gui];
    }
}

- (idUserInterfaceLocal *)findGui:(NSString *)qpath autoLoad:(BOOL)autoLoad needUnique:(BOOL)needUnique forceNOTUnique:(BOOL)forceNOTUnique {
    for ( idUserInterfaceLocal *gui in self.guis ) {
        if ( [[gui getSourceFile] ud_iequals:qpath] ) {
            if ( !forceNOTUnique && ( needUnique || [gui isInteractive] ) ) {
                break;
            }
            [gui addRef];
            return gui;
        }
    }

    if ( autoLoad ) {
        idUserInterfaceLocal *gui = [self allocGui];
        if ( [gui initFromFile:qpath] ) {
            [gui setUniqued:forceNOTUnique ? NO : needUnique];
            return gui;
        }
    }
    return nil;
}

- (BOOL)isKeyDown:(int)key {
    return [self.keysDown containsObject:@( key )];
}

- (void)setKey:(int)key down:(BOOL)down {
    if ( down ) {
        [self.keysDown addObject:@( key )];
    } else {
        [self.keysDown removeObject:@( key )];
    }
}

- (idMaterial *)findMaterial:(NSString *)name {
    NSString *key = [idDeclManager makeCanonicalName:name];
    idMaterial *material = self.materials[key];
    if ( material == nil ) {
        material = [[idMaterial alloc] initWithName:key manager:self];
        self.materials[key] = material;
    }
    return material;
}

- (BOOL)tableExists:(NSString *)name {
    return [self.declManager findDeclWithoutParsing:DECL_TABLE name:name makeDefault:NO] != nil;
}

- (void)playShaderDirectly:(NSString *)name {
    [self.playedSounds addObject:name];
}

- (void)uiWarning:(NSString *)message {
    [self.warnings addObject:message];
}

@end

#pragma mark - idUserInterfaceLocal

@implementation idUserInterfaceLocal {
    NSMapTable<idWindow *, NSMutableDictionary<NSString *, idDrawWin *> *> *_nameIndexes;
    BOOL                        active;
    BOOL                        loading;
    BOOL                        interactive;
    BOOL                        uniqued;

    idDict *                    state;
    idWindow *                  desktop;
    __weak idWindow *           bindHandler;

    NSString *                  source;
    NSMutableString *           activateStr;
    NSMutableString *           pendingCmd;
    NSMutableString *           returnCmd;
    unsigned int                timeStamp;

    float                       cursorX;
    float                       cursorY;

    int                         time;

    int                         refs;
}

- (instancetype)initWithManager:(idUserInterfaceManager *)manager {
    self = [super init];
    if (self) {
        _manager = manager;
        cursorX = cursorY = 0.0;
        desktop = nil;
        loading = NO;
        active = NO;
        interactive = NO;
        uniqued = NO;
        bindHandler = nil;
        //so the reg eval in gui parsing doesn't get bogus values
        time = 0;
        refs = 1;
        state = [[idDict alloc] init];
        source = @"";
        activateStr = [NSMutableString string];
        pendingCmd = [NSMutableString string];
        returnCmd = [NSMutableString string];
        _diagnostics = [NSMutableArray array];
    }
    return self;
}

- (NSString *)name {
    return source;
}

- (NSString *)comment {
    if ( desktop ) {
        return [desktop getComment];
    }
    return @"";
}

- (BOOL)isInteractive {
    return interactive;
}

- (BOOL)initFromFile:(NSString *)qpath {
    return [self initFromFile:qpath rebuild:YES cache:YES];
}

- (BOOL)initFromFile:(NSString *)qpath rebuild:(BOOL)rebuild cache:(BOOL)cache {
    return [self initFromText:nil path:qpath rebuild:rebuild];
}

- (BOOL)initFromText:(NSString *)text path:(NSString *)qpath {
    return [self initFromText:text path:qpath rebuild:YES];
}

/*
==============
idUserInterfaceLocal::InitFromFile
==============
*/
- (BOOL)initFromText:(NSString *)text path:(NSString *)qpath rebuild:(BOOL)rebuild {
    idUserInterfaceManager *uiManagerLocal = self.manager;

    if ( qpath.length == 0 ) {
        // FIXME: Memory leak!!
        return NO;
    }

    loading = YES;

    if ( rebuild ) {
        desktop = [[idWindow alloc] initWithGui:self];
    } else if ( desktop == nil ) {
        desktop = [[idWindow alloc] initWithGui:self];
    }

    source = [qpath copy];
    [state set:@"text" value:@"Test Text!"];

    idParser *src = [[idParser alloc] initWithFlags:LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                         fileSystem:uiManagerLocal.fileSystem];
    [self.diagnostics removeAllObjects];
    src.diagnostics = self.diagnostics;

    //Load the timestamp so reload guis will work correctly
    NSString *path = qpath;
    [uiManagerLocal.fileSystem readFile:path buffer:NULL timestamp:&timeStamp error:NULL];

    NSData *bytes __attribute__((objc_precise_lifetime)) = nil;
    if ( text != nil ) {
        bytes = [text ud_latin1Buffer];
        [src loadMemory:bytes.bytes length:(int)bytes.length - 1 name:path error:NULL];
    } else {
        [src loadFile:path isOSPath:NO error:NULL];
    }

    if ( [src isLoaded] ) {
        idToken token;
        idToken_Init( &token );
        while( [src readToken:&token error:NULL] ) {
            if ( UDTokenIcmp( &token, "windowDef" ) ) {
                [desktop setDC:uiManagerLocal.dc];
                if ( [desktop parse:src rebuild:rebuild] ) {
                    [desktop setFlag:WIN_DESKTOP];
                    [self fixupParmsOf:desktop];
                }
                continue;
            }
        }

        [state set:@"name" value:qpath];
    } else {
        [desktop setDC:uiManagerLocal.dc];
        [desktop setFlag:WIN_DESKTOP];
        desktop->name = @"Desktop";
        [desktop->text setData:[NSString stringWithFormat:@"Invalid GUI: %@", qpath]];
        [desktop->rect setData:idRectangle_Make( 0.0f, 0.0f, 640.0f, 480.0f )];
        desktop->drawRect = desktop->rect.data;
        [desktop->foreColor setData:idVec4_Make( 1.0f, 1.0f, 1.0f, 1.0f )];
        [desktop->backColor setData:idVec4_Make( 0.0f, 0.0f, 0.0f, 1.0f )];
        [desktop setupFromState];
        [uiManagerLocal uiWarning:[NSString stringWithFormat:@"Couldn't load gui: '%@'", qpath]];
        loading = NO;
        return NO;
    }

    interactive = [desktop interactive];

    if ( [uiManagerLocal.guis indexOfObjectIdenticalTo:self] == NSNotFound ) {
        [uiManagerLocal.guis addObject:self];
    }

    loading = NO;

    return YES;
}

/*
==============
idUserInterfaceLocal::HandleEvent
==============
*/
- (NSString *)handleEvent:(const sysEvent_t *)event time:(int)_time updateVisuals:(BOOL *)updateVisuals {

    time = _time;

    if ( bindHandler && event->evType == SE_KEY && event->evValue2 == 1 ) {
        NSString *ret = [bindHandler handleEvent:event updateVisuals:updateVisuals];
        bindHandler = nil;
        return ret;
    }

    if ( event->evType == SE_MOUSE || event->evType == SE_MOUSE_ABS ) {
        if ( !desktop || ([desktop getFlags] & WIN_MENUGUI) ) {
            // DG: this is a fullscreen GUI, scale the mousedelta added to cursorX/Y
            //     by 640/w, because the GUI pretends that everything is 640x480
            //     even if the actual resolution is higher => mouse moved too fast
            float w = self.manager.screenWidth;
            float h = self.manager.screenHeight;
            if( w <= 0.0f || h <= 0.0f ) {
                w = VIRTUAL_WIDTH;
                h = VIRTUAL_HEIGHT;
            }
            const float realW = w;
            const float realH = h;

            if( [self.manager.cvars getBool:@"r_scaleMenusTo43"] ) {
                // in case we're scaling menus to 4:3, we need to take that into account
                // when scaling the mouse events.
                // no, we can't just call uiManagerLocal.dc.GetFixScaleForMenu() or sth like that,
                // because when we're here dc.SetMenuScaleFix(YES) is not active and it'd just return (1, 1)!
                float aspectRatio = w/h;
                static const float virtualAspectRatio = (float)VIRTUAL_WIDTH/(float)VIRTUAL_HEIGHT; // 4:3
                if(aspectRatio > 1.4f) {
                    // widescreen (4:3 is 1.333 3:2 is 1.5, 16:10 is 1.6, 16:9 is 1.7778)
                    // => we need to modify cursorX scaling, by modifying w
                    w *= virtualAspectRatio/aspectRatio;
                } else if(aspectRatio < 1.24f) {
                    // portrait-mode, "thinner" than 5:4 (which is 1.25)
                    // => we need to scale cursorY via h
                    h *= aspectRatio/virtualAspectRatio;
                }
            }

            if( event->evType == SE_MOUSE ) {
                cursorX += event->evValue * ((float)VIRTUAL_WIDTH/w);
                cursorY += event->evValue2 * ((float)VIRTUAL_HEIGHT/h);
            } else { // SE_MOUSE_ABS
                // Note: In case of scaling to 4:3, w and h are already scaled down
                //       to the 4:3 size that fits into the real resolution.
                //       Otherwise xOffset/yOffset will just be 0
                float xOffset = (realW  - w) * 0.5f;
                float yOffset = (realH - h) * 0.5f;
                // offset the mouse coordinates into 4:3 area and scale down to 640x480
                // yes, result could be negative, doesn't matter, code below checks that anyway
                cursorX = (event->evValue  - xOffset) * ((float)VIRTUAL_WIDTH/w);
                cursorY = (event->evValue2 - yOffset) * ((float)VIRTUAL_HEIGHT/h);
            }
        } else {
            // not a fullscreen GUI but some ingame thing - no scaling needed
            cursorX += event->evValue;
            cursorY += event->evValue2;
        }

        if (cursorX < 0) {
            cursorX = 0;
        }
        if (cursorY < 0) {
            cursorY = 0;
        }
    }

    if ( desktop ) {
        return [desktop handleEvent:event updateVisuals:updateVisuals];
    }

    return @"";
}

/*
==============
idUserInterfaceLocal::HandleNamedEvent
==============
*/
- (void)handleNamedEvent:(NSString *)eventName {
    [desktop runNamedEvent:eventName];
}

/*
==============
idUserInterfaceLocal::Redraw
==============
*/
- (void)redraw:(int)_time {
    if ( [self.manager.cvars getInt:@"r_skipGuiShaders"] > 5 ) {
        return;
    }
    if ( !loading && desktop ) {
        time = _time;
        [self.manager.dc pushClipRect:self.manager.screenRect];
        [desktop redraw:0 y:0];
        [self.manager.dc popClipRect];
    }
}

- (void)runTimeEvents:(int)_time {
    int r_skipGuiShaders = [self.manager.cvars getInt:@"r_skipGuiShaders"];
    if ( r_skipGuiShaders > 5 ) {
        return;
    }
    if ( !loading && desktop ) {
        time = _time;
        // idWindow::Redraw's, before it draws
        if ( r_skipGuiShaders == 1 || [desktop getDC] == nil ) {
            return;
        }
        if ( [desktop getFlags] & WIN_DESKTOP && r_skipGuiShaders != 3 ) {
            [desktop runTimeEvents:time];
        }
    }
}

/*
==============
idUserInterfaceLocal::DrawCursor
==============
*/
- (void)drawCursor {
    if ( !desktop || [desktop getFlags] & WIN_MENUGUI ) {
        [self.manager.dc drawCursor:&cursorX y:&cursorY size:32.0f];
    } else {
        [self.manager.dc drawCursor:&cursorX y:&cursorY size:64.0f];
    }
}

- (idDict *)state {
    return state;
}

- (void)deleteStateVar:(NSString *)varName {
    [state deleteKey:varName];
}

- (void)setStateString:(NSString *)varName value:(NSString *)value {
    [state set:varName value:value];
}

- (void)setStateBool:(NSString *)varName value:(BOOL)value {
    [state setBool:varName value:value];
}

- (void)setStateInt:(NSString *)varName value:(int)value {
    [state setInt:varName value:value];
}

- (void)setStateFloat:(NSString *)varName value:(float)value {
    [state setFloat:varName value:value];
}

- (NSString *)getStateString:(NSString *)varName defaultString:(NSString *)defaultString {
    return [state getString:varName defaultString:defaultString];
}

- (BOOL)getStateBool:(NSString *)varName defaultString:(NSString *)defaultString {
    return [state getBool:varName defaultString:defaultString];
}

- (int)getStateInt:(NSString *)varName defaultString:(NSString *)defaultString {
    return atoi( [state getString:varName defaultString:defaultString].UTF8String );
}

- (float)getStateFloat:(NSString *)varName defaultString:(NSString *)defaultString {
    return atof( [state getString:varName defaultString:defaultString].UTF8String );
}

/*
==============
idUserInterfaceLocal::StateChanged
==============
*/
- (void)stateChanged:(int)_time redraw:(BOOL)redraw {
    time = _time;
    if (desktop) {
        // DG: little hack: allow game DLLs to do
        //     ui->SetStateBool("scaleto43", YES);
        //     ui->StateChanged(gameLocal.time);
        //     so we can force cursors.gui (crosshair) to be scaled, for example
        BOOL scaleTo43 = NO;
        if([state getBool:@"scaleto43" defaultString:@"0" out:&scaleTo43]) {
            if(scaleTo43)
                [desktop setFlag:WIN_SCALETO43];
            else
                [desktop clearFlag:WIN_SCALETO43];
        }
        // DG end

        [desktop stateChanged:redraw];
    }
    if ( [state getBool:@"noninteractive"] ) {
        interactive = NO;
    }
    else {
        if (desktop) {
            interactive = [desktop interactive];
        } else {
            interactive = NO;
        }
    }
}

/*
==============
idUserInterfaceLocal::Activate
==============
*/
- (NSString *)activate:(BOOL)activate time:(int)_time {
    time = _time;
    active = activate;
    if ( desktop ) {
        [activateStr setString:@""];
        [desktop activate:activate act:activateStr];
        return [activateStr copy];
    }
    return @"";
}

/*
==============
idUserInterfaceLocal::Trigger
==============
*/
- (void)trigger:(int)_time {
    time = _time;
    if ( desktop ) {
        [desktop trigger];
    }
}

/*
==============
idUserInterfaceLocal::RecurseSetKeyBindingNames
==============
*/
- (void)recurseSetKeyBindingNames:(idWindow *)window {
    int i;
    idWinVar *v = [window getWinVarByName:@"bind"];
    if ( v ) {
        // idKeyInput::KeysFromBinding: no keys are bound here
        [self setStateString:[v getName] value:@""];
    }
    i = 0;
    while ( i < [window getChildCount] ) {
        idWindow *next = [window getChild:i];
        if ( next ) {
            [self recurseSetKeyBindingNames:next];
        }
        i++;
    }
}

/*
==============
idUserInterfaceLocal::SetKeyBindingNames
==============
*/
- (void)setKeyBindingNames {
    if ( !desktop ) {
        return;
    }
    // walk the windows
    [self recurseSetKeyBindingNames:desktop];
}

- (BOOL)isUniqued { return uniqued; }
- (void)setUniqued:(BOOL)b { uniqued = b; }

/*
==============
idUserInterfaceLocal::SetCursor
==============
*/
- (void)setCursor:(float)x y:(float)y {
    cursorX = x;
    cursorY = y;
}

- (float)cursorX { return cursorX; }
- (float)cursorY { return cursorY; }

- (idDict *)getStateDict { return state; }
- (NSString *)getSourceFile { return source; }
- (idWindow *)getDesktop { return desktop; }
- (void)setBindHandler:(idWindow *)win { bindHandler = win; }
- (BOOL)active { return active; }
- (int)getTime { return time; }
- (void)setTime:(int)_time { time = _time; }
- (void)clearRefs { refs = 0; }
- (void)addRef { refs++; }
- (int)getRefs { return refs; }
- (NSMutableString *)getPendingCmd { return pendingCmd; }
- (NSMutableString *)getReturnCmd { return returnCmd; }


#pragma mark - The name index (not the engine's)

- (void)fixupParmsOf:(idWindow *)window {
    _nameIndexes = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
                                         valueOptions:NSPointerFunctionsStrongMemory];
    [window fixupParms];
    _nameIndexes = nil;
}

- (nullable NSDictionary<NSString *, idDrawWin *> *)nameIndexOf:(idWindow *)window {
    NSMapTable *indexes = _nameIndexes;
    if (indexes == nil) return nil;
    NSMutableDictionary<NSString *, idDrawWin *> *index = [indexes objectForKey:window];
    if (index == nil) {
        index = [NSMutableDictionary dictionary];
        idDrawWin *dw = [[idDrawWin alloc] init];
        dw.win = window;
        index[[[window getName] ud_foldedAZ]] = dw;
        UDIndexChildren(window, index);
        [indexes setObject:index forKey:window];
    }
    return index;
}

/// @a window's draw windows, by name, in FindChildByName's order: each
/// one's name, then (a full window) its own; the first of a name kept.
static void UDIndexChildren(idWindow *window, NSMutableDictionary<NSString *, idDrawWin *> *index) {
    for (idDrawWin *dw in window->drawWindows) {
        NSString *key = [(dw.win != nil ? [dw.win getName] : dw.simp->name) ud_foldedAZ];
        if (key != nil && index[key] == nil) {
            index[key] = dw;
        }
        if (dw.win != nil) {
            UDIndexChildren(dw.win, index);
        }
    }
}

@end
