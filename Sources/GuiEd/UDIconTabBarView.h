/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * IconTabBarView.h
 * Inspector-style icon tab bar (like Xcode inspector sidebar).
 * Drop in XIB, set icons, connect to an NSTabView (hidden tabs).
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
 
@protocol UDIconTabBarDelegate <NSObject>
@optional
- (void)iconTabBar:(id)sender didSelectTabAtIndex:(NSInteger)index;
@end
 
@interface UDIconTabBarView : NSView
 
// Configuration
@property (nonatomic, copy) NSArray<NSImage *> *icons;           // Normal icons (one per tab)
@property (nonatomic, copy) NSArray<NSImage *> *alternateIcons;  // Optional active/highlighted icons
@property (nonatomic) BOOL vertical;                             // YES = vertical sidebar (default), NO = horizontal
@property (nonatomic) CGFloat iconSize;                          // Default ~32pt
@property (nonatomic) CGFloat spacing;                           // Between buttons
@property (nonatomic, weak) IBOutlet NSTabView *contentTabView;  // Connect hidden NSTabView for content switching
@property (nonatomic, weak) id<UDIconTabBarDelegate> delegate;
 
// Selection
@property (nonatomic) NSInteger selectedIndex;
 
- (void)setupWithIcons:(NSArray<NSImage *> *)icons;  // Convenience
- (void)selectTabAtIndex:(NSInteger)index;
 
@end

NS_ASSUME_NONNULL_END
