/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * InspectorIcons.h — Icons for Inspector tabs.
 */

#import <AppKit/AppKit.h>

@interface UDInspectorIcons : NSObject

- (NSImage *)identityInspectorIcon;
- (NSImage *)attributesInspectorIcon;
- (NSImage *)sizeInspectorIcon;
- (NSImage *)connectionsInspectorIcon;
- (NSImage *)effectsInspectorIcon;

- (NSImage *)identityInspectorIconActive;
- (NSImage *)attributesInspectorIconActive;
- (NSImage *)sizeInspectorIconActive;
- (NSImage *)connectionsInspectorIconActive;
- (NSImage *)effectsInspectorIconActive;

@end
