/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UQTestWindow.m
 */

#import "UQTestWindow.h"
#import "UQExtension.h"
#import "UQProject.h"
#import "UQEditorHost.h"
#import "UDBaseEditorViewController.h"
#import "UDDeclEditorViewController.h"

/// What UDProject gives the extension: the window's folder.
@interface UQTestFolderProject : NSObject
@property (nonatomic, copy) NSURL *folderURL;
@end

@implementation UQTestFolderProject
@end

/// A tab: its document, and its editor when it has one of the extension's.
@interface UQTestTab : NSObject
@property (nonatomic, strong) UDCodeDocument *document;
@property (nonatomic, strong, nullable) NSViewController *editor;
@end

@implementation UQTestTab
@end

@implementation UQTestWindow {
    UQTestFolderProject *_project;
    NSMutableArray<UQTestTab *> *_tabs;
    UQTestTab *_selected;
    NSView *_editorArea;
    NSMutableDictionary<NSString *, id<UDFileSystemProvider>> *_providers;
}

+ (instancetype)windowOfFolder:(NSString *)folder extension:(UQExtension *)extension timeout:(NSTimeInterval)timeout error:(NSError **)error {
    UQTestWindow *window = [[self alloc] initWithFolder:folder extension:extension];
    __block BOOL started = NO;
    [window.quarry whenStarted:^(UDGameWorkspace *workspace) { started = YES; }];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!started && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!window.quarry.workspace) {
        if (error) *error = window.quarry.startupError;
        [window close];
        return nil;
    }
    [window.tree refresh];
    return window;
}

- (instancetype)initWithFolder:(NSString *)folder extension:(UQExtension *)extension {
    if (!(self = [super init])) return nil;
    _extension = extension;
    _project = [[UQTestFolderProject alloc] init];
    _project.folderURL = [NSURL fileURLWithPath:folder];
    _tabs = [NSMutableArray array];
    _providers = [NSMutableDictionary dictionary];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 800)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    // the navigator on the left, the editor in the middle, the inspector on the right
    NSView *content = _window.contentView;
    _tree = (UDTreeViewController *)[extension navigatorViewControllerForWorkbench:(id)self];
    _tree.view.frame = NSMakeRect(0, 0, 260, 800);
    _tree.view.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    [content addSubview:_tree.view];
    _editorArea = [[NSView alloc] initWithFrame:NSMakeRect(260, 0, 720, 800)];
    _editorArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:_editorArea];
    _inspectorHost = [[NSView alloc] initWithFrame:NSMakeRect(980, 0, 300, 800)];
    _inspectorHost.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
    [content addSubview:_inspectorHost];
    _quarry = [extension projectOfWorkbench:(id)self];
    return self;
}

- (UDGameWorkspace *)workspace {
    return _quarry.workspace;
}

- (id)project {
    return _project;
}

- (NSOutlineView *)outlineView {
    return _tree.outlineView;
}

- (NSSearchField *)nameFilterField {
    return _tree.filterField;
}

- (IBAction)nameFilterChanged:(id)sender {
    [_tree filterChanged:sender];
}

// ---------------------------------------------------------------------------
// MARK: - Tabs
// ---------------------------------------------------------------------------

- (UDCodeDocument *)selectedDocument {
    return _selected.document;
}

- (UQEditorHost *)selectedHost {
    return [_selected.editor isKindOfClass:[UQEditorHost class]] ? (UQEditorHost *)_selected.editor : nil;
}

- (UDBaseEditorViewController *)selectedEditor {
    return self.selectedHost.editor;
}

- (NSArray<UDBaseEditorViewController *> *)allEditors {
    NSMutableArray *editors = [NSMutableArray array];
    for (UQTestTab *tab in _tabs) {
        if ([tab.editor isKindOfClass:[UQEditorHost class]]) [editors addObject:[(UQEditorHost *)tab.editor editor]];
    }
    return editors;
}

- (NSArray<UDCodeDocument *> *)documents {
    return [_tabs valueForKey:@"document"];
}

/// @a tab in front: its editor's view in the middle, its first inspector on the right.
- (void)_select:(UQTestTab *)tab {
    _selected = tab;
    for (NSView *view in [_editorArea.subviews copy]) [view removeFromSuperview];
    for (NSView *view in [_inspectorHost.subviews copy]) [view removeFromSuperview];
    if (tab.editor) {
        NSView *view = tab.editor.view;
        view.frame = _editorArea.bounds;
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_editorArea addSubview:view];
    }
    NSViewController *first = self.inspectors.firstObject;
    if (first) [self showEditorInspector:first];
}

- (void)closeAllTabs {
    for (UQTestTab *tab in [_tabs copy]) {
        if ([tab.document.customDocument respondsToSelector:@selector(closeCustomDocument)]) {
            [tab.document.customDocument closeCustomDocument];
        }
    }
    [_tabs removeAllObjects];
    [self _select:nil];
}

- (id<UDFileSystemProvider>)_providerOfScheme:(NSString *)scheme {
    id<UDFileSystemProvider> provider = _providers[scheme];
    if (!provider) {
        provider = [_extension workbench:(id)self fileSystemProviderForScheme:scheme];
        if (provider) _providers[scheme] = provider;
    }
    return provider;
}

- (void)showURL:(NSURL *)url {
    for (UQTestTab *tab in _tabs) {
        if ([tab.document.URL isEqual:url]) {
            [self _select:tab];
            return;
        }
    }
    id<UDFileSystemProvider> provider = url.isFileURL ? nil : [self _providerOfScheme:url.scheme];
    NSError *error = nil;
    id<UDCustomDocument> custom = [_extension workbench:(id)self openCustomDocumentAtURL:url fileSystemProvider:provider error:&error];
    UDCodeDocument *document = custom
        ? [[UDCodeDocument alloc] initWithCustomDocument:custom URL:url fileSystemProvider:provider languageMode:nil]
        : [UDCodeDocument documentFromURL:url fileSystemProvider:provider error:&error];
    if (!document) {
        NSLog(@"UQTestWindow: %@ didn't open: %@", url, error);
        return;
    }
    UQTestTab *tab = [[UQTestTab alloc] init];
    tab.document = document;
    tab.editor = [_extension workbench:(id)self editorForDocument:document];
    [_tabs addObject:tab];
    [self _select:tab];
}

- (BOOL)showDocument:(UDCodeDocument *)document {
    for (UQTestTab *tab in _tabs) {
        if (tab.document == document) {
            [self _select:tab];
            return YES;
        }
    }
    return NO;
}

- (void)openFileAtPath:(NSString *)path line:(NSInteger)line character:(NSInteger)character length:(NSInteger)length {
    [self showURL:[UQProject URLOfGamePath:path]];
}

// ---------------------------------------------------------------------------
// MARK: - The inspector
// ---------------------------------------------------------------------------

- (NSArray<NSViewController *> *)inspectors {
    return self.selectedHost.inspectorViewControllers ?: @[];
}

- (BOOL)showEditorInspector:(NSViewController *)inspector {
    if (![self.inspectors containsObject:inspector]) return NO;
    for (NSView *view in [_inspectorHost.subviews copy]) [view removeFromSuperview];
    inspector.view.frame = _inspectorHost.bounds;
    inspector.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_inspectorHost addSubview:inspector.view];
    return YES;
}

- (void)showInspectorPaneTitled:(NSString *)title {
    [self.selectedHost showInspectorPaneTitled:title];
}

// ---------------------------------------------------------------------------
// MARK: - Save, undo, issues
// ---------------------------------------------------------------------------

- (IBAction)saveDocument:(id)sender {
    UDCodeDocument *document = self.selectedDocument;
    if (!document) return;
    [_window makeFirstResponder:nil];
    NSError *error = nil;
    if (![document saveToURL:document.URL error:&error]) NSLog(@"UQTestWindow: %@ not saved: %@", document.URL, error);
}

/// Undo: the front custom document's, as UDCode's window has it.
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    return self.selectedDocument.customDocument.undoManager;
}

- (void)errorsViewController:(id)controller didSelectDiagnostic:(UDDiagnosticItem *)diagnostic inStore:(UDDiagnosticStore *)store {
    [self.selectedHost revealDiagnostic:diagnostic];
}

// ---------------------------------------------------------------------------
// MARK: - Commands: the Editor menu's, then the front editor's
// ---------------------------------------------------------------------------

- (id)commands {
    return [_extension editorMenuItemsForWorkbench:(id)self].firstObject.target;
}

- (id)forwardingTargetForSelector:(SEL)selector {
    id commands = self.commands;
    if ([commands respondsToSelector:selector]) return commands;
    if ([self.selectedHost respondsToSelector:selector]) return self.selectedHost;
    return [super forwardingTargetForSelector:selector];
}

- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.commands respondsToSelector:selector] ||
           [self.selectedHost respondsToSelector:selector];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    id commands = self.commands;
    if ([commands respondsToSelector:item.action]) return [commands validateMenuItem:item];
    UQEditorHost *host = self.selectedHost;
    return host && [host respondsToSelector:item.action] ? [host validateMenuItem:item] : NO;
}

- (void)close {
    [self closeAllTabs];
    [_window close];
    _quarry = nil;
}

@end
