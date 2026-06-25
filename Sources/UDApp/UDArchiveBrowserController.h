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

NS_ASSUME_NONNULL_BEGIN

@interface UDArchiveBrowserController : NSWindowController <NSBrowserDelegate> {
    IBOutlet NSBrowser    *_browser;
    IBOutlet NSTextField  *_statusLabel;
    IBOutlet NSButton     *_addButton;
    IBOutlet NSButton     *_deleteButton;
    IBOutlet NSButton     *_extractButton;
    IBOutlet NSButton     *_openButton;

    UDArchiveDocument *_archiveDocument;
    UDDirectoryNode   *_rootNode;
}

@property (nonatomic, weak) IBOutlet NSBrowser    *browser;
@property (nonatomic, weak) IBOutlet NSTextField  *statusLabel;
@property (nonatomic, weak) IBOutlet NSButton     *addButton;
@property (nonatomic, weak) IBOutlet NSButton     *deleteButton;
@property (nonatomic, weak) IBOutlet NSButton     *extractButton;
@property (nonatomic, weak) IBOutlet NSButton     *openButton;

- (instancetype)initWithDocument:(UDArchiveDocument *)document;

/* ------------------------------------------------------------------ */
#pragma mark - IBActions

- (IBAction)addFile:(id)sender;
- (IBAction)deleteSelected:(id)sender;
- (IBAction)extractSelected:(id)sender;
- (IBAction)openSelected:(id)sender;

@end

NS_ASSUME_NONNULL_END
