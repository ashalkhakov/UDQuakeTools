#import <XCTest/XCTest.h>
#import "rvGEWorkspace.h"
#import "rvGEWindowWrapper.h"
#import "rvGESelectionMgr.h"
#import "rvGEModifier.h"
#import "rvGEOptions.h"
#import "UDOverlay.h"
#import "idUserInterface.h"
#import "idWindow.h"
#import "idDict.h"
#import "idWinVar.h"

// An original GUI: a panel with a button in it, a label, and a window whose
// rect is an expression.
static NSString *const UDCanvasGui =
    @"windowDef Desktop {\n"
     "\trect\t0, 0, 640, 480\n"
     "\twindowDef Panel {\n"
     "\t\trect\t100, 100, 200, 100\n"
     "\t\twindowDef Button {\n"
     "\t\t\trect\t10, 10, 50, 20\n"
     "\t\t\tfloat\tspeed\t2\n"
     "\t\t\tonAction {\n"
     "\t\t\t\tset \"gui::clicked\" \"1\" ;\n"
     "\t\t\t}\n"
     "\t\t}\n"
     "\t}\n"
     "\twindowDef Label {\n"
     "\t\trect\t400, 50, 100, 30\n"
     "\t\ttext\t\"ready\"\n"
     "\t}\n"
     "\twindowDef Moving {\n"
     "\t\trect\t\"gui::x\", 300, 50, 50\n"
     "\t}\n"
     "}\n";

@interface rvGEWorkspaceTests : XCTestCase
@property (nonatomic, strong) idUserInterfaceManager *manager;
@property (nonatomic, strong) rvGEWorkspace *workspace;
@end

@implementation rvGEWorkspaceTests

- (void)setUp {
    [super setUp];
    self.manager = [[idUserInterfaceManager alloc] initWithFileSystem:nil declManager:nil];
    [self.manager managerInit];
    self.workspace = [[rvGEWorkspace alloc] initWithManager:self.manager];
    XCTAssertTrue([self.workspace loadText:UDCanvasGui path:@"guis/canvas.gui"]);
    // the GUI at its own size in the window: a pixel a unit
    self.workspace.rect = idRectangle_Make(0, 0, 640, 480);
}

- (idWindow *)window:(NSString *)name {
    idDrawWin *dw = [[self.workspace.interface getDesktop] findChildByName:name];
    XCTAssertNotNil(dw.win, @"%@ is a window of its own while editing", name);
    return dw.win;
}

- (idRectangle)rectOf:(NSString *)name {
    return [rvGEWindowWrapper wrapperOf:[self window:name]].clientRect;
}

/// A drag from ( @a x0, @a y0 ) to ( @a x1, @a y1 ), as the mouse does it.
- (void)dragFromX:(float)x0 y:(float)y0 toX:(float)x1 y:(float)y1 shift:(BOOL)shift {
    [self.workspace mouseDownAtX:x0 y:y0 shift:shift time:0];
    // in steps, as a mouse moves, after the engine's 50 ms
    for (int i = 1; i <= 4; i++) {
        [self.workspace mouseMoveToX:x0 + (x1 - x0) * i / 4 y:y0 + (y1 - y0) * i / 4 time:100 + i];
    }
    [self.workspace mouseUp];
}

- (void)testEveryWindowIsWrappedWhileEditing {
    for (NSString *name in @[@"Panel", @"Button", @"Label", @"Moving"]) {
        XCTAssertNotNil([rvGEWindowWrapper wrapperOf:[self window:name]], @"%@", name);
    }
    rvGEWindowWrapper *button = [rvGEWindowWrapper wrapperOf:[self window:@"Button"]];
    XCTAssertEqual(button.screenRect.x, 110, @"its rect on the screen is its parent's plus its own");
    XCTAssertEqual(button.screenRect.y, 110);
    XCTAssertTrue([button canMoveAndSize]);
    XCTAssertFalse([[rvGEWindowWrapper wrapperOf:[self window:@"Moving"]] canMoveAndSize], @"an expression for a rect");
}

- (void)testAClickSelectsTheTopmostWindowNotTheDesktop {
    [self.workspace mouseDownAtX:115 y:115 shift:NO time:0];
    [self.workspace mouseUp];
    XCTAssertEqual([self.workspace.selections num], 1);
    XCTAssertEqual(self.workspace.selections[0], [self window:@"Button"], @"the child over its parent");

    [self.workspace mouseDownAtX:600 y:450 shift:NO time:1000];
    [self.workspace mouseUp];
    XCTAssertEqual([self.workspace.selections num], 0, @"the desktop is not selected (ignoreDesktopSelect)");
}

- (void)testADragMovesTheSelectionAsOneEdit {
    [self dragFromX:420 y:60 toX:460 y:80 shift:NO];
    idRectangle rect = [self rectOf:@"Label"];
    XCTAssertEqual(rect.x, 440);
    XCTAssertEqual(rect.y, 70);
    XCTAssertTrue(self.workspace.modified);
    XCTAssertTrue([self.workspace.text containsString:@"rect\t440,70,100,30"], @"%@", self.workspace.text);

    XCTAssertTrue([self.workspace.modifiers undo], @"the drag's moves are one edit");
    rect = [self rectOf:@"Label"];
    XCTAssertEqual(rect.x, 400);
    XCTAssertEqual(rect.y, 50);
    XCTAssertFalse([self.workspace.modifiers canUndo]);
    [self.workspace.modifiers redo];
    XCTAssertEqual([self rectOf:@"Label"].x, 440);
}

- (void)testAHandleSizesTheSelection {
    [self.workspace mouseDownAtX:420 y:60 shift:NO time:0];
    [self.workspace mouseUp];
    // the bottom right handle is just outside the label's corner
    XCTAssertEqual([self.workspace.selections hitTestX:502 y:82], HT_SIZE_BOTTOMRIGHT);
    XCTAssertEqual([self.workspace.selections hitTestX:450 y:65], HT_MOVE);
    [self dragFromX:502 y:82 toX:522 y:92 shift:NO];
    idRectangle rect = [self rectOf:@"Label"];
    XCTAssertEqual(rect.x, 400, @"sizing from the bottom right keeps the top left");
    XCTAssertEqual(rect.w, 120);
    XCTAssertEqual(rect.h, 40);
}

- (void)testShiftAddsToTheSelectionAndTheyMoveTogether {
    [self.workspace mouseDownAtX:420 y:60 shift:NO time:0];
    [self.workspace mouseUp];
    [self.workspace mouseDownAtX:250 y:150 shift:YES time:1000];
    [self.workspace mouseUp];
    XCTAssertEqual([self.workspace.selections num], 2);
    idRectangle around = [self.workspace.selections rect];
    XCTAssertEqual(around.x, 100, @"the rect around both");
    XCTAssertEqual(around.y, 50);
    XCTAssertEqual(around.w, 400);
    XCTAssertEqual(around.h, 150);
    [self dragFromX:420 y:60 toX:430 y:60 shift:NO];
    XCTAssertEqual([self rectOf:@"Label"].x, 410);
    XCTAssertEqual([self rectOf:@"Panel"].x, 110);
}

- (void)testAWindowWhoseRectIsAnExpressionDoesNotMove {
    [self dragFromX:30 y:320 toX:60 y:330 shift:NO];
    XCTAssertEqual([self.workspace.selections num], 1, @"it is selected");
    XCTAssertTrue([self.workspace.selections isExpression]);
    XCTAssertFalse([self.workspace.modifiers canUndo], @"and not moved");
}

- (void)testTheGridSnaps {
    self.workspace.options.gridSnap = YES;
    [self dragFromX:420 y:60 toX:433 y:64 shift:NO];
    idRectangle rect = [self rectOf:@"Label"];
    XCTAssertEqual((int)rect.x % 10, 0, @"%g", rect.x);
    XCTAssertEqual((int)rect.y % 10, 0, @"%g", rect.y);
}

- (void)testTheEditsAreTheUndoManagers {
    NSUndoManager *undoManager = [[NSUndoManager alloc] init];
    undoManager.groupsByEvent = NO;
    self.workspace.modifiers.undoManager = undoManager;
    [undoManager beginUndoGrouping];
    [self dragFromX:420 y:60 toX:460 y:80 shift:NO];
    [undoManager endUndoGrouping];
    XCTAssertTrue(undoManager.canUndo);
    XCTAssertEqualObjects(undoManager.undoActionName, @"Move");
    [undoManager undo];
    XCTAssertEqual([self rectOf:@"Label"].x, 400);
    XCTAssertTrue(undoManager.canRedo);
    [undoManager redo];
    XCTAssertEqual([self rectOf:@"Label"].x, 440);
}

- (void)testTheSelectionIsDrawn {
    [self.workspace mouseDownAtX:420 y:60 shift:NO time:0];
    [self.workspace mouseUp];
    UDOverlay *overlay = [[UDOverlay alloc] init];
    [self.workspace renderOverlayInto:overlay];
    // the rect around (4 lines), the window's (4), eight handles (4 each)
    XCTAssertEqual(overlay.lineVertexCount, (4 + 4 + 8 * 4) * 2u);
    // the first's corner mark (1) and its centre (2)
    XCTAssertEqual(overlay.triangleVertexCount, 3 * 3u);
}

#pragma mark - Properties

- (void)selectLabel {
    [self.workspace mouseDownAtX:420 y:60 shift:NO time:0];
    [self.workspace mouseUp];
}

- (NSString *)property:(NSString *)name {
    for (NSArray<NSString *> *row in self.workspace.properties) {
        if ([row[0] isEqualToString:name]) return row[1];
    }
    return nil;
}

- (void)testTheSelectedWindowsPropertiesAreItsState {
    XCTAssertNil(self.workspace.properties, @"none, with no window selected");
    [self selectLabel];
    XCTAssertEqualObjects([self property:@"rect"], @"400, 50, 100, 30");
    XCTAssertEqualObjects([self property:@"text"], @"ready", @"without its quotes");
    XCTAssertEqualObjects([self property:@"name"], @"Label");
}

- (void)testAPropertyIsSetAsTheWindowReadsIt {
    [self selectLabel];
    XCTAssertTrue([self.workspace setProperty:@"text" value:@"hello there"], @"quoted, as a string must be");
    XCTAssertEqualObjects([[self window:@"Label"] getWinVarByName:@"text"].string, @"hello there");
    XCTAssertTrue([self.workspace.text containsString:@"text\t\"hello there\""], @"%@", self.workspace.text);
    XCTAssertTrue([self.workspace setProperty:@"rect" value:@"10, 20, 30, 40"]);
    XCTAssertEqual([self rectOf:@"Label"].x, 10, @"the rect read again");
    XCTAssertEqual([self rectOf:@"Label"].w, 30);

    XCTAssertFalse([self.workspace setProperty:@"rect" value:@"1, 2, 3, 4 five"], @"what the window does not read all of is no value");
    XCTAssertEqualObjects([self property:@"rect"], @"10, 20, 30, 40", @"and changes nothing");

    [self.workspace.modifiers undo];
    XCTAssertEqual([self rectOf:@"Label"].x, 400, @"a Property Change is undone");
    [self.workspace.modifiers undo];
    XCTAssertEqualObjects([[self window:@"Label"] getWinVarByName:@"text"].string, @"ready");
}

#pragma mark - Scripts

- (void)testAWindowsScriptsAreItsVariablesAndScripts {
    NSString *text = [self.workspace scriptsTextOf:[self window:@"Button"]];
    XCTAssertTrue([text hasPrefix:@"float\t\"speed\"\t2\n\n"], @"%@", text);
    XCTAssertTrue([text containsString:@"onAction\n{"], @"%@", text);
    XCTAssertTrue([text containsString:@"set \"gui::clicked\" \"1\" ;"], @"%@", text);
}

- (void)testScriptsAreAppliedAsOneEdit {
    idWindow *button = [self window:@"Button"];
    NSString *text = @"float\t\"speed\"\t3\n\n"
                      "onAction\n{\n\tset \"gui::clicked\" \"2\" ;\n}\n\n"
                      "onNamedEvent flash\n{\n\tset \"gui::flash\" \"1\" ;\n}\n";
    NSString *message = nil;
    XCTAssertTrue([self.workspace setScriptsText:text of:button message:&message], @"%@", message);
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:button];
    XCTAssertEqualObjects([wrapper.variableDict getString:@"float\t\"speed\""], @"3");
    XCTAssertNotNil([wrapper.scriptDict getString:@"onNamedEvent flash" defaultString:nil]);
    XCTAssertTrue([self.workspace.text containsString:@"onNamedEvent flash"], @"written with the GUI");

    [self.workspace.modifiers undo];
    XCTAssertEqualObjects([wrapper.variableDict getString:@"float\t\"speed\""], @"2", @"a Scripts Change is undone");
    XCTAssertNil([wrapper.scriptDict getString:@"onNamedEvent flash" defaultString:nil]);
}

- (void)testScriptsThatAreNotScriptsAreRefused {
    NSString *message = nil;
    XCTAssertFalse([self.workspace setScriptsText:@"onBogus\n{\n}\n" of:[self window:@"Button"] message:&message]);
    XCTAssertTrue([message containsString:@"expected script name"], @"%@", message);
    XCTAssertFalse([self.workspace.modifiers canUndo], @"and nothing is changed");
}

@end
