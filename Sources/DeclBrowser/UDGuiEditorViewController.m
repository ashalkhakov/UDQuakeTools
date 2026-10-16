#import "UDGuiEditorViewController.h"
#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "UDGuiPlayer.h"
#import "UDGuiView.h"
#import "UDWorkspaceItem.h"
#import "idUserInterface.h"
#import "idDict.h"
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
    [self _run];

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

/// The GUI read and run from its time 0: the file, or the edited source.
- (void)_run {
    NSString *path = self.item.path;
    NSString *text = self.editorTextView.string;
    BOOL edited = self.runningText != nil && text != nil && ![text isEqualToString:self.runningText];
    if (edited) {
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
        [self.view.window makeFirstResponder:self.editorTextView];
    } else {
        // the source as edited, run; its errors in Issues
        if (![self.editorTextView.string isEqualToString:self.runningText]) {
            [self _run];
        }
        [self.view.window makeFirstResponder:self.guiView];
    }
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
    [self.guiView showFrame];
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
