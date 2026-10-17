#import "UDGuiEditorViewController.h"
#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "UDGuiPlayer.h"
#import "UDGuiView.h"
#import "UDWorkspaceItem.h"
#import "idUserInterface.h"
#import "idDict.h"
#import "idWindow.h"
#import "idGuiModel.h"
#import "UDSoftwareRenderer.h"
#import "UDTextFileDocument.h"
#import "UDOverlay.h"
#import "rvGEWorkspace.h"
#import "rvGEModifier.h"
#import "rvGESelectionMgr.h"
#import <UDCodeKit/UDDiagnosticStore.h>

static UDDiagnosticSource const UDGuiParseSource = @"gui";

@interface UDGuiEditorViewController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong, readwrite) UDGuiPlayer *player;
/// The text the GUI running was read from: the file's until the source is
/// edited, then the source's when the editor comes back.
@property (nonatomic, copy, nullable) NSString *runningText;
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
@end

@implementation UDGuiEditorViewController {
    NSArray<UDInspectorPane *> *_panes;
}

@synthesize showsSource = _showsSource;

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.item == nil) return;

    [[NSBundle bundleForClass:[UDGuiEditorViewController class]] loadNibNamed:@"UDGuiViewerView" owner:self topLevelObjects:nil];
    self.stateRows = @[];

    self.player = [[UDGuiPlayer alloc] initWithWorkspace:self.workspace];
    self.player.target = self;
    self.player.action = @selector(playerDidDrawFrame:);
    self.guiView.player = self.player;
    self.player.view = self.guiView;
    self.fileText = self.editorTextView.string;
    self.shownText = self.fileText;
    [self _run];

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

/// The GUI read and run from its time 0: the file, or the text as it is.
- (void)_run {
    NSString *path = self.item.path;
    NSString *text = [self _currentText];
    if (![text isEqualToString:self.fileText]) {
        [self.player loadText:text path:path];
    } else {
        [self.player loadFile:path];
    }
    self.runningText = text;
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

- (NSArray<UDInspectorPane *> *)inspectorPanes {
    if (self.stateView == nil) return @[];
    if (_panes == nil) {
        _panes = @[
            [UDInspectorPane paneWithTitle:@"State" letters:@"S" red:0.40 green:0.52 blue:0.72 view:self.stateView],
            [UDInspectorPane paneWithTitle:@"Log" letters:@"L" red:0.55 green:0.45 blue:0.30 view:self.logView],
        ];
    }
    return _panes;
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
    }
    if (!self.designDirty && ![[self _currentText] isEqualToString:self.designText]) {
        [self _loadDesign];
    }
    self.guiView.workspace = self.designWorkspace;
    self.guiView.designTarget = self;
    self.guiView.designAction = @selector(_designViewChanged:);
    for (NSControl *control in @[self.playButton, self.stepButton, self.restartButton, self.namedEventPopUp]) {
        control.enabled = NO;
    }
    [self _renderDesign];
}

- (void)_enterRun {
    self.designing = NO;
    self.modeControl.selectedSegment = 0;
    self.guiView.workspace = nil;
    for (NSControl *control in @[self.playButton, self.stepButton, self.restartButton]) {
        control.enabled = YES;
    }
    self.namedEventPopUp.enabled = self.namedEventPopUp.numberOfItems > 1;
    // the design's edits run
    if (![[self _currentText] isEqualToString:self.runningText]) {
        [self _run];
    }
    self.player.playing = self.playedBeforeDesigning;
    [self.guiView showFrame];
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
}

/// rvGEWorkspace::Render: the GUI still, at time 0, and over it the grid
/// and the selections.
- (void)_renderDesign {
    rvGEWorkspace *design = self.designWorkspace;
    idUserInterfaceManager *manager = design.manager;
    UDGuiView *view = self.guiView;
    NSRect rect = view.guiRect;
    design.rect = idRectangle_Make((float)NSMinX(rect), (float)NSMinY(rect), (float)NSWidth(rect), (float)NSHeight(rect));

    [manager.guiModel clear];
    [design.interface redraw:0];
    NSArray *surfaces = [manager.guiModel emitFullScreen];
    UDSoftwareRenderer *renderer = manager.renderer;
    UDTriangleList *triangles = [renderer trianglesOfSurfaces:surfaces time:0];
    NSImage *picture = nil;
    if (!view.drawsWithGL) {
        static const float black[4] = { 0, 0, 0, 1 };
        [renderer clearToColor:black];
        [renderer drawTriangles:triangles];
        picture = [UDGuiPlayer imageOf:[renderer image]];
    }
    UDOverlay *overlay = [[UDOverlay alloc] init];
    [design renderOverlayInto:overlay];
    [view showTriangles:triangles picture:picture pictureSize:NSMakeSize(renderer.width, renderer.height) overlay:overlay];
}

/// An edit of the design, its undo or its redo (the modifier stack's).
- (void)_designEdited:(id)sender {
    self.designDirty = YES;
    // the source, if it is up and not edited, shows it
    if (self.showsSource && [self.editorTextView.string isEqualToString:self.shownText]) {
        [self _showCanvasText];
    }
    if (self.designing) {
        [self _renderDesign];
    }
}

- (void)_selectionChanged:(NSNotification *)notification {
    if (self.designing) {
        [self _renderDesign];
    }
}

/// The view's mouse moved, sized or selected.
- (void)_designViewChanged:(id)sender {
    [self _renderDesign];
}

/// An Issue's line, in the source.
- (void)selectLine:(NSInteger)line character:(NSInteger)character length:(NSInteger)length {
    self.showsSource = YES;
    [super selectLine:line character:character length:length];
}

#pragma mark - The clock

- (IBAction)togglePlaying:(id)sender {
    self.player.playing = !self.player.playing;
    [self _showClock];
}

- (IBAction)step:(id)sender {
    self.player.playing = NO;
    [self.player step];
}

- (IBAction)restart:(id)sender {
    [self.player restart];
    [self _showState:YES];
}

- (void)playerDidDrawFrame:(UDGuiPlayer *)player {
    if (!self.designing) {
        [self.guiView showFrame];
    }
    [self _showClock];
    [self _showLog];
    [self _showState:NO];
}

- (void)_showClock {
    self.timeLabel.stringValue = [NSString stringWithFormat:@"%.2f s", self.player.time / 1000.0];
    self.playButton.title = self.player.playing ? @"Pause" : @"Play";
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

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.stateTable) return (NSInteger)self.stateRows.count;
    if (tableView == self.logTable) return (NSInteger)self.player.log.count;
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == self.stateTable) {
        if (row < 0 || row >= (NSInteger)self.stateRows.count) return nil;
        return self.stateRows[(NSUInteger)row][[column.identifier isEqualToString:@"key"] ? 0 : 1];
    }
    NSArray<NSString *> *log = self.player.log;
    return row >= 0 && row < (NSInteger)log.count ? log[(NSUInteger)row] : nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
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
