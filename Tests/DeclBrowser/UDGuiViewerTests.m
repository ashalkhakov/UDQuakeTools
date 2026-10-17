#import "UDDeclBrowserTestCase.h"

#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "UDBaseDocument.h"
#import "UDSoftwareRenderer.h"

#import "UDEditorTabManager.h"
#import "UDGuiEditorViewController.h"
#import "UDGuiGLView.h"
#import "UDGuiPlayer.h"
#import "UDGuiView.h"
#import "DMTabBar.h"
#import "idUserInterface.h"
#import "idDict.h"
#import "rvGEWorkspace.h"
#import "rvGEWindowWrapper.h"
#import "rvGESelectionMgr.h"
#import "UDOverlay.h"
#import <UDCodeKit/UDDiagnosticStore.h>

// An original GUI: a panel the state hides, a label a named event renames,
// a button whose action sets the state and returns a command, a lamp whose
// timeline (lit at 0.5 s) a named event starts.
static NSString *const UDViewerGUI =
    @"windowDef Desktop {\n"
     "\trect\t0, 0, 640, 480\n"
     "\tbackcolor\t0, 0, 0, 1\n"
     "\tmenugui\t1\n"
     "\twindowDef Panel {\n"
     "\t\trect\t40, 40, 300, 200\n"
     "\t\tbackcolor\t0.2, 0.3, 0.5, 1\n"
     "\t\tvisible\t(\"gui::hidepanel\" == 0)\n"
     "\t}\n"
     "\twindowDef Label {\n"
     "\t\trect\t40, 260, 300, 30\n"
     "\t\ttext\t\"ready\"\n"
     "\t}\n"
     "\twindowDef Go {\n"
     "\t\trect\t400, 300, 160, 60\n"
     "\t\tbackcolor\t0.8, 0.2, 0.2, 1\n"
     "\t\tonAction {\n"
     "\t\t\tset \"gui::clicked\" \"1\" ;\n"
     "\t\t\tset \"cmd\" \"udtest_go\" ;\n"
     "\t\t}\n"
     "\t}\n"
     "\twindowDef Lamp {\n"
     "\t\trect\t600, 420, 30, 30\n"
     "\t\tbackcolor\t0, 0, 0, 1\n"
     "\t\tnotime\t1\n"
     "\t\tonTime 500 {\n"
     "\t\t\tset \"backcolor\" \"0 1 0 1\" ;\n"
     "\t\t}\n"
     "\t}\n"
     "\tonNamedEvent udtestLight {\n"
     "\t\tresetTime \"Lamp\" \"0\" ;\n"
     "\t}\n"
     "\tonNamedEvent udtestRename {\n"
     "\t\tset \"Label::text\" \"renamed\" ;\n"
     "\t}\n"
     "}\n";

static NSString *const UDViewerScript =
    @"void udtest_main() {\n"
     "}\n";

@interface UDGuiViewerTests : UDDeclBrowserTestCase
@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, copy) NSString *savePath;
@end

@implementation UDGuiViewerTests

- (void)setUp {
    [super setUp];
    self.basePath = [self.scratchDirectory stringByAppendingPathComponent:@"install"];
    self.savePath = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *dir in @[@"base/guis", @"base/script"]) {
        [files createDirectoryAtPath:[self.basePath stringByAppendingPathComponent:dir] withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    [files createDirectoryAtPath:self.savePath withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDViewerGUI writeToFile:[self.basePath stringByAppendingPathComponent:@"base/guis/udtest_menu.gui"]
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDViewerScript writeToFile:[self.basePath stringByAppendingPathComponent:@"base/script/udtest.script"]
                     atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (UDWorkspaceWindowController *)openFixture {
    UDWorkspaceWindowController *controller = [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:self.basePath savePath:self.savePath]];
    [controller.window orderFront:nil];   // NSTabView sizes its views only in a window that is shown
    return controller;
}

- (UDGuiEditorViewController *)openGuiIn:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:@"guis/udtest_menu.gui" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDGuiEditorViewController class]], @"a GUI opens in the GUI viewer, not %@", editor);
    return (UDGuiEditorViewController *)editor;
}

/// A child window's var, whichever kind of window it became.
- (NSString *)var:(NSString *)var of:(NSString *)window in:(UDGuiEditorViewController *)editor {
    idDrawWin *dw = [[editor.player.gui getDesktop] findChildByName:window];
    return dw.win ? [[dw.win getWinVarByName:var] string] : [[dw.simp getWinVarByName:var] string];
}

/// A mouse event at @a guiPoint (the GUI's 640x480) of @a view, sent to it.
- (void)mouse:(NSEventType)type at:(NSPoint)guiPoint in:(UDGuiView *)view {
    NSPoint location = [view convertPoint:[view viewPointFromGui:guiPoint] toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:type location:location modifierFlags:0 timestamp:0
                                    windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    if (type == NSEventTypeLeftMouseDown) [view mouseDown:event];
    else if (type == NSEventTypeLeftMouseUp) [view mouseUp:event];
    else [view mouseMoved:event];
}

#pragma mark - Running

- (void)testAGuiOpensRunning {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    XCTAssertNotNil(editor.player.gui, @"the GUI should be loaded");
    XCTAssertEqual(editor.player.diagnostics.count, 0u, @"%@", editor.player.diagnostics);
    XCTAssertGreaterThan(editor.player.triangles.count, 0u, @"a frame should be drawn");
    XCTAssertEqualObjects([self var:@"text" of:@"Label" in:editor], @"ready");
    NSArray<NSString *> *events = [editor.namedEventPopUp.itemArray valueForKey:@"title"];
    XCTAssertTrue([events containsObject:@"udtestRename"], @"the named events are offered: %@", events);
    XCTAssertFalse(editor.showsSource, @"a GUI opens running, not as its text");
    XCTAssertFalse(editor.editorDocument.isDocumentEdited, @"opening a GUI is no edit");
}

- (void)testAClickRunsTheButtonsAction {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    UDGuiView *view = editor.guiView;
    NSPoint button = NSMakePoint(480, 330);
    [self mouse:NSEventTypeMouseMoved at:button in:view];
    [self mouse:NSEventTypeLeftMouseDown at:button in:view];
    [self mouse:NSEventTypeLeftMouseUp at:button in:view];
    XCTAssertEqualObjects([editor.player.gui getStateString:@"clicked" defaultString:@""], @"1", @"the button's onAction should run");
    XCTAssertTrue([editor.player.log containsObject:@"command udtest_go"], @"what it returns is logged: %@", editor.player.log);
}

- (void)testANamedEventFromThePullDown {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    NSMenuItem *item = [editor.namedEventPopUp itemWithTitle:@"udtestRename"];
    XCTAssertNotNil(item);
    [NSApp sendAction:item.action to:item.target from:item];
    XCTAssertEqualObjects([self var:@"text" of:@"Label" in:editor], @"renamed");
}

- (void)testTheStateIsEditedAsTheGameSetsIt {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    [controller showInspectorPaneTitled:@"State"];
    XCTAssertEqualObjects([self var:@"visible" of:@"Panel" in:editor], @"1");
    // a new key, named and given a value in the table
    NSSegmentedControl *plusMinus = [self segmentedControlWithAction:@selector(addOrRemoveStateKey:) inView:editor.stateView];
    plusMinus.selectedSegment = 0;
    [editor addOrRemoveStateKey:plusMinus];
    NSTableView *table = editor.stateTable;
    [table abortEditing];
    NSInteger row = table.selectedRow;
    XCTAssertGreaterThanOrEqual(row, 0, @"the new key is selected");
    [table.dataSource tableView:table setObjectValue:@"hidepanel" forTableColumn:[table tableColumnWithIdentifier:@"key"] row:row];
    NSInteger hideRow = -1;
    for (NSInteger i = 0; i < [table.dataSource numberOfRowsInTableView:table]; i++) {
        if ([[table.dataSource tableView:table objectValueForTableColumn:[table tableColumnWithIdentifier:@"key"] row:i] isEqual:@"hidepanel"]) hideRow = i;
    }
    XCTAssertGreaterThanOrEqual(hideRow, 0, @"the key is renamed");
    [table.dataSource tableView:table setObjectValue:@"1" forTableColumn:[table tableColumnWithIdentifier:@"value"] row:hideRow];
    XCTAssertEqualObjects([editor.player.gui getStateString:@"hidepanel" defaultString:@""], @"1");
    XCTAssertEqualObjects([self var:@"visible" of:@"Panel" in:editor], @"0", @"the panel's expression follows the state");
}

#pragma mark - The source

- (void)testAnEditedSourceRunsWhenTheEditorComesBack {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    editor.showsSource = YES;
    XCTAssertTrue([editor.viewerView isHidden], @"the source is shown instead");
    [self typeText:[UDViewerGUI stringByReplacingOccurrencesOfString:@"\"ready\"" withString:@"\"steady\""] intoTextView:editor.editorTextView];
    [self finishEvent];
    editor.showsSource = NO;
    XCTAssertFalse([editor.viewerView isHidden]);
    XCTAssertEqualObjects([self var:@"text" of:@"Label" in:editor], @"steady", @"the edited text runs");
    XCTAssertTrue(editor.editorDocument.isDocumentEdited, @"and the tab has an unsaved edit");
}

- (void)testABrokenSourceIsAnIssue {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    editor.showsSource = YES;
    [self typeText:@"windowDef Desktop {\n\trect 0, 0, 640, 480\n\ttext \"no end\n}\n" intoTextView:editor.editorTextView];
    [self finishEvent];
    editor.showsSource = NO;
    NSArray<UDDiagnosticItem *> *issues = editor.diagnosticStore.allDiagnostics;
    XCTAssertGreaterThan(issues.count, 0u, @"the parser's error should be in Issues");
    XCTAssertGreaterThan(issues.firstObject.line, 0, @"with its line");
}

#pragma mark - The window

- (void)testTheInspectorFollowsTheSelectedTab {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    [self openOutlinePath:@"script/udtest.script" inController:controller];
    XCTAssertEqual(controller.inspectorTabBar.tabBarItems.count, 0u, @"a script has no inspector");
    XCTAssertFalse([controller.inspectorPlaceholder isHidden], @"and the pane says so");

    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    XCTAssertEqual(controller.inspectorTabBar.tabBarItems.count, 4u, @"a GUI has its properties, its scripts, its state and its log");
    XCTAssertTrue([controller.inspectorPlaceholder isHidden]);
    XCTAssertEqual(editor.propertiesView.superview, controller.inspectorHost, @"the properties are shown first");

    controller.inspectorTabBar.selectedIndex = 3;
    [NSApp sendAction:@selector(inspectorTabChanged:) to:controller from:controller.inspectorTabBar];
    XCTAssertEqual(editor.logView.superview, controller.inspectorHost, @"the log, when it is chosen");
    XCTAssertNil(editor.propertiesView.superview);
}

- (void)testTheSidePanesKeepTheirWidths {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    NSArray<NSView *> *panes = controller.split.subviews;
    XCTAssertEqual(panes.count, 3u, @"navigator, editors, inspector");
    // a window that fits any screen it is tested on (xvfb's is 1280 wide),
    // then wider; on GNUstep the X server says when it has its new size
    NSWindow *window = controller.window;
    NSRect frame = window.frame;
    frame.size.width = 1000;
    [window setFrame:frame display:YES];
    [self spinUntil:^BOOL{ return NSWidth(window.frame) < 1001; } timeout:3.0];
    CGFloat left = NSWidth(panes[0].frame), right = NSWidth(panes[2].frame), centre = NSWidth(panes[1].frame);
    XCTAssertGreaterThanOrEqual(left, 160);
    XCTAssertGreaterThanOrEqual(right, 160);
    frame.size.width = 1200;
    [window setFrame:frame display:YES];
    [self spinUntil:^BOOL{ return NSWidth(panes[1].frame) > centre + 100; } timeout:3.0];
    XCTAssertEqualWithAccuracy(NSWidth(panes[0].frame), left, 1, @"the navigator keeps its width");
    XCTAssertEqualWithAccuracy(NSWidth(panes[2].frame), right, 1, @"the inspector keeps its width");
    XCTAssertEqualWithAccuracy(NSWidth(panes[1].frame), centre + 200, 1, @"the editors take the growth");
}

- (void)testTheNavigatorsBarSwitchesItsTabs {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    XCTAssertEqual(controller.navigatorTabBar.tabBarItems.count, (NSUInteger)controller.navigatorTabView.numberOfTabViewItems);
    controller.navigatorTabBar.selectedIndex = 2;
    [NSApp sendAction:@selector(navigatorTabChanged:) to:controller from:controller.navigatorTabBar];
    XCTAssertEqual([controller.navigatorTabView indexOfTabViewItem:controller.navigatorTabView.selectedTabViewItem], 2);
}

#pragma mark - Design

/// A mouse event at @a guiPoint, at @a seconds, sent to @a view.
- (void)mouse:(NSEventType)type at:(NSPoint)guiPoint time:(NSTimeInterval)seconds in:(UDGuiView *)view {
    NSPoint location = [view convertPoint:[view viewPointFromGui:guiPoint] toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:type location:location modifierFlags:0 timestamp:seconds
                                    windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    if (type == NSEventTypeLeftMouseDown) [view mouseDown:event];
    else if (type == NSEventTypeLeftMouseUp) [view mouseUp:event];
    else if (type == NSEventTypeLeftMouseDragged) [view mouseDragged:event];
    else [view mouseMoved:event];
}

/// A drag in the GUI's units, as the mouse does it: down, four moves after
/// the engine's 50 ms, up.
- (void)dragFrom:(NSPoint)from to:(NSPoint)to in:(UDGuiView *)view {
    [self mouse:NSEventTypeLeftMouseDown at:from time:1.0 in:view];
    for (int i = 1; i <= 4; i++) {
        NSPoint p = NSMakePoint(from.x + (to.x - from.x) * i / 4, from.y + (to.y - from.y) * i / 4);
        [self mouse:NSEventTypeLeftMouseDragged at:p time:1.1 + i * 0.01 in:view];
    }
    [self mouse:NSEventTypeLeftMouseUp at:to time:1.2 in:view];
}

- (UDGuiEditorViewController *)openDesignIn:(UDWorkspaceWindowController *)controller {
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    editor.modeControl.selectedSegment = 1;
    [editor changeMode:editor.modeControl];
    XCTAssertTrue(editor.designing);
    XCTAssertNotNil(editor.designWorkspace.interface, @"the GUI is loaded for editing");
    return editor;
}

- (idRectangle)designRectOf:(NSString *)name in:(UDGuiEditorViewController *)editor {
    idDrawWin *dw = [[editor.designWorkspace.interface getDesktop] findChildByName:name];
    return [rvGEWindowWrapper wrapperOf:dw.win].clientRect;
}

- (void)testADragInTheDesignMovesTheWindowWithUndo {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    [self dragFrom:NSMakePoint(480, 330) to:NSMakePoint(520, 350) in:editor.guiView];
    idRectangle moved = [self designRectOf:@"Go" in:editor];
    XCTAssertEqualWithAccuracy(moved.x, 440, 1, @"the button is moved by the drag");
    XCTAssertEqualWithAccuracy(moved.y, 320, 1);
    XCTAssertEqual([editor.designWorkspace.selections num], 1, @"and selected");
    [self finishEvent];
    XCTAssertTrue(editor.editorDocument.isDocumentEdited, @"a design's edit is the tab's");

    NSUndoManager *undoManager = editor.editorDocument.undoManager;
    XCTAssertEqualObjects(undoManager.undoActionName, @"Move");
    [undoManager undo];
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 400, 1, @"Undo puts it back");
    [undoManager redo];
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 440, 1, @"Redo moves it again");
}

- (void)testTheDesignsEditsAreSavedShownAndRun {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    [self dragFrom:NSMakePoint(480, 330) to:NSMakePoint(520, 350) in:editor.guiView];
    [self finishEvent];

    // saved: the GUI as the editor writes it, the button where it was put
    [NSApp sendAction:@selector(saveDocument:) to:controller from:nil];
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];
    NSString *saved = [NSString stringWithContentsOfFile:[self.savePath stringByAppendingPathComponent:@"base/guis/udtest_menu.gui"]
                                                encoding:NSISOLatin1StringEncoding error:NULL];
    XCTAssertTrue([saved containsString:@"rect\t440,320,160,60"], @"%@", saved);
    XCTAssertTrue([saved containsString:@"onNamedEvent udtestRename"], @"its scripts kept");

    // shown in the source, and run
    editor.showsSource = YES;
    XCTAssertTrue([editor.editorTextView.string containsString:@"rect\t440,320,160,60"], @"%@", editor.editorTextView.string);
    editor.showsSource = NO;
    editor.modeControl.selectedSegment = 0;
    [editor changeMode:editor.modeControl];
    XCTAssertEqualObjects([self var:@"rect" of:@"Go" in:editor], @"440 320 160 60", @"the design's edit runs");
}

- (void)testAnEditedSourceIsOneUndo {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    editor.showsSource = YES;
    [self typeText:[UDViewerGUI stringByReplacingOccurrencesOfString:@"400, 300, 160, 60" withString:@"10, 300, 160, 60"]
      intoTextView:editor.editorTextView];
    [self finishEvent];
    editor.showsSource = NO;
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 10, 1, @"the edited text is designed");

    NSUndoManager *undoManager = editor.editorDocument.undoManager;
    XCTAssertEqualObjects(undoManager.undoActionName, @"Edit Source");
    [undoManager undo];
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 400, 1, @"Undo takes the whole edit back");
    XCTAssertTrue([editor.editorTextView.string containsString:@"400, 300, 160, 60"]);
    [undoManager redo];
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 10, 1);
}

- (void)testTheSelectionIsDrawnOverTheDesign {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(480, 330) time:1.0 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(480, 330) time:1.05 in:editor.guiView];
    XCTAssertEqual([editor.designWorkspace.selections num], 1);
    UDOverlay *overlay = [[UDOverlay alloc] init];
    [editor.designWorkspace renderOverlayInto:overlay];
    XCTAssertGreaterThan(overlay.lineVertexCount, 0u, @"the selection and its handles");
    UDGuiGLView *gl = (UDGuiGLView *)editor.guiView.glView;
    if (gl != nil) {
        XCTAssertEqual(gl.overlay.lineVertexCount, overlay.lineVertexCount, @"drawn over the GUI");
    }
}

#pragma mark - The time

/// Whether the lamp's backcolor is green.
- (BOOL)lampIsLitIn:(UDGuiEditorViewController *)editor {
    NSString *color = [self var:@"backcolor" of:@"Lamp" in:editor];
    NSArray<NSString *> *parts = [[color stringByReplacingOccurrencesOfString:@"," withString:@" "] componentsSeparatedByString:@" "];
    parts = [parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    return parts.count == 4 && parts[1].floatValue > 0.5f;
}

- (void)namedEvent:(NSString *)name in:(UDGuiEditorViewController *)editor {
    NSMenuItem *item = [editor.namedEventPopUp itemWithTitle:name];
    XCTAssertNotNil(item, @"%@ is offered", name);
    XCTAssertTrue([editor.namedEventPopUp isEnabled]);
    [NSApp sendAction:item.action to:item.target from:item];
}

- (void)slide:(UDGuiEditorViewController *)editor to:(double)time {
    XCTAssertTrue([editor.timeSlider isEnabled]);
    editor.timeSlider.doubleValue = time;
    [NSApp sendAction:editor.timeSlider.action to:editor.timeSlider.target from:editor.timeSlider];
}

- (void)testTheSliderSeeksTheRunTheNamedEventsSentAgain {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    [editor togglePlaying:nil];
    XCTAssertFalse(editor.player.playing);
    XCTAssertGreaterThanOrEqual(editor.timeSlider.maxValue, 1500, @"as long as its time events");
    [self namedEvent:@"udtestLight" in:editor];
    [self slide:editor to:1000];
    XCTAssertEqual(editor.player.time, 1000);
    XCTAssertEqualObjects(editor.timeLabel.stringValue, @"1.00 s");
    XCTAssertTrue([self lampIsLitIn:editor], @"lit at 0.5 s: %@", [self var:@"backcolor" of:@"Lamp" in:editor]);
    [self slide:editor to:200];
    XCTAssertEqual(editor.player.time, 200);
    XCTAssertFalse([self lampIsLitIn:editor], @"back before it was lit");
    [self slide:editor to:1000];
    XCTAssertTrue([self lampIsLitIn:editor], @"the named event sent again on the way");
    [editor restart:nil];
    [self slide:editor to:1000];
    XCTAssertFalse([self lampIsLitIn:editor], @"Restart forgets it");
}

- (void)testTheDesignIsAtTheSlidersTime {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    XCTAssertFalse([editor.playButton isEnabled], @"a design does not play");
    XCTAssertTrue([editor.stepButton isEnabled]);
    [self namedEvent:@"udtestLight" in:editor];
    [self slide:editor to:1000];
    XCTAssertTrue([self lampIsLitIn:editor], @"the design drawn at 1 s");

    // an edit keeps the time
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(480, 330) time:1.0 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(480, 330) time:1.05 in:editor.guiView];
    [editor.designWorkspace nudgeX:10 y:0 size:NO];
    XCTAssertEqual(editor.player.time, 1000);
    XCTAssertTrue([[self var:@"rect" of:@"Go" in:editor] hasPrefix:@"410"], @"the edit is drawn: %@", [self var:@"rect" of:@"Go" in:editor]);
    XCTAssertTrue([self lampIsLitIn:editor]);

    // a drag moves the window in the run as it goes; run from its text once
    // it ends
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(490, 330) time:2.0 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseDragged at:NSMakePoint(510, 330) time:2.1 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseDragged at:NSMakePoint(530, 330) time:2.2 in:editor.guiView];
    NSString *ranText = editor.runningText;
    XCTAssertTrue([[self var:@"rect" of:@"Go" in:editor] hasPrefix:@"450"], @"moved as it is dragged: %@", [self var:@"rect" of:@"Go" in:editor]);
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(530, 330) time:2.3 in:editor.guiView];
    XCTAssertNotEqualObjects(editor.runningText, ranText, @"run again from the text");
    XCTAssertTrue([[self var:@"rect" of:@"Go" in:editor] hasPrefix:@"450"]);
    XCTAssertEqual(editor.player.time, 1000);

    // a window hidden in the design is not drawn, whatever its scripts do;
    // run, it is
    [self chooseWindow:@"Panel" in:editor];
    NSOutlineView *outline = editor.windowsOutline;
    NSTableColumn *eye = [outline tableColumnWithIdentifier:@"visible"];
    [outline.dataSource outlineView:outline setObjectValue:@NO forTableColumn:eye byItem:[outline itemAtRow:outline.selectedRow]];
    XCTAssertEqualObjects([self var:@"visible" of:@"Panel" in:editor], @"0");
    [editor changeMode:nil];
    XCTAssertFalse(editor.designing);
    XCTAssertEqual(editor.player.time, 1000, @"the run goes on from there");
    XCTAssertEqualObjects([self var:@"visible" of:@"Panel" in:editor], @"1");
}

#pragma mark - The navigator

- (void)testTheWindowsAreANavigatorOfTheGuisTab {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    NSUInteger own = controller.navigatorTabBar.tabBarItems.count;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    XCTAssertEqual(controller.navigatorTabBar.tabBarItems.count, own + 1, @"a GUI's tab adds its windows to the navigators");
    XCTAssertEqual((NSUInteger)controller.navigatorTabView.numberOfTabViewItems, own + 1);
    [controller showNavigatorPaneTitled:@"Windows"];
    XCTAssertEqual(editor.windowsView.superview != nil, YES, @"shown in the left pane");

    NSOutlineView *outline = editor.windowsOutline;
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        [rows addObject:[(idWindow *)[outline itemAtRow:row] getName]];
    }
    XCTAssertEqualObjects(rows, (@[@"Desktop", @"Panel", @"Label", @"Go", @"Lamp"]), @"the desktop open, its windows in it");

    [self openOutlinePath:@"script/udtest.script" inController:controller];
    XCTAssertEqual(controller.navigatorTabBar.tabBarItems.count, own, @"a script's tab has no windows");
}

- (void)testChoosingAWindowInTheNavigatorDesignsIt {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    NSOutlineView *outline = editor.windowsOutline;
    NSInteger row = -1;
    for (NSInteger i = 0; i < outline.numberOfRows; i++) {
        if ([[(idWindow *)[outline itemAtRow:i] getName] isEqualToString:@"Go"]) row = i;
    }
    XCTAssertGreaterThanOrEqual(row, 0);
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    XCTAssertTrue(editor.designing, @"choosing a window designs the GUI");
    XCTAssertEqual([editor.designWorkspace.selections num], 1);
    XCTAssertEqualObjects([editor.designWorkspace.selections[0] getName], @"Go");
}

- (void)testTheDesignsSelectionIsTheNavigators {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(480, 330) time:1.0 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(480, 330) time:1.05 in:editor.guiView];
    NSOutlineView *outline = editor.windowsOutline;
    XCTAssertEqual(outline.selectedRowIndexes.count, 1u);
    XCTAssertEqualObjects([(idWindow *)[outline itemAtRow:outline.selectedRow] getName], @"Go", @"clicked on the canvas, chosen in the navigator");
}

- (void)testTheEyeHidesAWindowInTheDesignOnly {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    NSOutlineView *outline = editor.windowsOutline;
    NSTableColumn *eye = [outline tableColumnWithIdentifier:@"visible"];
    idWindow *panel = nil;
    for (NSInteger i = 0; i < outline.numberOfRows; i++) {
        if ([[(idWindow *)[outline itemAtRow:i] getName] isEqualToString:@"Panel"]) panel = [outline itemAtRow:i];
    }
    XCTAssertNotNil(panel);
    XCTAssertEqualObjects([outline.dataSource outlineView:outline objectValueForTableColumn:eye byItem:panel], @YES);
    [outline.dataSource outlineView:outline setObjectValue:@NO forTableColumn:eye byItem:panel];
    XCTAssertTrue([rvGEWindowWrapper wrapperOf:panel].hidden, @"hidden in the design");
    XCTAssertFalse([editor.designWorkspace.text containsString:@"visible\t0"], @"the file's visible is as it was");
    // a click where it is finds what is under it
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(150, 150) time:1.0 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(150, 150) time:1.05 in:editor.guiView];
    XCTAssertEqual([editor.designWorkspace.selections num], 0, @"a hidden window is not chosen on the canvas");

    [editor.editorDocument.undoManager undo];
    XCTAssertFalse([rvGEWindowWrapper wrapperOf:panel].hidden, @"Undo shows it again");
}

#pragma mark - Properties

- (void)chooseWindow:(NSString *)name in:(UDGuiEditorViewController *)editor {
    NSOutlineView *outline = editor.windowsOutline;
    for (NSInteger i = 0; i < outline.numberOfRows; i++) {
        if ([[(idWindow *)[outline itemAtRow:i] getName] isEqualToString:name]) {
            [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i] byExtendingSelection:NO];
        }
    }
}

- (NSInteger)propertyRow:(NSString *)name in:(UDGuiEditorViewController *)editor {
    NSTableView *table = editor.propertiesTable;
    NSTableColumn *key = [table tableColumnWithIdentifier:@"key"];
    for (NSInteger i = 0; i < [table.dataSource numberOfRowsInTableView:table]; i++) {
        if ([[table.dataSource tableView:table objectValueForTableColumn:key row:i] isEqual:name]) return i;
    }
    return -1;
}

- (void)testThePropertiesAreTheChosenWindowsAndEditIt {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    XCTAssertFalse([editor.propertiesPlaceholder isHidden], @"no window chosen yet");
    [self chooseWindow:@"Go" in:editor];
    XCTAssertTrue([editor.propertiesPlaceholder isHidden]);
    NSTableView *table = editor.propertiesTable;
    NSTableColumn *value = [table tableColumnWithIdentifier:@"value"];
    NSInteger rectRow = [self propertyRow:@"rect" in:editor];
    XCTAssertGreaterThanOrEqual(rectRow, 0);
    XCTAssertEqualObjects([table.dataSource tableView:table objectValueForTableColumn:value row:rectRow], @"400, 300, 160, 60");

    [table.dataSource tableView:table setObjectValue:@"40, 30, 160, 60" forTableColumn:value row:rectRow];
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 40, 0.5, @"the rect as typed");
    XCTAssertEqualObjects(editor.editorDocument.undoManager.undoActionName, @"Property Change");

    [table.dataSource tableView:table setObjectValue:@"1, 2, 3, 4 five" forTableColumn:value row:[self propertyRow:@"rect" in:editor]];
    XCTAssertTrue([editor.propertiesMessage.stringValue hasPrefix:@"Invalid property value"], @"%@", editor.propertiesMessage.stringValue);
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 40, 0.5, @"and nothing changed");
}

- (void)testAPropertyIsAdded {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    [self chooseWindow:@"Label" in:editor];
    [editor addProperty:nil];
    NSTableView *table = editor.propertiesTable;
    [table abortEditing];
    NSInteger row = [table.dataSource numberOfRowsInTableView:table] - 1;
    [table.dataSource tableView:table setObjectValue:@"textscale" forTableColumn:[table tableColumnWithIdentifier:@"key"] row:row];
    [table.dataSource tableView:table setObjectValue:@"0.5" forTableColumn:[table tableColumnWithIdentifier:@"value"] row:row];
    XCTAssertGreaterThanOrEqual([self propertyRow:@"textscale" in:editor], 0, @"the new property is the window's");
    XCTAssertTrue([editor.designWorkspace.text containsString:@"textscale\t0.5"], @"%@", editor.designWorkspace.text);
}

#pragma mark - Scripts

- (void)testTheChosenWindowsScriptsAreEditedAndApplied {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    XCTAssertFalse([editor.scriptsPlaceholder isHidden]);
    [self chooseWindow:@"Go" in:editor];
    NSString *text = editor.scriptsText.string;
    XCTAssertTrue([text containsString:@"onAction"], @"%@", text);
    XCTAssertTrue([text containsString:@"udtest_go"], @"%@", text);

    editor.scriptsText.string = [text stringByReplacingOccurrencesOfString:@"udtest_go" withString:@"udtest_went"];
    [editor applyScripts:nil];
    XCTAssertTrue([editor.designWorkspace.text containsString:@"udtest_went"], @"the scripts are the window's");
    XCTAssertEqualObjects(editor.editorDocument.undoManager.undoActionName, @"Scripts Change");
    [editor.editorDocument.undoManager undo];
    XCTAssertTrue([editor.scriptsText.string containsString:@"udtest_go"], @"Undo shows the scripts as they were");

    editor.scriptsText.string = @"onWhatever\n{\n}\n";
    [editor applyScripts:nil];
    XCTAssertTrue([editor.scriptsMessage.stringValue hasPrefix:@"Script error"], @"%@", editor.scriptsMessage.stringValue);
}

#pragma mark - Commands

/// A key event of @a characters (and @a flags) sent to @a view.
- (void)key:(NSString *)characters flags:(NSEventModifierFlags)flags in:(UDGuiView *)view {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                                  windowNumber:view.window.windowNumber context:nil characters:characters
                   charactersIgnoringModifiers:characters isARepeat:NO keyCode:0];
    [view keyDown:event];
}

- (NSArray<NSString *> *)navigatorNamesIn:(UDGuiEditorViewController *)editor {
    NSOutlineView *outline = editor.windowsOutline;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSInteger i = 0; i < outline.numberOfRows; i++) {
        [names addObject:[(idWindow *)[outline itemAtRow:i] getName]];
    }
    return names;
}

- (void)testTheDesignsMenuOffersTheEditorsCommands {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    UDGuiView *view = editor.guiView;
    NSMenu *menu = [editor guiView:view designMenuAt:[view viewPointFromGui:NSMakePoint(480, 330)]];
    NSArray<NSString *> *titles = [menu.itemArray valueForKey:@"title"];
    for (NSString *title in @[@"New", @"Select", @"Arrange", @"Align", @"Make Same Size", @"Copy", @"Paste", @"Delete", @"Scripts…", @"Properties…"]) {
        XCTAssertTrue([titles containsObject:title], @"%@ in %@", title, titles);
    }
    NSArray<NSString *> *under = [[editor.selectMenu.itemArray valueForKey:@"title"] copy];
    XCTAssertEqualObjects(under, (@[@"Go", @"Desktop"]), @"the windows under the click");

    // New: a window, selected, in the navigator
    NSMenuItem *newEdit = [[menu itemWithTitle:@"New"].submenu itemWithTitle:@"editDef"];
    [NSApp sendAction:newEdit.action to:newEdit.target from:newEdit];
    XCTAssertEqualObjects([editor.designWorkspace.selections[0] getName], @"unnamed");
    XCTAssertTrue([[self navigatorNamesIn:editor] containsObject:@"unnamed"]);
    XCTAssertTrue([editor.designWorkspace.text containsString:@"editDef unnamed"]);
}

- (void)testTheKeysDeleteNudgeAndArrange {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    UDGuiView *view = editor.guiView;
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(480, 330) time:1.0 in:view];
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(480, 330) time:1.05 in:view];

    unichar right = NSRightArrowFunctionKey;
    [self key:[NSString stringWithCharacters:&right length:1] flags:0 in:view];
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 401, 0.5, @"the arrow nudges");

    [self key:@"[" flags:NSEventModifierFlagCommand | NSEventModifierFlagShift in:view];
    XCTAssertEqualObjects([[self navigatorNamesIn:editor] subarrayWithRange:NSMakeRange(0, 2)], (@[@"Desktop", @"Go"]), @"sent to the back");

    unichar backspace = 127;
    [self key:[NSString stringWithCharacters:&backspace length:1] flags:0 in:view];
    XCTAssertFalse([editor.designWorkspace.text containsString:@"windowDef Go"], @"deleted");
    XCTAssertFalse([[self navigatorNamesIn:editor] containsObject:@"Go"]);
    [editor.editorDocument.undoManager undo];
    XCTAssertTrue([[self navigatorNamesIn:editor] containsObject:@"Go"], @"and back");
}

- (void)testCopyAndPasteFromTheEditMenu {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    UDGuiView *view = editor.guiView;
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(480, 330) time:1.0 in:view];
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(480, 330) time:1.05 in:view];
    [view copy:nil];
    [view paste:nil];
    XCTAssertEqualObjects([editor.designWorkspace.selections[0] getName], @"Go1", @"a new window, named apart");
    XCTAssertTrue([editor.designWorkspace.text containsString:@"udtest_go"], @"its scripts with it");
    XCTAssertEqualObjects(editor.editorDocument.undoManager.undoActionName, @"Paste");
}

#pragma mark - GL

- (void)testGLDrawsWhatTheSoftwareRendererDraws {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    UDGuiGLView *gl = (UDGuiGLView *)editor.guiView.glView;
    if (gl == nil) {
        NSLog(@"UDGuiViewerTests: no GL here; the viewer draws in software");
        return;
    }
    // the same frame both ways, the GL surface at the picture's size
#ifdef __APPLE__
    gl.wantsBestResolutionOpenGLSurface = NO;
#endif
    // the GUI at its own size, pixel for pixel
    [editor.guiView setFrameSize:NSMakeSize(640, 480)];
    editor.player.playing = NO;
    editor.player.drawsPicture = YES;
    [editor.player renderFrame];
    [editor.guiView showFrame];
    NSBitmapImageRep *drawn = [gl readPicture];
    NSBitmapImageRep *expected = (NSBitmapImageRep *)editor.player.frame.representations.firstObject;
    XCTAssertNotNil(drawn);
    // scaled into the view: sample at the GUI's points
    NSInteger off = 0, samples = 0;
    for (int y = 10; y < 480; y += 20) {
        for (int x = 10; x < 640; x += 20) {
            NSInteger gx = x * drawn.pixelsWide / 640, gy = y * drawn.pixelsHigh / 480;
            const uint8_t *a = drawn.bitmapData + gy * drawn.bytesPerRow + gx * 4;
            const uint8_t *b = expected.bitmapData + y * expected.bytesPerRow + x * 4;
            for (int k = 0; k < 3; k++) {
                if (abs((int)a[k] - (int)b[k]) > 8) off++;
                samples++;
            }
        }
    }
    XCTAssertLessThan(off, samples / 100, @"GL (%@) should draw what software draws: %ld of %ld off", gl.glDescription, (long)off, (long)samples);
}

@end
