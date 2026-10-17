/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDTabBadge.h — RDLKit's RDLTabBadge (LGPL 2.1, from the XForms Designer's
 * XFDBadge): a tab bar item's icon, drawn rather than shipped.
 */

#import <AppKit/AppKit.h>

/// A round badge of color @a r @a g @a b carrying one or two letters, for a
/// tab bar item. Cached: the same badge again is free.
NSImage *UDTabBadge(NSString *letters, CGFloat r, CGFloat g, CGFloat b);
