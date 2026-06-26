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
- (nullable NSString *)_customCommandForExtension:(NSString *)ext;
@end

/* ------------------------------------------------------------------ */

@implementation UDArchiveBrowserController

@synthesize browser       = _browser;
@synthesize statusLabel   = _statusLabel;
@synthesize addButton     = _addButton;
@synthesize deleteButton  = _deleteButton;
@synthesize extractButton = _extractButton;
@synthesize openButton    = _openButton;

/* ------------------------------------------------------------------ */
#pragma mark - Init

- (instancetype)initWithDocument:(UDArchiveDocument *)document {
    self = [super initWithWindowNibName:@"UDArchiveDocument"];
    if (!self) {
        return nil;
    }
    _archiveDocument = document;
    return self;
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

    /* Add the game selection PopUpButton dynamically on the right side of buttonBar */
    NSView *buttonBar = [_openButton superview];
    if (buttonBar) {
        NSRect frame = NSMakeRect(buttonBar.bounds.size.width - 210, 3, 200, 22);
        NSPopUpButton *gamePopUp = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
        [gamePopUp setAutoresizingMask:NSViewMinXMargin];

        [gamePopUp addItemWithTitle:@"Auto Detect"];
        [gamePopUp addItemWithTitle:@"Quake 1"];
        [gamePopUp addItemWithTitle:@"Quake 2"];
        [gamePopUp addItemWithTitle:@"Daikatana"];
        [gamePopUp addItemWithTitle:@"Quake 3"];
        [gamePopUp addItemWithTitle:@"Doom 3"];

        [gamePopUp setTarget:self];
        [gamePopUp setAction:@selector(gameChanged:)];

        [buttonBar addSubview:gamePopUp];
        _gamePopUpButton = gamePopUp;
    }

    /* Auto detect game and set popup item title */
    [self _detectGame];
    if (_gamePopUpButton) {
        [[_gamePopUpButton itemAtIndex:0] setTitle:[NSString stringWithFormat:@"Auto Detect (%@)", _detectedGame]];
    }

    /* Populate the tree. */
    [self _reloadBrowser];
}

/* ------------------------------------------------------------------ */
#pragma mark - Tree management

- (void)_reloadBrowser {
    NSArray *entries = _archiveDocument.editor.currentEntries;
    _rootNode = [UDDirectoryNode rootNodeFromEntries:entries];
    [_browser loadColumnZero];
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
    return parentNode.children[(NSUInteger)selectedRow];
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
        return parentNode.children[(NSUInteger)row];
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
        return [[(UDArchiveEntry *)child path] stringByDeletingLastPathComponent];
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
    NSArray *entries   = _archiveDocument.editor.currentEntries;
    NSString *selPath  = [self _selectedPath];
    BOOL      hasSel   = (selPath.length > 0);
    BOOL      isLeaf   = [self _selectedIsLeaf];

    NSString *status;
    if (hasSel) {
        if (isLeaf) {
            UDArchiveEntry *entry = nil;
            for (UDArchiveEntry *e in entries) {
                if ([e.path isEqualToString:selPath]) {
                    entry = e;
                    break;
                }
            }
            if (entry) {
                status = [NSString stringWithFormat:@"%lu entr%@ — %@ (%llu bytes)",
                          (unsigned long)entries.count,
                          [self _entryPluralSuffix:entries.count],
                          selPath, entry.size];
            } else {
                status = [NSString stringWithFormat:@"%lu entr%@ — %@",
                          (unsigned long)entries.count,
                          [self _entryPluralSuffix:entries.count],
                          selPath];
            }
        } else {
            status = [NSString stringWithFormat:@"%lu entr%@ — %@/",
                      (unsigned long)entries.count,
                      [self _entryPluralSuffix:entries.count],
                      selPath];
        }
    } else {
        status = [NSString stringWithFormat:@"%lu entr%@",
                  (unsigned long)entries.count,
                  [self _entryPluralSuffix:entries.count]];
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

    id child = parentNode.children[(NSUInteger)row];
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
    return (p.length > 0) ? p.lastPathComponent
                           : _archiveDocument.archive.displayName;
}

/* Called when the user clicks a row in the browser. */
- (void)browserSingleClick:(id)sender {
    [self _updateStatusAndButtons];
}

/* ------------------------------------------------------------------ */
#pragma mark - IBActions

- (IBAction)addFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setTitle:@"Choose File to Add"];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];

    NSInteger result = [panel runModal];
    if (result == NSModalResponseOK) {
        [self _addFileAtURL:[panel URL]];
    }
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
    [self _reloadBrowser];
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
    [self _reloadBrowser];
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
    /* Locate the entry to obtain its size. */
    NSUInteger entrySize = 0;
    for (UDArchiveEntry *entry in _archiveDocument.editor.currentEntries) {
        if ([entry.path isEqualToString:archivePath]) {
            entrySize = (NSUInteger)entry.size;
            break;
        }
    }

    NSError *err  = nil;
    NSData  *data = [_archiveDocument.editor
        contentForEntryAtPath:archivePath
                        range:NSMakeRange(0, entrySize)
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
    NSString      *dirPrefix = [dirPath stringByAppendingString:@"/"];
    NSFileManager *fm        = [NSFileManager defaultManager];

    for (UDArchiveEntry *entry in _archiveDocument.editor.currentEntries) {
        BOOL isDirectChild = [entry.path isEqualToString:dirPath];
        BOOL isDescendant  = [entry.path hasPrefix:dirPrefix];
        if (!isDirectChild && !isDescendant) {
            continue;
        }

        NSString *relative = isDescendant
            ? [entry.path substringFromIndex:dirPrefix.length]
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
    NSString *selPath = [self _selectedPath];
    if (!selPath || ![self _selectedIsLeaf]) {
        return;
    }

    /* Find the entry to get its size. */
    UDArchiveEntry *entry = nil;
    for (UDArchiveEntry *e in _archiveDocument.editor.currentEntries) {
        if ([e.path isEqualToString:selPath]) {
            entry = e;
            break;
        }
    }
    if (!entry) {
        return;
    }

    /* Extract to a per-archive temporary path, then open with the OS or custom tool. */
    NSString *tempBase = [NSTemporaryDirectory()
                          stringByAppendingPathComponent:@"UDArchivist"];
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

    NSString *ext = [selPath pathExtension].lowercaseString;

    // 1. Check if the file is plain text data (built-in previewer)
    if ([UDArchiveBrowserController isPlainTextData:data extension:ext]) {
        NSString *textString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!textString) {
            textString = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        }
        if (textString) {
            _activeTextPreview = [[UDTextPreviewController alloc] initWithText:textString title:selPath];
            [NSApp beginSheet:[_activeTextPreview window]
               modalForWindow:[self window]
                modalDelegate:self
               didEndSelector:@selector(textPreviewSheetDidEnd:returnCode:contextInfo:)
                  contextInfo:NULL];
            return;
        }
    }

    // 2. Check Custom Mappings from user preferences
    NSString *cmdTemplate = [self _customCommandForExtension:ext];
    if (cmdTemplate.length > 0) {
        NSString *cmd = [cmdTemplate stringByReplacingOccurrencesOfString:@"%f" withString:tempPath];
        @try {
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:@"/bin/sh"];
            [task setArguments:@[@"-c", cmd]];
            [task launch];
            return;
        } @catch (NSException *exception) {
            NSLog(@"Failed to launch custom command '%@': %@", cmd, exception);
        }
    }

    // 3. Fallback to NSWorkspace openFile
    BOOL success = [[NSWorkspace sharedWorkspace] openFile:tempPath];
    if (!success) {
        // 4. GNUstep/Linux fallback: xdg-open
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:@"/usr/bin/xdg-open"] || [fm fileExistsAtPath:@"/usr/local/bin/xdg-open"]) {
            @try {
                NSTask *task = [[NSTask alloc] init];
                [task setLaunchPath:@"/usr/bin/xdg-open"];
                [task setArguments:@[tempPath]];
                [task launch];
            } @catch (NSException *exception) {
                NSLog(@"Failed to launch xdg-open: %@", exception);
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Failed to Open File"];
                [alert setInformativeText:[NSString stringWithFormat:@"Neither the default application nor xdg-open could open '%@'.", selPath.lastPathComponent]];
                [alert addButtonWithTitle:@"OK"];
                [alert runModal];
            }
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Failed to Open File"];
            [alert setInformativeText:[NSString stringWithFormat:@"No application associated with '%@'. Configure a custom helper in preferences.", ext]];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
    }
}

- (IBAction)gameChanged:(id)sender {
    NSInteger index = [_gamePopUpButton indexOfSelectedItem];
    if (index == 0) {
        [self _detectGame];
    } else {
        _detectedGame = [_gamePopUpButton titleOfSelectedItem];
    }
    NSLog(@"Active game profile set to: %@", _detectedGame);
}

- (void)_detectGame {
    NSURL *url = _archiveDocument.fileURL;
    NSString *detected = nil;

    // 1. Analyze parent directory name
    if (url) {
        NSString *parentDirName = [[url.path stringByDeletingLastPathComponent] lastPathComponent].lowercaseString;
        if ([parentDirName isEqualToString:@"id1"]) {
            detected = @"Quake 1";
        } else if ([parentDirName isEqualToString:@"baseq2"] || [parentDirName isEqualToString:@"rogue"] || [parentDirName isEqualToString:@"xatrix"]) {
            detected = @"Quake 2";
        } else if ([parentDirName isEqualToString:@"baseq3"] || [parentDirName isEqualToString:@"missionpack"]) {
            detected = @"Quake 3";
        } else if ([parentDirName isEqualToString:@"base"] || [parentDirName isEqualToString:@"d3xp"]) {
            detected = @"Doom 3";
        } else if ([parentDirName isEqualToString:@"data"]) {
            detected = @"Daikatana";
        }
    }

    // 2. Analyze filename if not detected yet
    if (!detected && url) {
        NSString *ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"pk4"]) {
            detected = @"Doom 3";
        } else if ([ext isEqualToString:@"pk3"]) {
            detected = @"Quake 3";
        }
    }

    // 3. Analyze internal file structure by probing entry paths
    if (!detected) {
        NSArray *entries = _archiveDocument.editor.currentEntries;
        NSUInteger walCount = 0;
        NSUInteger mtrCount = 0;
        NSUInteger d3Folders = 0;
        NSUInteger q2Folders = 0;

        for (UDArchiveEntry *entry in entries) {
            NSString *path = entry.path.lowercaseString;
            if ([path hasSuffix:@".wal"]) {
                walCount++;
            } else if ([path hasSuffix:@".mtr"] || [path hasSuffix:@".def"] || [path hasSuffix:@".script"]) {
                mtrCount++;
            }
            if ([path hasPrefix:@"materials/"] || [path hasPrefix:@"def/"] || [path hasPrefix:@"script/"]) {
                d3Folders++;
            }
            if ([path hasPrefix:@"pics/"] || [path hasPrefix:@"players/"]) {
                q2Folders++;
            }
        }

        if (d3Folders > 0 || mtrCount > 0) {
            detected = @"Doom 3";
        } else if (walCount > 0 || q2Folders > 0) {
            detected = @"Quake 2";
        } else if ([_archiveDocument.codec.formatIdentifier isEqualToString:@"com.udquake.daikatana-pak"]) {
            detected = @"Daikatana";
        }
    }

    if (!detected) {
        detected = @"Quake 1"; // Default fallback for pak files
    }

    _detectedGame = detected;
    NSLog(@"Auto-detected game: %@", _detectedGame);
}

- (nullable NSString *)_customCommandForExtension:(NSString *)ext {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *associations = [defaults dictionaryForKey:@"UDCustomFileAssociations"];
    if (associations) {
        return [associations objectForKey:[ext lowercaseString]];
    }
    return nil;
}

+ (BOOL)isPlainTextData:(NSData *)data extension:(NSString *)ext {
    NSArray *textExts = @[@"txt", @"cfg", @"mtr", @"def", @"script", @"shader", @"rc", @"menu", @"qc", @"lst", @"font", @"skin", @"map", @"ini", @"json"];
    if ([textExts containsObject:[ext lowercaseString]]) {
        return YES;
    }

    NSUInteger len = MIN(data.length, 512);
    if (len == 0) {
        return YES;
    }
    const char *bytes = data.bytes;
    for (NSUInteger i = 0; i < len; i++) {
        char c = bytes[i];
        if (c == '\0') {
            return NO;
        }
        if ((unsigned char)c < 32 && c != '\t' && c != '\n' && c != '\r') {
            return NO;
        }
    }
    return YES;
}

- (void)textPreviewSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    _activeTextPreview = nil;
}

@end
