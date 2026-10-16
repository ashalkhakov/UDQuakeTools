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
#import <UDCodeKit/UDDiagnosticStore.h>

// An original GUI: a panel the state hides, a label a named event renames,
// a button whose action sets the state and returns a command.
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
    XCTAssertEqual(controller.inspectorTabBar.tabBarItems.count, 2u, @"a GUI has its state and its log");
    XCTAssertTrue([controller.inspectorPlaceholder isHidden]);
    XCTAssertEqual(editor.stateView.superview, controller.inspectorHost, @"the state is shown first");

    controller.inspectorTabBar.selectedIndex = 1;
    [NSApp sendAction:@selector(inspectorTabChanged:) to:controller from:controller.inspectorTabBar];
    XCTAssertEqual(editor.logView.superview, controller.inspectorHost, @"the log, when it is chosen");
    XCTAssertNil(editor.stateView.superview);
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
