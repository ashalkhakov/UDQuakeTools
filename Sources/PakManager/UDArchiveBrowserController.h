/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDArchiveBrowserController — NSWindowController + NSBrowserDelegate.
 *
 * Manages the archive browser window.  Builds a UDDirectoryNode tree from
 * the document's editor and feeds it to an NSBrowser for navigation.
 * Handles Add / Delete / Extract / Open file operations.
 */

#import <AppKit/AppKit.h>

@class UDArchiveDocument;
@class UDDirectoryNode;
@class UDTextPreviewController;
@class UDGame;
@class UDGameDetectionService;
@class UDFileActionService;

NS_ASSUME_NONNULL_BEGIN

@interface UDArchiveBrowserController : NSWindowController <NSBrowserDelegate> {
    __weak IBOutlet NSBrowser    *_browser;
    __weak IBOutlet NSTextField  *_statusLabel;
    __weak IBOutlet NSButton     *_addButton;
    __weak IBOutlet NSButton     *_deleteButton;
    __weak IBOutlet NSButton     *_extractButton;
    __weak IBOutlet NSButton     *_openButton;
    __weak IBOutlet NSPopUpButton *_gamePopUpButton;
    __weak IBOutlet NSSearchField *_searchField;

    UDArchiveDocument *_archiveDocument;
    UDDirectoryNode   *_rootNode;

    UDGame                  *_activeGame;
    UDGame                  *_detectedGame;
    UDTextPreviewController *_activeTextPreview;

    UDGameDetectionService  *_gameDetectionService;
    UDFileActionService     *_fileActionService;
    NSString                *_searchString;
}

@property (nonatomic, weak) IBOutlet NSBrowser    *browser;
@property (nonatomic, weak) IBOutlet NSTextField  *statusLabel;
@property (nonatomic, weak) IBOutlet NSButton     *addButton;
@property (nonatomic, weak) IBOutlet NSButton     *deleteButton;
@property (nonatomic, weak) IBOutlet NSButton     *extractButton;
@property (nonatomic, weak) IBOutlet NSButton     *openButton;
@property (nonatomic, weak) IBOutlet NSPopUpButton *gamePopUpButton;
@property (nonatomic, weak) IBOutlet NSSearchField *searchField;

- (instancetype)initWithDocument:(UDArchiveDocument *)document;

/* ------------------------------------------------------------------ */
#pragma mark - IBActions

- (IBAction)addFile:(id)sender;
- (IBAction)deleteSelected:(id)sender;
- (IBAction)extractSelected:(id)sender;
- (IBAction)openSelected:(id)sender;
- (IBAction)gameChanged:(id)sender;

@end

NS_ASSUME_NONNULL_END
