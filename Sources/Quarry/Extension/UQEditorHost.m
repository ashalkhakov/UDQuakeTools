/*---------------------------------------------------------------------------------------------
 *  UQEditorHost.m
 *--------------------------------------------------------------------------------------------*/

#import "UQEditorHost.h"
#import "UDBaseEditorViewController.h"
#import "UDDeclEditorViewController.h"
#import "UDTabBadge.h"

/// An inspector pane as the inspector takes it: a view controller.
@interface UQPaneController : NSViewController
@property (nonatomic, strong) UDEditorPane *pane;
@end

@implementation UQPaneController
@end

@interface UQEditorHost () <UDEditorHosting>
@property (nonatomic, weak) IBOutlet NSSplitView *splitView;
@property (nonatomic, weak) IBOutlet NSTabView *navigatorTabs;
@property (nonatomic, weak) IBOutlet NSView *editorHost;
@end

@implementation UQEditorHost {
    NSArray<UQPaneController *> *_inspectors;
}

- (instancetype)initWithEditor:(UDBaseEditorViewController *)editor document:(UDCodeDocument *)document
                     workbench:(id<UDWorkbench>)workbench {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _editor = editor;
    _document = document;
    _workbench = workbench;
    editor.host = self;
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView {
    // its view first: its panes are its XIB's
    NSView *editorView = _editor.view;
    NSArray<UDEditorPane *> *panes = [_editor conformsToProtocol:@protocol(UDNavigating)]
        ? [(id<UDNavigating>)_editor navigatorPanes] : @[];
    if (!panes.count) {
        // the editor's own view, as the tab shows it
        self.view = editorView;
    } else {
        // its navigator panes on its left (UQEditorHost.xib)
        NSNib *nib = [[NSNib alloc] initWithNibNamed:@"UQEditorHost" bundle:[NSBundle bundleForClass:[UQEditorHost class]]];
        [nib instantiateWithOwner:self topLevelObjects:NULL];
        editorView.frame = _editorHost.bounds;
        editorView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_editorHost addSubview:editorView];
        for (UDEditorPane *pane in panes) {
            NSTabViewItem *tab = [[NSTabViewItem alloc] initWithIdentifier:pane.title];
            tab.label = pane.title;
            tab.view = pane.view;
            [_navigatorTabs addTabViewItem:tab];
        }
        if (panes.count > 1) _navigatorTabs.tabViewType = NSTopTabsBezelBorder;
    }
    if ([_editor isKindOfClass:[UDDeclEditorViewController class]]) {
        UDDiagnosticStore *store = [(UDDeclEditorViewController *)_editor diagnosticStore];
        if (store) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_issuesDidChange:)
                                                         name:UDDiagnosticsDidChangeNotification object:store];
            [self _issuesDidChange:nil];
        }
    }
}

/// The editor's issues, its document's (the Issues navigator's).
- (void)_issuesDidChange:(NSNotification *)note {
    UDDiagnosticStore *store = [(UDDeclEditorViewController *)_editor diagnosticStore];
    [_document.diagnosticStore setDiagnostics:store.allDiagnostics forSource:@"quarry"];
}

// ---------------------------------------------------------------------------
// MARK: - UDEditorPanes
// ---------------------------------------------------------------------------

- (NSArray<NSViewController *> *)inspectorViewControllers {
    if (_inspectors) return _inspectors;
    NSMutableArray *controllers = [NSMutableArray array];
    if ([_editor conformsToProtocol:@protocol(UDInspecting)]) {
        for (UDEditorPane *pane in [(id<UDInspecting>)_editor inspectorPanes]) {
            UQPaneController *controller = [[UQPaneController alloc] initWithNibName:nil bundle:nil];
            controller.pane = pane;
            controller.view = pane.view;
            controller.title = pane.title;
            [controllers addObject:controller];
        }
    }
    _inspectors = controllers;
    return _inspectors;
}

- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController {
    UDEditorPane *pane = [viewController isKindOfClass:[UQPaneController class]] ? [(UQPaneController *)viewController pane] : nil;
    return pane ? UDTabBadge(pane.letters, pane.red, pane.green, pane.blue) : nil;
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    if ([_editor isKindOfClass:[UDDeclEditorViewController class]]) {
        [(UDDeclEditorViewController *)_editor revealDiagnostic:diagnostic];
    }
}

// ---------------------------------------------------------------------------
// MARK: - The editor's commands (the GUI editor's zoom, grid): its
// ---------------------------------------------------------------------------

/// The window sends the front tab's view controller what it answers: what
/// the editor answers, then.
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [_editor respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
    return [_editor respondsToSelector:selector] ? _editor : [super forwardingTargetForSelector:selector];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return [_editor respondsToSelector:@selector(validateMenuItem:)] ? [(id)_editor validateMenuItem:item] : YES;
}

- (void)showInspectorPaneTitled:(NSString *)title {
    for (NSViewController *controller in [self inspectorViewControllers]) {
        if ([controller.title isEqualToString:title]) [_workbench showEditorInspector:controller];
    }
}

@end
