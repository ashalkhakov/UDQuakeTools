/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDInspectableTableView : NSTableView

- (void)beginEditingSelectedCell;

@end

NS_ASSUME_NONNULL_END