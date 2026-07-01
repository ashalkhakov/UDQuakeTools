/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDInspectableOutlineView.h"

@protocol UDInspectableOutlineViewEditingDelegate <NSObject>
@optional
- (void)beginEditingSelectedWindowIdentity:(id)sender;
@end

@implementation UDInspectableOutlineView

- (void)keyDown:(NSEvent *)event {
    BOOL isReturnKey = event.keyCode == 36 || event.keyCode == 76;
    BOOL isF2Key = event.keyCode == 120;
    if (isReturnKey || isF2Key) {
        id<UDInspectableOutlineViewEditingDelegate> editingDelegate = (id<UDInspectableOutlineViewEditingDelegate>)self.delegate;
        if ([editingDelegate respondsToSelector:@selector(beginEditingSelectedWindowIdentity:)]) {
            [editingDelegate beginEditingSelectedWindowIdentity:self];
            return;
        }
    }

    [super keyDown:event];
}

@end