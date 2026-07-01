/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDInspectableTableView.h"

@implementation UDInspectableTableView

- (void)keyDown:(NSEvent *)event {
    BOOL isReturnKey = event.keyCode == 36 || event.keyCode == 76;
    BOOL isF2Key = event.keyCode == 120;
    if (isReturnKey || isF2Key) {
        [self beginEditingSelectedCell];
        return;
    }

    [super keyDown:event];
}

- (void)beginEditingSelectedCell {
    NSInteger row = self.selectedRow;
    NSInteger column = self.selectedColumn;
    if (row < 0) {
        return;
    }
    if (column < 0) {
        column = 0;
    }

    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self editColumn:column row:row withEvent:nil select:YES];
    }];
}

@end