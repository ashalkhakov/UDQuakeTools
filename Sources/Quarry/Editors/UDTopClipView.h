/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDTopClipView.h — an inspector column's clip view: flipped, so a column
 * shorter than the pane sits at its top, not its bottom (its document view,
 * not flipped, lays itself out as before).
 */

#import <AppKit/AppKit.h>

@interface UDTopClipView : NSClipView
@end
