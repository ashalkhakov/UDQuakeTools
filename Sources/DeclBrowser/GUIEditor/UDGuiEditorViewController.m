#import "UDGuiEditorViewController.h"
#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "UDGuiPlayer.h"
#import "UDGuiView.h"
#import "UDTransportController.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceItem.h"
#import "idUserInterface.h"
#import "idDict.h"
#import "idWindow.h"
#import "idParser.h"
#import "idLexer.h"
#import "idStr.h"
#import "idGuiModel.h"
#import "UDSoftwareRenderer.h"
#import "UDTextFileDocument.h"
#import "UDOverlay.h"
#import "rvGEWorkspace.h"
#import "rvGEModifier.h"
#import "rvGESelectionMgr.h"
#import "rvGEWindowWrapper.h"
#import <UDCodeKit/UDDiagnosticStore.h>

static UDDiagnosticSource const UDGuiParseSource = @"gui";

@interface UDGuiEditorViewController () <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, strong, readwrite) UDGuiPlayer *player;
@property (nonatomic, copy, readwrite, nullable) NSString *runningText;
/// The state as the table shows it, sorted by key.
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *stateRows;
@property (nonatomic) NSUInteger logRowsShown;
/// When the state table was last brought up to date (a few times a second).
@property (nonatomic, strong, nullable) NSDate *stateShown;

@property (nonatomic, readwrite) BOOL designing;
@property (nonatomic, strong, readwrite, nullable) rvGEWorkspace *designWorkspace;
/// The text as the file has it (the source's when the tab opened).
@property (nonatomic, copy, nullable) NSString *fileText;
/// The text the source shows, and the design is in step with — but for
/// the canvas's edits since (designDirty).
@property (nonatomic, copy, nullable) NSString *shownText;
@property (nonatomic) BOOL designDirty;
/// What the workspace was loaded from.
@property (nonatomic, copy, nullable) NSString *designText;
@property (nonatomic) BOOL playedBeforeDesigning;
@property (nonatomic, strong, readwrite) UDTransportController *transport;
/// The run's window for each of the design's (the design's window the key).
@property (nonatomic, strong) NSMapTable<idWindow *, idWindow *> *runWindows;
/// The windows locked in the navigator: not chosen on the canvas.
@property (nonatomic, strong) NSHashTable<idWindow *> *lockedWindows;
/// The run the map is of (the player's GUI when it was mapped).
@property (nonatomic, weak) idUserInterfaceLocal *mappedRun;
/// Whether edits were made in the run since it was read.
@property (nonatomic) BOOL runEdited;
/// Whether the run is to be read again to hold the design as it is.
@property (nonatomic) BOOL runStale;
/// The names of the windows the design hid when it loaded.
@property (nonatomic, strong) NSMutableSet<NSString *> *loadedHidden;
/// The navigator's selection being set from the design's (not the other
/// way round).
@property (nonatomic) BOOL syncingWindows;
/// The Properties' rows, and the one being added (its name, while it has
/// no value yet).
@property (nonatomic, copy, nullable) NSArray<NSArray<NSString *> *> *propertyRows;
@property (nonatomic, copy, nullable) NSString *pendingProperty;
/// The window whose scripts the Scripts show, and their text as shown.
@property (nonatomic, weak, nullable) idWindow *scriptsWindow;
@property (nonatomic, copy, nullable) NSString *scriptsShownText;
@end

@implementation UDGuiEditorViewController {
    NSArray<UDEditorPane *> *_panes;
    NSArray<UDEditorPane *> *_navigatorPanes;
}

@synthesize showsSource = _showsSource;

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.item == nil) return;

    [[NSBundle bundleForClass:[UDGuiEditorViewController class]] loadNibNamed:@"UDGuiViewerView" owner:self topLevelObjects:nil];
    self.stateRows = @[];

    self.lockedWindows = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    self.runWindows = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
                                            valueOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    self.player = [[UDGuiPlayer alloc] initWithWorkspace:self.workspace];
    self.player.target = self;
    self.player.action = @selector(playerDidDrawFrame:);
    self.guiView.player = self.player;
    self.player.view = self.guiView;
    self.player.textSource = self;
    self.player.textSourceAction = @selector(runTextFor:);
    self.transport = [[UDTransportController alloc] init];
    self.transport.playable = self.player;
    self.transport.target = self;
    self.transport.action = @selector(transportMoved:);
    [self.transport installInView:self.transportView];
    self.fileText = self.editorTextView.string;
    self.shownText = self.fileText;
    [self _run];
    // loaded for editing too, its windows in the navigator
    [self _design];
    self.windowsOutline.target = self;
    self.windowsOutline.doubleAction = @selector(showProperties:);
    self.scriptsText.font = [NSFont userFixedPitchFontOfSize:11];
    [self _updateProperties];
    [self _updateScripts:YES];

    // a canvas edited since its text was shown saves its text
    if ([self.document isKindOfClass:[UDTextFileDocument class]]) {
        UDTextFileDocument *document = (UDTextFileDocument *)self.document;
        document.textSource = self;
        document.textSourceAction = @selector(documentTextFor:);
    }

    // The running GUI over the source, which is under it all along
    NSView *viewer = self.viewerView;
    viewer.frame = self.view.bounds;
    viewer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:viewer];
    [self _showViewer:YES];
}

/// The viewer, or the source under it: the one not shown hidden (the
/// viewer's toolbar is not opaque).
- (void)_showViewer:(BOOL)viewer {
    for (NSView *view in self.view.subviews) {
        view.hidden = (view == self.viewerView) != viewer;
    }
}

/// The GUI's text as it is now: the canvas's, if it was edited since the
/// source showed it, else the source's.
- (NSString *)_currentText {
    if (self.designDirty && self.designWorkspace != nil) {
        return [self.designWorkspace.text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    }
    return self.editorTextView.string ?: @"";
}

/// UDTextFileDocument's text source: the canvas's text, when it is ahead.
- (NSString *)documentTextFor:(id)document {
    return self.designDirty ? [self _currentText] : nil;
}

/// The GUI read and run on to the time it was at: the file, or the text
/// as it is; designing, loaded as the editor loads it (to take the
/// design's edits as they are made), the windows the design hides or shows
/// so.
- (void)_run {
    NSString *path = self.item.path;
    NSString *text = [self _currentText];
    self.player.editing = self.designing;
    self.player.windowVisibility = self.designing ? [self _designVisibility] : nil;
    self.runningText = text;
    self.runStale = NO;
    self.runEdited = NO;
    [self.runWindows removeAllObjects];
    [self.player loadText:[text isEqualToString:self.fileText] ? nil : text path:path time:self.player.time];
    [self _mapRunWindows];
    [self.transport update];
    [self _showDiagnostics];
    [self _fillNamedEvents];
    [self _showState:YES];
}

- (void)_showDiagnostics {
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    for (NSDictionary *d in self.player.diagnostics) {
        [items addObject:[[UDDiagnosticItem alloc] initWithLine:[d[@"line"] integerValue] column:0
                                                        message:d[@"message"] ?: @""
                                                       severity:[d[@"error"] boolValue] ? UDDiagnosticSeverityError : UDDiagnosticSeverityWarning
                                                         source:UDGuiParseSource]];
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDGuiParseSource];
}

#pragma mark - The inspector

- (NSArray<UDEditorPane *> *)inspectorPanes {
    if (self.stateView == nil) return @[];
    if (_panes == nil) {
        _panes = @[
            [UDEditorPane paneWithTitle:@"Properties" letters:@"P" red:0.62 green:0.42 blue:0.68 view:self.propertiesView],
            [UDEditorPane paneWithTitle:@"Scripts" letters:@"Sc" red:0.70 green:0.50 blue:0.30 view:self.scriptsView],
            [UDEditorPane paneWithTitle:@"State" letters:@"S" red:0.40 green:0.52 blue:0.72 view:self.stateView],
            [UDEditorPane paneWithTitle:@"Log" letters:@"L" red:0.55 green:0.45 blue:0.30 view:self.logView],
        ];
    }
    return _panes;
}

- (NSArray<UDEditorPane *> *)navigatorPanes {
    if (self.windowsView == nil) return @[];
    if (_navigatorPanes == nil) {
        _navigatorPanes = @[
            [UDEditorPane paneWithTitle:@"Windows" letters:@"W" red:0.35 green:0.60 blue:0.55 view:self.windowsView],
        ];
    }
    return _navigatorPanes;
}

#pragma mark - The navigator (rvGENavigator)

/// The design workspace, made and loaded if it is not yet (the navigator
/// shows its windows in Run too).
- (rvGEWorkspace *)_design {
    if (self.designWorkspace == nil) {
        idUserInterfaceManager *manager = [[idUserInterfaceManager alloc] initWithFileSystem:self.workspace.fileSystem
                                                                                declManager:self.workspace.declManager];
        [manager managerInit];
        rvGEWorkspace *design = [[rvGEWorkspace alloc] initWithManager:manager];
        design.modifiers.undoManager = self.document.undoManager;
        design.modifiers.target = self;
        design.modifiers.action = @selector(_designEdited:);
        self.designWorkspace = design;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_selectionChanged:)
                                                     name:rvGESelectionDidChangeNotification object:design.selections];
        [self _loadDesign];
    }
    return self.designWorkspace;
}

/// rvGENavigator::Update: the windows again, expanded as their wrappers are.
- (void)_updateNavigator {
    NSOutlineView *outline = self.windowsOutline;
    if (outline == nil) return;
    self.syncingWindows = YES;
    [outline reloadData];
    idWindow *desktop = [self.designWorkspace.interface getDesktop];
    if (desktop != nil) {
        [self _expandAsWrapped:desktop];
    }
    self.syncingWindows = NO;
    [self _updateNavigatorSelections];
}

- (void)_expandAsWrapped:(idWindow *)window {
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
    if (!wrapper.expanded) return;
    [self.windowsOutline expandItem:window];
    for (idWindow *child in [self _childrenOf:window]) {
        [self _expandAsWrapped:child];
    }
}

/// rvGENavigator::UpdateSelections: the rows of the selected windows
/// selected, and shown.
- (void)_updateNavigatorSelections {
    NSOutlineView *outline = self.windowsOutline;
    rvGEWorkspace *design = self.designWorkspace;
    if (outline == nil || design == nil) return;
    self.syncingWindows = YES;
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (idWindow *window in design.selections.windows) {
        // its parents opened, as Add's Expand does
        NSMutableArray<idWindow *> *parents = [NSMutableArray array];
        for (idWindow *parent = [window getParent]; parent != nil; parent = [parent getParent]) {
            [parents insertObject:parent atIndex:0];
        }
        for (idWindow *parent in parents) {
            [outline expandItem:parent];
        }
        NSInteger row = [outline rowForItem:window];
        if (row >= 0) [rows addIndex:(NSUInteger)row];
    }
    [outline selectRowIndexes:rows byExtendingSelection:NO];
    if (rows.count > 0) [outline scrollRowToVisible:(NSInteger)rows.firstIndex];
    self.syncingWindows = NO;
}

/// A window's children in the navigator: its wrapped ones not deleted.
- (NSArray<idWindow *> *)_childrenOf:(idWindow *)window {
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
    NSMutableArray<idWindow *> *children = [NSMutableArray array];
    for (int i = 0; i < [wrapper childCount]; i++) {
        idWindow *child = [wrapper childAtIndex:i];
        rvGEWindowWrapper *childWrapper = [rvGEWindowWrapper wrapperOf:child];
        if (childWrapper != nil && !childWrapper.deleted) [children addObject:child];
    }
    return children;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) {
        return [self.designWorkspace.interface getDesktop] != nil ? 1 : 0;
    }
    return (NSInteger)[self _childrenOf:item].count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        return [self.designWorkspace.interface getDesktop];
    }
    return [self _childrenOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [self _childrenOf:item].count > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item {
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:item];
    if ([column.identifier isEqualToString:@"visible"]) {
        return @(!wrapper.hidden);
    }
    if ([column.identifier isEqualToString:@"locked"]) {
        return @([self.lockedWindows containsObject:item]);
    }
    if ([column.identifier isEqualToString:@"scripts"]) {
        // the engine's scripts icon: a window with scripts or variables
        return [wrapper.variableDict numKeyVals] || [wrapper.scriptDict numKeyVals] ? @"\u0192" : @"";
    }
    return [(idWindow *)item getName];
}

/// The eye: HideWindow, UnhideWindow (an edit of the design, undone as one).
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column byItem:(id)item {
    if ([column.identifier isEqualToString:@"locked"]) {
        // the lock: the window (and its children) not chosen on the canvas;
        // the editor's alone, as the eye's is
        if ([object boolValue]) {
            [self.lockedWindows addObject:item];
        } else {
            [self.lockedWindows removeObject:item];
        }
        if (self.designing) [self _showDesign];
        return;
    }
    if (![column.identifier isEqualToString:@"visible"]) return;
    rvGEWorkspace *design = [self _design];
    if (![object boolValue]) {
        [design hideWindow:item];
    } else {
        [design unhideWindow:item];
    }
}

/// A window under a hidden one is drawn disabled, as the engine's are.
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column item:(id)item {
    BOOL disabled = NO;
    for (idWindow *parent = [(idWindow *)item getParent]; parent != nil; parent = [parent getParent]) {
        if ([rvGEWindowWrapper wrapperOf:parent].hidden) disabled = YES;
    }
    if ([cell respondsToSelector:@selector(setEnabled:)]) {
        [cell setEnabled:!disabled];
    }
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification {
    if (self.syncingWindows) return;
    [[rvGEWindowWrapper wrapperOf:notification.userInfo[@"NSObject"]] expand];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification {
    if (self.syncingWindows) return;
    [[rvGEWindowWrapper wrapperOf:notification.userInfo[@"NSObject"]] collapse];
}

/// The rows chosen: the design's selection, as the list view's changes
/// make it (Add, without expanding; Remove); the design shown.
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (self.syncingWindows) return;
    rvGEWorkspace *design = [self _design];
    NSOutlineView *outline = self.windowsOutline;
    NSMutableArray<idWindow *> *chosen = [NSMutableArray array];
    NSIndexSet *rows = outline.selectedRowIndexes;
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        id item = [outline itemAtRow:(NSInteger)row];
        if (item != nil) [chosen addObject:item];
    }
    self.syncingWindows = YES;
    for (idWindow *window in design.selections.windows) {
        if ([chosen indexOfObjectIdenticalTo:window] == NSNotFound) [design.selections remove:window];
    }
    for (idWindow *window in chosen) {
        [design.selections add:window expand:NO];
    }
    self.syncingWindows = NO;
    if (!self.designing && chosen.count > 0) {
        [self _enterDesign];
    } else if (self.designing) {
        [self _renderDesign];
    }
}

#pragma mark - Properties (rvGEProperties)

/// rvGEProperties::Update: the one selected window's state keys, or the
/// placeholder; the row being added after them.
- (void)_updateProperties {
    NSTableView *table = self.propertiesTable;
    if (table == nil || table.editedRow >= 0) return;
    NSArray<NSArray<NSString *> *> *rows = [self.designWorkspace properties];
    if (rows != nil && self.pendingProperty != nil) {
        rows = [rows arrayByAddingObject:@[self.pendingProperty, @""]];
    }
    if (rows == nil) self.pendingProperty = nil;
    self.propertyRows = rows;
    self.propertiesPlaceholder.hidden = rows != nil;
    table.enclosingScrollView.hidden = rows == nil;
    [table reloadData];
}

- (IBAction)addProperty:(id)sender {
    if (self.propertyRows == nil) {
        NSBeep();
        return;
    }
    self.pendingProperty = @"";
    [self _updateProperties];
    NSInteger row = (NSInteger)self.propertyRows.count - 1;
    [self.propertiesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self.propertiesTable editColumn:0 row:row withEvent:nil select:YES];
}

- (IBAction)showProperties:(id)sender {
    id controller = self.view.window.windowController;
    if ([controller isKindOfClass:[UDWorkspaceWindowController class]]) {
        [(UDWorkspaceWindowController *)controller showInspectorPaneTitled:@"Properties"];
    }
}

/// rvGEProperties::AddModifier: the value set, or why not.
- (void)_setProperty:(NSString *)name value:(NSString *)value {
    if (![self.designWorkspace setProperty:name value:value]) {
        // the engine's "Invalid property value" box, in the pane
        self.propertiesMessage.stringValue = [NSString stringWithFormat:@"Invalid property value '%@' for property '%@'", value, name];
        NSBeep();
        return;
    }
    self.propertiesMessage.stringValue = @"";
    self.pendingProperty = nil;
    [self _updateProperties];
}

#pragma mark - Scripts (GEItemScriptsDlg)

/// The one selected window's scripts in the text, unless the text is
/// being edited (and @a always is NO); the placeholder for none or many.
- (void)_updateScripts:(BOOL)always {
    NSTextView *textView = self.scriptsText;
    if (textView == nil) return;
    rvGEWorkspace *design = self.designWorkspace;
    idWindow *window = [design.selections num] == 1 ? design.selections[0] : nil;
    BOOL edited = self.scriptsShownText != nil && ![textView.string isEqualToString:self.scriptsShownText];
    if (!always && edited && window == self.scriptsWindow) return;
    self.scriptsWindow = window;
    self.scriptsPlaceholder.hidden = window != nil;
    textView.enclosingScrollView.hidden = window == nil;
    NSString *text = window != nil ? [design scriptsTextOf:window] : @"";
    [self _forgetScriptsTyping];
    textView.string = text;
    self.scriptsShownText = text;
    self.scriptsMessage.stringValue = @"";
}

/// The text view's own edits off the document's undo stack (the design's
/// edits are on it).
- (void)_forgetScriptsTyping {
    NSUndoManager *undoManager = self.document.undoManager;
    [undoManager removeAllActionsWithTarget:self.scriptsText.textStorage];
    [undoManager removeAllActionsWithTarget:self.scriptsText];
}

- (IBAction)applyScripts:(id)sender {
    idWindow *window = self.scriptsWindow;
    if (window == nil) {
        NSBeep();
        return;
    }
    NSString *message = nil;
    if (![self.designWorkspace setScriptsText:self.scriptsText.string of:window message:&message]) {
        // the engine's "Script Error" box, in the pane
        self.scriptsMessage.stringValue = [NSString stringWithFormat:@"Script error: %@", message ?: @""];
        NSBeep();
        return;
    }
    [self _updateScripts:YES];
}

- (IBAction)revertScripts:(id)sender {
    [self _updateScripts:YES];
}

#pragma mark - The design's menu

- (NSMenu *)guiView:(UDGuiView *)view designMenuAt:(NSPoint)point {
    rvGEWorkspace *design = self.designWorkspace;
    if (design == nil) return nil;
    // HandleRButtonDown's Select: the windows under the click
    NSMenu *select = self.selectMenu;
    [select removeAllItems];
    for (idWindow *window in [design windowsUnderX:(float)point.x y:(float)point.y]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[window getName] action:@selector(selectWindowFromMenu:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = window;
        item.state = [rvGEWindowWrapper wrapperOf:window].selected ? NSControlStateValueOn : NSControlStateValueOff;
        [select addItem:item];
    }
    return self.designMenu;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    rvGEWorkspace *design = self.designWorkspace;
    int selected = [design.selections num];
    SEL action = item.action;
    if (action == @selector(bringToFront:) || action == @selector(bringForward:) || action == @selector(sendToBack:)
        || action == @selector(sendBackward:) || action == @selector(copyWindows:) || action == @selector(deleteWindows:)) {
        return selected > 0;
    }
    if (action == @selector(makeChild:) || action == @selector(alignWindows:) || action == @selector(makeSameSize:)) {
        return selected > 1;
    }
    if (action == @selector(pasteWindows:)) {
        return [design canPaste];
    }
    if (action == @selector(showScripts:) || action == @selector(showProperties:)) {
        return selected == 1;
    }
    return [super validateMenuItem:item];
}

/// A command of the design's, and the design shown after it.
- (void)_designCommandDone {
    if (!self.designing) [self _enterDesign];
    [self _renderDesign];
}

- (IBAction)newWindow:(id)sender {
    [[self _design] addWindow:(rvGEWindowType)[sender tag]];
    [self _designCommandDone];
}

- (IBAction)selectWindowFromMenu:(id)sender {
    idWindow *window = [sender representedObject];
    if (window != nil) [self.designWorkspace.selections set:window];
    [self _designCommandDone];
}

- (IBAction)bringToFront:(id)sender {
    [self.designWorkspace bringSelectedToFront];
    [self _designCommandDone];
}

- (IBAction)bringForward:(id)sender {
    [self.designWorkspace bringSelectedForward];
    [self _designCommandDone];
}

- (IBAction)sendToBack:(id)sender {
    [self.designWorkspace sendSelectedToBack];
    [self _designCommandDone];
}

- (IBAction)sendBackward:(id)sender {
    [self.designWorkspace sendSelectedBackward];
    [self _designCommandDone];
}

- (IBAction)makeChild:(id)sender {
    if (![self.designWorkspace makeSelectedAChild]) NSBeep();
    [self _designCommandDone];
}

/// The menu's tags are the engine's EItemAlign, one on.
- (IBAction)alignWindows:(id)sender {
    [self.designWorkspace alignSelected:(rvGEItemAlign)([sender tag] - 1)];
    [self _designCommandDone];
}

/// Width (1), Height (2), Both (3).
- (IBAction)makeSameSize:(id)sender {
    NSInteger tag = [sender tag];
    [self.designWorkspace makeSelectedSameSizeWidth:(tag & 1) != 0 height:(tag & 2) != 0];
    [self _designCommandDone];
}

- (IBAction)copyWindows:(id)sender {
    [self.designWorkspace copySelected];
}

- (IBAction)pasteWindows:(id)sender {
    [[self _design] paste];
    [self _designCommandDone];
}

- (IBAction)deleteWindows:(id)sender {
    [self.designWorkspace deleteSelected];
    [self _designCommandDone];
}

- (IBAction)showScripts:(id)sender {
    id controller = self.view.window.windowController;
    if ([controller isKindOfClass:[UDWorkspaceWindowController class]]) {
        [(UDWorkspaceWindowController *)controller showInspectorPaneTitled:@"Scripts"];
    }
}

#pragma mark - Editor | Source

- (void)setShowsSource:(BOOL)showsSource {
    if (showsSource == _showsSource) return;
    _showsSource = showsSource;
    [self _showViewer:!showsSource];
    if (showsSource) {
        // the canvas's edits in the text
        [self _showCanvasText];
        [self.view.window makeFirstResponder:self.editorTextView];
    } else {
        NSString *text = self.editorTextView.string ?: @"";
        if (![text isEqualToString:self.shownText]) {
            // the source as edited: one edit, the text's own edits' place
            [self forgetTextEdits];
            NSUndoManager *undoManager = self.document.undoManager;
            [undoManager registerUndoWithTarget:self selector:@selector(_restoreSourceText:) object:self.shownText ?: @""];
            [undoManager setActionName:@"Edit Source"];
            [self _takeText:text];
        }
        [self.view.window makeFirstResponder:self.guiView];
    }
}

/// The source's text as the canvas has it now, if the canvas is ahead
/// (no edit of the text: the canvas's edits are on the undo stack).
- (void)_showCanvasText {
    if (!self.designDirty) return;
    NSString *text = [self _currentText];
    NSTextView *textView = self.editorTextView;
    NSUndoManager *undoManager = self.document.undoManager;
    [undoManager disableUndoRegistration];
    [textView.textStorage replaceCharactersInRange:NSMakeRange(0, textView.textStorage.length) withString:text];
    [undoManager enableUndoRegistration];
    self.shownText = text;
    self.designDirty = NO;
}

/// @a text the GUI's: the design read from it again (its edits before
/// forgotten), run, its errors in Issues.
- (void)_takeText:(NSString *)text {
    self.shownText = text;
    self.designDirty = NO;
    if (self.designWorkspace != nil) {
        [self _loadDesign];
    }
    [self _run];
    if (self.designing) {
        [self _renderDesign];
    }
}

/// Edit Source undone (or redone): the text before it back, in the source
/// and the design.
- (void)_restoreSourceText:(NSString *)text {
    NSString *current = self.shownText ?: @"";
    NSTextView *textView = self.editorTextView;
    NSUndoManager *undoManager = self.document.undoManager;
    [undoManager disableUndoRegistration];
    [textView.textStorage replaceCharactersInRange:NSMakeRange(0, textView.textStorage.length) withString:text];
    [undoManager enableUndoRegistration];
    [self _takeText:text];
    [undoManager registerUndoWithTarget:self selector:@selector(_restoreSourceText:) object:current];
    [undoManager setActionName:@"Edit Source"];
}

#pragma mark - Run | Design

- (IBAction)changeMode:(id)sender {
    BOOL design = [sender isKindOfClass:[NSSegmentedControl class]] ? [(NSSegmentedControl *)sender selectedSegment] == 1 : !self.designing;
    if (design == self.designing) return;
    if (design) {
        [self _enterDesign];
    } else {
        [self _enterRun];
    }
}

- (void)_enterDesign {
    self.designing = YES;
    self.modeControl.selectedSegment = 1;
    self.playedBeforeDesigning = self.player.playing;
    self.player.playing = NO;
    [self _design];
    if (!self.designDirty && ![[self _currentText] isEqualToString:self.designText]) {
        [self _loadDesign];
    }
    self.guiView.workspace = self.designWorkspace;
    self.guiView.designTarget = self;
    self.guiView.designAction = @selector(_designViewChanged:);
    self.guiView.designDelegate = self;
    self.transport.allowsPlaying = NO;
    [self _renderDesign];
}

- (void)_enterRun {
    self.designing = NO;
    self.modeControl.selectedSegment = 0;
    self.guiView.workspace = nil;
    self.transport.allowsPlaying = YES;
    // loaded as the game loads it, the design's edits in it, its hidden
    // windows as the file has them
    if (self.player.editing || self.runStale || ![[self _currentText] isEqualToString:self.runningText]) {
        [self _run];
    }
    self.player.playing = self.playedBeforeDesigning;
    [self.guiView showFrame];
    [self.transport update];
}

/// The workspace loaded from the text as it is (from the file, when that
/// is it): its selection and its edits gone.
- (void)_loadDesign {
    NSString *text = [self _currentText];
    if ([text isEqualToString:self.fileText]) {
        [self.designWorkspace loadFile:self.item.path];
    } else {
        [self.designWorkspace loadText:text path:self.item.path];
    }
    self.designText = text;
    self.runStale = YES;
    [self.lockedWindows removeAllObjects];
    // what it hides as loaded (the file's "visible", read): the run's too
    self.loadedHidden = [NSMutableSet set];
    idWindow *desktop = [self.designWorkspace.interface getDesktop];
    if (desktop != nil) {
        [self _addVisibilityOf:desktop to:nil];
    }
    [self _updateNavigator];
}

/// rvGEWorkspace::Render, at the time the player is at: the design run
/// there (its edits, its hidden windows not drawn), and over it the grid
/// and the selections.
- (void)_renderDesign {
    if (self.runStale || !self.player.editing) {
        [self _run];        // its frame shown
        return;
    }
    [self _showDesign];
}

/// @a modifier's edit (applied, undone or redone) made in the run as it
/// is, as the engine's editor makes it in its GUI: the run's window for the
/// edited one given its state again (rvGEWindowWrapper's
/// UpdateWindowState); its windows ordered and parented as the design's,
/// a window new to it read from its own text, and one whose scripts
/// changed read again so. NO where the run has no window for it: then it
/// is read again whole.
- (BOOL)_applyToRun:(nullable rvGEModifier *)modifier {
    if (modifier == nil) return YES;
    if ([modifier isKindOfClass:[rvGEModifierGroup class]]) {
        for (rvGEModifier *each in [(rvGEModifierGroup *)modifier modifiers]) {
            if (![self _applyToRun:each]) return NO;
        }
        return YES;
    }
    idWindow *window = modifier.window;
    if ([modifier isKindOfClass:[rvGEInsertModifier class]] || [modifier isKindOfClass:[rvGEZOrderModifier class]]) {
        if (![self _syncRunChildrenOf:[self.designWorkspace.interface getDesktop]]) return NO;
    } else if ([modifier isKindOfClass:[rvGEScriptsModifier class]]) {
        return [self _readRunWindowAgain:window];
    }
    idWindow *ran = [self.runWindows objectForKey:window];
    if (ran == nil) {
        // not in the run, and not to be: an inserted window's undo
        return [window getParent] == nil || [rvGEWindowWrapper wrapperOf:window].deleted;
    }
    [ran updateFromDictionary:[rvGEWindowWrapper wrapperOf:window].stateDict];
    return YES;
}

/// The player's text when it loads again by itself (a seek back,
/// Restart): the design as it is, if edits were made in the run since it
/// was read.
- (nullable NSString *)runTextFor:(UDGuiPlayer *)player {
    if (!self.designing || !self.runEdited) return nil;
    NSString *text = [self _currentText];
    self.runningText = text;
    self.runEdited = NO;
    return text;
}

/// Each design window's in the run (the same tree, but for the deleted, not
/// written), when the run is not the one mapped (loaded again).
- (void)_mapRunWindows {
    if (!self.designing) return;
    if (self.mappedRun == self.player.gui && self.runWindows.count > 0) return;
    [self.runWindows removeAllObjects];
    self.mappedRun = self.player.gui;
    [self _mapRunWindow:[self.player.gui getDesktop] to:[self.designWorkspace.interface getDesktop]];
}

/// @a design's run window @a run, and their children's, mapped.
- (void)_mapRunWindow:(nullable idWindow *)run to:(nullable idWindow *)design {
    if (run == nil || design == nil) return;
    [self.runWindows setObject:run forKey:design];
    int r = 0;
    for (int i = 0; i < [design getChildCount]; i++) {
        idWindow *child = [design getChild:i];
        if ([rvGEWindowWrapper wrapperOf:child].deleted) continue;
        if (r < [run getChildCount]) {
            [self _mapRunWindow:[run getChild:r] to:child];
        }
        r++;
    }
}

/// The run's children of @a design's window, and theirs, as the design
/// has them (in its order; a window new to the run read from its text, one
/// gone from the design gone): NO when a window is not to be had.
- (BOOL)_syncRunChildrenOf:(idWindow *)design {
    idWindow *run = [self.runWindows objectForKey:design];
    if (run == nil) return NO;
    NSMutableArray<idWindow *> *wanted = [NSMutableArray array];
    NSMutableArray<idWindow *> *fresh = [NSMutableArray array];
    for (int i = 0; i < [design getChildCount]; i++) {
        idWindow *child = [design getChild:i];
        idWindow *ran = [self.runWindows objectForKey:child];
        if (ran == nil) {
            if ([rvGEWindowWrapper wrapperOf:child].deleted) continue;     // never run
            ran = [self _runWindowFromTextOf:child];
            if (ran == nil) return NO;
            [fresh addObject:ran];
        }
        [wanted addObject:ran];
        if (![self _syncRunChildrenOf:child]) return NO;
    }
    BOOL same = [run getChildCount] == (int)wanted.count;
    for (int i = 0; same && i < (int)wanted.count; i++) {
        same = [run getChild:i] == wanted[(NSUInteger)i];
    }
    if (same) return YES;
    while ([run getChildCount] > 0) {
        [run removeChild:[run getChild:0]];
    }
    for (idWindow *ran in wanted) {
        idWindow *parent = [ran getParent];
        if (parent != nil && parent != run) {
            [parent removeChild:ran];
        }
        [run insertChild:ran before:nil];
    }
    // a new window's script names looked up where it is
    for (idWindow *ran in fresh) {
        [self.player.gui fixupParmsOf:ran];
    }
    return YES;
}

/// A window for the run, read from @a design's text (and its children's,
/// mapped) in the run's GUI, as the GUI reads a child's; not yet anywhere.
- (nullable idWindow *)_runWindowFromTextOf:(idWindow *)design {
    idWindow *desktop = [self.player.gui getDesktop];
    if (desktop == nil) return nil;
    NSMutableString *text = [NSMutableString stringWithString:@"UDRunHolder {\r\n"];
    [self.designWorkspace writeWindow:design depth:2 into:text];
    [text appendString:@"}\r\n"];
    NSData *bytes = [text ud_latin1Buffer];
    idParser *src = [[idParser alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:@"" 
                                               flags:LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                               error:NULL];
    idWindow *holder = [[idWindow alloc] initWithDC:[desktop getDC] gui:self.player.gui];
    [holder parse:src rebuild:NO];
    if ([holder getChildCount] != 1) return nil;
    idWindow *ran = [holder getChild:0];
    [holder removeChild:ran];
    [self _mapRunWindow:ran to:design];
    return ran;
}

/// @a design's window read again into the run, in its place (its scripts
/// changed); its script names looked up in the run as it is.
- (BOOL)_readRunWindowAgain:(idWindow *)design {
    idWindow *old = [self.runWindows objectForKey:design];
    idWindow *parent = [old getParent];
    if (old == nil || parent == nil) return NO;
    idWindow *ran = [self _runWindowFromTextOf:design];
    if (ran == nil) return NO;
    int index = [parent getChildIndex:old];
    idWindow *before = index + 1 < [parent getChildCount] ? [parent getChild:index + 1] : nil;
    [parent removeChild:old];
    [parent insertChild:ran before:before];
    [self.player.gui fixupParmsOf:ran];
    return YES;
}

/// The windows the design shows or hides, as it did not when it loaded, by
/// name, YES for shown.
- (NSDictionary<NSString *, NSNumber *> *)_designVisibility {
    NSMutableDictionary<NSString *, NSNumber *> *visibility = [NSMutableDictionary dictionary];
    idWindow *desktop = [self.designWorkspace.interface getDesktop];
    if (desktop != nil) {
        [self _addVisibilityOf:desktop to:visibility];
    }
    return visibility;
}

/// @a window's, and its children's: shown or hidden as they were not when
/// the design loaded (into @a visibility); or (no @a visibility) the names
/// of those hidden then.
- (void)_addVisibilityOf:(idWindow *)window to:(nullable NSMutableDictionary<NSString *, NSNumber *> *)visibility {
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
    if (wrapper == nil) return;
    NSString *name = [window getName];
    if (wrapper.deleted) {
        // not drawn, as not written (the run may have it, from before)
        if (visibility != nil) visibility[name] = @NO;
        return;
    }
    if (visibility == nil) {
        if (wrapper.hidden) [self.loadedHidden addObject:name];
    } else if (wrapper.hidden != [self.loadedHidden containsObject:name]) {
        visibility[name] = @(!wrapper.hidden);
    }
    for (int i = 0; i < [wrapper childCount]; i++) {
        idWindow *child = [wrapper childAtIndex:i];
        if (child != nil) {
            [self _addVisibilityOf:child to:visibility];
        }
    }
}

/// The windows the canvas passes through: the locked, and those the run
/// does not draw at its time (not visible, or no size).
- (NSSet<idWindow *> *)_passedWindows {
    [self _mapRunWindows];
    NSMutableSet<idWindow *> *passed = [NSMutableSet set];
    for (idWindow *window in self.lockedWindows) {
        [passed addObject:window];
    }
    for (idWindow *window in self.runWindows) {
        idWindow *ran = [self.runWindows objectForKey:window];
        idWinVar *visible = [ran getWinVarByName:@"visible"];
        idWinVar *rect = [ran getWinVarByName:@"rect"];
        BOOL shown = ![visible isKindOfClass:[idWinBool class]] || [(idWinBool *)visible data];
        if ([rect isKindOfClass:[idWinRectangle class]]) {
            idRectangle r = [(idWinRectangle *)rect data];
            shown = shown && r.w != 0 && r.h != 0;
        }
        if (!shown && window != [self.designWorkspace.interface getDesktop]) {
            [passed addObject:window];
        }
    }
    return passed;
}

/// The player's frame, and the design's grid and selections over it.
- (void)_showDesign {
    rvGEWorkspace *design = self.designWorkspace;
    design.passedWindows = [self _passedWindows];
    UDGuiView *view = self.guiView;
    NSRect rect = view.guiRect;
    design.rect = idRectangle_Make((float)NSMinX(rect), (float)NSMinY(rect), (float)NSWidth(rect), (float)NSHeight(rect));
    UDSoftwareRenderer *renderer = self.player.manager.renderer;
    UDOverlay *overlay = [[UDOverlay alloc] init];
    [design renderOverlayInto:overlay];
    [view showTriangles:self.player.triangles picture:self.player.frame
            pictureSize:NSMakeSize(renderer.width, renderer.height) overlay:overlay];
}

/// An edit of the design, its undo or its redo (the modifier stack's).
- (void)_designEdited:(id)sender {
    self.designDirty = YES;
    // the navigator's rows (hidden, shown), but for a drag's every step
    if (self.designWorkspace.dragType == HT_NONE) {
        // (GNUstep's reloadData drops the selection, and says so: the
        // design's is not to follow it)
        self.syncingWindows = YES;
        [self.windowsOutline reloadData];
        self.syncingWindows = NO;
        [self _updateNavigatorSelections];
        [self _updateProperties];
        [self _updateScripts:NO];
    }
    // the source, if it is up and not edited, shows it
    if (self.showsSource && [self.editorTextView.string isEqualToString:self.shownText]) {
        [self _showCanvasText];
    }
    // the run takes the edit as it is, or is read again
    [self _mapRunWindows];
    if (!self.runStale && self.player.editing && [self _applyToRun:[sender changedModifier]]) {
        self.runEdited = YES;
        self.player.windowVisibility = [self _designVisibility];
        [self.player renderFrame];     // its frame shown
    } else {
        self.runStale = YES;
        if (self.designing) {
            [self _renderDesign];
        }
    }
}

- (void)_selectionChanged:(NSNotification *)notification {
    if (!self.syncingWindows) {
        [self _updateNavigatorSelections];
    }
    self.pendingProperty = nil;
    self.propertiesMessage.stringValue = @"";
    [self _updateProperties];
    [self _updateScripts:NO];
    if (self.designing) {
        [self _renderDesign];
    }
}

/// The view's mouse moved, sized or selected.
- (void)_designViewChanged:(id)sender {
    [self _renderDesign];
    if (self.designWorkspace.dragType == HT_NONE) {
        [self _updateProperties];
    }
}

/// An Issue's line, in the source.
- (void)selectLine:(NSInteger)line character:(NSInteger)character length:(NSInteger)length {
    self.showsSource = YES;
    [super selectLine:line character:character length:length];
}

#pragma mark - The clock

/// The transport moved the player (restarted, sought, stepped): the state
/// as it is now.
- (void)transportMoved:(UDTransportController *)transport {
    [self _showState:YES];
}

- (void)playerDidDrawFrame:(UDGuiPlayer *)player {
    if (self.designing) {
        [self _showDesign];
    } else {
        [self.guiView showFrame];
    }
    [self.transport update];
    [self _showLog];
    [self _showState:NO];
}

#pragma mark - Named events

- (void)_fillNamedEvents {
    NSPopUpButton *popUp = self.namedEventPopUp;
    while (popUp.numberOfItems > 1) {
        [popUp removeItemAtIndex:1];
    }
    for (NSString *name in self.player.namedEvents) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:@selector(sendNamedEvent:) keyEquivalent:@""];
        item.target = self;
        [popUp.menu addItem:item];
    }
    popUp.enabled = popUp.numberOfItems > 1;
}

- (IBAction)sendNamedEvent:(id)sender {
    NSString *name = [sender isKindOfClass:[NSMenuItem class]] ? [(NSMenuItem *)sender title] : nil;
    if (name.length == 0) return;
    [self.player sendNamedEvent:name];
    [self.player renderFrame];
}

#pragma mark - State

/// The state's rows from the GUI's dict; the table reloaded when they
/// changed (not while a value is being typed, and only a few times a
/// second unless @a now).
- (void)_showState:(BOOL)now {
    NSTableView *table = self.stateTable;
    if (table == nil || table.editedRow >= 0) return;
    if (!now && self.stateShown != nil && -[self.stateShown timeIntervalSinceNow] < 0.25) return;
    self.stateShown = [NSDate date];

    idDict *state = [self.player.gui state];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (int i = 0; i < [state numKeyVals]; i++) {
        [keys addObject:[state keyAtIndex:i]];
    }
    NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray array];
    for (NSString *key in [keys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        [rows addObject:@[key, [state getString:key]]];
    }
    if ([rows isEqualToArray:self.stateRows]) return;
    self.stateRows = rows;
    [table reloadData];
}

- (IBAction)addOrRemoveStateKey:(id)sender {
    NSInteger segment = [sender isKindOfClass:[NSSegmentedControl class]] ? [(NSSegmentedControl *)sender selectedSegment] : 0;
    idUserInterfaceLocal *gui = self.player.gui;
    if (gui == nil) return;
    if (segment == 0) {
        NSString *key = @"new_key";
        for (int n = 2; [[gui state] getString:key defaultString:nil] != nil; n++) {
            key = [NSString stringWithFormat:@"new_key%d", n];
        }
        [gui setStateString:key value:@""];
        [self _stateChanged];
        NSUInteger row = NSNotFound;
        for (NSUInteger i = 0; i < self.stateRows.count && row == NSNotFound; i++) {
            if ([self.stateRows[i][0] isEqualToString:key]) row = i;
        }
        if (row != NSNotFound) {
            [self.stateTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            [self.stateTable editColumn:0 row:(NSInteger)row withEvent:nil select:YES];
        }
    } else {
        NSInteger row = self.stateTable.selectedRow;
        if (row < 0 || row >= (NSInteger)self.stateRows.count) return;
        [gui deleteStateVar:self.stateRows[(NSUInteger)row][0]];
        [self _stateChanged];
    }
}

/// As the game sets a GUI's state: then StateChanged, so its windows read it.
- (void)_stateChanged {
    [self.player.gui stateChanged:self.player.time redraw:NO];
    [self.player renderFrame];
    [self _showState:YES];
}

#pragma mark - The log

- (void)_showLog {
    NSUInteger count = self.player.log.count;
    if (count == self.logRowsShown) return;
    self.logRowsShown = count;
    [self.logTable reloadData];
    if (count > 0) {
        [self.logTable scrollRowToVisible:(NSInteger)count - 1];
    }
}

- (IBAction)clearLog:(id)sender {
    [self.player clearLog];
    self.logRowsShown = 0;
    [self.logTable reloadData];
}

#pragma mark - NSTableViewDelegate

/// A property's name is not edited, but the one being added.
- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView != self.propertiesTable || ![column.identifier isEqualToString:@"key"]) return YES;
    return self.pendingProperty != nil && row == (NSInteger)self.propertyRows.count - 1;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.propertiesTable) return (NSInteger)self.propertyRows.count;
    if (tableView == self.stateTable) return (NSInteger)self.stateRows.count;
    if (tableView == self.logTable) return (NSInteger)self.player.log.count;
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == self.propertiesTable) {
        if (row < 0 || row >= (NSInteger)self.propertyRows.count) return nil;
        return self.propertyRows[(NSUInteger)row][[column.identifier isEqualToString:@"key"] ? 0 : 1];
    }
    if (tableView == self.stateTable) {
        if (row < 0 || row >= (NSInteger)self.stateRows.count) return nil;
        return self.stateRows[(NSUInteger)row][[column.identifier isEqualToString:@"key"] ? 0 : 1];
    }
    NSArray<NSString *> *log = self.player.log;
    return row >= 0 && row < (NSInteger)log.count ? log[(NSUInteger)row] : nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == self.propertiesTable) {
        if (row < 0 || row >= (NSInteger)self.propertyRows.count) return;
        NSString *text = [object description] ?: @"";
        NSString *name = self.propertyRows[(NSUInteger)row][0];
        BOOL pending = self.pendingProperty != nil && row == (NSInteger)self.propertyRows.count - 1;
        if ([column.identifier isEqualToString:@"key"]) {
            // only the row being added is named
            if (pending) {
                self.pendingProperty = text;
                self.propertyRows = [[self.propertyRows subarrayWithRange:NSMakeRange(0, (NSUInteger)row)] arrayByAddingObject:@[text, @""]];
            }
            return;
        }
        if (name.length == 0) {
            NSBeep();
            return;
        }
        [self _setProperty:name value:text];
        return;
    }
    if (tableView != self.stateTable || row < 0 || row >= (NSInteger)self.stateRows.count) return;
    idUserInterfaceLocal *gui = self.player.gui;
    NSArray<NSString *> *was = self.stateRows[(NSUInteger)row];
    NSString *text = [object description] ?: @"";
    if ([column.identifier isEqualToString:@"key"]) {
        if (text.length == 0 || [text isEqualToString:was[0]]) return;
        [gui deleteStateVar:was[0]];
        [gui setStateString:text value:was[1]];
    } else {
        [gui setStateString:was[0] value:text];
    }
    [self _stateChanged];
}

@end
