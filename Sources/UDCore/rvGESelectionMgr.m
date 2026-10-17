/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGESelectionMgr.m — tools/guied/GESelectionMgr.cpp, ported.
 */

#import "rvGESelectionMgr.h"
#import "rvGEWindowWrapper.h"
#import "rvGEWorkspace.h"
#import "rvGEOptions.h"
#import "UDOverlay.h"
#import "idWindow.h"

NSNotificationName const rvGESelectionDidChangeNotification = @"rvGESelectionDidChange";

@implementation rvGESelectionMgr {
    NSMutableArray<idWindow *> *mSelections;
    idRectangle mRect;
    BOOL mExpression;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        mSelections = [NSMutableArray array];
    }
    return self;
}

- (NSArray<idWindow *> *)windows {
    return [mSelections copy];
}

- (int)num {
    return (int)mSelections.count;
}

- (idWindow *)objectAtIndexedSubscript:(NSUInteger)index {
    NSAssert(index < mSelections.count, @"a selection");
    return mSelections[index];
}

- (BOOL)isSelected:(idWindow *)window {
    return [mSelections indexOfObjectIdenticalTo:window] != NSNotFound;
}

- (BOOL)isExpression {
    return mExpression;
}

- (idRectangle)rect {
    [self updateRectangle];
    return mRect;
}

/// gApp's navigator, transformer and properties told.
- (void)_changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:rvGESelectionDidChangeNotification object:self];
}

/*
================
rvGESelectionMgr::SetSelection

Sets the only selection for the workspace to the given window
================
*/
- (void)set:(idWindow *)window {
    // Get rid of any current selections
    [self clear];

    // Add this selection now
    [self add:window];
}

- (void)add:(idWindow *)window {
    [self add:window expand:YES];
}

/*
================
rvGESelectionMgr::Add

Adds the given window to the selection list
================
*/
- (void)add:(idWindow *)window expand:(BOOL)expand {
    rvGEWindowWrapper *wrapper;

    wrapper = [rvGEWindowWrapper wrapperOf:window];
    NSAssert(wrapper, @"a wrapped window");

    // If the window is already selected then dont add the selection
    if ( wrapper.selected ) {
        return;
    }

    wrapper.selected = YES;

    [mSelections addObject:window];

    if ( expand ) {
        [wrapper expand];
    }

    [self updateExpression];
    [self _changed];
}

/*
================
rvGESelectionMgr::RemoveSelection

Removes the selection from the current workspace
================
*/
- (void)remove:(idWindow *)window {
    rvGEWindowWrapper *wrapper;

    wrapper = [rvGEWindowWrapper wrapperOf:window];
    NSAssert(wrapper, @"a wrapped window");

    // Dont bother if the window isnt selectd already
    if ( !wrapper.selected ) {
        return;
    }

    wrapper.selected = NO;

    [mSelections removeObjectIdenticalTo:window];

    [self updateExpression];
    [self _changed];
}

/*
================
rvGESelectionMgr::ClearSelections

Remove all of the current selections
================
*/
- (void)clear {
    for ( idWindow *window in mSelections ) {
        [rvGEWindowWrapper wrapperOf:window].selected = NO;
    }

    [mSelections removeAllObjects];

    mExpression = NO;
    [self _changed];
}

/*
================
rvGESelectionMgr::Render

Render the selections including the move/size bars
================
*/
- (void)renderInto:(UDOverlay *)overlay {
    if ( !mSelections.count ) {
        return;
    }

    [self updateRectangle];

    idVec4 color = self.workspace.options.selectionColor;
    idVec4 opaque = idVec4_Make( color.x, color.y, color.z, 1.0f );
    [overlay addLineLoopX0:mRect.x y0:mRect.y x1:mRect.x + mRect.w y1:mRect.y
                        x2:mRect.x + mRect.w y2:mRect.y + mRect.h x3:mRect.x y3:mRect.y + mRect.h color:opaque];

    idVec4 faded = idVec4_Make( color.x, color.y, color.z, 0.75f );

    for ( NSUInteger i = 0; i < mSelections.count; i ++ ) {
        rvGEWindowWrapper *wrapper;
        idRectangle rect;

        wrapper = [rvGEWindowWrapper wrapperOf:mSelections[i]];
        NSAssert(wrapper, @"a wrapped window");

        rect = [self.workspace workspaceToWindowRect:wrapper.screenRect];

        if ( i == 0 ) {
            [overlay addTriangleX0:rect.x y0:rect.y x1:rect.x + GUIED_GRABSIZE y1:rect.y x2:rect.x y2:rect.y + GUIED_GRABSIZE color:faded];
        }

        [overlay addLineLoopX0:rect.x y0:rect.y x1:rect.x + rect.w y1:rect.y
                            x2:rect.x + rect.w y2:rect.y + rect.h x3:rect.x y3:rect.y + rect.h color:faded];

        [overlay addQuadX0:rect.x + (rect.w - GUIED_CENTERSIZE) / 2 y0:rect.y + (rect.h - GUIED_CENTERSIZE) / 2
                        x1:rect.x + (rect.w + GUIED_CENTERSIZE) / 2 y1:rect.y + (rect.h - GUIED_CENTERSIZE) / 2
                        x2:rect.x + (rect.w + GUIED_CENTERSIZE) / 2 y2:rect.y + (rect.h + GUIED_CENTERSIZE) / 2
                        x3:rect.x + (rect.w - GUIED_CENTERSIZE) / 2 y3:rect.y + (rect.h + GUIED_CENTERSIZE) / 2 color:faded];
    }

    if ( mExpression ) {
        return;
    }

    // the handles, as GL_POLYGON_MODE GL_LINE quads
    const float g = GUIED_GRABSIZE;
    const float hg = (float)(GUIED_GRABSIZE / 2);      // (an int's half, as the engine's)
    float x = mRect.x, y = mRect.y, w = mRect.w, h = mRect.h;
    // Top Left
    [overlay addLineLoopX0:x - g y0:y - g x1:x - 1 y1:y - g x2:x - 1 y2:y - 1 x3:x - g y3:y - 1 color:opaque];
    // Left
    [overlay addLineLoopX0:x - g y0:y + h / 2 - hg x1:x - 1 y1:y + h / 2 - hg x2:x - 1 y2:y + h / 2 + hg x3:x - g y3:y + h / 2 + hg color:opaque];
    // Bototm Left
    [overlay addLineLoopX0:x - g y0:y + h + 1 x1:x - 1 y1:y + h + 1 x2:x - 1 y2:y + h + g x3:x - g y3:y + h + g color:opaque];
    // Bottom
    [overlay addLineLoopX0:x - hg + w / 2 y0:y + h + 1 x1:x + hg + w / 2 y1:y + h + 1 x2:x + hg + w / 2 y2:y + h + g x3:x - hg + w / 2 y3:y + h + g color:opaque];
    // Bottom Right
    [overlay addLineLoopX0:x + w + 1 y0:y + h + 1 x1:x + w + g y1:y + h + 1 x2:x + w + g y2:y + h + g x3:x + w + 1 y3:y + h + g color:opaque];
    // Right
    [overlay addLineLoopX0:x + w + 1 y0:y + h / 2 - hg x1:x + w + g y1:y + h / 2 - hg x2:x + w + g y2:y + h / 2 + hg x3:x + w + 1 y3:y + h / 2 + hg color:opaque];
    // Top Right
    [overlay addLineLoopX0:x + w + 1 y0:y - g x1:x + w + g y1:y - g x2:x + w + g y2:y - 1 x3:x + w + 1 y3:y - 1 color:opaque];
    // Top
    [overlay addLineLoopX0:x - hg + w / 2 y0:y - g x1:x + hg + w / 2 y1:y - g x2:x + hg + w / 2 y2:y - 1 x3:x - hg + w / 2 y3:y - 1 color:opaque];
}

/*
================
rvGESelectionMgr::UpdateRectangle

Update the selection rectangle from all the currently selected items.
================
*/
- (void)updateRectangle {
    NSAssert(self.workspace, @"a selection's workspace");

    if ( mSelections.count <= 0 ) {
        return;
    }

    // Start with the first selections retangle
    mRect = [rvGEWindowWrapper wrapperOf:mSelections[0]].screenRect;

    // Its easier to do the calculates with it being top left and bottom right
    // so temporarly convert width and height to right and bottom
    mRect.w += mRect.x;
    mRect.h += mRect.y;

    // Merge all the rest of the rectangles to make the actual selection rectangle
    for ( NSUInteger i = 1; i < mSelections.count; i ++ ) {
        idRectangle selRect;
        selRect = [rvGEWindowWrapper wrapperOf:mSelections[i]].screenRect;

        mRect.w = MAX(selRect.x + selRect.w, mRect.w);
        mRect.h = MAX(selRect.y + selRect.h, mRect.h);
        mRect.x = MIN(selRect.x, mRect.x);
        mRect.y = MIN(selRect.y, mRect.y);
    }

    mRect.w -= mRect.x;
    mRect.h -= mRect.y;

    mRect = [self.workspace workspaceToWindowRect:mRect];
}

/*
================
rvGESelectionMgr::UpdateExpression

Update whether or not the selection has an expression in it
================
*/
- (void)updateExpression {
    mExpression = NO;
    for ( idWindow *window in mSelections ) {
        rvGEWindowWrapper *wrapper;
        wrapper = [rvGEWindowWrapper wrapperOf:window];
        if ( wrapper && ![wrapper canMoveAndSize] ) {
            mExpression = YES;
            break;
        }
    }
}

static BOOL UDRectContains(float rx, float ry, float rw, float rh, float x, float y) {
    idRectangle r = idRectangle_Make( rx, ry, rw, rh );
    return idRectangle_Contains( &r, x, y );
}

/*
================
rvGESelectionMgr::HitTest

Test to see if the given coordinate is within the selection rectangle and if it is
see what its over.
================
*/
- (rvGEHitTest)hitTestX:(float)x y:(float)y {
    if ( !mSelections.count ) {
        return HT_NONE;
    }

    [self updateRectangle];

    // Inside the rectangle is moving
    if ( idRectangle_Contains( &mRect, x, y ) ) {
        return mExpression ? HT_SELECT : HT_MOVE;
    }

    if ( mExpression ) {
        return HT_NONE;
    }

    const float g = GUIED_GRABSIZE;
    const float hg = (float)(GUIED_GRABSIZE / 2);

    // Check for top left sizing
    if ( UDRectContains( mRect.x - g, mRect.y - g, g, g, x, y ) ) {
        return HT_SIZE_TOPLEFT;
    }

    // Check for left sizing
    if ( UDRectContains( mRect.x - g, mRect.y + mRect.h / 2 - hg, g, g, x, y ) ) {
        return HT_SIZE_LEFT;
    }

    // Check for bottom left sizing
    if ( UDRectContains( mRect.x - g, mRect.y + mRect.h, g, g, x, y ) ) {
        return HT_SIZE_BOTTOMLEFT;
    }

    // Check for bottom sizing
    if ( UDRectContains( mRect.x + mRect.w / 2 - hg, mRect.y + mRect.h, g, g, x, y ) ) {
        return HT_SIZE_BOTTOM;
    }

    // Check for bottom right sizing
    if ( UDRectContains( mRect.x + mRect.w, mRect.y + mRect.h, g, g, x, y ) ) {
        return HT_SIZE_BOTTOMRIGHT;
    }

    // Check for right sizing
    if ( UDRectContains( mRect.x + mRect.w, mRect.y + mRect.h / 2 - hg, g, g, x, y ) ) {
        return HT_SIZE_RIGHT;
    }

    // Check for top right sizing
    if ( UDRectContains( mRect.x + mRect.w, mRect.y - g, g, g, x, y ) ) {
        return HT_SIZE_TOPRIGHT;
    }

    // Check for top sizing
    if ( UDRectContains( mRect.x + mRect.w / 2 - hg, mRect.y - g, g, g, x, y ) ) {
        return HT_SIZE_TOP;
    }

    return HT_NONE;
}

/*
================
rvGESelectionMgr::GetBottomMost

Returns the bottom most selected window.
================
*/
- (idWindow *)bottomMost {
    idWindow *bottom;
    int depth;

    depth = 9999;
    bottom = nil;

    // Loop through all the selections and find the bottom most window
    for ( idWindow *window in mSelections ) {
        idWindow *parent;
        int tempDepth;

        // Calculate the depth of the window by iterating back through the windows parents
        for ( tempDepth = 0, parent = window; parent; parent = [parent getParent], tempDepth++ );

        // If the new depth is less than the current depth then this window is below
        if ( tempDepth < depth ) {
            depth = tempDepth;
            bottom = window;
        }
    }

    return bottom;
}

@end
