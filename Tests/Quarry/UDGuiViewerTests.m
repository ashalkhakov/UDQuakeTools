#import "UDTransportController.h"
#import "UDWorkspace.h"
#import "UDQuarryTestCase.h"

#import <AppKit/AppKit.h>     // before Core Data (GNUstep: NSPredicateEditorRowTemplate.h)
#import "idFileSystem.h"
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
#import "rvGEOptions.h"
#import "UDGuiEditorOptionsController.h"
#import "UDGuiItemPropertiesController.h"
#import "UDGuiScriptsController.h"
#import "UDReferencePicker.h"
#import "UDExpressionEditor.h"
#import "rvGEScript.h"
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

@interface UDGuiViewerTests : UDQuarryTestCase
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
    XCTAssertEqual(controller.inspectorTabBar.tabBarItems.count, 5u, @"a GUI has its properties, its layout, its scripts, its state and its log");
    XCTAssertTrue([controller.inspectorPlaceholder isHidden]);
    XCTAssertEqual(editor.propertiesView.superview, controller.inspectorHost, @"the properties are shown first");

    controller.inspectorTabBar.selectedIndex = 4;
    [NSApp sendAction:@selector(inspectorTabChanged:) to:controller from:controller.inspectorTabBar];
    XCTAssertEqual(editor.logView.superview, controller.inspectorHost, @"the log, when it is chosen");
    XCTAssertNil(editor.propertiesView.superview);
}

- (void)testTheSidePanesKeepTheirWidths {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    NSArray<NSView *> *panes = controller.split.subviews;
    XCTAssertEqual(panes.count, 3u, @"navigator, editors, inspector");
    // a window that fits any screen it is tested on with room to grow
    // (Windows CI's is 1024 wide, xvfb's 1280), then wider; a screen
    // narrower than that keeps it on the screen, and the editors take what
    // growth there is. On GNUstep the window server says when it has its
    // new size.
    NSWindow *window = controller.window;
    NSRect frame = window.frame;
    frame.size.width = 900;
    [window setFrame:frame display:YES];
    [self spinUntil:^BOOL{ return NSWidth(window.frame) < 901; } timeout:3.0];
    CGFloat left = NSWidth(panes[0].frame), right = NSWidth(panes[2].frame), centre = NSWidth(panes[1].frame);
    CGFloat narrow = NSWidth(window.frame);
    XCTAssertGreaterThanOrEqual(left, 160);
    XCTAssertGreaterThanOrEqual(right, 160);
    frame.size.width = 1200;
    [window setFrame:frame display:YES];
    [self spinUntil:^BOOL{ return NSWidth(panes[1].frame) > centre + 40; } timeout:3.0];
    CGFloat grown = NSWidth(window.frame) - narrow;
    XCTAssertGreaterThan(grown, 40, @"the window is wider");
    XCTAssertEqualWithAccuracy(NSWidth(panes[0].frame), left, 1, @"the navigator keeps its width");
    XCTAssertEqualWithAccuracy(NSWidth(panes[2].frame), right, 1, @"the inspector keeps its width");
    XCTAssertEqualWithAccuracy(NSWidth(panes[1].frame), centre + grown, 1, @"the editors take the growth");
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

/// The source shown, nothing of the canvas over it: on GNUstep the GL
/// view's X window taken down while it is hidden, put up as it draws again
/// (the stack's NSOpenGLView, gnustep-patches' opengl-view-hidden).
- (void)testTheSourceIsNotUnderTheCanvas {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    UDGuiGLView *gl = (UDGuiGLView *)editor.guiView.glView;
    if (gl == nil) return;
    [editor.view.window display];
    XCTAssertEqual(gl.openGLContext.view, gl, @"drawn");
    editor.showsSource = YES;
    XCTAssertTrue([gl isHiddenOrHasHiddenAncestor]);
#ifdef GNUSTEP
    XCTAssertNil(gl.openGLContext.view, @"its X window down");
#endif
    editor.showsSource = NO;
    [editor.view.window display];
    XCTAssertEqual(gl.openGLContext.view, gl, @"drawn again");
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
    XCTAssertTrue([editor.transport.timeSlider isEnabled]);
    // the slider's range the GUI's, once the player has it
    XCTAssertTrue([self spinUntil:^BOOL{ return editor.transport.timeSlider.maxValue >= time; } timeout:10],
                  @"the slider reaches %g: %g", time, editor.transport.timeSlider.maxValue);
    editor.transport.timeSlider.doubleValue = time;
    [NSApp sendAction:editor.transport.timeSlider.action to:editor.transport.timeSlider.target from:editor.transport.timeSlider];
}

- (void)testTheSliderSeeksTheRunTheNamedEventsSentAgain {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    [editor.transport togglePlaying:nil];
    XCTAssertFalse(editor.player.playing);
    XCTAssertGreaterThanOrEqual(editor.transport.timeSlider.maxValue, 1500, @"as long as its time events");
    [self namedEvent:@"udtestLight" in:editor];
    [self slide:editor to:1000];
    XCTAssertEqual(editor.player.time, 1000);
    XCTAssertEqualObjects(editor.transport.timeLabel.stringValue, @"1.00 s");
    XCTAssertTrue([self lampIsLitIn:editor], @"lit at 0.5 s: %@", [self var:@"backcolor" of:@"Lamp" in:editor]);
    [self slide:editor to:200];
    XCTAssertEqual(editor.player.time, 200);
    XCTAssertFalse([self lampIsLitIn:editor], @"back before it was lit");
    [self slide:editor to:1000];
    XCTAssertTrue([self lampIsLitIn:editor], @"the named event sent again on the way");
    [editor.transport restart:nil];
    [self slide:editor to:1000];
    XCTAssertFalse([self lampIsLitIn:editor], @"Restart forgets it");
}

- (void)testTheDesignIsAtTheSlidersTime {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    XCTAssertFalse([editor.transport.playButton isEnabled], @"a design does not play");
    XCTAssertTrue([editor.transport.stepButton isEnabled]);
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

    // a drag moves the window in the run as it goes, the run never read
    // again
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(490, 330) time:2.0 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseDragged at:NSMakePoint(510, 330) time:2.1 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseDragged at:NSMakePoint(530, 330) time:2.2 in:editor.guiView];
    NSString *ranText = editor.runningText;
    XCTAssertTrue([[self var:@"rect" of:@"Go" in:editor] hasPrefix:@"450"], @"moved as it is dragged: %@", [self var:@"rect" of:@"Go" in:editor]);
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(530, 330) time:2.3 in:editor.guiView];
    XCTAssertEqualObjects(editor.runningText, ranText, @"the edits made in the run, not read again");
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

/// The names of @a window's tree, depth first; the design's deleted not.
- (NSArray<NSString *> *)treeNamesOf:(idWindow *)window {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
    if (wrapper.deleted) return names;
    [names addObject:[window getName]];
    for (int i = 0; i < [window getChildCount]; i++) {
        [names addObjectsFromArray:[self treeNamesOf:[window getChild:i]]];
    }
    return names;
}

- (idWindow *)designWindow:(NSString *)name in:(UDGuiEditorViewController *)editor {
    return [[editor.designWorkspace.interface getDesktop] findChildByName:name].win;
}

- (idWindow *)runWindow:(NSString *)name in:(UDGuiEditorViewController *)editor {
    return [[editor.player.gui getDesktop] findChildByName:name].win;
}

- (void)testEveryEditIsMadeInTheRunAsItIs {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    rvGEWorkspace *design = editor.designWorkspace;
    NSUndoManager *undo = editor.editorDocument.undoManager;
    [self namedEvent:@"udtestLight" in:editor];
    [self slide:editor to:1000];
    NSString *ranText = editor.runningText;

    // pasted, with its scripts
    [design.selections set:[self designWindow:@"Go" in:editor]];
    [design copySelected];
    [design paste];
    [self checkRunOf:editor ranText:ranText after:@"Paste"];
    XCTAssertNotNil([self runWindow:@"Go1" in:editor]);
    [undo undo];
    [self checkRunOf:editor ranText:ranText after:@"Paste undone"];
    XCTAssertNil([self runWindow:@"Go1" in:editor]);
    [undo redo];
    [self checkRunOf:editor ranText:ranText after:@"Paste redone"];

    // deleted: not drawn
    [design.selections set:[self designWindow:@"Go1" in:editor]];
    [design deleteSelected];
    XCTAssertEqualObjects([self var:@"visible" of:@"Go1" in:editor], @"0");
    [undo undo];
    XCTAssertEqualObjects([self var:@"visible" of:@"Go1" in:editor], @"1");
    [self checkRunOf:editor ranText:ranText after:@"Delete undone"];

    // ordered, parented
    [design.selections set:[self designWindow:@"Go" in:editor]];
    [design sendSelectedToBack];
    [self checkRunOf:editor ranText:ranText after:@"Send to Back"];
    [undo undo];
    [self checkRunOf:editor ranText:ranText after:@"Send to Back undone"];
    [design.selections set:[self designWindow:@"Panel" in:editor]];
    [design.selections add:[self designWindow:@"Go" in:editor]];
    XCTAssertTrue([design makeSelectedAChild]);
    [self checkRunOf:editor ranText:ranText after:@"Make Child"];
    XCTAssertEqualObjects([[[self runWindow:@"Go" in:editor] getParent] getName], @"Panel");

    // new
    [design addWindow:WT_NORMAL];
    [self checkRunOf:editor ranText:ranText after:@"New"];

    // its scripts
    [self chooseWindow:@"Lamp" in:editor];
    [self openEvent:@"onTime 500" in:editor];
    [self chooseStatementAtRow:0 in:editor];
    editor.scriptsController.parameterField2.stringValue = @"0 1 1 1";
    [editor.scriptsController statementEdited:editor.scriptsController.parameterField2];
    XCTAssertEqualObjects(editor.runningText, ranText, @"scripts: not read again");
    NSString *script = [[rvGEWindowWrapper wrapperOf:[self runWindow:@"Lamp" in:editor]].scriptDict getString:@"onTime 500"];
    XCTAssertTrue([script containsString:@"0 1 1 1"], @"the run's lamp read again: %@", script);

    // read again by itself (a seek back): the edits kept, and still made
    [self slide:editor to:200];
    [self slide:editor to:1000];
    XCTAssertEqualObjects([self treeNamesOf:[editor.player.gui getDesktop]], [self treeNamesOf:[design.interface getDesktop]], @"the edits kept");
    XCTAssertEqualObjects([[[self runWindow:@"Go" in:editor] getParent] getName], @"Panel");
    [design.selections set:[self designWindow:@"Go" in:editor]];
    NSString *before = [self var:@"rect" of:@"Go" in:editor];
    [design nudgeX:5 y:0 size:NO];
    XCTAssertNotEqualObjects([self var:@"rect" of:@"Go" in:editor], before, @"an edit after it made in the run read again");
}

/// The run as it was (its text, its time, the lamp lit) and its windows
/// the design's, after @a what.
- (void)checkRunOf:(UDGuiEditorViewController *)editor ranText:(NSString *)ranText after:(NSString *)what {
    XCTAssertEqualObjects(editor.runningText, ranText, @"%@: made in the run, not read again", what);
    XCTAssertEqual(editor.player.time, 1000, @"%@", what);
    XCTAssertTrue([self lampIsLitIn:editor], @"%@: the run where it was", what);
    XCTAssertEqualObjects([self treeNamesOf:[editor.player.gui getDesktop]], [self treeNamesOf:[editor.designWorkspace.interface getDesktop]],
                          @"%@: the run's windows the design's", what);
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
        [rows addObject:[self rowName:row of:outline]];
    }
    XCTAssertEqualObjects(rows, (@[@"Desktop", @"\u0192 onNamedEvent udtestLight", @"\u0192 onNamedEvent udtestRename",
                                   @"Panel", @"Label", @"Go", @"Lamp"]), @"the desktop open, its events and its windows in it");

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
        if ([[self rowName:i of:outline] isEqualToString:@"Go"]) row = i;
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
    XCTAssertEqualObjects([self rowName:outline.selectedRow of:outline], @"Go", @"clicked on the canvas, chosen in the navigator");
}

- (void)testTheEyeHidesAWindowInTheDesignOnly {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    NSOutlineView *outline = editor.windowsOutline;
    NSTableColumn *eye = [outline tableColumnWithIdentifier:@"visible"];
    idWindow *panel = nil;
    for (NSInteger i = 0; i < outline.numberOfRows; i++) {
        if ([[self rowName:i of:outline] isEqualToString:@"Panel"]) panel = [outline itemAtRow:i];
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

- (void)testALockedWindowIsNotChosenOnTheCanvas {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    NSOutlineView *outline = editor.windowsOutline;
    NSTableColumn *lock = [outline tableColumnWithIdentifier:@"locked"];
    XCTAssertNotNil(lock, @"the navigator has a lock");
    idWindow *go = [self designWindow:@"Go" in:editor];
    XCTAssertEqualObjects([outline.dataSource outlineView:outline objectValueForTableColumn:lock byItem:go], @NO);
    [outline.dataSource outlineView:outline setObjectValue:@YES forTableColumn:lock byItem:go];
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(480, 330) time:1.0 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(480, 330) time:1.05 in:editor.guiView];
    XCTAssertEqual([editor.designWorkspace.selections num], 0, @"clicked through");
    [self chooseWindow:@"Go" in:editor];
    XCTAssertEqual(editor.designWorkspace.selections[0], go, @"the navigator still chooses it");
    XCTAssertFalse([editor.designWorkspace.text containsString:@"lock"], @"the editor's alone");
    [outline.dataSource outlineView:outline setObjectValue:@NO forTableColumn:lock byItem:go];
    [editor.designWorkspace.selections clear];
    [self mouse:NSEventTypeLeftMouseDown at:NSMakePoint(480, 330) time:2.0 in:editor.guiView];
    [self mouse:NSEventTypeLeftMouseUp at:NSMakePoint(480, 330) time:2.05 in:editor.guiView];
    XCTAssertEqual(editor.designWorkspace.selections[0], go, @"unlocked, chosen again");
}

#pragma mark - Properties

- (void)chooseWindow:(NSString *)name in:(UDGuiEditorViewController *)editor {
    NSOutlineView *outline = editor.windowsOutline;
    for (NSInteger i = 0; i < outline.numberOfRows; i++) {
        if ([[self rowName:i of:outline] isEqualToString:name]) {
            [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i] byExtendingSelection:NO];
        }
    }
}

#pragma mark - Item properties (GEItemPropsDlg) and Layout (GETransformer)

- (void)testTheItemPropertiesPagesShowAndEditTheChosenWindow {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    XCTAssertTrue([editor.propertiesScroll isHidden], @"no window chosen yet");
    XCTAssertFalse([editor.propertiesPlaceholder isHidden]);
    UDGuiItemPropertiesController *props = editor.itemProperties;

    [self chooseWindow:@"Panel" in:editor];
    XCTAssertFalse([editor.propertiesScroll isHidden], @"its groups, one under the other");
    XCTAssertTrue([editor.propertiesPlaceholder isHidden]);
    XCTAssertEqualObjects(props.nameField.stringValue, @"Panel");
    XCTAssertEqualObjects(props.typeField.stringValue, @"windowDef");
    for (NSView *control in @[props.nameField, props.visibleButton, props.backgroundField, props.textScaleField,
                              props.fontPopUp, editor.layoutXField]) {
        XCTAssertTrue([control.toolTip containsString:@" "], @"help on %@", control);
    }
    XCTAssertFalse(props.visibleButton.isEnabled, @"its visible is an expression");
    XCTAssertEqual(props.useBackColorButton.state, NSControlStateValueOn);
    NSColor *back = [props.backColorWell.color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    XCTAssertEqualWithAccuracy(back.blueComponent, 0.5, 0.001);
    XCTAssertFalse(props.backgroundField.isEnabled, @"no material: its controls off");

    [self chooseWindow:@"Lamp" in:editor];
    XCTAssertEqual(props.noTimeButton.state, NSControlStateValueOn);

    // the Text page: the text, quoted, one Item Properties edit
    [self chooseWindow:@"Label" in:editor];
    XCTAssertEqual(props.useTextButton.state, NSControlStateValueOn);
    XCTAssertEqualObjects(props.textField.stringValue, @"ready");
    props.textField.stringValue = @"steady";
    [props textChanged:props.textField];
    XCTAssertTrue([editor.designWorkspace.text containsString:@"text\t\"steady\""], @"%@", editor.designWorkspace.text);
    XCTAssertEqualObjects(editor.editorDocument.undoManager.undoActionName, @"Item Properties");
    XCTAssertEqualObjects(props.textField.stringValue, @"steady", @"shown as it is now");
    [editor.editorDocument.undoManager undo];
    XCTAssertEqualObjects(props.textField.stringValue, @"ready", @"and undone");

    // the Image page: a border, in the well's color
    [self chooseWindow:@"Go" in:editor];
    props.borderSizeField.stringValue = @"2";
    [props imageChanged:props.borderSizeField];
    XCTAssertTrue(props.borderColorWell.isEnabled, @"a border: its color");
    XCTAssertTrue([editor.designWorkspace.text containsString:@"bordersize\t2"], @"%@", editor.designWorkspace.text);
    XCTAssertTrue([editor.designWorkspace.text containsString:@"bordercolor\t0,0,0,1"], @"%@", editor.designWorkspace.text);
    XCTAssertTrue([editor.designWorkspace.text containsString:@"backcolor\t0.8, 0.2, 0.2, 1"], @"the back color as it was: %@", editor.designWorkspace.text);

    // the General page: not shown
    props.visibleButton.state = NSControlStateValueOff;
    [props generalChanged:props.visibleButton];
    XCTAssertTrue([editor.designWorkspace.text containsString:@"visible\t0"], @"%@", editor.designWorkspace.text);
}

- (void)testTheLayoutMovesAndSizesTheSelection {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    XCTAssertFalse([editor.layoutPlaceholder isHidden], @"nothing chosen");
    XCTAssertTrue([editor.layoutXField isHidden]);

    [self chooseWindow:@"Go" in:editor];
    XCTAssertTrue([editor.layoutPlaceholder isHidden]);
    XCTAssertEqualObjects(editor.layoutXField.stringValue, @"400");
    XCTAssertEqualObjects(editor.layoutYField.stringValue, @"300");
    XCTAssertEqualObjects(editor.layoutWField.stringValue, @"160");
    XCTAssertEqualObjects(editor.layoutHField.stringValue, @"60");

    editor.layoutXField.stringValue = @"420";
    [editor layoutChanged:editor.layoutXField];
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].x, 420, 0.5);
    XCTAssertEqualObjects(editor.editorDocument.undoManager.undoActionName, @"Transform Move");
    editor.layoutWField.stringValue = @"200";
    [editor layoutChanged:editor.layoutWField];
    XCTAssertEqualWithAccuracy([self designRectOf:@"Go" in:editor].w, 200, 0.5);
    XCTAssertEqualObjects(editor.editorDocument.undoManager.undoActionName, @"Transform Size");
    XCTAssertEqualObjects(editor.layoutXField.stringValue, @"420", @"the fields as the window is");
}

#pragma mark - Scripts

/// The Scripts' events table's row of @a key opened (a double-click).
- (void)openEvent:(NSString *)key in:(UDGuiEditorViewController *)editor {
    UDGuiScriptsController *scripts = editor.scriptsController;
    NSInteger row = -1;
    for (NSInteger i = 0; i < [scripts numberOfRowsInTableView:scripts.eventsTable]; i++) {
        if ([[scripts tableView:scripts.eventsTable objectValueForTableColumn:[scripts.eventsTable tableColumnWithIdentifier:@"event"] row:i] isEqual:key]) row = i;
    }
    XCTAssertGreaterThanOrEqual(row, 0, @"%@ in the events", key);
    [scripts.eventsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [scripts openEvent:nil];
}

- (void)chooseStatementAtRow:(NSInteger)row in:(UDGuiEditorViewController *)editor {
    [editor.scriptsController.statementsOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

- (NSString *)statementAtRow:(NSInteger)row in:(UDGuiEditorViewController *)editor {
    NSOutlineView *outline = editor.scriptsController.statementsOutline;
    return [outline.dataSource outlineView:outline objectValueForTableColumn:outline.tableColumns.firstObject byItem:[outline itemAtRow:row]];
}

- (void)add:(NSString *)command in:(UDGuiEditorViewController *)editor {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:command action:@selector(addStatement:) keyEquivalent:@""];
    item.representedObject = command;
    [editor.scriptsController addStatement:item];
}

- (void)testAWindowsScriptsAreEditedAsStatements {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    UDGuiScriptsController *scripts = editor.scriptsController;
    NSUndoManager *undo = editor.editorDocument.undoManager;
    XCTAssertEqualObjects(scripts.pages.selectedTabViewItem.identifier, @"none");

    // a window's: its events, and a row of each under it in the navigator
    [self chooseWindow:@"Go" in:editor];
    XCTAssertEqualObjects(scripts.pages.selectedTabViewItem.identifier, @"window");
    XCTAssertEqual([scripts numberOfRowsInTableView:scripts.eventsTable], 1);
    XCTAssertEqualObjects(scripts.eventKey, @"onAction", @"its first event's script, under its events");
    XCTAssertEqual(scripts.eventsTable.selectedRow, 0);
    XCTAssertEqual(scripts.statementsOutline.numberOfRows, 2);

    // an event's: its statements, one chosen, its parameters named
    [self openEvent:@"onAction" in:editor];
    XCTAssertEqualObjects(editor.selectedEvent.key, @"onAction");
    NSOutlineView *navigator = editor.windowsOutline;
    XCTAssertEqualObjects([self rowName:navigator.selectedRow of:navigator], @"\u0192 onAction", @"its row, under Go, chosen in the navigator");
    XCTAssertEqualObjects(scripts.pages.selectedTabViewItem.identifier, @"window", @"the events still there, the script under them");
    XCTAssertEqualObjects(scripts.eventPopUp.titleOfSelectedItem, @"onAction");
    XCTAssertEqual(scripts.statementsOutline.numberOfRows, 2);
    XCTAssertEqualObjects([self statementAtRow:1 in:editor], @"set \"cmd\" \"udtest_go\"");
    [self chooseStatementAtRow:1 in:editor];
    XCTAssertEqualObjects(scripts.parameterLabel1.stringValue, @"Variable:");
    XCTAssertEqualObjects(scripts.parameterField2.stringValue, @"udtest_go");
    XCTAssertTrue([scripts.parameterField1.toolTip containsString:@"gui::name"], @"%@", scripts.parameterField1.toolTip);
    scripts.parameterField2.stringValue = @"udtest_went";
    [scripts statementEdited:scripts.parameterField2];
    XCTAssertTrue([editor.designWorkspace.text containsString:@"set \"cmd\" \"udtest_went\""], @"%@", editor.designWorkspace.text);
    XCTAssertEqualObjects(undo.undoActionName, @"Statement Change");
    [undo undo];
    XCTAssertEqualObjects([self statementAtRow:1 in:editor], @"set \"cmd\" \"udtest_go\"", @"Undo shows it as it was");

    // added after the chosen one, filled in, moved first, taken off
    [self chooseStatementAtRow:1 in:editor];
    [self add:@"localSound" in:editor];
    XCTAssertEqual(scripts.statementsOutline.numberOfRows, 3);
    XCTAssertEqualObjects(undo.undoActionName, @"Add Statement");
    XCTAssertEqual(scripts.statementsOutline.selectedRow, 2, @"the new one chosen");
    scripts.parameterField1.stringValue = @"guisounds_click";
    [scripts statementEdited:scripts.parameterField1];
    XCTAssertTrue([editor.designWorkspace.text containsString:@"localSound \"guisounds_click\""], @"%@", editor.designWorkspace.text);
    XCTAssertTrue([scripts moveStatement:scripts.selectedStatement toParent:nil index:0]);
    XCTAssertEqualObjects([self statementAtRow:0 in:editor], @"localSound \"guisounds_click\"");
    XCTAssertEqualObjects(undo.undoActionName, @"Move Statement");

    // an if, a statement in it, its condition
    [scripts.statementsOutline deselectAll:nil];
    [self add:@"if" in:editor];
    XCTAssertEqualObjects([self statementAtRow:3 in:editor], @"if 1");
    scripts.conditionField.stringValue = @"\"gui::clicked\" == 1";
    [scripts statementEdited:scripts.conditionField];
    [self add:@"evalRegs" in:editor];
    XCTAssertEqual([editor.scriptsController.statementsOutline levelForRow:4], 1, @"in the if");
    XCTAssertTrue([editor.designWorkspace.text containsString:@"if \"gui::clicked\" == 1 {"], @"%@", editor.designWorkspace.text);
    [self chooseStatementAtRow:4 in:editor];
    [scripts removeStatement:nil];
    XCTAssertEqual(scripts.statementsOutline.numberOfRows, 4);

    // a new event: a time, then another time
    [self chooseWindow:@"Go" in:editor];
    NSMenuItem *time = [[NSMenuItem alloc] initWithTitle:@"onTime" action:@selector(addEvent:) keyEquivalent:@""];
    time.representedObject = @"onTime";
    [scripts addEvent:time];
    XCTAssertEqualObjects(editor.selectedEvent.key, @"onTime 0", @"opened");
    scripts.eventParameterField.stringValue = @"250";
    [scripts changeEvent:scripts.eventParameterField];
    XCTAssertEqualObjects(editor.selectedEvent.key, @"onTime 250");
    XCTAssertTrue([editor.designWorkspace.text containsString:@"onTime 250"], @"%@", editor.designWorkspace.text);

    // the events' rows choose the script shown, the navigator following
    XCTAssertEqual([scripts numberOfRowsInTableView:scripts.eventsTable], 2);
    [scripts.eventsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [scripts openEvent:nil];
    XCTAssertEqualObjects(scripts.eventKey, @"onAction");
    XCTAssertEqualObjects(scripts.eventPopUp.titleOfSelectedItem, @"onAction");
    XCTAssertEqualObjects(editor.selectedEvent.key, @"onAction");
    XCTAssertEqualObjects([self rowName:navigator.selectedRow of:navigator], @"\u0192 onAction");

    // a variable
    [self chooseWindow:@"Go" in:editor];
    NSSegmentedControl *plus = [[NSSegmentedControl alloc] init];
    plus.segmentCount = 2;
    plus.selectedSegment = 0;
    [scripts addOrRemoveVariable:plus];
    XCTAssertEqual([scripts numberOfRowsInTableView:scripts.variablesTable], 1);
    [scripts tableView:scripts.variablesTable setObjectValue:@"0.5" forTableColumn:[scripts.variablesTable tableColumnWithIdentifier:@"value"] row:0];
    XCTAssertTrue([editor.designWorkspace.text containsString:@"definefloat\t\"variable1\"\t0.5"], @"%@", editor.designWorkspace.text);
}

- (void)testAStatementsWindowsAndVariablesArePicked {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    UDGuiScriptsController *scripts = editor.scriptsController;
    [self chooseWindow:@"Go" in:editor];
    [self openEvent:@"onAction" in:editor];
    [self chooseStatementAtRow:1 in:editor];
    [self add:@"setFocus" in:editor];
    XCTAssertFalse([scripts.parameterPick1 isHidden], @"a window to pick");
    [self pick:1 action:@selector(pickParameter:) under:scripts.pages sheetOver:editor.view.window
          with:^(UDReferencePicker *picker) {
              XCTAssertTrue([picker.shownNames containsObject:@"Lamp"], @"the GUI's windows: %@", picker.shownNames);
              [self choose:@"Panel" in:picker];
          } picker:^UDReferencePicker *{ return scripts.referencePicker; }];
    XCTAssertEqualObjects([self statementAtRow:2 in:editor], @"setFocus \"Panel\"");

    [self chooseStatementAtRow:0 in:editor];
    __block NSArray<NSString *> *variables = nil;
    [self pick:1 action:@selector(pickParameter:) under:scripts.pages sheetOver:editor.view.window
          with:^(UDReferencePicker *picker) {
              variables = picker.shownNames;
              [picker cancel:nil];
          } picker:^UDReferencePicker *{ return scripts.referencePicker; }];
    XCTAssertTrue([variables containsObject:@"Label::text"], @"a window's variables: %@", variables);
    XCTAssertTrue([scripts.parameterPick2 isHidden], @"a value has no picker");
}

- (void)testAConditionIsEditedAsAnExpression {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openGuiIn:controller];
    UDGuiScriptsController *scripts = editor.scriptsController;
    [self chooseWindow:@"Go" in:editor];
    [self openEvent:@"onAction" in:editor];
    [scripts.statementsOutline deselectAll:nil];
    [self add:@"if" in:editor];
    [self click:@selector(editCondition:) tag:0 under:scripts.pages sheetOver:editor.view.window with:^(UDExpressionEditor *expression) {
        [expression setText:@"( 1"];
        XCTAssertTrue([expression.status containsString:@"')'"], @"idParser's: %@", expression.status);
        [expression setText:@""];
        [expression selectCategoryNamed:@"Variables"];
        XCTAssertTrue([expression insertEntryNamed:@"Label::visible"]);
        XCTAssertEqualObjects(expression.text, @"\"Label::visible\"");
        XCTAssertEqualObjects(expression.status, @"Reads as the engine reads it.");
        [expression ok:nil];
    }];
    XCTAssertTrue([editor.designWorkspace.text containsString:@"if \"Label::visible\" {"], @"%@", editor.designWorkspace.text);
}

#pragma mark - Commands

/// A key event of @a characters (and @a flags) sent to @a view.
- (void)key:(NSString *)characters flags:(NSEventModifierFlags)flags in:(UDGuiView *)view {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                                  windowNumber:view.window.windowNumber context:nil characters:characters
                   charactersIgnoringModifiers:characters isARepeat:NO keyCode:0];
    [view keyDown:event];
}

/// A navigator row's name: a window's, or an event's ("\u0192 onAction").
- (NSString *)rowName:(NSInteger)row of:(NSOutlineView *)outline {
    return [outline.dataSource outlineView:outline objectValueForTableColumn:[outline tableColumnWithIdentifier:@"name"] byItem:[outline itemAtRow:row]];
}

- (NSArray<NSString *> *)navigatorNamesIn:(UDGuiEditorViewController *)editor {
    NSOutlineView *outline = editor.windowsOutline;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSInteger i = 0; i < outline.numberOfRows; i++) {
        // the windows' rows (not their events')
        NSString *name = [self rowName:i of:outline];
        if (![name hasPrefix:@"\u0192 "]) [names addObject:name];
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

#pragma mark - The options (GEOptions, GEOptionsDlg)

- (BOOL)validate:(SEL)action in:(UDWorkspaceWindowController *)controller state:(NSControlStateValue *)state {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""];
    BOOL enabled = [controller validateMenuItem:item];
    if (state != NULL) *state = item.state;
    return enabled;
}

- (void)testTheGridCommandsAreKeptInTheWorkspace {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    rvGEOptions *options = editor.designWorkspace.options;
    NSControlStateValue state;
    XCTAssertTrue([self validate:@selector(toggleGrid:) in:controller state:&state], @"the View menu's, for the GUI's tab");
    XCTAssertEqual(state, NSControlStateValueOff, @"no grid at first");

    [NSApp sendAction:@selector(toggleGrid:) to:controller from:nil];
    XCTAssertTrue(options.gridVisible);
    [self validate:@selector(toggleGrid:) in:controller state:&state];
    XCTAssertEqual(state, NSControlStateValueOn, @"checked");
    [NSApp sendAction:@selector(toggleGridSnap:) to:controller from:nil];
    XCTAssertTrue(options.gridSnap);

    XCTAssertEqualObjects([editor.workspace settingsForTool:@"GUIEditor"][@"gridVisible"], @YES, @"saved in the workspace");
    XCTAssertEqualObjects([editor.workspace settingsForTool:@"GUIEditor"][@"gridSnap"], @YES);
    XCTAssertTrue([controller.document isDocumentEdited], @"which is saved with it");

    // set elsewhere (another GUI's tab): this one's follow
    NSMutableDictionary *registry = [options.registry mutableCopy];
    registry[@"gridWidth"] = @25;
    registry[@"gridVisible"] = @NO;
    [editor.workspace setSettings:registry forTool:@"GUIEditor"];
    XCTAssertEqual(options.gridWidth, 25);
    XCTAssertFalse(options.gridVisible);
}

- (void)testTheOptionsSheetSetsTheOptions {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    rvGEOptions *options = editor.designWorkspace.options;
    XCTAssertTrue([self validate:@selector(showGuiEditorOptions:) in:controller state:NULL]);

    __block BOOL shown = NO;
    void (^fill)(NSWindow *) = ^(NSWindow *sheet) {
        shown = YES;
        UDGuiEditorOptionsController *sheetController = sheet.windowController;
        XCTAssertEqualObjects(sheetController.gridWidthField.stringValue, @"10", @"the options' own");
        [self selectTabLabeled:@"Grid" inView:sheet.contentView];
        [self typeText:@"32" intoField:sheetController.gridWidthField];
        [[self buttonTitled:@"Show the grid" inView:sheet.contentView] performClick:nil];
        [[self buttonTitled:@"OK" inView:sheet.contentView] performClick:nil];
    };
#ifdef GNUSTEP
    // a sheet is a modal window there, run by -beginSheet:…
    [self whenModalWindowAppears:fill];
    [NSApp sendAction:@selector(showGuiEditorOptions:) to:controller from:nil];
#else
    [NSApp sendAction:@selector(showGuiEditorOptions:) to:controller from:nil];
    NSWindow *sheet = controller.window.attachedSheet;
    XCTAssertNotNil(sheet, @"a sheet over the workspace's window");
    if (sheet != nil) fill(sheet);
    [self spinUntil:^BOOL{ return controller.window.attachedSheet == nil; } timeout:5];
#endif
    XCTAssertTrue(shown);
    XCTAssertEqual(options.gridWidth, 32);
    XCTAssertTrue(options.gridVisible);
    XCTAssertEqual(options.lastOptionsPage, 1, @"the page shown kept");
    XCTAssertEqualObjects([editor.workspace settingsForTool:@"GUIEditor"][@"gridWidth"], @32, @"saved in the workspace");
}

#pragma mark - Zoom and the status bar (GEWorkspace, GEStatusBar)

- (void)testTheZoomGoesByTheEnginesLevels {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    UDGuiView *view = editor.guiView;
    view.frameSize = NSMakeSize(800, 500);
    XCTAssertEqual(view.zoom, UDGuiZoomFit, @"fitted as it opens");
    XCTAssertEqualWithAccuracy(view.scale, 500.0 / 480.0, 0.001);

    [NSApp sendAction:@selector(zoomIn:) to:controller from:nil];
    XCTAssertEqual(view.zoom, 6, @"from fitted (104%), the next level up: 150%");
    XCTAssertEqual(view.zoomPercent, 150);
    XCTAssertTrue([editor.statusField.stringValue hasSuffix:@"Zoom: 150%"], @"%@", editor.statusField.stringValue);
    XCTAssertEqualWithAccuracy(NSWidth(view.guiRect), 960, 0.5);
    XCTAssertEqualWithAccuracy(editor.designWorkspace.rect.w, 960, 0.5, @"the design where the GUI is drawn");

    // larger than the view: the wheel scrolls it, as far as its edges
    view.scrollOffset = NSMakePoint(1000, 1000);
    XCTAssertEqualWithAccuracy(view.scrollOffset.x, (960 - 800) / 2.0, 0.5);
    XCTAssertEqualWithAccuracy(view.scrollOffset.y, (720 - 500) / 2.0, 0.5);
    XCTAssertEqualWithAccuracy(NSMaxX(view.guiRect), 800, 1, @"its right edge at the view's");

    [NSApp sendAction:@selector(zoomIn:) to:controller from:nil];
    [NSApp sendAction:@selector(zoomIn:) to:controller from:nil];
    [NSApp sendAction:@selector(zoomIn:) to:controller from:nil];
    XCTAssertEqual(view.zoomPercent, 300, @"ZoomIn stops at the last level");
    XCTAssertEqual(view.scrollOffset.x, 0, @"centered again");
    for (int i = 0; i < 10; i++) [NSApp sendAction:@selector(zoomOut:) to:controller from:nil];
    XCTAssertEqual(view.zoomPercent, 25, @"ZoomOut stops at 25%");
    XCTAssertEqual(view.scrollOffset.y, 0, @"smaller than the view: nothing to scroll");
    [NSApp sendAction:@selector(zoomToFit:) to:controller from:nil];
    XCTAssertEqual(view.zoom, UDGuiZoomFit);
    [NSApp sendAction:@selector(zoomOut:) to:controller from:nil];
    XCTAssertEqual(view.zoomPercent, 100, @"from fitted (104%), the next level down");
}

- (void)testTheStatusBarIsShownAsTheOptionsHaveIt {
    UDWorkspaceWindowController *controller = [self openFixture];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openDesignIn:controller];
    NSTextField *status = editor.statusField;
    XCTAssertFalse(status.isHidden, @"shown by default");
    XCTAssertTrue([status.stringValue hasPrefix:@"Tris: "], @"%@", status.stringValue);
    XCTAssertGreaterThan([[status.stringValue substringFromIndex:6] intValue], 0, @"the triangles drawn: %@", status.stringValue);
    NSRect canvas = editor.guiView.frame;

    NSControlStateValue state;
    XCTAssertTrue([self validate:@selector(toggleStatusBar:) in:controller state:&state]);
    XCTAssertEqual(state, NSControlStateValueOn);
    [NSApp sendAction:@selector(toggleStatusBar:) to:controller from:nil];
    XCTAssertTrue(status.isHidden);
    XCTAssertGreaterThan(NSHeight(editor.guiView.frame), NSHeight(canvas), @"the canvas takes its place");
    XCTAssertEqualObjects([editor.workspace settingsForTool:@"GUIEditor"][@"statusBarVisible"], @NO, @"kept in the options");
    [NSApp sendAction:@selector(toggleStatusBar:) to:controller from:nil];
    XCTAssertFalse(status.isHidden);
    XCTAssertEqual(NSHeight(editor.guiView.frame), NSHeight(canvas));
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
