/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl Browser window controller.
 */

#import <AppKit/AppKit.h>

@class UDDeclModel;
@class UDDeclBrowserViewModel;
@class UDGame;

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclBrowserWindowController : NSWindowController <NSBrowserDelegate, NSSearchFieldDelegate> {
    __unsafe_unretained IBOutlet NSSearchField *_searchField;
    __unsafe_unretained IBOutlet NSPopUpButton *_gamePopUpButton;
    __unsafe_unretained IBOutlet NSBrowser *_browser;
    __unsafe_unretained IBOutlet NSTextField *_statusLabel;
    __unsafe_unretained IBOutlet NSTextField *_pathLabel;
    __unsafe_unretained IBOutlet NSTextView *_bodyView;

    UDDeclBrowserViewModel *_viewModel;
}

@property (nonatomic, unsafe_unretained) IBOutlet NSSearchField *searchField;
@property (nonatomic, unsafe_unretained) IBOutlet NSPopUpButton *gamePopUpButton;
@property (nonatomic, unsafe_unretained) IBOutlet NSBrowser *browser;
@property (nonatomic, unsafe_unretained) IBOutlet NSTextField *statusLabel;
@property (nonatomic, unsafe_unretained) IBOutlet NSTextField *pathLabel;
@property (nonatomic, unsafe_unretained) IBOutlet NSTextView *bodyView;

- (void)reloadFromDirectoryURL:(nullable NSURL *)directoryURL;

- (IBAction)searchChanged:(id)sender;
- (IBAction)gameChanged:(id)sender;
- (IBAction)openFolder:(id)sender;

@end

NS_ASSUME_NONNULL_END
