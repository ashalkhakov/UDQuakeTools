/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGETransformer.m
 */

#import "rvGETransformer.h"
#import "rvGEWorkspace.h"
#import "rvGESelectionMgr.h"
#import "rvGEWindowWrapper.h"
#import "idWindow.h"

@implementation rvGETransformer {
    idWindow *__weak mRelative;
}

- (instancetype)initWithWorkspace:(rvGEWorkspace *)workspace {
    self = [super init];
    if (self) {
        _workspace = workspace;
    }
    return self;
}

/// The selection's rect in the workspace, relative to mRelative.
- (idRectangle)_relativeRect {
    rvGEWorkspace *mWorkspace = self.workspace;
    idRectangle rect = [mWorkspace windowToWorkspaceRect:[mWorkspace.selections rect]];

    // The transformer coords are relative to the botto most selected window's parent so
    // adjust the rect accordingly
    idWindow *relative = mRelative;
    if ( relative ) {
        idRectangle screenRect = [rvGEWindowWrapper wrapperOf:relative].screenRect;
        rect.x -= screenRect.x;
        rect.y -= screenRect.y;
    }
    return rect;
}

/*
================
rvGETransformer::Update

Update the enabled/disabled states based on the selections and update
the rectangle coordinates
================
*/
- (BOOL)update:(idRectangle *)rect {
    BOOL state = NO;

    mRelative = nil;

    rvGEWorkspace *mWorkspace = self.workspace;
    if ( mWorkspace && [mWorkspace.selections num] ) {
        state = YES;
        mRelative = [[mWorkspace.selections bottomMost] getParent];

        // Make the rectangle relative to the given parent
        idRectangle r = [self _relativeRect];
        *rect = idRectangle_Make( (int)r.x, (int)r.y, (int)r.w, (int)r.h );
    } else {
        *rect = idRectangle_Make( 0, 0, 0, 0 );
    }

    return state;
}

/*
================
rvGETransformer::WndProc

EN_KILLFOCUS: the edited field applied
================
*/
- (void)setField:(rvGETransformerField)field value:(int)value {
    rvGEWorkspace *mWorkspace = self.workspace;
    if ( !mWorkspace || ![mWorkspace.selections num] ) {
        return;
    }
    mRelative = [[mWorkspace.selections bottomMost] getParent];

    idRectangle rect = [self _relativeRect];

    switch ( field ) {
        case rvGETransformerX:
            if ( value - rect.x ) {
                [mWorkspace addModifierMove:@"Transform Move" x:value - rect.x y:0 snap:NO];
            }
            break;

        case rvGETransformerY:
            if ( value - rect.y ) {
                [mWorkspace addModifierMove:@"Transform Move" x:0 y:value - rect.y snap:NO];
            }
            break;

        case rvGETransformerW:
            if ( value - rect.w ) {
                [mWorkspace addModifierSize:@"Transform Size" l:0 t:0 r:value - rect.w b:0 snap:NO];
            }
            break;

        case rvGETransformerH:
            if ( value - rect.h ) {
                [mWorkspace addModifierSize:@"Transform Size" l:0 t:0 r:0 b:value - rect.h snap:NO];
            }
            break;
    }
}

@end
