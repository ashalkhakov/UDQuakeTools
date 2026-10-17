/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEWorkspace.m — tools/guied/GEWorkspace.cpp and GEWorkspaceFile.cpp,
 * ported (the file's half here; the window's in Quarry).
 */

#import "rvGEWorkspace.h"
#import "rvGEWindowWrapper.h"
#import "idUserInterface.h"
#import "idWindow.h"
#import "idDict.h"
#import "idLexer.h"
#import "idStr.h"
#import "idDeviceContext.h"
#import "idListWindow.h"
#import "idSliderWindow.h"
#import "idEditWindow.h"
#import "idChoiceWindow.h"
#import "idRenderWindow.h"
#import "idBindWindow.h"
#import "UDDeclCodec.h"
#import "idWinVar.h"
#import "idToken.h"
#import "idParser.h"
#import "rvGEOptions.h"
#import "rvGEModifier.h"
#import "rvGEScript.h"
#import "UDOverlay.h"

/// SCREEN_WIDTH, SCREEN_HEIGHT: the GUI's.
#define SCREEN_WIDTH    640
#define SCREEN_HEIGHT   480

@interface rvGEWorkspace ()
@property (nonatomic, strong, readwrite, nullable) idUserInterfaceLocal *interface;
@property (nonatomic, readwrite) rvGEHitTest dragType;
@end

/// rvGEClipboardItem: a copied window's state (with its "windowType"),
/// scripts and variables.
@interface rvGEClipboardItem : NSObject
@property (nonatomic, strong) idDict *stateDict;
@property (nonatomic, strong) idDict *scriptDict;
@property (nonatomic, strong) idDict *varDict;
@end

@implementation rvGEClipboardItem
@end

/// rvGEWorkspace::mClipboard (static: every workspace's)
static NSMutableArray<rvGEClipboardItem *> *UDClipboard(void) {
    static NSMutableArray<rvGEClipboardItem *> *clipboard;
    if ( clipboard == nil ) {
        clipboard = [NSMutableArray array];
    }
    return clipboard;
}

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
        manager.editorWrapperClass = [rvGEWindowWrapper class];
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
    [self mouseDownAtX:x y:y shift:shift below:NO time:time];
}

- (void)mouseDownAtX:(float)x y:(float)y shift:(BOOL)shift below:(BOOL)below time:(int)time {
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
    NSSet<idWindow *> *passing = self.passedWindows;
    if ( self.clickedThroughWindows.count > 0 ) {
        passing = [(passing ?: [NSSet set]) setByAddingObjectsFromSet:self.clickedThroughWindows];
    }
    idWindow *window = [wrapper windowFromPointX:point.x y:point.y visibleOnly:YES passing:passing];

    // (not the engine's: the one below the selected one there, chosen)
    if ( below ) {
        NSArray<idWindow *> *under = [self windowsAtX:x y:y];
        NSUInteger at = NSNotFound;
        for ( NSUInteger i = 0; i < under.count && at == NSNotFound; i++ ) {
            if ( [mSelections isSelected:under[i]] ) {
                at = i;
            }
        }
        window = under.count == 0 ? nil : under[at == NSNotFound ? 0 : (at + 1) % under.count];
        if ( window ) {
            [mSelections set:window];
            self.dragType = HT_MOVE;
            mDragPoint = [self windowToWorkspacePoint:mDragPoint];
            return;
        }
    }

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

        case MOD_DELETE:
            return [[rvGEDeleteModifier alloc] initWithName:@"Delete" window:window];

        case MOD_SEND_BACKWARD:
            return [[rvGEZOrderModifier alloc] initWithName:@"Send Backward" window:window change:ZO_BACKWARD];

        case MOD_SEND_BACK:
            return [[rvGEZOrderModifier alloc] initWithName:@"Send to Back" window:window change:ZO_BACK];

        case MOD_BRING_FORWARD:
            return [[rvGEZOrderModifier alloc] initWithName:@"Bring Forward" window:window change:ZO_FORWARD];

        case MOD_BRING_FRONT:
            return [[rvGEZOrderModifier alloc] initWithName:@"Bring to Front" window:window change:ZO_FRONT];

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
        [rows addObject:@[ [state keyAtIndex:i], rvGE_StripQuotes( [state valueAtIndex:i] ) ]];
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

#pragma mark - GEItemPropsDlg

/*
================
rvGEWorkspace::EditSelectedProperties

The item properties' state applied to the one selected window
================
*/
- (BOOL)applyItemProperties:(idDict *)dict {
    rvGESelectionMgr *mSelections = self.selections;
    if ( ![mSelections num] || [mSelections num] > 1 ) {
        return NO;
    }

    [self.modifiers append:[[rvGEStateModifier alloc] initWithName:@"Item Properties" window:mSelections[0] dict:dict]];
    self.modified = YES;

    return YES;
}

#pragma mark - GEItemScriptsDlg

/*
================
GEItescriptsDlg_Init

Fills the scripts' text from the window's variables and scripts
================
*/
- (NSString *)scriptsTextOf:(idWindow *)window {
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
    NSMutableString *script = [NSMutableString string];
    int i;

    for ( i = 0; i < [wrapper.variableDict numKeyVals]; i ++ ) {
        [script appendString:[wrapper.variableDict keyAtIndex:i]];
        [script appendString:@"\t"];
        [script appendString:[wrapper.variableDict valueAtIndex:i]];
        [script appendString:@"\n"];
    }

    if ( i ) {
        [script appendString:@"\n"];
    }

    for ( i = 0; i < [wrapper.scriptDict numKeyVals]; i ++ ) {
        [script appendFormat:@"%@\n", [wrapper.scriptDict keyAtIndex:i]];
        [script appendString:[wrapper.scriptDict valueAtIndex:i]];
        [script appendString:@"\n\n"];
    }

    return script;
}

/// The first error a parser's diagnostics say, with its line.
static NSString *UDFirstError(NSArray<NSDictionary *> *diagnostics) {
    for ( NSDictionary *d in diagnostics ) {
        if ( [d[@"error"] boolValue] ) {
            return [NSString stringWithFormat:@"line %@: %@", d[@"line"], d[@"message"]];
        }
    }
    return nil;
}

/*
================
GEItescriptsDlg_Apply

Applies the script text to the window's variables and scripts
================
*/
- (BOOL)setScriptsText:(NSString *)parse of:(idWindow *)window message:(NSString **)message {
    idDict *variables = [[idDict alloc] init];
    idDict *scripts = [[idDict alloc] init];
    if ( ![self _readScriptsText:parse variables:variables scripts:scripts message:message] ) {
        return NO;
    }
    [self.modifiers append:[[rvGEScriptsModifier alloc] initWithName:@"Scripts Change" window:window variables:variables scripts:scripts]];
    self.modified = YES;
    return YES;
}

/// (not the engine's) The scripts editor's edits: @a window's variables and
/// scripts as these, one edit named @a name, read as Apply reads its text.
- (BOOL)setScripts:(idDict *)scripts variables:(idDict *)variables of:(idWindow *)window named:(NSString *)name
           message:(NSString **)message {
    NSMutableString *text = [NSMutableString string];
    for ( int i = 0; i < [variables numKeyVals]; i ++ ) {
        [text appendFormat:@"%@\t%@\n", [variables keyAtIndex:i], [variables valueAtIndex:i]];
    }
    for ( int i = 0; i < [scripts numKeyVals]; i ++ ) {
        [text appendFormat:@"%@\n%@\n\n", [scripts keyAtIndex:i], [scripts valueAtIndex:i]];
    }
    idDict *readVariables = [[idDict alloc] init];
    idDict *readScripts = [[idDict alloc] init];
    if ( ![self _readScriptsText:text variables:readVariables scripts:readScripts message:message] ) {
        return NO;
    }
    // each script read as its statements, too: commands the run knows
    for ( int i = 0; i < [readScripts numKeyVals]; i ++ ) {
        NSString *why = nil;
        if ( [[readScripts keyAtIndex:i] caseInsensitiveCompare:@"scriptDef"] != NSOrderedSame &&
             ![rvGEScript statementsFromText:[readScripts valueAtIndex:i] message:&why] ) {
            if ( message ) *message = [NSString stringWithFormat:@"%@: %@", [readScripts keyAtIndex:i], why];
            return NO;
        }
    }
    [self.modifiers append:[[rvGEScriptsModifier alloc] initWithName:name window:window variables:readVariables scripts:readScripts]];
    self.modified = YES;
    return YES;
}

/// GEItescriptsDlg_Apply's reading: @a parse's variables and scripts.
- (BOOL)_readScriptsText:(NSString *)parse variables:(idDict *)variables scripts:(idDict *)scripts message:(NSString **)message {

    NSData *bytes __attribute__((objc_precise_lifetime)) = [parse ud_latin1Buffer];
    // the engine's parser throws on an error; this one says so (in its
    // diagnostics, given before the text is loaded)
    idParser *src = [[idParser alloc] initWithFlags:LEXFL_ALLOWMULTICHARLITERALS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                         fileSystem:nil];
    NSMutableArray<NSDictionary *> *diagnostics = [NSMutableArray array];
    src.diagnostics = diagnostics;
    [src loadMemory:bytes.bytes length:(int)bytes.length - 1 name:@"" error:NULL];
    idToken token;
    idToken_Init( &token );

    #define UDFAIL(text) do { if ( message ) *message = (text); return NO; } while (0)

    while ( [src readToken:&token error:NULL] ) {
        NSString *scriptName = nil;
        NSMutableString *out = [NSMutableString string];
        NSString *tokenString = UDTokenLatin1String( &token );

        if ( UDTokenIcmp( &token, "definevec4" ) ) {
            idToken token2;
            idToken_Init( &token2 );

            if ( ![src readToken:&token2 error:NULL] ) {
                UDFAIL( @"expected define name" );
            }

            idWinVec4 *var = [[idWinVec4 alloc] init];
            idWindow *tempwin = [[idWindow alloc] initWithGui:self.interface];
            int i;

            [src setMarker];
            for ( i = 0; i < 3; i ++ ) {
                [tempwin parseExpression:src var:var component:0];
                [src expectTokenString:@"," error:NULL];
            }
            [tempwin parseExpression:src var:var component:0];
            [src stringFromMarker:out clean:YES error:NULL];
            if ( UDFirstError( diagnostics ) ) UDFAIL( UDFirstError( diagnostics ) );

            [variables set:[NSString stringWithFormat:@"%@\t\"%@\"", tokenString, UDTokenLatin1String( &token2 )] value:out];
            continue;
        }
        else if ( UDTokenIcmp( &token, "definefloat" ) || UDTokenIcmp( &token, "float" ) ) {
            idToken token2;
            idToken_Init( &token2 );

            if ( ![src readToken:&token2 error:NULL] ) {
                UDFAIL( @"expected define name" );
            }

            idWinFloat *var = [[idWinFloat alloc] init];
            idWindow *tempwin = [[idWindow alloc] initWithGui:self.interface];

            [src setMarker];
            [tempwin parseExpression:src var:var component:0];
            [src stringFromMarker:out clean:YES error:NULL];
            if ( UDFirstError( diagnostics ) ) UDFAIL( UDFirstError( diagnostics ) );

            [variables set:[NSString stringWithFormat:@"%@\t\"%@\"", tokenString, UDTokenLatin1String( &token2 )] value:out];
            continue;
        }
        // If the token is a scriptdef then just parse out the
        // braced section and add it to the list.  Right now only
        // one scriptdef per window is supported
        else if ( UDTokenIcmp( &token, "scriptdef" ) ) {
            scriptName = @"scriptDef";
        }
        else if ( UDTokenIcmp( &token, "ontime" ) ) {
            if ( ![src readToken:&token error:NULL] ) {
                UDFAIL( @"expected time" );
            }
            scriptName = [@"onTime " stringByAppendingString:UDTokenLatin1String( &token )];
        }
        // (the engine's "onEvent"; Parse's onNamedEvent, which the wrapper keeps)
        else if ( UDTokenIcmp( &token, "onevent" ) || UDTokenIcmp( &token, "onnamedevent" ) ) {
            if ( ![src readToken:&token error:NULL] ) {
                UDFAIL( @"expected time" );
            }
            scriptName = [@"onNamedEvent " stringByAppendingString:UDTokenLatin1String( &token )];
        }
        else {
            int i;
            for ( i = 0; i < SCRIPT_COUNT; i ++ ) {
                if ( [idWindow_ScriptNames[i] ud_iequals:tokenString] ) {
                    scriptName = idWindow_ScriptNames[i];
                    break;
                }
            }

            if ( i >= SCRIPT_COUNT ) {
                UDFAIL( ([NSString stringWithFormat:@"expected script name, not '%@'", tokenString]) );
            }
        }

        if ( ![src parseBracedSectionExact:out tabs:1 error:NULL] || UDFirstError( diagnostics ) ) {
            UDFAIL( UDFirstError( diagnostics ) ?: ([NSString stringWithFormat:@"%@: expected a braced script", scriptName]) );
        }

        [scripts set:scriptName value:out];
    }
    #undef UDFAIL

    return YES;
}

#pragma mark - The editor's commands

- (void)deleteSelected {
    [self addModifierToSelection:MOD_DELETE];
    [self.selections clear];
}

/*
================
rvGEWorkspace::NewWindow

Create a new window
================
*/
- (idWindow *)newWindow:(idDict *)state type:(rvGEWindowType)type {
    idWindow *desktop = [self.interface getDesktop];
    idDeviceContext *dc = [desktop getDC];
    idWindow *window;
    rvGEWindowWrapper *wrapper;
    int count;
    NSString *baseName;

    switch ( type ) {
        case WT_NORMAL:
            window = [[idWindow alloc] initWithDC:dc gui:self.interface];
            break;

        case WT_BIND:
            window = [[idBindWindow alloc] initWithDC:dc gui:self.interface];
            break;

        case WT_RENDER:
            window = [[idRenderWindow alloc] initWithDC:dc gui:self.interface];
            break;

        case WT_CHOICE:
            window = [[idChoiceWindow alloc] initWithDC:dc gui:self.interface];
            break;

        case WT_EDIT:
            window = [[idEditWindow alloc] initWithDC:dc gui:self.interface];
            break;

        // not in the engine, whose Paste of a copied slider or list came here
        // to an assert and a NULL window
        case WT_SLIDER:
            window = [[idSliderWindow alloc] initWithDC:dc gui:self.interface];
            break;

        case WT_LIST:
            window = [[idListWindow alloc] initWithDC:dc gui:self.interface];
            break;

        default:
            return nil;
    }

    baseName = state ? [state getString:@"name" defaultString:@"unnamed"] : @"unnamed";
    if ( [baseName hasPrefix:@"\""] ) {
        // idStr::StripQuotes
        NSUInteger end = baseName.length;
        if ( end > 1 && [baseName characterAtIndex:end - 1] == '"' ) end--;
        baseName = [baseName substringWithRange:NSMakeRange(1, end - 1)];
    }

    count = 0;
    if ( [desktop findChildByName:baseName] ) {
        count = 1;
        while ( 1 ) {
            idDrawWin *dw = [desktop findChildByName:[NSString stringWithFormat:@"%@%d", baseName, count]];
            if ( !dw ) {
                break;
            }
            wrapper = [rvGEWindowWrapper wrapperOf:dw.win];
            if ( wrapper && wrapper.deleted ) {
                break;
            }
            count++;
        }
    }

    NSString *winName = count ? [NSString stringWithFormat:@"%@%d", baseName, count] : baseName;
    NSString *winTemplate = [winName stringByAppendingString:@" { }"];

    NSData *bytes __attribute__((objc_precise_lifetime)) = [winTemplate ud_latin1Buffer];
    idParser *src = [[idParser alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:@""
                                               flags:LEXFL_ALLOWMULTICHARLITERALS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                               error:NULL];
    [window parse:src rebuild:YES];

    wrapper = [rvGEWindowWrapper wrapperOf:window];
    if ( state ) {
        [wrapper setState:state];
    }

    [wrapper setStateKey:@"name" value:winName update:YES];
    [wrapper finish];

    self.modified = YES;

    return window;
}

- (idWindow *)addWindow:(rvGEWindowType)type {
    idWindow *window;
    idDict *state = [[idDict alloc] init];

    [state set:@"rect" value:@"0,0,100,100"];
    [state set:@"visible" value:@"1"];

    window = [self newWindow:state type:type];
    if ( !window ) {
        return nil;
    }

    [self.modifiers append:[[rvGEInsertModifier alloc] initWithName:@"New" window:window parent:[self.interface getDesktop] before:nil]];
    [self.selections set:window];

    return window;
}

- (void)bringSelectedForward {
    [self addModifierToSelection:MOD_BRING_FORWARD];
}

- (void)bringSelectedToFront {
    [self addModifierToSelection:MOD_BRING_FRONT];
}

- (void)sendSelectedToBack {
    [self addModifierToSelection:MOD_SEND_BACK];
}

- (void)sendSelectedBackward {
    [self addModifierToSelection:MOD_SEND_BACKWARD];
}

/*
================
rvGEWorkspace::MakeSelectedSameSize

Align the selected items to the first one using the given align type
================
*/
- (void)makeSelectedSameSizeWidth:(BOOL)changeWidth height:(BOOL)changeHeight {
    rvGESelectionMgr *mSelections = self.selections;
    if ( [mSelections num] < 2 ) {
        return;
    }
    rvGEModifierGroup *group = [[rvGEModifierGroup alloc] init];
    idRectangle rectTo = [rvGEWindowWrapper wrapperOf:mSelections[0]].clientRect;

    for ( int i = 1; i < [mSelections num]; i ++ ) {
        idRectangle rectFrom;
        float width = 0;
        float height = 0;

        rectFrom = [rvGEWindowWrapper wrapperOf:mSelections[i]].clientRect;

        if ( changeWidth ) {
            width = rectTo.w - rectFrom.w;
        }

        if ( changeHeight ) {
            height = rectTo.h - rectFrom.h;
        }

        [group append:[[rvGESizeModifier alloc] initWithName:@"Make Same Size" window:mSelections[i] l:0 t:0 r:width b:height]];
    }

    [self.modifiers append:group];

    // Cant merge alignments
    [self.modifiers blockNextMerge];

    self.modified = YES;
}

/*
================
rvGEWorkspace::AlignSelected

Align the selected items to the first one using the given align type
================
*/
- (void)alignSelected:(rvGEItemAlign)align {
    static NSString *const alignNames[] = { @"Lefts", @"Centers", @"Rights", @"Tops", @"Middles", @"Bottoms" };
    rvGESelectionMgr *mSelections = self.selections;

    if ( [mSelections num] < 2 ) {
        return;
    }

    NSString *modName = [@"Align " stringByAppendingString:alignNames[align]];
    rvGEModifierGroup *group = [[rvGEModifierGroup alloc] init];

    idRectangle rectTo = [rvGEWindowWrapper wrapperOf:mSelections[0]].screenRect;

    // Everything gets aligned to the first selection so run
    // through all other selections and move them.
    for ( int i = 1; i < [mSelections num]; i ++ ) {
        float x = 0;
        float y = 0;
        idRectangle rectFrom;

        rectFrom = [rvGEWindowWrapper wrapperOf:mSelections[i]].screenRect;

        switch ( align ) {
            case ALIGN_LEFTS:
                x = rectTo.x - rectFrom.x;
                y = 0;
                break;

            case ALIGN_RIGHTS:
                x = (rectTo.x + rectTo.w) - (rectFrom.x + rectFrom.w);
                y = 0;
                break;

            case ALIGN_CENTERS:
                x = (rectTo.x + rectTo.w / 2) - (rectFrom.x + rectFrom.w / 2);
                y = 0;
                break;

            case ALIGN_TOPS:
                y = rectTo.y - rectFrom.y;
                x = 0;
                break;

            case ALIGN_BOTTOMS:
                x = 0;
                y = (rectTo.y + rectTo.h) - (rectFrom.y + rectFrom.h);
                break;

            case ALIGN_MIDDLES:
                x = 0;
                y = (rectTo.y + rectTo.h / 2) - (rectFrom.y + rectFrom.h / 2);
                break;
        }

        [group append:[[rvGEMoveModifier alloc] initWithName:modName window:mSelections[i] x:x y:y]];
    }

    [self.modifiers append:group];

    // Cant merge alignments
    [self.modifiers blockNextMerge];

    self.modified = YES;
}

/*
================
rvGEWorkspace::MakeSelectedAChild

Makes the selected windows a child of the first selected window
================
*/
- (BOOL)makeSelectedAChild {
    rvGESelectionMgr *mSelections = self.selections;
    if ( [mSelections num] < 2 ) {
        return NO;
    }

    if ( ![[rvGEWindowWrapper wrapperOf:mSelections[0]] canHaveChildren] ) {
        // "Cannot add children to an htmlDef item"
        return NO;
    }

    rvGEModifierGroup *group = [[rvGEModifierGroup alloc] init];
    for ( int i = 1; i < [mSelections num]; i ++ ) {
        if ( [mSelections[i] getParent] == mSelections[0] ) {
            continue;
        }

        if ( ![mSelections[i] getParent] ) {
            continue;
        }

        [group append:[[rvGEInsertModifier alloc] initWithName:@"Make Child" window:mSelections[i] parent:mSelections[0] before:nil]];
    }

    [self.modifiers append:group];

    self.modified = YES;
    return YES;
}

- (void)copySelected {
    NSMutableArray<rvGEClipboardItem *> *mClipboard = UDClipboard();
    rvGESelectionMgr *mSelections = self.selections;

    // Clear the current clipboard
    [mClipboard removeAllObjects];

    for ( int i = 0; i < [mSelections num]; i ++ ) {
        rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:mSelections[i]];
        NSAssert( wrapper, @"a wrapped window" );

        rvGEClipboardItem *item = [[rvGEClipboardItem alloc] init];
        item.stateDict = [wrapper.stateDict copy];
        item.scriptDict = [wrapper.scriptDict copy];
        item.varDict = [wrapper.variableDict copy];
        [item.stateDict set:@"windowType" value:[rvGEWindowWrapper stringFromWindowType:wrapper.windowType]];

        [mClipboard addObject:item];
    }
}

- (BOOL)canPaste {
    return UDClipboard().count > 0;
}

- (void)paste {
    NSMutableArray<rvGEClipboardItem *> *mClipboard = UDClipboard();
    rvGESelectionMgr *mSelections = self.selections;
    rvGEModifierGroup *group = [[rvGEModifierGroup alloc] init];

    [mSelections clear];

    for ( rvGEClipboardItem *item in mClipboard ) {
        idDict *state = [item.stateDict copy];
        rvGEWindowType type;

        type = [rvGEWindowWrapper windowTypeFromString:[state getString:@"windowType" defaultString:@"windowDef"]];
        [state deleteKey:@"windowType"];

        idWindow *window = [self newWindow:state type:type];
        if ( !window ) {
            continue;
        }
        [group append:[[rvGEInsertModifier alloc] initWithName:@"Paste" window:window parent:[self.interface getDesktop] before:nil]];
        [mSelections add:window];

        rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
        idDict *scripts = wrapper.scriptDict, *variables = wrapper.variableDict;
        [scripts clear];
        for ( int k = 0; k < [item.scriptDict numKeyVals]; k++ ) [scripts set:[item.scriptDict keyAtIndex:k] value:[item.scriptDict valueAtIndex:k]];
        [variables clear];
        for ( int k = 0; k < [item.varDict numKeyVals]; k++ ) [variables set:[item.varDict keyAtIndex:k] value:[item.varDict valueAtIndex:k]];
    }

    [self.modifiers append:group];

    self.modified = YES;
}

- (void)nudgeX:(float)x y:(float)y size:(BOOL)size {
    if ( ![self.selections num] || [self.selections isExpression] ) {
        return;
    }
    if ( size ) {
        // AddModifierSizeNudge
        [self addModifierSize:@"Nudge Size" l:0 t:0 r:x b:y snap:NO];
    } else {
        // AddModifierMoveNudge
        [self addModifierMove:@"Nudge Move" x:x y:y snap:NO];
    }
}

/*
================
rvGEWorkspace::BuildSelectMenuEnumProc

Builds the list of windows under the point for the select menu
================
*/
- (void)_addWindowsUnder:(idVec2)point of:(rvGEWindowWrapper *)wrapper into:(NSMutableArray<idWindow *> *)menu {
    if ( !wrapper ) {
        return;
    }

    for ( int i = 0; i < [wrapper childCount]; i ++ ) {
        rvGEWindowWrapper *child = [rvGEWindowWrapper wrapperOf:[wrapper childAtIndex:i]];
        // (not the engine's: a window passed through, its children too)
        if ( child && [self.passedWindows containsObject:child.window] ) {
            continue;
        }
        [self _addWindowsUnder:point of:child into:menu];

        if ( !child || child.deleted || child.hidden ) {
            continue;
        }

        idRectangle rect = child.screenRect;
        if ( idRectangle_Contains( &rect, point.x, point.y ) ) {
            [menu addObject:child.window];
        }
    }
}

- (NSArray<idWindow *> *)windowsAtX:(float)x y:(float)y {
    NSMutableArray<idWindow *> *under = [NSMutableArray array];
    idVec2 point = [self windowToWorkspacePoint:idVec2_Make( x, y )];
    rvGEWindowWrapper *desktop = [rvGEWindowWrapper wrapperOf:[self.interface getDesktop]];
    for ( int i = [desktop childCount] - 1; i >= 0; i-- ) {
        [self _addWindowsAt:point of:[rvGEWindowWrapper wrapperOf:[desktop childAtIndex:i]] into:under];
    }
    if ( !self.options.ignoreDesktopSelect && [self.interface getDesktop] ) {
        [under addObject:[self.interface getDesktop]];
    }
    return under;
}

/// @a wrapper's window and its children under @a point, as
/// WindowFromPoint looks: the children front to back, each before its
/// parent.
- (void)_addWindowsAt:(idVec2)point of:(nullable rvGEWindowWrapper *)wrapper into:(NSMutableArray<idWindow *> *)under {
    if ( !wrapper || wrapper.hidden || wrapper.deleted || [self.passedWindows containsObject:wrapper.window] ) {
        return;
    }
    for ( int i = [wrapper childCount] - 1; i >= 0; i-- ) {
        [self _addWindowsAt:point of:[rvGEWindowWrapper wrapperOf:[wrapper childAtIndex:i]] into:under];
    }
    idRectangle rect = wrapper.screenRect;
    if ( idRectangle_Contains( &rect, point.x, point.y ) ) {
        [under addObject:wrapper.window];
    }
}

- (NSArray<idWindow *> *)windowsUnderX:(float)x y:(float)y {
    NSMutableArray<idWindow *> *menu = [NSMutableArray array];
    idVec2 point = [self windowToWorkspacePoint:idVec2_Make( x, y )];

    // Build a list of all the windows under the menu point
    [self _addWindowsUnder:point of:[rvGEWindowWrapper wrapperOf:[self.interface getDesktop]] into:menu];

    // Add the desktop window always
    if ( [self.interface getDesktop] ) {
        [menu addObject:[self.interface getDesktop]];
    }
    return menu;
}

@end
