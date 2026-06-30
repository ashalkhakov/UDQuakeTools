/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDArchiveBrowserController.h"
#import "UDArchiveDocument.h"
#import "UDArchiveEditor.h"
#import "UDArchiveEntry.h"
#import "UDDirectoryNode.h"
#import "UDStagedFileSource.h"
#import "UDArchive.h"
#import "UDTextPreviewController.h"
#import "UDArchiveCodec.h"
#import "UDGame.h"
#import "UDGameDetectionService.h"
#import "UDFileActionService.h"

/* ------------------------------------------------------------------ */
#pragma mark - Private interface

@interface UDArchiveBrowserController ()
/** Returns the UDDirectoryNode that *owns* column c (i.e. the parent node
 *  whose children fill that column).  Column 0 is owned by the root node. */
- (nullable id)_nodeForColumn:(NSInteger)column;
/** Returns the child object (UDDirectoryNode or UDArchiveEntry) that is
 *  currently selected, searching from the rightmost loaded column leftward. */
- (nullable id)_selectedChild;
- (nullable NSString *)_selectedPath;
- (BOOL)_selectedIsLeaf;
/** The archive directory path that new files should be placed into. */
- (NSString *)_currentDirectoryPath;
- (void)_reloadBrowser;
- (void)_updateStatusAndButtons;
/** Returns "entry" or "entries" for a given count. */
- (NSString *)_entryPluralSuffix:(NSUInteger)count;
- (void)_addFileAtURL:(NSURL *)fileURL;
- (void)_extractEntryAtPath:(NSString *)archivePath toURL:(NSURL *)destURL;
- (void)_extractDirectoryAtPath:(NSString *)dirPath toDirectoryURL:(NSURL *)destDir;
- (void)_detectGame;
- (void)_addDirectoryAtURL:(NSURL *)directoryURL;
- (nullable NSString *)_promptForNameWithTitle:(NSString *)title
                                  informative:(NSString *)informative
                                  defaultName:(NSString *)defaultName;
@end

/* ------------------------------------------------------------------ */

@implementation UDArchiveBrowserController

@synthesize browser         = _browser;
@synthesize statusLabel     = _statusLabel;
@synthesize addButton       = _addButton;
@synthesize deleteButton    = _deleteButton;
@synthesize extractButton   = _extractButton;
@synthesize openButton      = _openButton;
@synthesize gamePopUpButton = _gamePopUpButton;
@synthesize searchField     = _searchField;

/* ------------------------------------------------------------------ */
#pragma mark - Init

- (instancetype)initWithDocument:(UDArchiveDocument *)document {
    self = [super initWithWindowNibName:@"UDArchiveDocument"];
    if (!self) {
        return nil;
    }
    _archiveDocument = document;
    _gameDetectionService = [[UDGameDetectionService alloc] init];
    _fileActionService = [[UDFileActionService alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_archiveEditorDidChange:)
                                                 name:UDArchiveEditorDidChangeNotification
                                               object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* ------------------------------------------------------------------ */
#pragma mark - Window lifecycle

- (void)windowDidLoad {
    [super windowDidLoad];

    /* Wire up target/action for double-click programmatically. */
    [_browser setTarget:self];
    [_browser setDoubleAction:@selector(openSelected:)];

    /* Configure browser display. */
    [_browser setMaxVisibleColumns:4];
    [_browser setMinColumnWidth:120];
    [_browser setAllowsEmptySelection:YES];
    [_browser setAllowsMultipleSelection:NO];
    [_browser setSeparatesColumns:YES];
    [_browser setTitled:YES];

    /* Auto detect game and set popup item title */
    [self _detectGame];
    _activeGame = _detectedGame;
    if (_gamePopUpButton) {
        [[_gamePopUpButton itemAtIndex:0] setTitle:[NSString stringWithFormat:@"Auto Detect (%@)", _detectedGame.displayName]];
    }

    /* Populate the tree. */
    [self _reloadBrowser];
}

- (void)searchChanged:(id)sender {
    _searchString = [sender stringValue];
    [self _reloadBrowser];
}

- (void)_archiveEditorDidChange:(NSNotification *)notification {
    if (notification.object != _archiveDocument.editor) {
        return;
    }
    [self _reloadBrowserPreservingSelection];
}

/* ------------------------------------------------------------------ */
#pragma mark - Tree management

/**
 * Full reset: rebuilds _rootNode and reloads from column zero.
 * Use for initial load and search-filter changes.
 */
- (void)_reloadBrowser {
    UDDirectoryNode *liveRoot = _archiveDocument.editor ? _archiveDocument.editor.currentRoot : nil;
    NSArray *entries = liveRoot ? [liveRoot allEntries] : @[];
    if (_searchString && _searchString.length > 0) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (UDArchiveEntry *entry in entries) {
            NSRange r = [entry.path rangeOfString:_searchString options:NSCaseInsensitiveSearch];
            if (r.location != NSNotFound) {
                [filtered addObject:entry];
            }
        }
        _rootNode = [UDDirectoryNode rootNodeFromEntries:filtered];
    } else {
        _rootNode = liveRoot ?: [UDDirectoryNode rootNode];
    }
    [_browser loadColumnZero];
    [self _updateStatusAndButtons];
}

/**
 * Soft reload: preserves the user's current column/selection path.
 * Rebuilds _rootNode, fully reloads the browser, then navigates back
 * to the same path. If the previously-selected item was deleted, stops
 * at the deepest still-existing ancestor instead.
 */
- (void)_reloadBrowserPreservingSelection {
    /* Capture selection state as a breadcrumb of child names. */
    NSMutableArray<NSString *> *breadcrumb = [NSMutableArray array];
    NSInteger lastColumn = [_browser lastColumn];
    for (NSInteger c = 0; c <= lastColumn; c++) {
        NSInteger row = [_browser selectedRowInColumn:c];
        if (row < 0) {
            break;
        }
        id node = [self _nodeForColumn:c];
        if (![node isKindOfClass:[UDDirectoryNode class]]) {
            break;
        }
        NSArray *children = [(UDDirectoryNode *)node children];
        if (row >= (NSInteger)children.count) {
            break;
        }
        id child = [children objectAtIndex:(NSUInteger)row];
        NSString *name = [child isKindOfClass:[UDDirectoryNode class]]
            ? [(UDDirectoryNode *)child name]
            : [(UDArchiveEntry *)child name];
        [breadcrumb addObject:name];
    }

    /* Full data + UI reset. */
    [self _reloadBrowser];

    /* Re-navigate column by column until a name is missing (item deleted). */
    for (NSUInteger depth = 0; depth < breadcrumb.count; depth++) {
        NSString *name = [breadcrumb objectAtIndex:depth];
        id node = [self _nodeForColumn:(NSInteger)depth];
        if (![node isKindOfClass:[UDDirectoryNode class]]) {
            break;
        }
        NSArray *children = [(UDDirectoryNode *)node children];
        NSInteger matchRow = -1;
        for (NSInteger row = 0; row < (NSInteger)children.count; row++) {
            id child = [children objectAtIndex:(NSUInteger)row];
            NSString *childName = [child isKindOfClass:[UDDirectoryNode class]]
                ? [(UDDirectoryNode *)child name]
                : [(UDArchiveEntry *)child name];
            if ([childName isEqualToString:name]) {
                matchRow = row;
                break;
            }
        }
        if (matchRow < 0) {
            break; /* item no longer exists — stay at deepest valid ancestor */
        }
        [_browser selectRow:matchRow inColumn:(NSInteger)depth];
    }

    [self _updateStatusAndButtons];
}

/* ------------------------------------------------------------------ */
#pragma mark - Selection helpers

/**
 * Return the UDDirectoryNode that owns column `column`.
 * Column 0 → root node.
 * Column n → child selected in column n-1 (must be a UDDirectoryNode).
 */
- (nullable id)_nodeForColumn:(NSInteger)column {
    if (column < 0) {
        return nil;
    }
    if (column == 0) {
        return _rootNode;
    }

    id parent = [self _nodeForColumn:column - 1];
    if (![parent isKindOfClass:[UDDirectoryNode class]]) {
        return nil;
    }
    UDDirectoryNode *parentNode = (UDDirectoryNode *)parent;

    NSInteger selectedRow = [_browser selectedRowInColumn:column - 1];
    if (selectedRow < 0 || selectedRow >= (NSInteger)parentNode.children.count) {
        return nil;
    }
    return [parentNode.children objectAtIndex:(NSUInteger)selectedRow];
}

/**
 * Return the currently-selected child object by scanning from the rightmost
 * loaded column backwards to find the first column with a row selection.
 */
- (nullable id)_selectedChild {
    NSInteger lastColumn = [_browser lastColumn];
    for (NSInteger c = lastColumn; c >= 0; c--) {
        NSInteger row = [_browser selectedRowInColumn:c];
        if (row < 0) {
            continue;
        }
        id parent = [self _nodeForColumn:c];
        if (![parent isKindOfClass:[UDDirectoryNode class]]) {
            continue;
        }
        UDDirectoryNode *parentNode = (UDDirectoryNode *)parent;
        if (row >= (NSInteger)parentNode.children.count) {
            continue;
        }
        return [parentNode.children objectAtIndex:(NSUInteger)row];
    }
    return nil;
}

/** Full archive path of the selected item, or nil if nothing is selected. */
- (nullable NSString *)_selectedPath {
    id child = [self _selectedChild];
    if (!child) {
        return nil;
    }
    if ([child isKindOfClass:[UDDirectoryNode class]]) {
        return [(UDDirectoryNode *)child path];
    }
    if ([child isKindOfClass:[UDArchiveEntry class]]) {
        return [(UDArchiveEntry *)child path];
    }
    return nil;
}

/** YES if the selected item is a file leaf (UDArchiveEntry). */
- (BOOL)_selectedIsLeaf {
    return [[self _selectedChild] isKindOfClass:[UDArchiveEntry class]];
}

/**
 * Archive directory path where new files should land when the user clicks Add.
 * If a file is selected, returns its parent directory.
 * If a directory is selected, returns that directory.
 * Falls back to the root (@"") when nothing is selected.
 */
- (NSString *)_currentDirectoryPath {
    id child = [self _selectedChild];
    if (!child) {
        /* Use the path of the deepest visible column's owning node. */
        id node = [self _nodeForColumn:[_browser lastColumn]];
        if ([node isKindOfClass:[UDDirectoryNode class]]) {
            return [(UDDirectoryNode *)node path];
        }
        return @"";
    }
    if ([child isKindOfClass:[UDArchiveEntry class]]) {
        UDDirectoryNode *parent = [(UDArchiveEntry *)child parent];
        return parent ? parent.path : @"";
    }
    if ([child isKindOfClass:[UDDirectoryNode class]]) {
        return [(UDDirectoryNode *)child path];
    }
    return @"";
}

- (NSString *)_entryPluralSuffix:(NSUInteger)count {
    return (count == 1) ? @"y" : @"ies";
}

- (void)_updateStatusAndButtons {
    NSUInteger totalCount = _archiveDocument.editor.currentRoot.allEntries.count;
    NSString *selPath  = [self _selectedPath];
    BOOL      hasSel   = (selPath.length > 0);
    BOOL      isLeaf   = [self _selectedIsLeaf];
    id        selected = [self _selectedChild];

    NSString *status;
    if (hasSel) {
        if (isLeaf) {
            UDArchiveEntry *entry = [selected isKindOfClass:[UDArchiveEntry class]]
                ? (UDArchiveEntry *)selected : nil;
            if (entry) {
                status = [NSString stringWithFormat:@"%lu entr%@ — %@ (%llu bytes)",
                          (unsigned long)totalCount,
                          [self _entryPluralSuffix:totalCount],
                          selPath, (unsigned long long)entry.size];
            } else {
                status = [NSString stringWithFormat:@"%lu entr%@ — %@",
                          (unsigned long)totalCount,
                          [self _entryPluralSuffix:totalCount],
                          selPath];
            }
        } else {
            status = [NSString stringWithFormat:@"%lu entr%@ — %@/",
                      (unsigned long)totalCount,
                      [self _entryPluralSuffix:totalCount],
                      selPath];
        }
    } else {
        status = [NSString stringWithFormat:@"%lu entr%@",
                  (unsigned long)totalCount,
                  [self _entryPluralSuffix:totalCount]];
    }

    [_statusLabel   setStringValue:status];
    [_deleteButton  setEnabled:hasSel];
    [_extractButton setEnabled:hasSel];
    [_openButton    setEnabled:(hasSel && isLeaf)];
}

/* ------------------------------------------------------------------ */
#pragma mark - NSBrowserDelegate (column-based API)

- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column {
    id node = [self _nodeForColumn:column];
    if (![node isKindOfClass:[UDDirectoryNode class]]) {
        return 0;
    }
    return (NSInteger)[(UDDirectoryNode *)node children].count;
}

- (void)browser:(NSBrowser *)sender
willDisplayCell:(id)cell
          atRow:(NSInteger)row
         column:(NSInteger)column {
    id parent = [self _nodeForColumn:column];
    if (![parent isKindOfClass:[UDDirectoryNode class]]) {
        return;
    }
    UDDirectoryNode *parentNode = (UDDirectoryNode *)parent;
    if (row < 0 || row >= (NSInteger)parentNode.children.count) {
        return;
    }

    id child = [parentNode.children objectAtIndex:(NSUInteger)row];
    NSString *title;
    BOOL      isLeaf;

    if ([child isKindOfClass:[UDDirectoryNode class]]) {
        title  = [(UDDirectoryNode *)child name];
        isLeaf = NO;
    } else {
        title  = [(UDArchiveEntry *)child name];
        isLeaf = YES;
    }

    [cell setStringValue:title];
    [cell setLeaf:isLeaf];
    [cell setLoaded:YES];
    [cell setEnabled:YES];
}

- (NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column {
    id node = [self _nodeForColumn:column];
    if (![node isKindOfClass:[UDDirectoryNode class]]) {
        return @"";
    }
    NSString *p = [(UDDirectoryNode *)node path];
    NSString *displayName = _archiveDocument.archive ? _archiveDocument.archive.displayName : @"Untitled";
    return (p.length > 0) ? p.lastPathComponent
                           : displayName;
}

/* Called when the user clicks a row in the browser. */
- (void)browserSingleClick:(id)sender {
    [self _updateStatusAndButtons];
}

/* ------------------------------------------------------------------ */
#pragma mark - IBActions

- (IBAction)addFile:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setTitle:@"Choose File to Add"];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:YES];

    NSInteger result = [panel runModal];
    if (result == NSModalResponseOK) {
        for (NSURL *url in panel.URLs) {
            [self _addFileAtURL:url];
        }
    }
}

- (IBAction)addFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setTitle:@"Choose Folder to Add"];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setCanCreateDirectories:NO];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSModalResponseOK) {
        [self _addDirectoryAtURL:[panel URL]];
    }
}

- (IBAction)renameSelected:(id)sender {
    (void)sender;
    NSString *path = [self _selectedPath];
    if (path.length == 0) {
        return;
    }

    NSString *currentName = path.lastPathComponent;
    NSString *newName = [self _promptForNameWithTitle:@"Rename"
                                          informative:@"Enter a new name."
                                          defaultName:currentName];
    if (newName.length == 0 || [newName isEqualToString:currentName]) {
        return;
    }

    NSString *parentPath = [path stringByDeletingLastPathComponent];
    NSString *targetPath = (parentPath.length > 0)
        ? [parentPath stringByAppendingFormat:@"/%@", newName]
        : newName;

    NSError *err = nil;
    if (![_archiveDocument.editor moveNodeFromPath:path toPath:targetPath error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return;
    }

    [_archiveDocument updateChangeCount:NSChangeDone];
    /* Reload is handled by UDArchiveEditorDidChangeNotification. */
}

- (void)_addFileAtURL:(NSURL *)fileURL {
    NSString *dirPath     = [self _currentDirectoryPath];
    NSString *fileName    = fileURL.lastPathComponent;
    NSString *archivePath = (dirPath.length > 0)
        ? [dirPath stringByAppendingFormat:@"/%@", fileName]
        : fileName;

    UDStagedFileSource *src = [[UDStagedFileSource alloc] initWithFileURL:fileURL];
    NSError *err = nil;
    if (![_archiveDocument.editor addSource:src atPath:archivePath error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return;
    }

    [_archiveDocument updateChangeCount:NSChangeDone];
    /* Reload is handled by UDArchiveEditorDidChangeNotification. */
}

- (void)_addDirectoryAtURL:(NSURL *)directoryURL {
    NSString *basePath = [self _currentDirectoryPath];
    NSString *rootName = directoryURL.lastPathComponent;
    NSString *rootArchivePath = (basePath.length > 0)
        ? [basePath stringByAppendingFormat:@"/%@", rootName]
        : rootName;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator =
        [fm enumeratorAtURL:directoryURL
  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                     options:NSDirectoryEnumerationSkipsHiddenFiles
                errorHandler:^BOOL(NSURL *url, NSError *error) {
                    NSLog(@"Warning: failed to enumerate '%@': %@", url.path, error);
                    return YES;
                }];

    BOOL addedAny = NO;
    for (NSURL *childURL in enumerator) {
        NSNumber *isDirValue = nil;
        [childURL getResourceValue:&isDirValue forKey:NSURLIsDirectoryKey error:NULL];
        if (isDirValue.boolValue) {
            continue;
        }

        NSString *relative = [childURL.path substringFromIndex:directoryURL.path.length];
        if ([relative hasPrefix:@"/"]) {
            relative = [relative substringFromIndex:1];
        }
        if (relative.length == 0) {
            continue;
        }

        NSString *archivePath = [rootArchivePath stringByAppendingFormat:@"/%@", relative];
        archivePath = [archivePath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];

        UDStagedFileSource *src = [[UDStagedFileSource alloc] initWithFileURL:childURL];
        NSError *err = nil;
        if (![_archiveDocument.editor addSource:src atPath:archivePath error:&err]) {
            [[NSAlert alertWithError:err] runModal];
            return;
        }
        addedAny = YES;
    }

    if (addedAny) {
        [_archiveDocument updateChangeCount:NSChangeDone];
        /* Reload is handled by UDArchiveEditorDidChangeNotification. */
    }
}

- (nullable NSString *)_promptForNameWithTitle:(NSString *)title
                                  informative:(NSString *)informative
                                  defaultName:(NSString *)defaultName {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle:title ?: @"Rename"];
    [panel setPrompt:@"OK"];
    [panel setCanCreateDirectories:NO];
    [panel setNameFieldStringValue:defaultName ?: @""];

    if ([panel runModal] != NSModalResponseOK) {
        return nil;
    }

    NSString *chosenName = panel.URL.lastPathComponent ?: @"";
    return [chosenName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (IBAction)deleteSelected:(id)sender {
    NSString *path = [self _selectedPath];
    if (!path) {
        return;
    }

    NSAlert *confirm = [[NSAlert alloc] init];
    [confirm setMessageText:[NSString stringWithFormat:
        @"Delete \"%@\"?", path.lastPathComponent]];
    [confirm setInformativeText:
        @"This will remove the entry from the archive when you save."];
    [confirm addButtonWithTitle:@"Delete"];
    [confirm addButtonWithTitle:@"Cancel"];

    if ([confirm runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSError *err = nil;
    if (![_archiveDocument.editor removeNodeAtPath:path error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return;
    }

    [_archiveDocument updateChangeCount:NSChangeDone];
    /* Reload is handled by UDArchiveEditorDidChangeNotification. */
}

- (IBAction)extractSelected:(id)sender {
    NSString *selPath = [self _selectedPath];
    if (!selPath) {
        return;
    }

    if ([self _selectedIsLeaf]) {
        /* Single file — ask where to save it. */
        NSSavePanel *panel = [NSSavePanel savePanel];
        [panel setNameFieldStringValue:selPath.lastPathComponent];
        if ([panel runModal] == NSModalResponseOK) {
            [self _extractEntryAtPath:selPath toURL:[panel URL]];
        }
    } else {
        /* Directory — ask for destination folder. */
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setTitle:@"Choose Extraction Destination"];
        [panel setCanChooseFiles:NO];
        [panel setCanChooseDirectories:YES];
        [panel setCanCreateDirectories:YES];
        if ([panel runModal] == NSModalResponseOK) {
            [self _extractDirectoryAtPath:selPath toDirectoryURL:[panel URL]];
        }
    }
}

- (void)_extractEntryAtPath:(NSString *)archivePath toURL:(NSURL *)destURL {
    UDArchiveEntry *entry = [_archiveDocument.editor.currentRoot entryAtRelativePath:archivePath];
    if (!entry) {
        return;
    }

    NSError *err  = nil;
    NSData  *data = [_archiveDocument.editor
        contentForEntryAtPath:archivePath
                        range:NSMakeRange(0, (NSUInteger)entry.size)
                        error:&err];
    if (!data) {
        [[NSAlert alertWithError:err] runModal];
        return;
    }
    if (![data writeToURL:destURL options:NSDataWritingAtomic error:&err]) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)_extractDirectoryAtPath:(NSString *)dirPath
               toDirectoryURL:(NSURL *)destDir {
    UDDirectoryNode *dirNode = [_archiveDocument.editor.currentRoot directoryAtRelativePath:dirPath];
    NSArray<UDArchiveEntry *> *entriesToExtract = dirNode ? [dirNode allEntries] : @[];
    NSUInteger prefixLength = dirPath.length > 0 ? dirPath.length + 1 : 0; /* skip "dirPath/" */
    NSFileManager *fm = [NSFileManager defaultManager];

    for (UDArchiveEntry *entry in entriesToExtract) {
        NSString *relative = prefixLength > 0 && entry.path.length > prefixLength
            ? [entry.path substringFromIndex:prefixLength]
            : entry.path.lastPathComponent;

        NSURL   *destURL = [destDir URLByAppendingPathComponent:relative];
        NSError *err     = nil;

        if (![fm createDirectoryAtURL:[destURL URLByDeletingLastPathComponent]
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:&err]) {
            NSLog(@"Warning: could not create directory for '%@': %@", relative, err);
            continue;
        }

        NSData *data = [_archiveDocument.editor
            contentForEntryAtPath:entry.path
                            range:NSMakeRange(0, (NSUInteger)entry.size)
                            error:&err];
        if (!data) {
            NSLog(@"Warning: could not read '%@': %@", entry.path, err);
            continue;
        }
        if (![data writeToURL:destURL options:NSDataWritingAtomic error:&err]) {
            NSLog(@"Warning: could not write '%@': %@", destURL.path, err);
        }
    }
}

- (IBAction)openSelected:(id)sender {
    id selected = [self _selectedChild];
    if (![selected isKindOfClass:[UDArchiveEntry class]]) {
        return;
    }
    UDArchiveEntry *entry = (UDArchiveEntry *)selected;
    NSString *selPath = entry.path;

    /* Extract to a per-archive temporary path, then open with the action service. */
    NSString *tempBase = [NSTemporaryDirectory()
                         stringByAppendingPathComponent:@"PakManager"];
    NSString *tempPath = [tempBase stringByAppendingPathComponent:selPath];
    NSURL    *tempURL  = [NSURL fileURLWithPath:tempPath];

    NSError *err = nil;
    if (![[NSFileManager defaultManager]
            createDirectoryAtURL:[tempURL URLByDeletingLastPathComponent]
     withIntermediateDirectories:YES
                      attributes:nil
                           error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return;
    }

    NSData *data = [_archiveDocument.editor
        contentForEntryAtPath:selPath
                       range:NSMakeRange(0, (NSUInteger)entry.size)
                       error:&err];
    if (!data) {
        [[NSAlert alertWithError:err] runModal];
        return;
    }
    if (![data writeToURL:tempURL options:NSDataWritingAtomic error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return;
    }

    _activeTextPreview = [_fileActionService openFileAtPath:tempPath
                                                  withData:data
                                              parentWindow:[self window]
                                             modalDelegate:self
                                            didEndSelector:@selector(textPreviewSheetDidEnd:returnCode:contextInfo:)];
}

- (IBAction)gameChanged:(id)sender {
    NSInteger index = [_gamePopUpButton indexOfSelectedItem];
    if (index == 0) {
        [self _detectGame];
        _activeGame = _detectedGame;
    } else {
        _activeGame = [UDGame gameWithDisplayName:[_gamePopUpButton titleOfSelectedItem]];
    }
    NSLog(@"Active game profile set to: %@", _activeGame.displayName);
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    SEL action = [item action];
    NSString *selPath = [self _selectedPath];
    BOOL hasSel = (selPath.length > 0);

    if (action == @selector(deleteSelected:) ||
        action == @selector(renameSelected:) ||
        action == @selector(extractSelected:)) {
        return hasSel;
    }

    if (action == @selector(openSelected:)) {
        return hasSel && [self _selectedIsLeaf];
    }

    return YES;
}

- (void)_detectGame {
    _detectedGame = [_gameDetectionService detectGameForURL:_archiveDocument.fileURL
                                                   entries:_archiveDocument.editor.currentEntries
                                           codecIdentifier:_archiveDocument.codec.formatIdentifier];
    NSLog(@"Auto-detected game: %@", _detectedGame.displayName);
}

- (void)textPreviewSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    _activeTextPreview = nil;
}

@end
