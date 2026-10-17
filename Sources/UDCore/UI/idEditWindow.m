/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idEditWindow.m — ui/EditWindow.cpp, ported. See idEditWindow.h.
 */

#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "idEditWindow.h"
#import "idSliderWindow.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "UDDeclCodec.h"
#import "idDeviceContext.h"
#import "idCVarSystem.h"
#import "idDict.h"
#import "idParser.h"

/// Sys_GetConsoleKey (sys/events.cpp): in_kbd "auto" on a US layout, the
/// key of SDL_SCANCODE_GRAVE, and no shifted key.
static unsigned char Sys_GetConsoleKey( BOOL shifted ) {
    return shifted ? 0 : '`';
}

@implementation idEditWindow

- (BOOL)parseInternalVar:(NSString *)_name parser:(idParser *)src {
    if ( [_name ud_iequals:@"maxchars"]) {
        int i = 0;
        [src parseInt:&i error:NULL];
        maxChars = i;
        return YES;
    }
    if ( [_name ud_iequals:@"numeric"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        numeric = b;
        return YES;
    }
    if ( [_name ud_iequals:@"wrap"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        wrap = b;
        return YES;
    }
    if ( [_name ud_iequals:@"readonly"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        readonly = b;
        return YES;
    }
    if ( [_name ud_iequals:@"forceScroll"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        forceScroll = b;
        return YES;
    }
    if ( [_name ud_iequals:@"source"]) {
        sourceFile = [self parseString:src] ?: sourceFile;
        return YES;
    }
    if ( [_name ud_iequals:@"password"] ) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        [password setData:b];
        return YES;
    }
    if ( [_name ud_iequals:@"cvarMax"]) {
        int i = 0;
        [src parseInt:&i error:NULL];
        cvarMax = i;
        return YES;
    }

    return [super parseInternalVar:_name parser:src];
}

- (idWinVar *)getWinVarByName:(NSString *)_name fixup:(BOOL)fixup owner:(idDrawWin **)owner {
    if ( [_name ud_iequals:@"cvar"] ) {
        return cvarStr;
    }
    if ( [_name ud_iequals:@"password"] ) {
        return password;
    }
    if ( [_name ud_iequals:@"liveUpdate"] ) {
        return liveUpdate;
    }
    if ( [_name ud_iequals:@"cvarGroup"] ) {
        return cvarGroup;
    }
    return [super getWinVarByName:_name fixup:fixup owner:owner];
}

- (void)editCommonInit {
    maxChars = 128;
    numeric = NO;
    paintOffset = 0;
    cursorPos = 0;
    cursorLine = 0;
    cvarMax = 0;
    wrap = NO;
    sourceFile = @"";
    scroller = nil;
    sizeBias = 0;
    lastTextLength = 0;
    forceScroll = NO;
    [password setData:NO];
    cvar = nil;
    [liveUpdate setData:YES];
    readonly = NO;

    scroller = [[idSliderWindow alloc] initWithDC:dc gui:gui];
}

- (void)constructEditMembers {
    breaks = [NSMutableArray array];
    password = [[idWinBool alloc] init];
    cvarStr = [[idWinStr alloc] init];
    liveUpdate = [[idWinBool alloc] init];
    cvarGroup = [[idWinStr alloc] init];
}

- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)g {
    self = [super initWithDC:d gui:g];
    if (self) {
        [self constructEditMembers];
        dc = d;
        gui = g;
        [self editCommonInit];
    }
    return self;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)g {
    self = [super initWithGui:g];
    if (self) {
        [self constructEditMembers];
        gui = g;
        [self editCommonInit];
    }
    return self;
}


- (void)gainFocus {
    cursorPos = (int)[text length];
    [self ensureCursorVisible];
}

- (void)draw:(int)time x:(float)x y:(float)y {
    idVec4 color = foreColor.data;

    [self updateCvar:YES force:NO];

    int len = (int)[text length];
    if ( len != lastTextLength ) {
        [scroller setValue:0.0f];
        [self ensureCursorVisible];
        lastTextLength = len;
    }
    float scale = textScale.data;

    NSString *buffer;
    if ( password.data ) {
        buffer = [@"" stringByPaddingToLength:[text data].length withString:@"*" startingAtIndex:0];
    } else {
        buffer = [text data];
    }

    if ( cursorPos > len ) {
        cursorPos = len;
    }

    idRectangle drawRectangle = textRect;

    drawRectangle.x -= paintOffset;
    drawRectangle.w += paintOffset;

    if ( wrap && [scroller getHigh] > 0.0f ) {
        float lineHeight = [self getMaxCharHeight] + 5;
        drawRectangle.y -= [scroller getValue] * lineHeight;
        drawRectangle.w -= sizeBias;
        drawRectangle.h = ( breaks.count + 1 ) * lineHeight;
    }

    if ( hover && !noEvents.data && [self contains:[gui cursorX] y:[gui cursorY]] ) {
        color = hoverColor.data;
    } else {
        hover = NO;
    }
    if ( flags & WIN_FOCUS ) {
        color = hoverColor.data;
    }

    [dc drawText:buffer textScale:scale textAlign:0 color:color rectDraw:drawRectangle wrap:wrap cursor:(flags & WIN_FOCUS) ? cursorPos : -1];
}

/*
=============
idEditWindow::HandleEvent
=============
*/
- (NSString *)handleEvent:(const sysEvent_t *)event updateVisuals:(BOOL *)updateVisuals {
    NSString *ret = @"";
    idUserInterfaceManager *manager = [gui manager];

    if ( wrap ) {
        // need to call this to allow proper focus and capturing on embedded children
        ret = [super handleEvent:event updateVisuals:updateVisuals];
        if ( ret.length ) {
            return ret;
        }
    }

    if ( ( event->evType != SE_CHAR && event->evType != SE_KEY ) ) {
        return ret;
    }

    // idStr::Copynz( buffer, text.c_str(), MAX_EDITFIELD )
    NSMutableString *buffer = [[text string] mutableCopy];
    if ( buffer.length > MAX_EDITFIELD - 1 ) {
        [buffer deleteCharactersInRange:NSMakeRange( MAX_EDITFIELD - 1, buffer.length - ( MAX_EDITFIELD - 1 ) )];
    }
    int key = event->evValue;
    int len = (int)[text length];

    if ( event->evType == SE_CHAR ) {
        if ( event->evValue == Sys_GetConsoleKey( [manager isKeyDown:K_SHIFT] ) ) {
            return @"";
        }

        if ( updateVisuals ) {
            *updateVisuals = YES;
        }

        if ( maxChars && len > maxChars ) {
            len = maxChars;
        }

        if ( ( key == K_ENTER || key == K_KP_ENTER ) && event->evValue2 ) {
            [self runScript:ON_ACTION];
            [self runScript:ON_ENTER];
            return [cmd copy];
        }

        if ( key == K_ESCAPE ) {
            [self runScript:ON_ESC];
            return [cmd copy];
        }

        if ( readonly ) {
            return @"";
        }

        if ( key == 'h' - 'a' + 1 || key == K_BACKSPACE ) {   // ctrl-h is backspace
            if ( cursorPos > 0 ) {
                if ( cursorPos >= len ) {
                    // buffer[len - 1] = 0
                    [buffer deleteCharactersInRange:NSMakeRange( len - 1, buffer.length - ( len - 1 ) )];
                    cursorPos = len - 1;
                } else {
                    // memmove( &buffer[ cursorPos - 1 ], &buffer[ cursorPos ], len + 1 - cursorPos )
                    [buffer deleteCharactersInRange:NSMakeRange( cursorPos - 1, 1 )];
                    cursorPos--;
                }

                [text setData:buffer];
                [self updateCvar:NO force:NO];
                [self runScript:ON_ACTION];
            }

            return @"";
        }

        //
        // ignore any non printable chars (except enter when wrap is enabled)
        //
        if ( wrap && (key == K_ENTER || key == K_KP_ENTER) ) {
        } else if ( !idStr_CharIsPrintable( key ) ) {
            return @"";
        }

        if ( numeric ) {
            if ( ( key < '0' || key > '9' ) && key != '.' ) {
                return @"";
            }
        }

        unichar character = (unichar)key;
        NSString *keyString = [NSString stringWithCharacters:&character length:1];
        if ( [dc getOverStrike] ) {
            if ( maxChars && cursorPos >= maxChars ) {
                return @"";
            }
            // buffer[ cursorPos ] = key
            if ( cursorPos < (int)buffer.length ) {
                [buffer replaceCharactersInRange:NSMakeRange( cursorPos, 1 ) withString:keyString];
            } else {
                [buffer appendString:keyString];
            }
        } else {
            if ( ( len == MAX_EDITFIELD - 1 ) || ( maxChars && len >= maxChars ) ) {
                return @"";
            }
            [buffer insertString:keyString atIndex:MIN( (NSUInteger)cursorPos, buffer.length )];
        }

        [text setData:buffer];
        [self updateCvar:NO force:NO];
        [self runScript:ON_ACTION];

        if ( cursorPos < len + 1 ) {
            cursorPos++;
        }
        [self ensureCursorVisible];

    } else if ( event->evType == SE_KEY && event->evValue2 ) {

        if ( updateVisuals ) {
            *updateVisuals = YES;
        }

        if ( key == K_DEL ) {
            if ( readonly ) {
                return ret;
            }
            if ( cursorPos < len ) {
                // memmove( &buffer[cursorPos], &buffer[cursorPos + 1], len - cursorPos )
                [buffer deleteCharactersInRange:NSMakeRange( cursorPos, 1 )];
                [text setData:buffer];
                [self updateCvar:NO force:NO];
                [self runScript:ON_ACTION];
            }
            return ret;
        }

        if ( key == K_RIGHTARROW )  {
            if ( cursorPos < len ) {
                if ( [manager isKeyDown:K_CTRL] ) {
                    // skip to next word
                    while( ( cursorPos < len ) && ( [buffer characterAtIndex:cursorPos] != ' ' ) ) {
                        cursorPos++;
                    }

                    while( ( cursorPos < len ) && ( [buffer characterAtIndex:cursorPos] == ' ' ) ) {
                        cursorPos++;
                    }
                } else {
                    if ( cursorPos < len ) {
                        cursorPos++;
                    }
                }
            }

            [self ensureCursorVisible];

            return ret;
        }

        if ( key == K_LEFTARROW ) {
            if ( [manager isKeyDown:K_CTRL] ) {
                // skip to previous word
                while( ( cursorPos > 0 ) && ( [buffer characterAtIndex:cursorPos - 1] == ' ' ) ) {
                    cursorPos--;
                }

                while( ( cursorPos > 0 ) && ( [buffer characterAtIndex:cursorPos - 1] != ' ' ) ) {
                    cursorPos--;
                }
            } else {
                if ( cursorPos > 0 ) {
                    cursorPos--;
                }
            }

            [self ensureCursorVisible];

            return ret;
        }

        if ( key == K_HOME ) {
            if ( [manager isKeyDown:K_CTRL] || cursorLine <= 0 || ( cursorLine >= (int)breaks.count ) ) {
                cursorPos = 0;
            } else {
                cursorPos = breaks[cursorLine].intValue;
            }
            [self ensureCursorVisible];
            return ret;
        }

        if ( key == K_END )  {
            if ( [manager isKeyDown:K_CTRL] || (cursorLine < -1) || ( cursorLine >= (int)breaks.count - 1 ) ) {
                cursorPos = len;
            } else {
                cursorPos = breaks[cursorLine + 1].intValue - 1;
            }
            [self ensureCursorVisible];
            return ret;
        }

        if ( key == K_INS ) {
            if ( !readonly ) {
                [dc setOverStrike:![dc getOverStrike]];
            }
            return ret;
        }

        if ( key == K_DOWNARROW ) {
            if ( [manager isKeyDown:K_CTRL] ) {
                [scroller setValue:[scroller getValue] + 1.0f];
            } else {
                if ( cursorLine < (int)breaks.count - 1 ) {
                    int offset = cursorPos - breaks[cursorLine].intValue;
                    cursorPos = breaks[cursorLine + 1].intValue + offset;
                    [self ensureCursorVisible];
                }
            }
        }

        if (key == K_UPARROW ) {
            if ( [manager isKeyDown:K_CTRL] ) {
                [scroller setValue:[scroller getValue] - 1.0f];
            } else {
                if ( cursorLine > 0 ) {
                    int offset = cursorPos - breaks[cursorLine].intValue;
                    cursorPos = breaks[cursorLine - 1].intValue + offset;
                    [self ensureCursorVisible];
                }
            }
        }

        if ( key == K_ENTER || key == K_KP_ENTER ) {
            [self runScript:ON_ACTION];
            [self runScript:ON_ENTER];
            return [cmd copy];
        }

        if ( key == K_ESCAPE ) {
            [self runScript:ON_ESC];
            return [cmd copy];
        }

    } else if ( event->evType == SE_KEY && !event->evValue2 ) {
        if ( key == K_ENTER || key == K_KP_ENTER ) {
            [self runScript:ON_ENTERRELEASE];
            return [cmd copy];
        } else {
            [self runScript:ON_ACTIONRELEASE];
        }
    }

    return ret;
}

- (void)postParse {
    [super postParse];

    if ( maxChars == 0 ) {
        maxChars = 10;
    }
    if ( sourceFile.length ) {
        void *buffer = NULL;
        idFileSystem *fileSystem = [gui manager].fileSystem;
        if ( [fileSystem readFile:sourceFile buffer:&buffer timestamp:NULL error:NULL] >= 0 && buffer ) {
            [text setData:[NSString ud_stringWithLatin1:(char *) buffer]];
            [fileSystem freeFile:buffer error:NULL];
        } else {
            [text setData:@""];
        }
    }

    [self initCvar];
    [self initScroller:NO];

    [self ensureCursorVisible];

    flags |= WIN_CANFOCUS;
}

/*
================
idEditWindow::InitScroller

This is the same as in idListWindow
================
*/
- (void)initScroller:(BOOL)horizontal
{
    NSString *thumbImage = @"guis/assets/scrollbar_thumb.tga";
    NSString *barImage = @"guis/assets/scrollbarv.tga";
    NSString *scrollerName = @"_scrollerWinV";

    if (horizontal) {
        barImage = @"guis/assets/scrollbarh.tga";
        scrollerName = @"_scrollerWinH";
    }

    idMaterial *mat = [[gui manager] findMaterial:barImage];
    [mat setSort:SS_GUI];
    sizeBias = [mat getImageWidth];

    idRectangle scrollRect;
    if (horizontal) {
        sizeBias = [mat getImageHeight];
        scrollRect.x = 0;
        scrollRect.y = (clientRect.h - sizeBias);
        scrollRect.w = clientRect.w;
        scrollRect.h = sizeBias;
    } else {
        scrollRect.x = (clientRect.w - sizeBias);
        scrollRect.y = 0;
        scrollRect.w = sizeBias;
        scrollRect.h = clientRect.h;
    }

    [scroller initWithDefaults:scrollerName rect:scrollRect foreColor:foreColor.data matColor:matColor.data background:mat.name thumbShader:thumbImage vertical:!horizontal scrollbar:YES];
    [self insertChild:scroller before:nil];
    [scroller setBuddy:self];
}

- (void)handleBuddyUpdate:(idWindow *)buddy {
}

- (void)ensureCursorVisible
{
    if ( readonly ) {
        cursorPos = -1;
    } else if ( maxChars == 1 ) {
        cursorPos = 0;
    }

    if ( !dc ) {
        return;
    }

    [self setFont];
    if ( !wrap ) {
        int cursorX = 0;
        if ( password.data ) {
            cursorX = cursorPos * [dc charWidth:'*' scale:textScale.data];
        } else {
            int i = 0;
            NSString *t = [text data];
            while ( i < (int)[text length] && i < cursorPos ) {
                if ( [t ud_isColorAtIndex:i] ) {
                    i += 2;
                } else {
                    cursorX += [dc charWidth:[t characterAtIndex:i] scale:textScale.data];
                    i++;
                }
            }
        }
        int maxWidth = [self getMaxCharWidth];
        int left = cursorX - maxWidth;
        int right = ( cursorX - textRect.w ) + maxWidth;

        if ( paintOffset > left ) {
            // When we go past the left side, we want the text to jump 6 characters
            paintOffset = left - maxWidth * 6;
        }
        if ( paintOffset <  right) {
            paintOffset = right;
        }
        if ( paintOffset < 0 ) {
            paintOffset = 0;
        }
        [scroller setRange:0.0f high:0.0f step:1.0f];

    } else {
        // Word wrap

        [breaks removeAllObjects];
        idRectangle drawRectangle = textRect;
        drawRectangle.w -= sizeBias;
        [dc drawText:[text data] textScale:textScale.data textAlign:textAlign color:idDeviceContext_colorWhite rectDraw:drawRectangle wrap:YES cursor:(flags & WIN_FOCUS) ? cursorPos : -1 calcOnly:YES breaks:breaks limit:0];

        int fit = textRect.h / ([self getMaxCharHeight] + 5);
        if ( fit < (int)breaks.count + 1 ) {
            [scroller setRange:0 high:breaks.count + 1 - fit step:1];
        } else {
            // The text fits completely in the box
            [scroller setRange:0.0f high:0.0f step:1.0f];
        }

        if ( forceScroll ) {
            [scroller setValue:(int)breaks.count - fit];
        } else if ( readonly ) {
        } else {
            cursorLine = 0;
            for ( int i = 1; i < (int)breaks.count; i++ ) {
                if ( cursorPos >= breaks[i].intValue ) {
                    cursorLine = i;
                } else {
                    break;
                }
            }
            int topLine = (int)( [scroller getValue] );
            if ( cursorLine < topLine ) {
                [scroller setValue:cursorLine];
            } else if ( cursorLine >= topLine + fit) {
                [scroller setValue:( cursorLine - fit ) + 1];
            }
        }
    }
}

- (void)activate:(BOOL)activate act:(NSMutableString *)act {
    [super activate:activate act:act];
    if ( activate ) {
        [self updateCvar:YES force:YES];
        [self ensureCursorVisible];
    }
}

/*
============
idEditWindow::InitCvar
============
*/
- (void)initCvar {
    if ( [cvarStr string].length == 0 ) {
        // text.GetName() == NULL: never, GetName gives "" for no name
        cvar = nil;
        return;
    }

    cvar = [[gui manager].cvars find:[cvarStr string]];
    if ( !cvar ) {
        [[gui manager] uiWarning:[NSString stringWithFormat:@"idEditWindow::InitCvar: gui '%@' window '%@' references undefined cvar '%@'", [gui getSourceFile], name, [cvarStr string]]];
        return;
    }
}

/*
============
idEditWindow::UpdateCvar
============
*/
- (void)updateCvar:(BOOL)read force:(BOOL)force {
    if ( force || liveUpdate.data ) {
        if ( cvar ) {
            if ( read ) {
                [text setData:[cvar getString]];
            } else {
                [cvar setString:[text string]];
                if ( cvarMax && ( [cvar getInteger] > cvarMax ) ) {
                    [cvar setInteger:cvarMax];
                }
            }
        }
    }
}

/*
============
idEditWindow::RunNamedEvent
============
*/
- (void)runNamedEvent:(NSString *)eventName {
    if ( ![eventName ud_cmpn:@"cvar read " length:10] ) {
        NSString *group = [eventName substringFromIndex:10];
        if ( [group isEqualToString:[cvarGroup string]] ) {
            [self updateCvar:YES force:YES];
        }
    } else if ( ![eventName ud_cmpn:@"cvar write " length:11] ) {
        NSString *group = [eventName substringFromIndex:11];
        if ( [group isEqualToString:[cvarGroup string]] ) {
            [self updateCvar:NO force:YES];
        }
    }
}

@end
