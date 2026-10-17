/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEWorkspace.m — tools/guied/GEWorkspace.cpp and GEWorkspaceFile.cpp,
 * ported (the file's half here; the window's in Decl Browser).
 */

#import "rvGEWorkspace.h"
#import "rvGEWindowWrapper.h"
#import "idUserInterface.h"
#import "idWindow.h"
#import "idDict.h"
#import "idLexer.h"
#import "idStr.h"
#import "rvGEOptions.h"
#import "rvGEModifier.h"
#import "UDOverlay.h"

/// SCREEN_WIDTH, SCREEN_HEIGHT: the GUI's.
#define SCREEN_WIDTH    640
#define SCREEN_HEIGHT   480

@interface rvGEWorkspace ()
@property (nonatomic, strong, readwrite, nullable) idUserInterfaceLocal *interface;
@property (nonatomic, readwrite) rvGEHitTest dragType;
@end

@implementation rvGEWorkspace {
    idVec2 mDragPoint;
    int mDragTime;
    BOOL mDragX;
    BOOL mDragY;
}

- (instancetype)initWithManager:(idUserInterfaceManager *)manager {
    self = [super init];
    if (self) {
        _manager = manager;
        manager.editing = YES;
        _options = [[rvGEOptions alloc] init];
        _selections = [[rvGESelectionMgr alloc] init];
        _selections.workspace = self;
        _modifiers = [[rvGEModifierStack alloc] init];
        _rect = idRectangle_Make( 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT );
        _dragType = HT_NONE;
    }
    return self;
}

/*
================
rvGEWorkspace::LoadFile

Loads the given gui file.
================
*/
- (BOOL)loadFile:(NSString *)qpath {
    return [self _load:nil path:qpath];
}

- (BOOL)loadText:(NSString *)text path:(NSString *)qpath {
    return [self _load:text path:qpath];
}

- (BOOL)_load:(nullable NSString *)text path:(NSString *)qpath {
    if (self.interface != nil) {
        [self.manager deAlloc:self.interface];
    }
    // a new GUI: none of the last one's selections or edits
    [self.selections clear];
    [self.modifiers reset];
    self.modified = NO;
    self.dragType = HT_NONE;

    // Let the real window system parse it first (the engine's FindGui of a
    // copy, unique: a GUI of its own, not the cache's)
    idUserInterfaceLocal *gui = [self.manager allocGui];
    BOOL result = text != nil ? [gui initFromText:text path:qpath] : [gui initFromFile:qpath];
    self.interface = gui;

    if ( result ) {
        [[rvGEWindowWrapper wrapperOf:[gui getDesktop]] expand];
    }

    return result;
}

- (NSString *)text {
    NSMutableString *out = [NSMutableString string];
    idWindow *window = [self.interface getDesktop];
    if (window != nil) {
        [self writeWindow:window depth:1 into:out];
    }
    return out;
}

/*
================
rvGEWorkspace::WriteTabs

Writes the given number of tabs to the given file
================
*/
static void WriteTabs( NSMutableString *file, int depth ) {
    int i;

    for ( i = 0; i < depth; i ++ ) {
        [file appendString:@"\t"];
    }
}

/*
================
rvGEWorkspace::WriteWindow

Writes the contents of the given window to the file
================
*/
- (void)writeWindow:(idWindow *)window depth:(int)depth into:(NSMutableString *)file {
    rvGEWindowWrapper *wrapper;
    int i;

    wrapper = [rvGEWindowWrapper wrapperOf:window];
    if ( !wrapper ) {
        return;
    }

    if ( wrapper.deleted ) {
        return;
    }

    // Window def header
    WriteTabs( file, depth - 1 );

    [file appendString:[rvGEWindowWrapper stringFromWindowType:wrapper.windowType]];
    [file appendString:@" "];

    [file appendString:[window getName]];
    [file appendString:@"\r\n"];

    WriteTabs( file, depth - 1 );

    [file appendString:@"{\r\n"];

    idDict *state = wrapper.stateDict;
    for ( i = 0; i < [state numKeyVals]; i ++ ) {
        NSString *key = [state keyAtIndex:i];

        // Dont write name to the files
        if ( [key ud_iequals:@"name"] ) {
            continue;
        }

        WriteTabs( file, depth );

        [file appendString:key];
        [file appendString:@"\t"];

        NSString *value = [state valueAtIndex:i];
        for ( NSUInteger p = 0; p < value.length; p ++ ) {
            unichar c = [value characterAtIndex:p];
            switch ( c ) {
                case '\n':
                    [file appendString:@"\\n"];
                    break;

                default:
                    [file appendFormat:@"%C", c];
                    break;
            }
        }

        [file appendString:@"\r\n"];
    }

    idDict *variables = wrapper.variableDict;
    for ( i = 0; i < [variables numKeyVals]; i ++ ) {
        WriteTabs( file, depth );

        [file appendString:[variables keyAtIndex:i]];
        [file appendString:@"\t"];
        [file appendString:[variables valueAtIndex:i]];
        [file appendString:@"\r\n"];
    }

    idDict *scripts = wrapper.scriptDict;
    if ( [scripts numKeyVals] ) {
        [file appendString:@"\r\n"];
    }

    for ( i = 0; i < [scripts numKeyVals]; i ++ ) {
        WriteTabs( file, depth );

        [file appendString:[scripts keyAtIndex:i]];
        [file appendString:@" "];

        NSData *bytes __attribute__((objc_precise_lifetime)) = [[scripts valueAtIndex:i] ud_latin1Buffer];
        idLexer *src = [[idLexer alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:@""
                                                 flags:LEXFL_ALLOWMULTICHARLITERALS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                            fileSystem:nil error:NULL];
        NSMutableString *out = [NSMutableString string];
        [src parseBracedSectionExact:out tabs:depth + 1 skippingCommentsAndStrings:YES error:NULL];

        [file appendString:out];
        [file appendString:@"\r\n"];
        [file appendString:@"\r\n"];
    }

    for ( i = 0; i < [wrapper childCount]; i ++ ) {
        idWindow *child = [wrapper childAtIndex:i];

        [self writeWindow:child depth:depth + 1 into:file];
    }

    // Window def footer
    WriteTabs( file, depth - 1 );

    [file appendString:@"}\r\n"];
}

#pragma mark - The canvas

/*
================
rvGEWorkspace::WindowToWorkspace

Converts the given coordinates in windows space to the workspace's coordinates.
================
*/
- (idVec2)windowToWorkspacePoint:(idVec2)point {
    idRectangle mRect = self.rect;
    point.x = (point.x - mRect.x) / mRect.w * SCREEN_WIDTH;
    point.y = (point.y - mRect.y) / mRect.h * SCREEN_HEIGHT;
    return point;
}

- (idRectangle)windowToWorkspaceRect:(idRectangle)rect {
    idRectangle mRect = self.rect;
    rect.x = (rect.x - mRect.x) / mRect.w * SCREEN_WIDTH;
    rect.y = (rect.y - mRect.y) / mRect.h * SCREEN_HEIGHT;
    rect.w = rect.w / mRect.w * SCREEN_WIDTH;
    rect.h = rect.h / mRect.h * SCREEN_HEIGHT;
    return rect;
}

/*
================
rvGEWorkspace::WindowToWorkspace

Converts the given workspace coordinates to the windows coordinates.
================
*/
- (idVec2)workspaceToWindowPoint:(idVec2)point {
    idRectangle mRect = self.rect;
    point.x = mRect.x + (point.x / SCREEN_WIDTH * mRect.w);
    point.y = mRect.y + (point.y / SCREEN_HEIGHT * mRect.h);
    return point;
}

- (idRectangle)workspaceToWindowRect:(idRectangle)rect {
    idRectangle mRect = self.rect;
    rect.x = mRect.x + (rect.x / SCREEN_WIDTH * mRect.w);
    rect.y = mRect.y + (rect.y / SCREEN_HEIGHT * mRect.h);
    rect.w = rect.w / SCREEN_WIDTH * mRect.w;
    rect.h = rect.h / SCREEN_HEIGHT * mRect.h;
    return rect;
}

/*
================
rvGEWorkspace::HandleLButtonDown

Handles the left mouse down message in the workspace
================
*/
- (void)mouseDownAtX:(float)x y:(float)y shift:(BOOL)shift time:(int)time {
    if ( self.interface == nil ) {
        return;
    }

    idVec2 point = [self windowToWorkspacePoint:idVec2_Make( x, y )];

    // Make sure whatever modifications get generated cant be merged into whats already there
    [self.modifiers blockNextMerge];

    mDragPoint = idVec2_Make( x, y );
    mDragTime = time;
    mDragX = YES;
    mDragY = YES;

    rvGESelectionMgr *mSelections = self.selections;

    // If we have selections then start a drag
    if ( [mSelections num] ) {
        self.dragType = [mSelections hitTestX:mDragPoint.x y:mDragPoint.y];
    }

    rvGEWindowWrapper *wrapper;
    wrapper = [rvGEWindowWrapper wrapperOf:[self.interface getDesktop]];
    idWindow *window = [wrapper windowFromPointX:point.x y:point.y visibleOnly:YES];

    // dissallow selection of the desktop.
    if ( self.options.ignoreDesktopSelect && window == [self.interface getDesktop] ) {
        window = nil;
    }

    if ( self.dragType == HT_MOVE || self.dragType == HT_NONE ) {
        if ( window ) {
            BOOL selected;

            selected = [mSelections isSelected:window];

            if ( shift ) {
                if ( !selected ) {
                    [mSelections add:window];
                    self.dragType = HT_MOVE;
                } else {
                    [mSelections remove:window];
                }
            } else if ( !selected && self.dragType == HT_NONE ) {
                [mSelections set:window];
                self.dragType = HT_MOVE;
            }
        } else {
            [mSelections clear];
        }
    }

    if ( [mSelections isExpression] ) {
        self.dragType = HT_SELECT;
    }

    mDragPoint = [self windowToWorkspacePoint:mDragPoint];
}

/*
================
rvGEWorkspace::HandleLButtonUp

Handles the left mouse up message in the workspace
================
*/
- (void)mouseUp {
    if ( self.dragType != HT_NONE ) {
        [self.modifiers blockNextMerge];
    }

    // No more dragging
    self.dragType = HT_NONE;
}

/*
================
rvGEWorkspace::HandleMouseMove

Handles the moving of the mouse for dragging and cursor updating
================
*/
- (void)mouseMoveToX:(float)x y:(float)y time:(int)time {
    idVec2 cursor;

    // Convert the window point to the workspace before updating the
    // cursor with the position
    cursor = [self windowToWorkspacePoint:idVec2_Make( x, y )];

    // If not dragging then just update the cursor and return
    if ( self.dragType == HT_NONE ) {
        return;
    }

    // Dont allow a drag move start until the button has been down for 100 ms or so
    if ( self.dragType == HT_MOVE && time - mDragTime <= 50 ) {
        return;
    }

    rvGEOptions *options = self.options;
    BOOL snap = options.gridSnap;

    // Handle grid snapping
    if ( snap ) {
        int gridWidth = options.gridWidth;
        cursor.x = (float)(((int)cursor.x + gridWidth / 2) / gridWidth * gridWidth);
        cursor.y = (float)(((int)cursor.y + gridWidth / 2) / gridWidth * gridWidth);
    }

    // If the cursor hasnt moved then there is nothing to update with the drag
    if ( (int) cursor.x == (int) mDragPoint.x && (int) cursor.y == (int) mDragPoint.y ) {
        return;
    }

    switch ( self.dragType ) {
        case HT_MOVE:
            [self addModifierMove:@"Move" x:cursor.x - mDragPoint.x y:cursor.y - mDragPoint.y snap:snap];
            break;

        case HT_SIZE_BOTTOM:
            [self addModifierSize:@"Size" l:0 t:0 r:0 b:cursor.y - mDragPoint.y snap:snap];
            break;

        case HT_SIZE_TOP:
            [self addModifierSize:@"Size" l:0 t:cursor.y - mDragPoint.y r:0 b:0 snap:snap];
            break;

        case HT_SIZE_RIGHT:
            [self addModifierSize:@"Size" l:0 t:0 r:cursor.x - mDragPoint.x b:0 snap:snap];
            break;

        case HT_SIZE_LEFT:
            [self addModifierSize:@"Size" l:cursor.x - mDragPoint.x t:0 r:0 b:0 snap:snap];
            break;

        case HT_SIZE_TOPLEFT:
            [self addModifierSize:@"Size" l:cursor.x - mDragPoint.x t:cursor.y - mDragPoint.y r:0 b:0 snap:snap];
            break;

        case HT_SIZE_TOPRIGHT:
            [self addModifierSize:@"Size" l:0 t:cursor.y - mDragPoint.y r:cursor.x - mDragPoint.x b:0 snap:snap];
            break;

        case HT_SIZE_BOTTOMLEFT:
            [self addModifierSize:@"Size" l:cursor.x - mDragPoint.x t:0 r:0 b:cursor.y - mDragPoint.y snap:snap];
            break;

        case HT_SIZE_BOTTOMRIGHT:
            [self addModifierSize:@"Size" l:0 t:0 r:cursor.x - mDragPoint.x b:cursor.y - mDragPoint.y snap:snap];
            break;

        default:
            break;
    }

    // If the x coordinate has changed then update it
    if ( (int)cursor.x != (int)mDragPoint.x && mDragX ) {
        mDragPoint.x = cursor.x;
    }

    // If the y coordinate has changed then update it
    if ( (int)cursor.y != (int)mDragPoint.y && mDragY ) {
        mDragPoint.y = cursor.y;
    }
}

/*
================
rvGEWorkspace::UpdateCursor

The cursor over ( x, y ) in the window: what the selection is there (HT_NONE
is the arrow).
================
*/
- (rvGEHitTest)cursorTypeAtX:(float)x y:(float)y {
    if ( self.dragType != HT_NONE ) {
        return self.dragType;
    }
    return [self.selections hitTestX:x y:y];
}

/*
================
rvGEWorkspace::AddModifierMove

Adds a move modifier with the given offsets
================
*/
- (void)addModifierMove:(NSString *)modName x:(float)x y:(float)y snap:(BOOL)snap {
    idRectangle scaleRect;
    idRectangle newRect;

    rvGESelectionMgr *mSelections = self.selections;

    scaleRect = [self windowToWorkspaceRect:[mSelections rect]];
    newRect = scaleRect;
    newRect.x += x;
    newRect.y += y;

    if ( snap ) {
        [self.options snapRectToGrid:&newRect snapLeft:YES snapTop:YES snapWidth:NO snapHeight:NO];
    }

    rvGEModifierGroup *group = [[rvGEModifierGroup alloc] init];
    for ( int i = 0; i < [mSelections num]; i ++ ) {
        if ( ![mSelections[i] getParent] ) {
            continue;
        }

        // IF the parent window is being moved around as well then dont move this one.
        if ( [rvGEWindowWrapper wrapperOf:[mSelections[i] getParent]].selected ) {
            // We still need the modifier there so the selection can be restored and
            // so the rectangle gets updated
            [group append:[[rvGEMoveModifier alloc] initWithName:modName window:mSelections[i] x:0 y:0]];
            continue;
        }

        [group append:[[rvGEMoveModifier alloc] initWithName:modName window:mSelections[i] x:newRect.x - scaleRect.x y:newRect.y - scaleRect.y]];
    }

    [self.modifiers append:group];

    self.modified = YES;
}

/*
================
rvGEWorkspace::AddModifierSize

Adds a size modifier with the given offsets
================
*/
- (void)addModifierSize:(NSString *)modName l:(float)l t:(float)t r:(float)r b:(float)b snap:(BOOL)snap {
    idRectangle scaleRect;
    idRectangle sizeRect;
    idRectangle newRect;

    rvGESelectionMgr *mSelections = self.selections;

    scaleRect = [self windowToWorkspaceRect:[mSelections rect]];
    newRect = scaleRect;
    newRect.x += l;
    newRect.y += t;
    newRect.w += (r - l);
    newRect.h += (b - t);

    // Restrict sizing below 1 width
    if ( newRect.w <= 1 ) {
        newRect.x = newRect.x - (l ? (1 - newRect.w) : 0);
        mDragPoint.x = newRect.x;
        newRect.w = 1;
        mDragX = NO;
    } else {
        mDragX = YES;
    }

    // Restrict sizing below 1 height
    if ( newRect.h <= 1 ) {
        newRect.y = newRect.y - (t ? (1 - newRect.h) : 0);
        mDragPoint.y = newRect.y;
        newRect.h = 1;
        mDragY = NO;
    } else {
        mDragY = YES;
    }

    if ( snap ) {
        [self.options snapRectToGrid:&newRect snapLeft:l != 0.0f snapTop:t != 0.0f snapWidth:r != 0.0f snapHeight:b != 0.0f];
    }

    rvGEModifierGroup *group = [[rvGEModifierGroup alloc] init];
    for ( int i = 0; i < [mSelections num]; i ++ ) {
        sizeRect = [rvGEWindowWrapper wrapperOf:mSelections[i]].screenRect;

        l = (newRect.x + ((sizeRect.x - scaleRect.x) / scaleRect.w) * newRect.w) - sizeRect.x;
        t = (newRect.y + ((sizeRect.y - scaleRect.y) / scaleRect.h) * newRect.h) - sizeRect.y;
        r = (sizeRect.w / scaleRect.w * newRect.w) - sizeRect.w + l;
        b = (sizeRect.h / scaleRect.h * newRect.h) - sizeRect.h + t;

        // This is sorta crufty but needs to be done.  When a parent is being sized at the same
        // time as a child you will get double movement because the child is relative to the parent.  Therefore
        // we need to subtract out the closest parents sizing.
        idWindow *parent = mSelections[i];
        while ( nil != (parent = [parent getParent]) ) {
            rvGEWindowWrapper *pwrapper = [rvGEWindowWrapper wrapperOf:parent];
            float offset;

            if ( !pwrapper.selected ) {
                continue;
            }

            sizeRect = pwrapper.screenRect;

            // Subtract out the left and right modifications
            offset = ((newRect.x + ((sizeRect.x - scaleRect.x) / scaleRect.w) * newRect.w) - sizeRect.x);
            l -= offset;
            r -= offset;

            // Subtract out the top and bottom modifications
            offset = ((newRect.y + ((sizeRect.y - scaleRect.y) / scaleRect.h) * newRect.h) - sizeRect.y);
            t -= offset;
            b -= offset;

            break;
        }

        [group append:[[rvGESizeModifier alloc] initWithName:modName window:mSelections[i] l:l t:t r:r b:b]];
    }

    [self.modifiers append:group];

    self.modified = YES;
}

/*
================
rvGEWorkspace::RenderGrid

Renders the grid on top of the user interface
================
*/
- (void)renderGridInto:(UDOverlay *)overlay {
    float x;
    float y;
    float step;
    rvGEOptions *options = self.options;
    idVec4 color = options.gridColor;
    idRectangle mRect = self.rect;
    // g_ZoomScales[mZoom]: the GUI's size in the window over its own
    float zoomScale = mRect.w / SCREEN_WIDTH;

    // See if the grid is off before rendering it
    if ( !options.gridVisible ) {
        return;
    }

    idVec4 faded = idVec4_Make( color.x, color.y, color.z, 0.5f );

    step = options.gridWidth * zoomScale;
    for ( x = mRect.x + mRect.w; x >= mRect.x && step > 0; x -= step ) {
        [overlay addLineFromX:x y:mRect.y toX:x y:mRect.y + mRect.h color:faded];
    }
    step = options.gridHeight * zoomScale;
    for ( y = mRect.y + mRect.h; y >= mRect.y && step > 0; y -= step ) {
        [overlay addLineFromX:mRect.x y:y toX:mRect.x + mRect.w y:y color:faded];
    }

    idVec4 opaque = idVec4_Make( color.x, color.y, color.z, 1.0f );

    step = options.gridWidth * zoomScale;
    for ( x = mRect.x + mRect.w; x >= mRect.x && step > 0; x -= step * 4 ) {
        [overlay addLineFromX:x y:mRect.y toX:x y:mRect.y + mRect.h color:opaque];
    }
    step = options.gridHeight * zoomScale;
    for ( y = mRect.y + mRect.h; y >= mRect.y && step > 0; y -= step * 4 ) {
        [overlay addLineFromX:mRect.x y:y toX:mRect.x + mRect.w y:y color:opaque];
    }
}

- (void)renderOverlayInto:(UDOverlay *)overlay {
    [self renderGridInto:overlay];
    [self.selections renderInto:overlay];
}

#pragma mark - AddModifiers

/*
================
rvGEWorkspace::CreateModifier

Creates a new modifier of the given type
================
*/
- (nullable rvGEModifier *)createModifier:(rvGEModifierType)type window:(idWindow *)window {
    switch ( type ) {
        case MOD_HIDE:
            return [[rvGEHideModifier alloc] initWithName:@"Hide" window:window hide:YES];

        case MOD_UNHIDE:
            return [[rvGEHideModifier alloc] initWithName:@"Hide" window:window hide:NO];

        default:
            return nil;
    }
}

/*
================
rvGEWorkspace::AddModifiers

Add the specific modifier for the given window
================
*/
- (void)addModifier:(rvGEModifierType)type window:(idWindow *)window {
    rvGEModifier *mod = [self createModifier:type window:window];
    if ( mod ) {
        [self.modifiers append:mod];
    }
    self.modified = YES;
}

- (void)addModifierToSelection:(rvGEModifierType)type {
    rvGESelectionMgr *mSelections = self.selections;

    // Nothing to move if there is no selection
    if ( ![mSelections num] ) {
        return;
    }
    // More than one selection requires a modifier group
    else if ( [mSelections num] > 1 ) {
        rvGEModifierGroup *group = [[rvGEModifierGroup alloc] init];
        for ( int i = 0; i < [mSelections num]; i ++ ) {
            rvGEModifier *mod = [self createModifier:type window:mSelections[i]];
            if ( mod ) {
                [group append:mod];
            }
        }
        [self.modifiers append:group];
    }
    // Single modifier
    else {
        rvGEModifier *mod = [self createModifier:type window:mSelections[0]];
        if ( mod ) {
            [self.modifiers append:mod];
        }
    }

    self.modified = YES;
}

- (void)hideSelected {
    [self addModifierToSelection:MOD_HIDE];
    [self.selections clear];
}

- (void)unhideSelected {
    [self addModifierToSelection:MOD_UNHIDE];
}

- (void)hideWindow:(idWindow *)window {
    [self addModifier:MOD_HIDE window:window];
}

- (void)unhideWindow:(idWindow *)window {
    [self addModifier:MOD_UNHIDE window:window];
}

#pragma mark - rvGEProperties

/// idStr::StripQuotes
static NSString *UDStripQuotes(NSString *s) {
    if ( ![s hasPrefix:@"\""] ) {
        return s;
    }
    NSUInteger end = s.length;
    // Remove the trailing quote first
    if ( end > 1 && [s characterAtIndex:end - 1] == '"' ) {
        end--;
    }
    // Strip the leading quote now
    return [s substringWithRange:NSMakeRange(1, end - 1)];
}

/*
================
rvGEProperties::Update

Update the properties in the window
================
*/
- (NSArray<NSArray<NSString *> *> *)properties {
    if ( [self.selections num] != 1 ) {
        return nil;
    }
    rvGEWindowWrapper *mWrapper = [rvGEWindowWrapper wrapperOf:self.selections[0]];
    NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray array];
    idDict *state = mWrapper.stateDict;
    for ( int i = 0; i < [state numKeyVals]; i ++ ) {
        [rows addObject:@[ [state keyAtIndex:i], UDStripQuotes( [state valueAtIndex:i] ) ]];
    }
    return rows;
}

/*
================
rvGEProperties::AddModifier

Add a state modifier for the given key / value pair
================
*/
- (BOOL)setProperty:(NSString *)name value:(NSString *)value {
    if ( [self.selections num] != 1 ) {
        return NO;
    }
    rvGEWindowWrapper *mWrapper = [rvGEWindowWrapper wrapperOf:self.selections[0]];
    NSString *tempvalue = value;

    if ( ![mWrapper verifyStateKey:name value:tempvalue result:NULL] ) {
        tempvalue = [NSString stringWithFormat:@"\"%@\"", value];
        if ( ![mWrapper verifyStateKey:name value:tempvalue result:NULL] ) {
            return NO;
        }
    }

    idDict *tempstate = [mWrapper.stateDict copy];
    [tempstate set:name value:tempvalue];

    [self.modifiers append:[[rvGEStateModifier alloc] initWithName:@"Property Change" window:mWrapper.window dict:tempstate]];
    self.modified = YES;

    return YES;
}

@end
