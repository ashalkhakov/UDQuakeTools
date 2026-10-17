/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idListWindow.m — ui/ListWindow.cpp, ported. See idListWindow.h.
 */

#import "idListWindow.h"
#import "idSliderWindow.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "UDDeclCodec.h"
#import "idDeviceContext.h"
#import "idDict.h"
#import "idParser.h"
#import "idToken.h"

// Number of pixels above the text that the rect starts
static const int pixelOffset = 3;

// number of pixels between columns
static const int tabBorder = 4;

// Time in milliseconds between clicks to register as a double-click
static const int doubleClickSpeed = 300;

/// idStr::Find( c, start ): its index from @a start, -1 for none
static int FindChar( NSString *s, unichar c, int start ) {
    int l = (int)s.length;
    for ( int i = start; i < l; i++ ) {
        if ( [s characterAtIndex:i] == c ) {
            return i;
        }
    }
    return -1;
}

@implementation idListWindow

- (idTabRect *)tabs { return (idTabRect *)tabInfo.mutableBytes; }
- (int)numTabs { return (int)( tabInfo.length / sizeof( idTabRect ) ); }

- (void)listCommonInit {
    [typed setString:@""];
    typedTime = 0;
    clickTime = 0;
    [currentSel removeAllObjects];
    top = 0;
    sizeBias = 0;
    horizontal = NO;
    scroller = [[idSliderWindow alloc] initWithDC:dc gui:gui];
    multipleSel = NO;
}

- (void)constructListMembers {
    tabInfo = [NSMutableData data];
    tabStopStr = @"";
    tabAlignStr = @"";
    tabVAlignStr = @"";
    tabTypeStr = @"";
    tabIconSizeStr = @"";
    tabIconVOffsetStr = @"";
    iconMaterials = [NSMutableDictionary dictionary];
    listItems = [NSMutableArray array];
    currentSel = [NSMutableArray array];
    listName = @"";
    typed = [NSMutableString string];
}

- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)g {
    self = [super initWithDC:d gui:g];
    if (self) {
        [self constructListMembers];
        dc = d;
        gui = g;
        [self listCommonInit];
    }
    return self;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)g {
    self = [super initWithGui:g];
    if (self) {
        [self constructListMembers];
        gui = g;
        [self listCommonInit];
    }
    return self;
}


- (void)setCurrentSel:(int)sel {
    [currentSel removeAllObjects];
    [currentSel addObject:@( sel )];
}

- (void)clearSelection:(int)sel {
    NSUInteger cur = [currentSel indexOfObject:@( sel )];
    if ( cur != NSNotFound ) {
        [currentSel removeObjectAtIndex:cur];
    }
}

- (void)addCurrentSel:(int)sel {
    [currentSel addObject:@( sel )];
}

- (int)getCurrentSel {
    return ( currentSel.count ) ? currentSel[0].intValue : 0;
}

- (BOOL)isSelected:(int)index {
    return ( [currentSel indexOfObject:@( index )] != NSNotFound );
}


- (NSString *)handleEvent:(const sysEvent_t *)event updateVisuals:(BOOL *)updateVisuals {
    idUserInterfaceManager *manager = [gui manager];
    // need to call this to allow proper focus and capturing on embedded children
    NSString *ret = [super handleEvent:event updateVisuals:updateVisuals];

    float vert = [self getMaxCharHeight];
    int numVisibleLines = textRect.h / vert;

    int key = event->evValue;

    if ( event->evType == SE_KEY ) {
        if ( !event->evValue2 ) {
            // We only care about key down, not up
            return ret;
        }

        if ( key == K_MOUSE1 || key == K_MOUSE2 ) {
            // If the user clicked in the scroller, then ignore it
            if ( [scroller contains:[gui cursorX] y:[gui cursorY]] ) {
                return ret;
            }
        }

        if ( ( key == K_ENTER || key == K_KP_ENTER ) ) {
            [self runScript:ON_ENTER];
            return [cmd copy];
        }

        if ( key == K_MWHEELUP ) {
            key = K_UPARROW;
        } else if ( key == K_MWHEELDOWN ) {
            key = K_DOWNARROW;
        }

        if ( key == K_MOUSE1) {
            if ([self contains:[gui cursorX] y:[gui cursorY]]) {
                int cur = ( int )( ( [gui cursorY] - actualY - pixelOffset ) / vert ) + top;
                if ( cur >= 0 && cur < (int)listItems.count ) {
                    if ( multipleSel && [manager isKeyDown:K_CTRL] ) {
                        if ( [self isSelected:cur] ) {
                            [self clearSelection:cur];
                        } else {
                            [self addCurrentSel:cur];
                        }
                    } else {
                        if ( [self isSelected:cur] && ( [gui getTime] < clickTime + doubleClickSpeed ) ) {
                            // Double-click causes ON_ENTER to get run
                            [self runScript:ON_ENTER];
                            return [cmd copy];
                        }
                        [self setCurrentSel:cur];

                        clickTime = [gui getTime];
                    }
                } else {
                    [self setCurrentSel:(int)listItems.count - 1];
                }
            }
        } else if ( key == K_UPARROW || key == K_PGUP || key == K_DOWNARROW || key == K_PGDN ) {
            int numLines = 1;

            if ( key == K_PGUP || key == K_PGDN ) {
                numLines = numVisibleLines / 2;
            }

            if ( key == K_UPARROW || key == K_PGUP ) {
                numLines = -numLines;
            }

            if ( [manager isKeyDown:K_CTRL] ) {
                top += numLines;
            } else {
                [self setCurrentSel:[self getCurrentSel] + numLines];
            }
        } else {
            return ret;
        }
    } else if ( event->evType == SE_CHAR ) {
        if ( !idStr_CharIsPrintable(key) ) {
            return ret;
        }

        if ( [gui getTime] > typedTime + 1000 ) {
            [typed setString:@""];
        }
        typedTime = [gui getTime];
        [typed appendFormat:@"%C", (unichar)key];

        for ( int i=0; i<(int)listItems.count; i++ ) {
            if ( [typed ud_icmpn:listItems[i] length:(NSInteger)typed.length] == 0 ) {
                [self setCurrentSel:i];
                break;
            }
        }

    } else {
        return ret;
    }

    if ( [self getCurrentSel] < 0 ) {
        [self setCurrentSel:0];
    }

    if ( [self getCurrentSel] >= (int)listItems.count ) {
        [self setCurrentSel:(int)listItems.count - 1];
    }

    if ( [scroller getHigh] > 0.0f ) {
        if ( ![manager isKeyDown:K_CTRL] ) {
            if ( top > [self getCurrentSel] - 1 ) {
                top = [self getCurrentSel] - 1;
            }
            if ( top < [self getCurrentSel] - numVisibleLines + 2 ) {
                top = [self getCurrentSel] - numVisibleLines + 2;
            }
        }

        if ( top > (int)listItems.count - 2 ) {
            top = (int)listItems.count - 2;
        }
        if ( top < 0 ) {
            top = 0;
        }
        [scroller setValue:top];
    } else {
        top = 0;
        [scroller setValue:0.0f];
    }

    if ( key != K_MOUSE1 ) {
        // Send a fake mouse click event so onAction gets run in our parents
        // (sys->GenerateMouseButtonEvent( 1, YES ))
        const sysEvent_t ev = { SE_KEY, K_MOUSE1, YES };
        [super handleEvent:&ev updateVisuals:updateVisuals];
    }

    if ( currentSel.count > 0 ) {
        for ( int i = 0; i < (int)currentSel.count; i++ ) {
            [gui setStateInt:[NSString stringWithFormat:@"%@_sel_%i", listName, i] value:currentSel[i].intValue];
        }
    } else {
        [gui setStateInt:[NSString stringWithFormat:@"%@_sel_0", listName] value:0];
    }
    [gui setStateInt:[NSString stringWithFormat:@"%@_numsel", listName] value:(int)currentSel.count];

    return ret;
}


- (BOOL)parseInternalVar:(NSString *)_name parser:(idParser *)src {
    if ([_name ud_iequals:@"horizontal"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        horizontal = b;
        return YES;
    }
    if ([_name ud_iequals:@"listname"]) {
        listName = [self parseString:src] ?: listName;
        return YES;
    }
    if ([_name ud_iequals:@"tabstops"]) {
        tabStopStr = [self parseString:src] ?: tabStopStr;
        return YES;
    }
    if ([_name ud_iequals:@"tabaligns"]) {
        tabAlignStr = [self parseString:src] ?: tabAlignStr;
        return YES;
    }
    if ([_name ud_iequals:@"multipleSel"]) {
        BOOL b = NO;
        [src parseBool:&b error:NULL];
        multipleSel = b;
        return YES;
    }
    if([_name ud_iequals:@"tabvaligns"]) {
        tabVAlignStr = [self parseString:src] ?: tabVAlignStr;
        return YES;
    }
    if([_name ud_iequals:@"tabTypes"]) {
        tabTypeStr = [self parseString:src] ?: tabTypeStr;
        return YES;
    }
    if([_name ud_iequals:@"tabIconSizes"]) {
        tabIconSizeStr = [self parseString:src] ?: tabIconSizeStr;
        return YES;
    }
    if([_name ud_iequals:@"tabIconVOffset"]) {
        tabIconVOffsetStr = [self parseString:src] ?: tabIconVOffsetStr;
        return YES;
    }

    // strName.Left(4) Icmp "mtr_"
    if([[_name substringToIndex:MIN( (NSUInteger)4, _name.length )] ud_iequals:@"mtr_"]) {
        NSString *matName = @"";
        idMaterial* mat;

        matName = [self parseString:src] ?: matName;
        mat = [[gui manager] findMaterial:matName];
            [mat setImageClassifications:1];  // just for resource tracking
        if ( mat && ![mat defaulted] ) {
            [mat setSort:SS_GUI];
        }
        iconMaterials[_name] = mat;
        return YES;
    }

    return [super parseInternalVar:_name parser:src];
}

- (idWinVar *)getWinVarByName:(NSString *)_name fixup:(BOOL)fixup owner:(idDrawWin **)owner {
    return [super getWinVarByName:_name fixup:fixup owner:owner];
}

/// A parser over @a bytes (PostParse's idParsers); the caller holds them.
- (idParser *)listParser:(NSData *)bytes name:(NSString *)listNameString {
    return [[idParser alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:listNameString
                                      flags:LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_NOSTRINGESCAPECHARS error:NULL];
}

- (void)postParse {
    [super postParse];

    [self initScroller:horizontal];

    NSMutableArray<NSNumber *> *tabStops = [NSMutableArray array];
    NSMutableArray<NSNumber *> *tabAligns = [NSMutableArray array];
    idToken tok;
    idToken_Init( &tok );
    if (tabStopStr.length) {
        NSData *bytes __attribute__((objc_precise_lifetime)) = [tabStopStr ud_latin1Buffer];
        idParser *src = [self listParser:bytes name:@"tabstops"];
        while ([src readToken:&tok error:NULL]) {
            if (UDTokenIs(&tok, ",")) {
                continue;
            }
            [tabStops addObject:@( atoi(tok.text) )];
        }
    }
    if (tabAlignStr.length) {
        NSData *bytes __attribute__((objc_precise_lifetime)) = [tabAlignStr ud_latin1Buffer];
        idParser *src = [self listParser:bytes name:@"tabaligns"];
        while ([src readToken:&tok error:NULL]) {
            if (UDTokenIs(&tok, ",")) {
                continue;
            }
            [tabAligns addObject:@( atoi(tok.text) )];
        }
    }
    NSMutableArray<NSNumber *> *tabVAligns = [NSMutableArray array];
    if (tabVAlignStr.length) {
        NSData *bytes __attribute__((objc_precise_lifetime)) = [tabVAlignStr ud_latin1Buffer];
        idParser *src = [self listParser:bytes name:@"tabvaligns"];
        while ([src readToken:&tok error:NULL]) {
            if (UDTokenIs(&tok, ",")) {
                continue;
            }
            [tabVAligns addObject:@( atoi(tok.text) )];
        }
    }

    NSMutableArray<NSNumber *> *tabTypes = [NSMutableArray array];
    if (tabTypeStr.length) {
        NSData *bytes __attribute__((objc_precise_lifetime)) = [tabTypeStr ud_latin1Buffer];
        idParser *src = [self listParser:bytes name:@"tabtypes"];
        while ([src readToken:&tok error:NULL]) {
            if (UDTokenIs(&tok, ",")) {
                continue;
            }
            [tabTypes addObject:@( atoi(tok.text) )];
        }
    }
    NSMutableArray<NSValue *> *tabSizes = [NSMutableArray array];
    if (tabIconSizeStr.length) {
        NSData *bytes __attribute__((objc_precise_lifetime)) = [tabIconSizeStr ud_latin1Buffer];
        idParser *src = [self listParser:bytes name:@"tabiconsizes"];
        while ([src readToken:&tok error:NULL]) {
            if (UDTokenIs(&tok, ",")) {
                continue;
            }
            idVec2 size;
            size.x = atoi(tok.text);

            [src readToken:&tok error:NULL];    //","
            [src readToken:&tok error:NULL];

            size.y = atoi(tok.text);
            [tabSizes addObject:[NSValue valueWithBytes:&size objCType:@encode(idVec2)]];
        }
    }

    NSMutableArray<NSNumber *> *tabIconVOffsets = [NSMutableArray array];
    if (tabIconVOffsetStr.length) {
        NSData *bytes __attribute__((objc_precise_lifetime)) = [tabIconVOffsetStr ud_latin1Buffer];
        idParser *src = [self listParser:bytes name:@"tabiconvoffsets"];
        while ([src readToken:&tok error:NULL]) {
            if (UDTokenIs(&tok, ",")) {
                continue;
            }
            [tabIconVOffsets addObject:@( atof(tok.text) )];
        }
    }

    int c = (int)tabStops.count;
    BOOL doAligns = (tabAligns.count == tabStops.count);
    for (int i = 0; i < c; i++) {
        idTabRect r;
        r.x = tabStops[i].intValue;
        r.w = (i < c - 1) ? tabStops[i+1].intValue - r.x - tabBorder : -1;
        r.align = (doAligns) ? tabAligns[i].intValue : 0;
        if(tabVAligns.count > 0 && i < (int)tabVAligns.count) {
            r.valign = tabVAligns[i].intValue;
        } else {
            r.valign = 0;
        }
        if(tabTypes.count > 0 && i < (int)tabTypes.count) {
            r.type = tabTypes[i].intValue;
        } else {
            r.type = TAB_TYPE_TEXT;
        }
        if(tabSizes.count > 0 && i < (int)tabSizes.count ) {
            [tabSizes[i] getValue:&r.iconSize];
        } else {
            r.iconSize = idVec2_Make( 0, 0 );
        }
        if(tabIconVOffsets.count > 0 && i < (int)tabIconVOffsets.count) {
            r.iconVOffset = tabIconVOffsets[i].floatValue;
        } else {
            r.iconVOffset = 0;
        }
        [tabInfo appendBytes:&r length:sizeof( r )];
    }
    flags |= WIN_CANFOCUS;
}

/*
================
idListWindow::InitScroller

This is the same as in idEditWindow
================
*/
- (void)initScroller:(BOOL)isHorizontal
{
    NSString *thumbImage = @"guis/assets/scrollbar_thumb.tga";
    NSString *barImage = @"guis/assets/scrollbarv.tga";
    NSString *scrollerName = @"_scrollerWinV";

    if (isHorizontal) {
        barImage = @"guis/assets/scrollbarh.tga";
        scrollerName = @"_scrollerWinH";
    }

    idMaterial *mat = [[gui manager] findMaterial:barImage];
    [mat setSort:SS_GUI];
    sizeBias = [mat getImageWidth];

    idRectangle scrollRect;
    if (isHorizontal) {
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

    [scroller initWithDefaults:scrollerName rect:scrollRect foreColor:foreColor.data matColor:matColor.data background:mat.name thumbShader:thumbImage vertical:!isHorizontal scrollbar:YES];
    [self insertChild:scroller before:nil];
    [scroller setBuddy:self];
}

/// idStr::Mid( start, len, result )
static NSString *Mid( NSString *s, int start, int len ) {
    int i = (int)s.length;
    if ( i == 0 || len <= 0 || start >= i ) {
        return @"";
    }
    if ( start + len >= i ) {
        len = i - start;
    }
    return [s substringWithRange:NSMakeRange( start, len )];
}

- (void)draw:(int)time x:(float)x y:(float)y {
    idVec4 color;
    int count = (int)listItems.count;
    idRectangle drawRectangle = textRect;
    float scale = textScale.data;
    float lineHeight = [self getMaxCharHeight];

    float bottom = idRectangle_Bottom( &textRect );
    float width = textRect.w;

    if ( [scroller getHigh] > 0.0f ) {
        if ( horizontal ) {
            bottom -= sizeBias;
        } else {
            width -= sizeBias;
            drawRectangle.w = width;
        }
    }

    if ( noEvents.data || ![self contains:[gui cursorX] y:[gui cursorY]] ) {
        hover = NO;
    }

    idTabRect *tabs = [self tabs];
    int numTabs = [self numTabs];
    for (int i = top; i < count; i++) {
        if ( [self isSelected:i] ) {
            drawRectangle.h = lineHeight;
            [dc drawFilledRect:drawRectangle.x y:drawRectangle.y + pixelOffset width:drawRectangle.w height:drawRectangle.h color:borderColor.data];
            if ( flags & WIN_FOCUS ) {
                idVec4 focusColor = borderColor.data;
                focusColor.w = 1.0f;
                [dc drawRect:drawRectangle.x y:drawRectangle.y + pixelOffset width:drawRectangle.w height:drawRectangle.h size:1.0f color:focusColor];
            }
        }
        drawRectangle.y ++;
        drawRectangle.h = lineHeight - 1;
        if ( hover && !noEvents.data && [self containsRect:drawRectangle x:[gui cursorX] y:[gui cursorY]] ) {
            color = hoverColor.data;
        } else {
            color = foreColor.data;
        }
        drawRectangle.h = lineHeight + pixelOffset;
        drawRectangle.y --;

        if ( numTabs > 0 ) {
            int start = 0;
            int tab = 0;
            NSString *item = listItems[i];
            int itemLength = (int)item.length;
            int stop = FindChar( item, '\t', 0 );
            while ( start < itemLength ) {
                if ( tab >= numTabs ) {
                    [[gui manager] uiWarning:[NSString stringWithFormat:@"idListWindow::Draw: gui '%@' window '%@' tabInfo.Num() exceeded", [gui getSourceFile], name]];
                    break;
                }
                NSString *work = Mid( listItems[i], start, stop - start );

                drawRectangle.x = textRect.x + tabs[tab].x;
                drawRectangle.w = (tabs[tab].w == -1) ? width - tabs[tab].x : tabs[tab].w;
                [dc pushClipRect:drawRectangle];

                if ( tabs[tab].type == TAB_TYPE_TEXT ) {
                    [dc drawText:work textScale:scale textAlign:tabs[tab].align color:color rectDraw:drawRectangle wrap:NO cursor:-1];
                } else if (tabs[tab].type == TAB_TYPE_ICON) {

                    idMaterial *iconMat;

                    // leaving the icon name empty doesn't draw anything
                    if ( work.length != 0 ) {

                        iconMat = iconMaterials[work];
                        if ( iconMat == nil ) {
                            iconMat = [[gui manager] findMaterial:@"_default"];
                        }

                        idRectangle iconRect = { 0, 0, 0, 0 };
                        iconRect.w = tabs[tab].iconSize.x;
                        iconRect.h = tabs[tab].iconSize.y;

                        if(tabs[tab].align == ALIGN_LEFT) {
                            iconRect.x = drawRectangle.x;
                        } else if (tabs[tab].align == ALIGN_CENTER) {
                            iconRect.x = drawRectangle.x + drawRectangle.w/2.0f - iconRect.w/2.0f;
                        } else if (tabs[tab].align == ALIGN_RIGHT) {
                            iconRect.x  = drawRectangle.x + drawRectangle.w - iconRect.w;
                        }

                        if(tabs[tab].valign == 0) { //Top
                            iconRect.y = drawRectangle.y + tabs[tab].iconVOffset;
                        } else if(tabs[tab].valign == 1) { //Center
                            iconRect.y = drawRectangle.y + drawRectangle.h/2.0f - iconRect.h/2.0f + tabs[tab].iconVOffset;
                        } else if(tabs[tab].valign == 2) { //Bottom
                            iconRect.y = drawRectangle.y + drawRectangle.h - iconRect.h + tabs[tab].iconVOffset;
                        }

                        [dc drawMaterial:iconRect.x y:iconRect.y w:iconRect.w h:iconRect.h mat:iconMat color:idVec4_Make(1.0f,1.0f,1.0f,1.0f) scalex:1.0f scaley:1.0f];

                    }
                }

                [dc popClipRect];

                start = stop + 1;
                stop = FindChar( item, '\t', start );
                if ( stop < 0 ) {
                    stop = itemLength;
                }
                tab++;
            }
            drawRectangle.x = textRect.x;
            drawRectangle.w = width;
        } else {
            [dc drawText:listItems[i] textScale:scale textAlign:0 color:color rectDraw:drawRectangle wrap:NO cursor:-1];
        }
        drawRectangle.y += lineHeight;
        if ( drawRectangle.y > bottom ) {
            break;
        }
    }
}

- (void)activate:(BOOL)activate act:(NSMutableString *)act {
    [super activate:activate act:act];

    if ( activate ) {
        [self updateList];
    }
}

- (void)handleBuddyUpdate:(idWindow *)buddy {
    top = [scroller getValue];
}

- (void)updateList {
    [listItems removeAllObjects];
    for (int i = 0; i < MAX_LIST_ITEMS; i++) {
        NSString *key = [NSString stringWithFormat:@"%@_item_%i", listName, i];
        // State().GetString( key, "", str ): whether it is there
        NSString *str = [[gui state] getString:key defaultString:nil];
        if ( str != NULL ) {
            if ( str.length ) {
                [listItems addObject:str];
            }
        } else {
            break;
        }
    }
    float vert = [self getMaxCharHeight];
    int fit = textRect.h / vert;
    int selection = [[gui state] getInt:[NSString stringWithFormat:@"%@_sel_0", listName]];
    if ( (int)listItems.count < fit ) {
        [scroller setRange:0.0f high:0.0f step:1.0f];
        top = 0;
        [scroller setValue:0.0f];
    } else {
        [scroller setRange:0.0f high:(listItems.count - fit) + 1.0f step:1.0f];

        // DG: scroll to selected item
        float value = [scroller getValue];
        if ( value < 0.0f ) {
            value = 0.0f;
            top = 0;
        } else if ( value > listItems.count - 1 ) {
            value = listItems.count - 1;
        }
        float maxVisibleVal = MIN(value + fit, [scroller getHigh]);
        if ( selection >= 0 && (selection < value || selection > maxVisibleVal) ) {
            // if selected entry is not currently visible, center it (if possible)
            value = MAX(0.0f, selection - 0.5f * fit);
        }

        [scroller setValue:value];
        top = value;
    }

    [self setCurrentSel:selection];

    typedTime = 0;
    clickTime = 0;
    [typed setString:@""];
}

- (void)stateChanged:(BOOL)redraw {
    [self updateList];
}

@end
