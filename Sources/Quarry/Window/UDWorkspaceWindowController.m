#import "UDWorkspaceWindowController.h"
#import "UDDeclManagedObjects.h"
#import "UDPDAEditorViewController.h"
#import "UDDeclEditorViewController.h"
#import "UDWorkspaceDocument.h"
#import "UDDeclBrowser.h"
#import "UDEditorTabManager.h"
#import "UDWorkspace.h"
#import "UDBaseEditorViewController.h"
#import "UDBaseDocument.h"
#import "UDDeclDocument.h"
#import "UDDeclItem.h"
#import "UDWorkspaceSettingsWindowController.h"
#import "UDNewDeclWindowController.h"
#import "UDWorkspaceOpeningController.h"
#import <UDCodeKit/UDTabBarView.h>
#import <UDCodeKit/UDErrorsViewController.h>
#import "UDTextPromptPanel.h"
#import "UDTextEditorViewController.h"
#import "UDFileItem.h"
#import "UDScriptServer.h"
#import "idDeclManager.h"
#import "DMTabBar.h"
#import "UDTabBadge.h"
#import "UDScriptDebugger.h"
#import <objc/runtime.h>

// The panes' widths: what each side opens at, the least it can be dragged
// to, and the least the editors keep (RDLKit's designer's, near enough).
static const CGFloat UDNavigatorWidth = 240;
static const CGFloat UDInspectorWidth = 280;
static const CGFloat UDSidePaneMinimum = 160;
static const CGFloat UDEditorsMinimum = 400;
// the editors over the debug area: each at least so high
static const CGFloat UDEditorsMinimumHeight = 120;
static const CGFloat UDDebugAreaMinimum = 80;

@interface UDWorkspaceWindowController ()
@property (nonatomic, strong) UDEditorTabManager *tabManager;
@property (nonatomic, weak) IBOutlet NSView *issuesHost;
@property (nonatomic, strong) UDErrorsViewController *issuesNavigator;
@property (nonatomic, strong, nullable) UDWorkspaceSettingsWindowController *settingsController;
// "Opening…", while the workspace restarts with new settings.
@property (nonatomic, strong, nullable) UDWorkspaceOpeningController *openingController;
@property (nonatomic, readonly, getter=isRestarting) BOOL restarting;
/// The selected editor's inspector panes, as the right pane shows them, and
/// the title of the one last chosen (chosen again where an editor has it).
@property (nonatomic, copy) NSArray<UDEditorPane *> *inspectorPanes;
@property (nonatomic, copy, nullable) NSString *inspectorTitle;
/// The navigator's own tabs (the bar's items, their tab view items), and the
/// selected editor's after them.
@property (nonatomic, copy) NSArray<DMTabBarItem *> *navigatorItems;
@property (nonatomic) NSInteger navigatorFixedCount;
@property (nonatomic, copy) NSArray<UDEditorPane *> *navigatorPanes;
@property (nonatomic, strong, readwrite) UDScriptDebugger *scriptDebugger;
/// The debug area's height while shown (kept while it is hidden).
@property (nonatomic) CGFloat debugAreaHeight;
@property (nonatomic, readwrite, getter=isDebugAreaShown) BOOL debugAreaShown;
@end

@interface UDWorkspaceWindowController (UDScriptDebuggerDelegate) <UDScriptDebuggerDelegate, UDBreakpointNavigatorDelegate>
@end

@implementation UDWorkspaceWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"UDWorkspaceWindow"];
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // GNUstep: harden every scroll view in the window against the
    // scroller-autohide layout recursion (see UDBaseEditorViewController.h).
    [self.window.contentView ud_disableScrollerAutohideRecursively];

    self.declBrowser = [[UDDeclBrowser alloc] initWithWorkspace:self.workspace];
    self.declBrowser.delegate = self;

    [self.declBrowser attachToOutlineViews:self.outlineView searchOutline:self.searchOutlineView];
    [self.declBrowser reset];          // builds the full tree

    // Xcode-like editor tabs: both the UDTabBarView strip and the tabless
    // NSTabView below it live in UDWorkspaceWindow.xib; the tab manager
    // drives them as one control (dirty dot, close/pin buttons,
    // drag-to-reorder, horizontal scrolling).
    self.tabManager = [[UDEditorTabManager alloc] initWithTabView:self.tabView
                                                            tabBar:self.tabBarView
                                                         workspace:self.workspace];

    // The Issues tab: UDCodeKit's navigator (UDCode's too), listing the open
    // tabs' diagnostics; a click goes to one.
    self.issuesNavigator = [[UDErrorsViewController alloc] init];
    self.issuesNavigator.delegate = self;
    self.issuesNavigator.view.frame = self.issuesHost.bounds;
    self.issuesNavigator.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.issuesHost addSubview:self.issuesNavigator.view];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editorsDidChange:)
                                                 name:UDEditorTabManagerEditorsDidChangeNotification
                                               object:self.tabManager];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_selectedEditorDidChange:)
                                                 name:UDEditorTabManagerSelectionDidChangeNotification
                                               object:self.tabManager];
    [self _buildPanes];
    [self _buildDebugger];
    [self _selectedEditorDidChange:nil];
}

#pragma mark - The panes

/// The navigator's tab bar, after its tab view's items (RDLKit's
/// RDLFillTabBar), and the sides at their widths.
- (void)_buildPanes {
    NSArray<NSArray *> *navigator = @[
        @[ @"D", @"Decls and files", @0.47, @0.53, @0.64 ],
        @[ @"F", @"Find", @0.36, @0.55, @0.42 ],
        @[ @"I", @"Issues", @0.78, @0.42, @0.25 ],
        @[ @"Db", @"Debug", @0.36, @0.62, @0.45 ],
        @[ @"Bp", @"Breakpoints", @0.30, @0.50, @0.80 ],
    ];
    NSMutableArray<DMTabBarItem *> *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < navigator.count && i < (NSUInteger)self.navigatorTabView.numberOfTabViewItems; i++) {
        NSArray *tab = navigator[i];
        DMTabBarItem *item = [DMTabBarItem tabBarItemWithIcon:UDTabBadge(tab[0], [tab[2] doubleValue], [tab[3] doubleValue], [tab[4] doubleValue]) tag:i];
        item.toolTip = tab[1];
        [items addObject:item];
    }
    self.navigatorItems = items;
    self.navigatorFixedCount = (NSInteger)items.count;
    self.navigatorPanes = @[];
    self.navigatorTabBar.tabBarItems = items;
    [self.navigatorTabBar setTarget:self action:@selector(navigatorTabChanged:)];
    self.navigatorTabBar.selectedIndex = 0;
    self.inspectorPanes = @[];
    [self.inspectorTabBar setTarget:self action:@selector(inspectorTabChanged:)];
    [self _setDefaultPaneWidths];
}

/// The tab the bar has chosen. (The sender is the bar: an item's -tag read
/// off it is NSView's, -1.)
- (IBAction)navigatorTabChanged:(id)sender {
    NSUInteger index = self.navigatorTabBar.selectedIndex;
    if (index < (NSUInteger)self.navigatorTabView.numberOfTabViewItems) {
        [self.navigatorTabView selectTabViewItemAtIndex:(NSInteger)index];
    }
}

- (IBAction)inspectorTabChanged:(id)sender {
    NSUInteger index = self.inspectorTabBar.selectedIndex;
    if (index < self.inspectorPanes.count) {
        self.inspectorTitle = self.inspectorPanes[index].title;
        [self _showInspectorPane:self.inspectorPanes[index]];
    }
}

/// The left pane: its own tabs, and the editor's after them; the tab shown
/// kept if the editor has it (or it is one of the pane's own), else the
/// first.
- (void)_showNavigatorOf:(UDBaseEditorViewController *)editor {
    NSArray<UDEditorPane *> *panes = [editor conformsToProtocol:@protocol(UDNavigating)]
        ? ((id<UDNavigating>)editor).navigatorPanes : @[];
    if ([panes isEqualToArray:self.navigatorPanes]) return;
    NSTabView *tabView = self.navigatorTabView;
    NSInteger fixed = self.navigatorFixedCount;
    NSInteger selected = [tabView indexOfTabViewItem:tabView.selectedTabViewItem];
    NSString *selectedTitle = selected >= fixed && selected - fixed < (NSInteger)self.navigatorPanes.count
        ? self.navigatorPanes[(NSUInteger)(selected - fixed)].title : nil;

    // the last editor's tabs out (the view each brought taken back off)
    while (tabView.numberOfTabViewItems > fixed) {
        NSTabViewItem *item = [tabView tabViewItemAtIndex:fixed];
        [tabView removeTabViewItem:item];
    }
    self.navigatorPanes = panes;
    NSMutableArray<DMTabBarItem *> *items = [self.navigatorItems mutableCopy];
    NSInteger chosen = selectedTitle == nil ? MIN(selected, fixed - 1) : 0;
    for (NSUInteger i = 0; i < panes.count; i++) {
        UDEditorPane *pane = panes[i];
        NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:pane.title];
        item.label = pane.title;
        item.view = pane.view;
        [tabView addTabViewItem:item];
        DMTabBarItem *barItem = [DMTabBarItem tabBarItemWithIcon:UDTabBadge(pane.letters, pane.red, pane.green, pane.blue)
                                                             tag:(NSUInteger)fixed + i];
        barItem.toolTip = pane.title;
        [items addObject:barItem];
        if ([pane.title isEqualToString:selectedTitle]) chosen = fixed + (NSInteger)i;
    }
    self.navigatorTabBar.tabBarItems = items;
    self.navigatorTabBar.selectedIndex = (NSUInteger)MAX(chosen, 0);
    [tabView selectTabViewItemAtIndex:MAX(chosen, 0)];
}

/// The editor's navigator tab @a title shown (a GUI's windows, when its
/// design is wanted).
- (void)showNavigatorPaneTitled:(NSString *)title {
    for (NSUInteger i = 0; i < self.navigatorPanes.count; i++) {
        if ([self.navigatorPanes[i].title isEqualToString:title]) {
            NSInteger index = self.navigatorFixedCount + (NSInteger)i;
            self.navigatorTabBar.selectedIndex = (NSUInteger)index;
            [self.navigatorTabView selectTabViewItemAtIndex:index];
        }
    }
}

- (void)showInspectorPaneTitled:(NSString *)title {
    for (NSUInteger i = 0; i < self.inspectorPanes.count; i++) {
        if ([self.inspectorPanes[i].title isEqualToString:title]) {
            self.inspectorTitle = title;
            self.inspectorTabBar.selectedIndex = i;
            [self _showInspectorPane:self.inspectorPanes[i]];
        }
    }
}

/// The right pane: the editor's panes in its bar, the one chosen before if
/// it has one of that title, else its first; "No Inspector" for none.
- (void)_showInspectorOf:(UDBaseEditorViewController *)editor {
    NSArray<UDEditorPane *> *panes = [editor conformsToProtocol:@protocol(UDInspecting)]
        ? ((id<UDInspecting>)editor).inspectorPanes : @[];
    if ([panes isEqualToArray:self.inspectorPanes]) return;
    self.inspectorPanes = panes;
    NSMutableArray<DMTabBarItem *> *items = [NSMutableArray array];
    NSUInteger chosen = 0;
    for (NSUInteger i = 0; i < panes.count; i++) {
        UDEditorPane *pane = panes[i];
        DMTabBarItem *item = [DMTabBarItem tabBarItemWithIcon:UDTabBadge(pane.letters, pane.red, pane.green, pane.blue) tag:i];
        item.toolTip = pane.title;
        [items addObject:item];
        if ([pane.title isEqualToString:self.inspectorTitle]) chosen = i;
    }
    self.inspectorTabBar.tabBarItems = items;
    self.inspectorPlaceholder.hidden = panes.count > 0;
    if (panes.count > 0) {
        self.inspectorTabBar.selectedIndex = chosen;
        [self _showInspectorPane:panes[chosen]];
    } else {
        [self _showInspectorPane:nil];
    }
}

/// @a pane's view, alone in the host, filling it.
- (void)_showInspectorPane:(UDEditorPane *)pane {
    NSView *host = self.inspectorHost;
    for (NSView *view in [host.subviews copy]) {
        if (view != self.inspectorPlaceholder) [view removeFromSuperview];
    }
    if (pane == nil) return;
    NSView *view = pane.view;
    view.frame = host.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [host addSubview:view];
}

#pragma mark - The split (RDLKit's designer's)

// The widths each side opens at, set here: GSXib5 lays a split's subviews
// out itself rather than keeping the frames in the XIB.
- (void)_setDefaultPaneWidths {
    NSSplitView *split = self.split;
    if (split.subviews.count < 3) return;
    CGFloat width = NSWidth(split.bounds), divider = split.dividerThickness;
    // a window too narrow for both keeps what the split worked out
    if (width < UDNavigatorWidth + UDInspectorWidth + 2 * divider + UDEditorsMinimum) return;
    [split setPosition:UDNavigatorWidth ofDividerAtIndex:0];
    [split setPosition:width - UDInspectorWidth - divider ofDividerAtIndex:1];
}

/// What a wider window is for is wider editors: the sides keep the width
/// they were dragged to, as Xcode's do. Below the window's least width,
/// everyone gives, so none is squeezed away.
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview {
    if (splitView == self.editorSplit) return subview != self.debugPane;     // the editors take the change
    NSArray<NSView *> *panes = splitView.subviews;
    if (NSWidth(splitView.bounds) < self.window.minSize.width) return YES;
    return subview != panes.firstObject && subview != panes.lastObject;
}

#if !defined(__APPLE__)
// GNUstep's -adjustSubviews sizes the last subview to what is left and never
// asks -shouldAdjustSizeOfSubview: about it, so the inspector could not keep
// its width: the same rule, by hand. (RDLKit's designer's.)
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    if (splitView == self.editorSplit) {
        [self _layOutEditorSplit];
        return;
    }
    NSArray<NSView *> *subviews = splitView.subviews;
    NSUInteger n = subviews.count;
    if (n == 0) return;
    BOOL vertical = splitView.isVertical;
    NSRect bounds = splitView.bounds;
    CGFloat divider = splitView.dividerThickness;
    CGFloat total = (vertical ? NSWidth(bounds) : NSHeight(bounds)) - divider * (CGFloat)(n - 1);
    CGFloat spans[n];
    BOOL adjusts[n];
    CGFloat oldAdjustable = 0, fixed = 0;
    NSUInteger adjustableCount = 0;
    for (NSUInteger i = 0; i < n; i++) {
        NSRect frame = subviews[i].frame;
        spans[i] = vertical ? NSWidth(frame) : NSHeight(frame);
        adjusts[i] = ![splitView isSubviewCollapsed:subviews[i]] && [self splitView:splitView shouldAdjustSizeOfSubview:subviews[i]];
        if (adjusts[i]) {
            oldAdjustable += spans[i];
            adjustableCount++;
        } else {
            fixed += spans[i];
        }
    }
    CGFloat forAdjustable = MAX(0, total - fixed);
    CGFloat running = 0;
    for (NSUInteger i = 0; i < n; i++) {
        CGFloat span = spans[i];
        if (adjusts[i]) {
            span = oldAdjustable > 0.5 ? forAdjustable * (spans[i] / oldAdjustable) : forAdjustable / (CGFloat)adjustableCount;
        }
        NSRect rect = vertical ? NSMakeRect(running, 0, span, NSHeight(bounds)) : NSMakeRect(0, running, NSWidth(bounds), span);
        subviews[i].frame = [splitView centerScanRect:rect];
        running += span + divider;
    }
}
#endif

/// Each side has a floor, so a pane dragged to nothing can be had back;
/// the editors keep theirs.
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index {
    if (splitView == self.editorSplit) return MAX(proposed, UDEditorsMinimumHeight);
    return index == 0 ? MAX(proposed, UDSidePaneMinimum) : MAX(proposed, NSMinX([splitView.subviews[(NSUInteger)index] frame]) + UDEditorsMinimum);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index {
    if (splitView == self.editorSplit) return MIN(proposed, NSHeight(splitView.bounds) - splitView.dividerThickness - UDDebugAreaMinimum);
    CGFloat width = NSWidth(splitView.bounds), divider = splitView.dividerThickness;
    if (index == (NSInteger)splitView.subviews.count - 2) {
        return MIN(proposed, width - UDSidePaneMinimum - divider);
    }
    return MIN(proposed, width - NSWidth([splitView.subviews.lastObject frame]) - 2 * divider - UDEditorsMinimum);
}

#pragma mark - Editor | Source

/// The switch is the selected tab's: an editor with a source (a structured
/// decl editor, a GUI), shown as it is.
- (void)_selectedEditorDidChange:(NSNotification *)notification {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    BOOL hasSource = [editor conformsToProtocol:@protocol(UDSourceRepresenting)];
    self.representationControl.enabled = hasSource;
    self.representationControl.selectedSegment = hasSource && ((id<UDSourceRepresenting>)editor).showsSource ? 1 : 0;
    [self _showInspectorOf:editor];
    [self _showNavigatorOf:editor];
}

- (IBAction)showRepresentation:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor conformsToProtocol:@protocol(UDSourceRepresenting)]) {
        ((id<UDSourceRepresenting>)editor).showsSource = self.representationControl.selectedSegment == 1;
    }
    // As it is: the source stays up when its text does not parse.
    [self _selectedEditorDidChange:nil];
}

-(UDWorkspace *)workspace {
    return ((UDWorkspaceDocument *)self.document).workspace;
}

#pragma mark - Undo

// The standard Core Data undo wiring: the window hands the CURRENT tab's
// document undo manager to the responder chain, so Edit > Undo / Redo in
// the main menu operate on the active editor. For decl documents that is
// their private editing context's undo manager — Core Data registers every
// managed object change with it automatically; the forms themselves need no
// undo code at all. (This controller is the window's delegate, wired in
// UDWorkspaceWindow.xib.)
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    NSUndoManager *undoManager = [self.tabManager selectedEditor].editorDocument.undoManager;
    return undoManager ?: [self.document undoManager];
}

#pragma mark - Saving (File menu)

// The window controller sits in the responder chain BEFORE the workspace
// document, so it owns the File menu save actions — VSCode-style:
//   Save       (Cmd-S)        the current tab's document only
//   Save All   (Opt-Cmd-S)    every dirty open tab
//   Save As…   (Shift-Cmd-S)  the current decl under a new name, as a new decl

- (IBAction)saveDocument:(id)sender {
    UDBaseDocument *document = [self.tabManager selectedEditor].editorDocument;
    if (document == nil) {
        return;
    }

    // Commit any in-flight field editing before saving; the keyboard goes
    // back where it was.
    NSResponder *responder = [self _endEditing];

    NSError *error = nil;
    if (![document ud_save:&error]) {
        [self presentError:error];
    }
    [self.window makeFirstResponder:responder];
}

/// Ends the editing in progress (a field's), and says who had the keyboard:
/// the text view, the text field (not its field editor), ...
- (NSResponder *)_endEditing {
    NSResponder *responder = self.window.firstResponder;
    if ([responder isKindOfClass:[NSText class]] && ((NSText *)responder).isFieldEditor
        && [((NSText *)responder).delegate isKindOfClass:[NSResponder class]]) {
        responder = (NSResponder *)((NSText *)responder).delegate;
    }
    [self.window makeFirstResponder:nil];
    return responder;
}

- (IBAction)saveAllDocuments:(id)sender {
    NSResponder *responder = [self _endEditing];

    for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
        UDBaseDocument *document = editor.editorDocument;
        if (document == nil || !document.isDocumentEdited) {
            continue;
        }
        NSError *error = nil;
        if (![document ud_save:&error]) {
            [self presentError:error];
        }
    }
    [self.window makeFirstResponder:responder];
}

- (IBAction)saveDocumentAs:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    UDBaseDocument *document = editor.editorDocument;
    if (![document isKindOfClass:[UDDeclDocument class]]) {
        NSBeep();
        return;
    }

    UDDeclDocument *declDocument = (UDDeclDocument *)document;
    if (declDocument.declObject == nil) {
        NSBeep(); // legacy raw-text decl types don't support Save As yet
        return;
    }

    [self.window makeFirstResponder:nil];

    declType_t type = declDocument.declType;
    NSString *typeName = [self.workspace.declManager declNameFromType:type];
    NSString *originalName = declDocument.declObject.name;

    NSString *newName = [self _runNamePromptWithTitle:[NSString stringWithFormat:@"Save %@ \u201C%@\u201D As", typeName, originalName]
        message:@"The current content is saved as a new decl with this name, in the same file. The original decl keeps its last saved state."
        okButtonTitle:@"Save" typeName:typeName type:type initialValue:originalName];
    if (newName == nil) {
        return; // cancelled
    }

    NSError *error = nil;
    UDDeclBase *newDecl = [declDocument saveAsNewDeclNamed:newName error:&error];
    if (newDecl == nil) {
        [self presentError:error];
        return;
    }

    // The buffer's content now lives in the new decl: re-open the editor on
    // it (the original tab reverted to its last saved state) and refresh the
    // browser tree so the new decl shows up.
    NSString *oldPath = editor.item.path;
    if (oldPath.length > 0) {
        [self.tabManager closeTabForPath:oldPath];
    }
    UDDeclItem *newItem = [[UDDeclItem alloc] initWithType:type declName:newName path:newName];
    [self.tabManager openEditorForWorkspaceItem:newItem];
    [self.declBrowser reset];
}

/// Asks for a new decl's name. Returns nil on cancel; keeps asking while the
/// name is empty or already taken.
- (NSString *)_runNamePromptWithTitle:(NSString *)title
                              message:(NSString *)message
                        okButtonTitle:(NSString *)okButtonTitle
                             typeName:(NSString *)typeName
                                 type:(declType_t)type
                         initialValue:(NSString *)initialValue {
    NSString *value = initialValue ?: @"";

    while (YES) {
        NSString *entered = [UDTextPromptPanel runModalPromptWithTitle:title
                                                               message:message
                                                          initialValue:value
                                                         okButtonTitle:okButtonTitle];
        if (entered == nil) {
            return nil; // cancelled
        }
        value = entered; // re-show what the user typed if we loop

        NSString *candidate = [entered stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (candidate.length == 0) {
            continue;
        }
        if ([self.workspace.declManager findDeclWithoutParsing:type name:candidate makeDefault:NO] != nil) {
            NSAlert *taken = [[NSAlert alloc] init];
            taken.messageText = @"Name already in use";
            taken.informativeText = [NSString stringWithFormat:@"A %@ decl named “%@” already exists. Choose a different name.", typeName, candidate];
            [taken runModal];
            continue;
        }
        return candidate;
    }
}

#pragma mark - New PDA, New Skin

// File > New PDA…, New Skin…: a decl of its own name, in a file of its own
// (newpdas/<name>.pda, skins/<name>.skin: the type's folder, where the store
// puts a new decl), opened in its editor; Save writes the file.
- (IBAction)newPDA:(id)sender {
    [self _newDeclOfTypeName:@"pda" title:@"New PDA" fileName:@"newpdas/<name>.pda"];
}

- (IBAction)newSkin:(id)sender {
    [self _newDeclOfTypeName:@"skin" title:@"New Skin" fileName:@"skins/<name>.skin"];
}

- (void)_newDeclOfTypeName:(NSString *)typeName title:(NSString *)title fileName:(NSString *)fileName {
    idDeclManager *declManager = self.workspace.declManager;
    declType_t type = [declManager declTypeFromName:typeName];
    NSString *name = [self _runNamePromptWithTitle:title
        message:[NSString stringWithFormat:@"It gets a file of its own, %@, written when it is saved.", fileName]
        okButtonTitle:@"Create" typeName:typeName type:type
        initialValue:[declManager newName:type base:[typeName stringByAppendingString:@"_"]]];
    if (name == nil) return;

    NSError *error = nil;
    if (![self _createDeclOfTypeName:typeName named:name fileName:nil error:&error]) {
        [self presentError:error];
        return;
    }
    [self.declBrowser reset];
    [self.tabManager openEditorForWorkspaceItem:[[UDDeclItem alloc] initWithType:type declName:name path:name]];
}

#pragma mark - New Declaration

// File > New Declaration…: DialogDeclNew's type, name and file; the decl
// starts from its type's default definition, in that file (a new one, or
// one the decls already come from), and opens in its editor.
- (IBAction)newDecl:(id)sender {
    id selected = [self.outlineView itemAtRow:self.outlineView.selectedRow];
    NSString *typeName = [selected isKindOfClass:[UDDeclItem class]]
        ? [self.workspace.declManager declNameFromType:((UDDeclItem *)selected).type] : nil;
    UDNewDeclWindowController *dialog = [[UDNewDeclWindowController alloc] initWithDeclManager:self.workspace.declManager
                                                                                        typeName:typeName];
    if ([dialog runModal] != NSModalResponseOK) return;

    NSError *error = nil;
    if (![self _createDeclOfTypeName:dialog.typeName named:dialog.declName fileName:dialog.fileName error:&error]) {
        [self presentError:error];
        return;
    }
    declType_t type = [self.workspace.declManager declTypeFromName:dialog.typeName];
    [self.declBrowser reset];
    [self.tabManager openEditorForWorkspaceItem:[[UDDeclItem alloc] initWithType:type declName:dialog.declName path:dialog.declName]];
}

/// A new decl of @a typeName in @a fileName, or where the store puts one of
/// its type when that is nil.
- (BOOL)_createDeclOfTypeName:(NSString *)typeName named:(NSString *)name fileName:(NSString *)fileName error:(NSError **)error {
    NSManagedObjectContext *context = [self.workspace newDeclEditingContextWithError:error];
    if (context == nil) return NO;
    NSString *entityName = [UDDeclBase ud_entityNameForDeclTypeName:typeName
                                                              inModel:context.persistentStoreCoordinator.managedObjectModel];
    if (entityName == nil) return NO;
    UDDeclBase *decl = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:context];
    decl.name = name;
    if (fileName.length > 0) {
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"DeclFile"];
        request.predicate = [NSPredicate predicateWithFormat:@"fileName ==[c] %@", fileName];
        NSManagedObject *file = [[context executeFetchRequest:request error:NULL] firstObject];
        if (file == nil) {
            file = [NSEntityDescription insertNewObjectForEntityForName:@"DeclFile" inManagedObjectContext:context];
            [file setValue:fileName forKey:@"fileName"];
        }
        [decl setValue:file forKey:@"sourceFile"];
    }
    return [context save:error];
}

#pragma mark - Workspace settings

// File > Workspace Settings…: edit ALL workspace settings (paths, game,
// file system flags, decl options) in the tabbed settings window, a plain
// window (no modal session holding the menus); OK or Cancel come back to
// -_settingsDidFinish:. On OK the workspace is restarted in place: the new
// paths/game invalidate the loaded VFS and decls, so every tab is closed
// and the browser tree rebuilt.
- (IBAction)showWorkspaceSettings:(id)sender {
    if (self.settingsController != nil) {
        [self.settingsController showWindow:nil];
        return;
    }
    UDWorkspaceSettingsWindowController *settingsWC =
        [[UDWorkspaceSettingsWindowController alloc] initWithWindowNibName:@"UDWorkspaceSettings"];
    settingsWC.document = self.document;
    settingsWC.target = self;
    settingsWC.action = @selector(_settingsDidFinish:);
    self.settingsController = settingsWC;
    [settingsWC showWindow:nil];
}

- (void)_settingsDidFinish:(UDWorkspaceSettingsWindowController *)settingsWC {
    self.settingsController = nil;
    if (settingsWC.result != NSModalResponseOK) {
        return;
    }

    // Applying settings restarts the workspace, which discards any unsaved
    // editor changes — get the user's blessing first.
    BOOL hasDirtyEditors = NO;
    for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
        if (editor.editorDocument.isDocumentEdited) {
            hasDirtyEditors = YES;
            break;
        }
    }
    if (hasDirtyEditors) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Apply settings and reload the workspace?";
        alert.informativeText = @"Some open editors have unsaved changes. Applying the new settings reloads the workspace and discards them.";
        [alert addButtonWithTitle:@"Apply and Discard"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return; // nothing applied
        }
    }

    // Apply the scratch copy to the real workspace and restart it in place.
    UDWorkspace *workspace = self.workspace;
    [workspace applySettingsFromDictionary:settingsWC.scratchWorkspace.dictionaryRepresentation];
    [self.document updateChangeCount:NSChangeDone];

    [self.tabManager closeAllTabs];
    [self.declBrowser clear];
    [UDScriptServer stopForWorkspace:workspace];
    [workspace shutdown];

    // It starts again in the background, "Opening…" over the window, which
    // offers nothing meanwhile (its outline empty, its commands off).
    self.openingController = [[UDWorkspaceOpeningController alloc] initWithWorkspaceName:[(NSDocument *)self.document displayName]];
    [self.openingController showOverWindow:self.window];
    [workspace startupInBackgroundWithTarget:self action:@selector(_workspaceDidRestart:)];
}

- (void)_workspaceDidRestart:(UDWorkspace *)workspace {
    [self.openingController close];
    self.openingController = nil;
    if (workspace.startupError != nil) {
        [self presentError:workspace.startupError];
        return;
    }
    [self.declBrowser reset];
}

- (BOOL)isRestarting {
    return self.openingController != nil;
}

#pragma mark - Issues

/// The text tabs' stores, by their names, in the Issues navigator.
- (void)_editorsDidChange:(NSNotification *)notification {
    NSMutableArray<UDDiagnosticStore *> *stores = [NSMutableArray array];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
        if ([editor isKindOfClass:[UDTextEditorViewController class]]) {
            ((UDTextEditorViewController *)editor).breakpointStore = self.scriptDebugger.breakpoints;
        }
        // A script's errors, a PDA's missing references: any editor's store.
        if (![editor respondsToSelector:@selector(diagnosticStore)]) continue;
        UDDiagnosticStore *store = [(id)editor diagnosticStore];
        if (store == nil) continue;
        [stores addObject:store];
        [names addObject:editor.item.name ?: editor.item.path ?: @""];
    }
    [self.issuesNavigator setStores:stores displayNames:names];
}

- (void)errorsViewController:(UDErrorsViewController *)vc
         didSelectDiagnostic:(UDDiagnosticItem *)diagnostic
                     inStore:(UDDiagnosticStore *)store {
    for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
        if ([editor isKindOfClass:[UDDeclEditorViewController class]] &&
            ((UDDeclEditorViewController *)editor).diagnosticStore == store) {
            [self.tabManager openEditorForWorkspaceItem:editor.item];
            [(UDDeclEditorViewController *)editor revealDiagnostic:diagnostic];
            return;
        }
        if (![editor isKindOfClass:[UDTextEditorViewController class]] ||
            ((UDTextEditorViewController *)editor).diagnosticStore != store) continue;
        [self.tabManager openEditorForWorkspaceItem:editor.item];
        // The diagnostic's line is 1-based, its column 0-based.
        [(UDTextEditorViewController *)editor selectLine:MAX(diagnostic.line - 1, 0)
                                               character:MAX(diagnostic.column, 0) length:0];
        [self _selectedEditorDidChange:nil];    // a GUI's tab goes to its source for it
        return;
    }
}

#pragma mark - Test Declaration

- (IBAction)testDecl:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) {
        [(UDTextEditorViewController *)editor testDecl:sender];
    } else {
        NSBeep();
    }
}

#pragma mark - Copy and Paste, an editor's own

// What no view before the window takes (a text view copies its text): the
// editor's, when it has its own (the material editor's stages).
- (IBAction)copy:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor respondsToSelector:@selector(copy:)]) {
        [(id)editor copy:sender];
    } else {
        NSBeep();
    }
}

- (IBAction)paste:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor respondsToSelector:@selector(paste:)]) {
        [(id)editor paste:sender];
    } else {
        NSBeep();
    }
}

#pragma mark - The GUI editor's View commands

- (IBAction)toggleGrid:(id)sender {
    [self _sendToEditor:_cmd from:sender];
}

- (IBAction)toggleGridSnap:(id)sender {
    [self _sendToEditor:_cmd from:sender];
}

- (IBAction)showGuiEditorOptions:(id)sender {
    [self _sendToEditor:_cmd from:sender];
}

- (IBAction)toggleStatusBar:(id)sender {
    [self _sendToEditor:_cmd from:sender];
}

- (IBAction)zoomIn:(id)sender {
    [self _sendToEditor:_cmd from:sender];
}

- (IBAction)zoomOut:(id)sender {
    [self _sendToEditor:_cmd from:sender];
}

- (IBAction)zoomToFit:(id)sender {
    [self _sendToEditor:_cmd from:sender];
}

/// A command the selected editor takes when it has it.
- (void)_sendToEditor:(SEL)action from:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor respondsToSelector:action]) {
        [NSApp sendAction:action to:editor from:sender];
    } else {
        NSBeep();
    }
}

#pragma mark - The debugger (UDScriptDebugger)

/// The debugger's views in their hosts: the navigator's tab; the bar over
/// the area, under the editors, hidden until a session starts.
- (void)_buildDebugger {
    self.scriptDebugger = [[UDScriptDebugger alloc] initWithWorkspace:self.workspace];
    self.scriptDebugger.delegate = self;
    NSView *navigator = self.scriptDebugger.navigator.view;
    navigator.frame = self.debugNavigatorHost.bounds;
    navigator.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.debugNavigatorHost addSubview:navigator];
    NSView *breakpoints = self.scriptDebugger.breakpointNavigator.view;
    breakpoints.frame = self.breakpointNavigatorHost.bounds;
    breakpoints.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.breakpointNavigatorHost addSubview:breakpoints];
    self.scriptDebugger.breakpointNavigator.delegate = self;
    // the breakpoints and watches kept as VS Code keeps them: the
    // workspace's state, not its settings (no save asked for)
    NSString *workspacePath = [(NSDocument *)self.document fileURL].path ?: self.workspace.fs_basepath ?: @"Untitled";
    self.scriptDebugger.breakpoints.autosaveName = [@"Quarry Debugger " stringByAppendingString:workspacePath];
    [self.debugBarHost addSubview:self.scriptDebugger.bar.view];
    [self.debugAreaHost addSubview:self.scriptDebugger.area.view];
    self.debugAreaHeight = 240;
    self.debugAreaShown = NO;
    [self _layOutEditorSplit];
}

/// The editors over the debug area (its height kept, or none while it is
/// hidden), and in it the bar over the area: laid out here, as a pane that
/// was no height lays out nothing by its autoresizing.
- (void)_layOutEditorSplit {
    NSSplitView *split = self.editorSplit;
    if (split == nil || split.subviews.count < 2) return;
    NSRect bounds = split.bounds;
    CGFloat divider = split.dividerThickness;
    CGFloat pane = self.debugAreaShown ? MIN(self.debugAreaHeight, NSHeight(bounds) - divider - UDEditorsMinimumHeight) : 0;
    pane = MAX(pane, 0);
    CGFloat editorsHeight = NSHeight(bounds) - pane - (self.debugAreaShown ? divider : 0);
    // the editors on top, flipped or not
    BOOL flipped = split.isFlipped;
    NSView *editors = split.subviews[0];
    editors.frame = NSMakeRect(0, flipped ? 0 : NSHeight(bounds) - editorsHeight, NSWidth(bounds), editorsHeight);
    self.debugPane.frame = NSMakeRect(0, flipped ? NSHeight(bounds) - pane : 0, NSWidth(bounds), pane);
    self.debugPane.hidden = !self.debugAreaShown;
    [self _layOutDebugPane];
}

- (void)_layOutDebugPane {
    NSRect bounds = self.debugPane.bounds;
    // hidden: the bar and the area keep their size, as their own views'
    // autoresizing does not come back from none (the variables' scroll view
    // came back reaching over the area's top, its first row under it)
    if (!self.debugAreaShown || NSHeight(bounds) < 1) return;
    NSView *bar = self.scriptDebugger.bar.view;
    CGFloat barHeight = MIN(NSHeight(bar.frame) > 0 ? NSHeight(bar.frame) : 28, NSHeight(bounds));
    BOOL flipped = self.debugPane.isFlipped;
    self.debugBarHost.frame = NSMakeRect(0, flipped ? 0 : NSHeight(bounds) - barHeight, NSWidth(bounds), barHeight);
    self.debugAreaHost.frame = NSMakeRect(0, flipped ? barHeight : 0, NSWidth(bounds), MAX(NSHeight(bounds) - barHeight, 0));
    bar.frame = self.debugBarHost.bounds;
    self.scriptDebugger.area.view.frame = self.debugAreaHost.bounds;
}

/// A divider's drag: the area's new height, kept.
- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    if (notification.object != self.editorSplit || !self.debugAreaShown) return;
    CGFloat height = NSHeight(self.debugPane.frame);
    if (height >= UDDebugAreaMinimum) self.debugAreaHeight = height;
    [self _layOutDebugPane];
}

- (void)_setDebugAreaShown:(BOOL)shown {
    if (shown == self.debugAreaShown) return;
    self.debugAreaShown = shown;
    [self _layOutEditorSplit];
    [self.editorSplit setNeedsDisplay:YES];
}

/// Debug > Toggle Breakpoint, from the window (on GNUstep a view's
/// controller is not among its responders): the selected script's tab's.
- (IBAction)toggleBreakpoint:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) [(UDTextEditorViewController *)editor toggleBreakpoint:sender];
    else NSBeep();
}

- (IBAction)runToCursor:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) [(UDTextEditorViewController *)editor runToCursor:sender];
    else NSBeep();
}

- (IBAction)jumpToCursor:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) [(UDTextEditorViewController *)editor jumpToCursor:sender];
    else NSBeep();
}

- (IBAction)toggleDebugArea:(id)sender {
    [self _setDebugAreaShown:!self.debugAreaShown];
}

- (void)_presentDebuggerError:(NSError *)error {
    NSAlert *alert = [NSAlert alertWithError:error];
    [alert beginSheetModalForWindow:self.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

- (IBAction)startDebugging:(id)sender {
    NSError *error = nil;
    if (![self.scriptDebugger run:&error]) [self _presentDebuggerError:error];
}

- (IBAction)attachDebugger:(id)sender {
    NSError *error = nil;
    if (![self.scriptDebugger attach:&error]) [self _presentDebuggerError:error];
}

- (IBAction)stopDebugging:(id)sender {
    [self.scriptDebugger.bar stop:sender];
}

- (IBAction)debugContinueOrPause:(id)sender {
    [self.scriptDebugger.bar continueOrPause:sender];
}

- (IBAction)debugStepOver:(id)sender {
    [self.scriptDebugger.bar stepOver:sender];
}

- (IBAction)debugStepInto:(id)sender {
    [self.scriptDebugger.bar stepInto:sender];
}

- (IBAction)debugStepOut:(id)sender {
    [self.scriptDebugger.bar stepOut:sender];
}

/// The debugger's menu items: its bar's say for the session's actions
/// (compared with sel_isEqual: GNUstep's runtime gives a XIB's selector
/// another pointer).
- (BOOL)_validateDebugAction:(SEL)action menuItem:(NSMenuItem *)menuItem handled:(BOOL *)handled {
    *handled = YES;
    UDDebugBarViewController *bar = self.scriptDebugger.bar;
    // Run while debugging: a restart, as Xcode's
    if (sel_isEqual(action, @selector(startDebugging:))) return self.workspace != nil;
    if (sel_isEqual(action, @selector(attachDebugger:))) return self.workspace != nil && !self.scriptDebugger.debugging;
    if (sel_isEqual(action, @selector(stopDebugging:))) return [bar canPerformAction:@selector(stop:)];
    if (sel_isEqual(action, @selector(debugContinueOrPause:))) {
        menuItem.title = self.scriptDebugger.session.state == UDDebugSessionStateRunning ? @"Pause" : @"Continue";
        return [bar canPerformAction:@selector(continueOrPause:)];
    }
    if (sel_isEqual(action, @selector(debugStepOver:))) return [bar canPerformAction:@selector(stepOver:)];
    if (sel_isEqual(action, @selector(debugStepInto:))) return [bar canPerformAction:@selector(stepInto:)];
    if (sel_isEqual(action, @selector(debugStepOut:))) return [bar canPerformAction:@selector(stepOut:)];
    if (sel_isEqual(action, @selector(toggleBreakpoint:))) {
        UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
        return [editor isKindOfClass:[UDTextEditorViewController class]] && ((UDTextEditorViewController *)editor).breakpointStore != nil;
    }
    if (sel_isEqual(action, @selector(runToCursor:))) {
        UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
        return [editor isKindOfClass:[UDTextEditorViewController class]] && self.scriptDebugger.session.canContinue;
    }
    if (sel_isEqual(action, @selector(jumpToCursor:))) {
        UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
        return [editor isKindOfClass:[UDTextEditorViewController class]] && self.scriptDebugger.session.canJump;
    }
    if (sel_isEqual(action, @selector(toggleDebugArea:))) {
        menuItem.title = self.debugAreaShown ? @"Hide Debug Area" : @"Show Debug Area";
        return YES;
    }
    *handled = NO;
    return NO;
}

#pragma mark - Jump to Definition

- (IBAction)jumpToDefinition:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) {
        [(UDTextEditorViewController *)editor jumpToDefinition:sender];
    } else {
        NSBeep();
    }
}

- (void)openFileAtPath:(NSString *)path line:(NSInteger)line character:(NSInteger)character length:(NSInteger)length {
    UDBaseEditorViewController *editor = [self.tabManager openEditorForWorkspaceItem:[[UDFileItem alloc] initWithPath:path]];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) {
        [(UDTextEditorViewController *)editor selectLine:line character:character length:length];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UDEditorTabManagerEditorsDidChangeNotification
                                                  object:self.tabManager];
    // The settings go with the workspace, unapplied.
    self.settingsController.target = nil;
    [self.settingsController close];
    self.settingsController = nil;
    [self.tabManager closeAllTabs];
    [UDScriptServer stopForWorkspace:self.workspace];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (self.isRestarting) {
        return NO;
    }
    BOOL handled = NO;
    BOOL valid = [self _validateDebugAction:action menuItem:menuItem handled:&handled];
    if (handled) return valid;

    if (action == @selector(jumpToDefinition:) || action == @selector(testDecl:)) {
        UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
        return [editor isKindOfClass:[UDTextEditorViewController class]] &&
               [(UDTextEditorViewController *)editor validateMenuItem:menuItem];
    }

    if (action == @selector(copy:) || action == @selector(paste:) || action == @selector(toggleGrid:)
        || action == @selector(toggleGridSnap:) || action == @selector(showGuiEditorOptions:)
        || action == @selector(toggleStatusBar:) || action == @selector(zoomIn:) || action == @selector(zoomOut:)
        || action == @selector(zoomToFit:)) {
        UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
        return [editor respondsToSelector:action] &&
               (![editor respondsToSelector:@selector(validateMenuItem:)] || [(id)editor validateMenuItem:menuItem]);
    }

    if (action == @selector(showWorkspaceSettings:)) {
        return self.workspace != nil;
    }
    if (action == @selector(saveDocument:)) {
        UDBaseDocument *document = [self.tabManager selectedEditor].editorDocument;
        return document != nil && document.isDocumentEdited;
    }
    if (action == @selector(saveAllDocuments:)) {
        for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
            if (editor.editorDocument.isDocumentEdited) {
                return YES;
            }
        }
        return NO;
    }
    if (action == @selector(newDecl:) || action == @selector(newPDA:) || action == @selector(newSkin:)) {
        return self.workspace.declManager != nil;
    }
    if (action == @selector(saveDocumentAs:)) {
        UDBaseDocument *document = [self.tabManager selectedEditor].editorDocument;
        return [document isKindOfClass:[UDDeclDocument class]] &&
               ((UDDeclDocument *)document).declObject != nil;
    }
    return YES;
}

//
// text editing
//

- (void)textDidChange:(NSNotification *)notification {
#if 0
    id selected = /* currently selected decl */;
    if (selected) {
        [self.document setText:self.textView.string forDecl:selected];
        [self.document updateChangeCount:NSChangeDone];
    }
#endif
}

- (IBAction)nameFilterChanged:(NSSearchField *)sender {
    NSString *name = sender.stringValue;
    
    [self.declBrowser findByName:(name.length ? name : @"*")];
}

- (IBAction)textContainsFilterChanged:(NSSearchField *)sender {
    NSString *name = sender.stringValue;
    
    [self.declBrowser findContaining:name ?: @""];
}

#pragma mark - UDDeclBrowserDelegate

- (void)declBrowser:(UDDeclBrowser *)browser didSelectResource:(UDWorkspaceItem *)resource {
    if (resource.kind == UDWorkspaceItemKindGroup) {
        return;
    }

    [self.tabManager openEditorForWorkspaceItem:resource];
}

- (void)declBrowserDidClearSelection:(UDDeclBrowser *)browser {
    // TODO: do something about it?
}

@end

@implementation UDWorkspaceWindowController (UDScriptDebuggerDelegate)

/// The selected frame's script: opened, its line chosen (a pak's, read-only).
- (void)scriptDebugger:(UDScriptDebugger *)debugger showScript:(NSString *)gamePath line:(NSInteger)line {
    [self openFileAtPath:gamePath line:MAX(line - 1, 0) character:0 length:0];
}

/// A session: the debug area, and the debug navigator.
- (void)scriptDebuggerDidStart:(UDScriptDebugger *)debugger {
    [self _setDebugAreaShown:YES];
    [self _showDebugNavigator];
}

/// Stopped: Quarry forward, at the debug navigator, as Xcode does.
- (void)scriptDebuggerDidStop:(UDScriptDebugger *)debugger {
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self _setDebugAreaShown:YES];
    [self _showDebugNavigator];
}

- (void)_showDebugNavigator {
    NSUInteger debug = 3;
    if (debug < (NSUInteger)self.navigatorTabView.numberOfTabViewItems) {
        self.navigatorTabBar.selectedIndex = debug;
        [self.navigatorTabView selectTabViewItemAtIndex:(NSInteger)debug];
    }
}

#pragma mark - UDBreakpointNavigatorDelegate

- (void)breakpointNavigator:(UDBreakpointNavigatorViewController *)navigator showBreakpoint:(UDBreakpoint *)breakpoint {
    NSString *gamePath = [self.workspace gamePathOfDiskPath:breakpoint.path];
    if (gamePath != nil) [self openFileAtPath:gamePath line:MAX(breakpoint.line - 1, 0) character:0 length:0];
}

- (void)breakpointNavigator:(UDBreakpointNavigatorViewController *)navigator editBreakpoint:(UDBreakpoint *)breakpoint {
    [self breakpointNavigator:navigator showBreakpoint:breakpoint];
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) {
        [(UDTextEditorViewController *)editor editBreakpointAtLine:breakpoint.line];
    }
}

@end
