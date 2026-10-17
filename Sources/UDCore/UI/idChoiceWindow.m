/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idChoiceWindow.m — ui/ChoiceWindow.cpp, ported; and the video modes it
 * injects (renderer/RenderSystem_init.cpp's r_vidModes and their lists).
 */

#import "idChoiceWindow.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "UDDeclCodec.h"
#import "idDeviceContext.h"
#import "idCVarSystem.h"
#import "idDict.h"
#import "idParser.h"
#import "idLexer.h"
#import "idToken.h"
#include <ctype.h>

#pragma mark - r_vidModes (renderer/RenderSystem_init.cpp)

typedef struct vidmode_s {
    const char *description;
    int         width, height;
} vidmode_t;

static vidmode_t r_vidModes[] = {
    { "Mode  0: 320x240",       320,    240 },
    { "Mode  1: 400x300",       400,    300 },
    { "Mode  2: 512x384",       512,    384 },
    { "Mode  3: 640x480",       640,    480 },
    { "Mode  4: 800x600",       800,    600 },
    { "Mode  5: 1024x768",      1024,   768 },
    { "Mode  6: 1152x864",      1152,   864 },
    { "Mode  7: 1280x1024",     1280,   1024 },
    { "Mode  8: 1600x1200",     1600,   1200 },
    // DG: from here on: modes I added.
    { "Mode  9: 1280x720",      1280,   720 },
    { "Mode 10: 1366x768",      1366,   768 },
    { "Mode 11: 1440x900",      1440,   900 },
    { "Mode 12: 1400x1050",     1400,   1050 },
    { "Mode 13: 1600x900",      1600,   900 },
    { "Mode 14: 1680x1050",     1680,   1050 },
    { "Mode 15: 1920x1080",     1920,   1080 },
    { "Mode 16: 1920x1200",     1920,   1200 },
    { "Mode 17: 2048x1152",     2048,   1152 },
    { "Mode 18: 2560x1600",     2560,   1600 },
    { "Mode 19: 3200x2400",     3200,   2400 },
    { "Mode 20: 3840x2160",     3840,   2160 },
    { "Mode 21: 4096x2304",     4096,   2304 },
    { "Mode 22: 2880x1800",     2880,   1800 },
    { "Mode 23: 2560x1440",     2560,   1440 },
    { "Mode 24: 1440x1080",     1440,   1080 },
    { "Mode 25: 1280x800",      1280,   800 },
    // 21:9 resolutions
    { "Mode 26: 2560x1080",     2560,   1080 },
    { "Mode 27: 3440x1440",     3440,   1440 },
    { "Mode 28: 3840x1600",     3840,   1600 },
    { "Mode 29: 5120x2160",     5120,   2160 },
    // 32:9 resolutions
    { "Mode 30: 3840x1080",     3840,   1080 },
    { "Mode 31: 5120x1440",     5120,   1440 },
    { "Mode 32: 7680x2160",     7680,   2160 },
};
// DG: made this an enum so even stupid compilers accept it as array length below
enum {  s_numVidModes = sizeof( r_vidModes ) / sizeof( r_vidModes[0] ) };

struct vidModePtr {
    vidmode_t* vidMode;
    int modeIndex;
};

static struct vidModePtr sortedVidModes[s_numVidModes];

static int vidModeCmp(const void* vm1, const void* vm2)
{
    const struct vidModePtr* v1 = (const struct vidModePtr*)vm1;
    const struct vidModePtr* v2 = (const struct vidModePtr*)vm2;

    // sort primarily by width, secondarily by height
    int wdiff = v1->vidMode->width - v2->vidMode->width;
    return (wdiff != 0) ? wdiff : (v1->vidMode->height - v2->vidMode->height);
}

static void initSortedVidModes(void)
{
    if(sortedVidModes[0].vidMode != NULL)
    {
        // already initialized
        return;
    }

    for(int i=0; i<s_numVidModes; ++i)
    {
        sortedVidModes[i].modeIndex = i;
        sortedVidModes[i].vidMode = &r_vidModes[i];
    }

    qsort(sortedVidModes, s_numVidModes, sizeof(struct vidModePtr), vidModeCmp);
}

// DG: the following two functions are part of a horrible hack in ChoiceWindow.cpp
//     to overwrite the default resolution list in the system options menu

// "r_custom*;640x480;800x600;1024x768;..."
NSString *R_GetVidModeListString(BOOL addCustom)
{
    initSortedVidModes();
    NSMutableString *ret = [NSMutableString stringWithString:addCustom ? @"r_custom*" : @""];

    for(int i=0; i<s_numVidModes; ++i)
    {
        // for some reason, modes 0-2 are not used. maybe too small for GUI?
        if(sortedVidModes[i].modeIndex >= 3 && sortedVidModes[i].vidMode != NULL)
        {
            [ret appendFormat:@";%dx%d", sortedVidModes[i].vidMode->width, sortedVidModes[i].vidMode->height];
        }
    }
    return ret;
}

// r_mode values for resolutions from R_GetVidModeListString(): "-1;3;4;5;..."
NSString *R_GetVidModeValsString(BOOL addCustom)
{
    initSortedVidModes();
    NSMutableString *ret = [NSMutableString stringWithString:addCustom ? @"-1" : @""]; // for custom resolutions using r_customWidth/r_customHeight
    for(int i=0; i<s_numVidModes; ++i)
    {
        // for some reason, modes 0-2 are not used. maybe too small for GUI?
        if(sortedVidModes[i].modeIndex >= 3 && sortedVidModes[i].vidMode != NULL)
        {
            [ret appendString:@";"];
            [ret appendFormat:@"%d", sortedVidModes[i].modeIndex];
        }
    }
    return ret;
}
// DG end


@implementation idChoiceWindow

/*
============
idChoiceWindow::InitVars
============
*/
- (void)initVars {
    if ( [cvarStr length] ) {
        cvar = [[gui manager].cvars find:[cvarStr string]];
        if ( !cvar ) {
            if (![[cvarStr string] isEqualToString:@"s_driver"] && ![[cvarStr string] isEqualToString:@"net_serverAllowServerMod"])
                [[gui manager] uiWarning:[NSString stringWithFormat:@"idChoiceWindow::InitVars: gui '%@' window '%@' references undefined cvar '%@'", [gui getSourceFile], name, [cvarStr string]]];
            return;
        }
        [updateStr.list addObject:cvarStr];
    }
    if ( [guiStr length] ) {
        [updateStr.list addObject:guiStr];
    }
    [updateStr setGuiInfo:[gui getStateDict]];
    [updateStr update];
}

/*
============
idChoiceWindow::CommonInit
============
*/
- (void)choiceCommonInit {
    currentChoice = 0;
    choiceType = 0;
    cvar = nil;
    [liveUpdate setData:YES];
    [choices removeAllObjects];
}

- (void)constructChoiceMembers {
    latchedChoices = @"";
    choicesStr = [[idWinStr alloc] init];
    latchedVals = @"";
    choiceVals = [[idWinStr alloc] init];
    choices = [NSMutableArray array];
    values = [NSMutableArray array];
    guiStr = [[idWinStr alloc] init];
    cvarStr = [[idWinStr alloc] init];
    updateStr = [[idMultiWinVar alloc] init];
    liveUpdate = [[idWinBool alloc] init];
    updateGroup = [[idWinStr alloc] init];
}

- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)g {
    self = [super initWithDC:d gui:g];
    if (self) {
        [self constructChoiceMembers];
        dc = d;
        gui = g;
        [self choiceCommonInit];
    }
    return self;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)g {
    self = [super initWithGui:g];
    if (self) {
        [self constructChoiceMembers];
        gui = g;
        [self choiceCommonInit];
    }
    return self;
}

- (void)runNamedEvent:(NSString *)eventName {
    if ( ![eventName ud_cmpn:@"cvar read " length:10] ) {
        NSString *group = [eventName substringFromIndex:10];
        if ( [group isEqualToString:[updateGroup string]] ) {
            [self updateVars:YES force:YES];
        }
    } else if ( ![eventName ud_cmpn:@"cvar write " length:11] ) {
        NSString *group = [eventName substringFromIndex:11];
        if ( [group isEqualToString:[updateGroup string]] ) {
            [self updateVars:NO force:YES];
        }
    }
}

- (void)updateVars:(BOOL)read force:(BOOL)force {
    if ( force || liveUpdate.data ) {
        if ( cvar && [cvarStr needsUpdate] ) {
            if ( read ) {
                [cvarStr set:[cvar getString]];
            } else {
                [cvar setString:[cvarStr string]];
            }
        }
        if ( !read && [guiStr needsUpdate] ) {
            [guiStr set:[NSString stringWithFormat:@"%i", currentChoice]];
        }
    }
}

- (NSString *)handleEvent:(const sysEvent_t *)event updateVisuals:(BOOL *)updateVisuals {
    int key;
    BOOL runAction = NO;
    BOOL runAction2 = NO;

    if ( event->evType == SE_KEY ) {
        key = event->evValue;

        if ( key == K_RIGHTARROW || key == K_KP_RIGHTARROW || key == K_MOUSE1)  {
            // never affects the state, but we want to execute script handlers anyway
            if ( !event->evValue2 ) {
                [self runScript:ON_ACTIONRELEASE];
                return [cmd copy];
            }
            currentChoice++;
            if (currentChoice >= (int)choices.count) {
                currentChoice = 0;
            }
            runAction = YES;
        }

        if ( key == K_LEFTARROW || key == K_KP_LEFTARROW || key == K_MOUSE2) {
            // never affects the state, but we want to execute script handlers anyway
            if ( !event->evValue2 ) {
                [self runScript:ON_ACTIONRELEASE];
                return [cmd copy];
            }
            currentChoice--;
            if (currentChoice < 0) {
                currentChoice = (int)choices.count - 1;
            }
            runAction = YES;
        }

        if ( !event->evValue2 ) {
            // is a key release with no action catch
            return @"";
        }

    } else if ( event->evType == SE_CHAR ) {

        key = event->evValue;

        int potentialChoice = -1;
        for ( int i = 0; i < (int)choices.count; i++ ) {
            if ( choices[i].length && toupper(key) == toupper([choices[i] characterAtIndex:0]) ) {
                if ( i < currentChoice && potentialChoice < 0 ) {
                    potentialChoice = i;
                } else if ( i > currentChoice ) {
                    potentialChoice = -1;
                    currentChoice = i;
                    break;
                }
            }
        }
        if ( potentialChoice >= 0 ) {
            currentChoice = potentialChoice;
        }

        runAction = YES;
        runAction2 = YES;

    } else {
        return @"";
    }

    if ( runAction ) {
        [self runScript:ON_ACTION];
    }

    if ( choiceType == 0 ) {
        [cvarStr set:[NSString stringWithFormat:@"%i", currentChoice]];
    } else if ( values.count ) {
        [cvarStr set:values[ currentChoice ]];
    } else {
        [cvarStr set:choices[ currentChoice ]];
    }

    [self updateVars:NO force:NO];

    if ( runAction2 ) {
        [self runScript:ON_ACTIONRELEASE];
    }

    return [cmd copy];
}


- (void)validateChoice {
    if ( currentChoice < 0 || currentChoice >= (int)choices.count ) {
        currentChoice = 0;
    }
    if ( choices.count == 0 ) {
        [choices addObject:@"No Choices Defined"];
    }
}

- (void)updateChoice {
    if ( !updateStr.list.count ) {
        return;
    }
    [self updateVars:YES force:NO];
    [updateStr update];
    if ( choiceType == 0 ) {
        // ChoiceType 0 stores current as an integer in either cvar or gui
        // If both cvar and gui are defined then cvar wins, but they are both updated
        if ( [updateStr.list[ 0 ] needsUpdate] ) {
            currentChoice = atoi( [updateStr.list[ 0 ] string].UTF8String );
        }
        [self validateChoice];
    } else {
        // ChoiceType 1 stores current as a cvar string
        int c = ( values.count ) ? (int)values.count : (int)choices.count;
        int i;
        for ( i = 0; i < c; i++ ) {
            if ( [[cvarStr string] ud_iequals:( values.count ) ? values[i] : choices[i]] ) {
                break;
            }
        }
        if (i == c) {
            i = 0;
        }
        currentChoice = i;
        [self validateChoice];
    }
}

- (BOOL)parseInternalVar:(NSString *)_name parser:(idParser *)src {
    if ([_name ud_iequals:@"choicetype"]) {
        int i = 0;
        [src parseInt:&i error:NULL];
        choiceType = i;
        return YES;
    }
    if ([_name ud_iequals:@"currentchoice"]) {
        int i = 0;
        [src parseInt:&i error:NULL];
        currentChoice = i;
        return YES;
    }
    return [super parseInternalVar:_name parser:src];
}


- (idWinVar *)getWinVarByName:(NSString *)_name fixup:(BOOL)fixup owner:(idDrawWin **)owner {
    if ( [_name ud_iequals:@"choices"] ) {
        return choicesStr;
    }
    if ( [_name ud_iequals:@"values"] ) {
        return choiceVals;
    }
    if ( [_name ud_iequals:@"cvar"] ) {
        return cvarStr;
    }
    if ( [_name ud_iequals:@"gui"] ) {
        return guiStr;
    }
    if ( [_name ud_iequals:@"liveUpdate"] ) {
        return liveUpdate;
    }
    if ( [_name ud_iequals:@"updateGroup"] ) {
        return updateGroup;
    }

    return [super getWinVarByName:_name fixup:fixup owner:owner];
}

// update the lists whenever the WinVar have changed
- (void)updateChoicesAndVals {
    idToken token;
    idToken_Init( &token );
    NSMutableString *str2 = [NSMutableString string];
    idFileSystem *fileSystem = [gui manager].fileSystem;

    if ( ![latchedChoices ud_iequals:[choicesStr string]] ) {
        [choices removeAllObjects];
        idLexer *src = [[idLexer alloc] initWithFlags:LEXFL_NOFATALERRORS | LEXFL_ALLOWPATHNAMES | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                           fileSystem:fileSystem];
        NSData *bytes __attribute__((objc_precise_lifetime)) = [[choicesStr string] ud_latin1Buffer];
        [src loadMemory:bytes.bytes length:(int)bytes.length - 1 name:@"<ChoiceList>" startLine:1 error:NULL];
        if ( [src isLoaded] ) {
            while( [src readToken:&token error:NULL] ) {
                if ( UDTokenIs( &token, ";" ) ) {
                    if ( str2.length ) {
                        [str2 setString:[str2 ud_stringByStrippingTrailingWhitespace]];
                        [str2 setString:[[gui manager].languageDict getString:[str2 copy]]];
                        [choices addObject:[str2 copy]];
                        [str2 setString:@""];
                    }
                    continue;
                }
                [str2 appendString:UDTokenLatin1String( &token )];
                [str2 appendString:@" "];
            }
            if ( str2.length ) {
                [str2 setString:[str2 ud_stringByStrippingTrailingWhitespace]];
                [choices addObject:[str2 copy]];
            }
        }
        latchedChoices = [choicesStr string];
    }
    if ( [choiceVals length] && ![latchedVals ud_iequals:[choiceVals string]] ) {
        [values removeAllObjects];
        idLexer *src = [[idLexer alloc] initWithFlags:LEXFL_ALLOWPATHNAMES | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                           fileSystem:fileSystem];
        NSData *bytes __attribute__((objc_precise_lifetime)) = [[choiceVals string] ud_latin1Buffer];
        [src loadMemory:bytes.bytes length:(int)bytes.length - 1 name:@"<ChoiceVals>" startLine:1 error:NULL];
        [str2 setString:@""];
        BOOL negNum = NO;
        if ( [src isLoaded] ) {
            while( [src readToken:&token error:NULL] ) {
                if (UDTokenIs( &token, "-" )) {
                    negNum = YES;
                    continue;
                }
                if (UDTokenIs( &token, ";" )) {
                    if (str2.length) {
                        [str2 setString:[str2 ud_stringByStrippingTrailingWhitespace]];
                        [values addObject:[str2 copy]];
                        [str2 setString:@""];
                    }
                    continue;
                }
                if ( negNum ) {
                    [str2 appendString:@"-"];
                    negNum = NO;
                }
                [str2 appendString:UDTokenLatin1String( &token )];
                [str2 appendString:@" "];
            }
            if ( str2.length ) {
                [str2 setString:[str2 ud_stringByStrippingTrailingWhitespace]];
                [values addObject:[str2 copy]];
            }
        }
        if ( choices.count != values.count ) {
            [[gui manager] uiWarning:[NSString stringWithFormat:@"idChoiceWindow:: gui '%@' window '%@' has value count unequal to choices count", [gui getSourceFile], name]];
        }
        latchedVals = [choiceVals string];
    }
}

- (void)postParse {
    [super postParse];

    // DG: HACKHACKFUCKINGUGLYHACK: overwrite resolution list
    //     to support more resolutions and widescreen and stuff.
    BOOL injectResolutions = NO;
    BOOL injectCustomMode = YES;

    /*
     * Mods that have their own video settings menu can tell dhewm3 to replace the
     * "choices" and "values" entries in their choiceDef with the resolutions supported by
     * dhewm3 (and corresponding modes). So if we add new video modes to dhewm3,
     * they'll automatically appear in the menu without changing the .gui
     * To enable this, the mod authors only need to add an "injectResolutions 1" entry
     * to their resolution choiceDef. By default, the first entry will be "r_custom*"
     * for r_mode -1, which means "custom resolution, use r_customWidth and r_customHeight".
     * If that entry shoud be disabled for the mod, just add another entry:
     * "injectCustomResolutionMode 0"
     */
    idWinVar* wv = [self getWinVarByName:@"injectResolutions"];
    if(wv != nil) {
        NSString *val = [wv string];
        if(val.length && ![val isEqualToString:@"0"]) {
            injectResolutions = YES;
            wv = [self getWinVarByName:@"injectCustomResolutionMode"];
            if(wv != nil) {
                NSString *val2 = [wv string];
                if(val2.length && [val2 isEqualToString:@"0"]) {
                    injectCustomMode = NO;
                }
            }
        }
    }
    else if( [[self getName] isEqualToString:@"OS2Primary"] && [[cvarStr data] isEqualToString:@"r_mode"]
             && ( [[[self getGui] getSourceFile] ud_iequals:@"guis/demo_mainmenu.gui"] ||
                  [[[self getGui] getSourceFile] ud_iequals:@"guis/mainmenu.gui"] ) )
    {
        // always enable this for base/ and d3xp/ mainmenu.gui (like we did before)
        injectResolutions = YES;
    }

    if(injectResolutions) {
        [choicesStr set:R_GetVidModeListString(injectCustomMode)];
        [choiceVals set:R_GetVidModeValsString(injectCustomMode)];
    }
    // DG end

    [self updateChoicesAndVals];

    [self initVars];
    [self updateChoice];
    [self updateVars:NO force:NO];

    flags |= WIN_CANFOCUS;
}

- (void)draw:(int)time x:(float)x y:(float)y {
    idVec4 color = foreColor.data;

    [self updateChoicesAndVals];
    [self updateChoice];

    // FIXME: It'd be really cool if textAlign worked, but a lot of the guis have it set wrong because it used to not work
    textAlign = 0;

    // (the engine reads past an empty list here)
    if ( textShadow && currentChoice >= 0 && currentChoice < (int)choices.count ) {
        NSString *shadowText = [choices[currentChoice] ud_stringByRemovingColors];
        idRectangle shadowRect = textRect;

        shadowRect.x += textShadow;
        shadowRect.y += textShadow;

        [dc drawText:shadowText textScale:textScale.data textAlign:textAlign color:idDeviceContext_colorBlack rectDraw:shadowRect wrap:NO cursor:-1];
        }

    if ( hover && !noEvents.data && [self contains:[gui cursorX] y:[gui cursorY]] ) {
        color = hoverColor.data;
    } else {
        hover = NO;
    }
    if ( flags & WIN_FOCUS ) {
        color = hoverColor.data;
    }

    if(choices.count > 0 && currentChoice >= 0 && currentChoice < (int)choices.count) {
        [dc drawText:choices[currentChoice] textScale:textScale.data textAlign:textAlign color:color rectDraw:textRect wrap:NO cursor:-1];
    }
}

- (void)activate:(BOOL)activate act:(NSMutableString *)act {
    [super activate:activate act:act];
    if ( activate ) {
        // sets the gui state based on the current choice the window contains
        [self updateChoice];
    }
}

@end
