#import <XCTest/XCTest.h>
#import "rvGEWorkspace.h"
#import "rvGEWindowWrapper.h"
#import "rvGESelectionMgr.h"
#import "rvGEModifier.h"
#import "rvGEOptions.h"
#import "rvGETransformer.h"
#import "rvGEScript.h"
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

- (void)testAClickPassesThroughThePassedWindowsAndOptionReachesBelow {
    // ⌥: the next window down at the point, round again after the last
    [self.workspace mouseDownAtX:115 y:115 shift:NO time:0];
    [self.workspace mouseUp];
    XCTAssertEqual(self.workspace.selections[0], [self window:@"Button"]);
    [self.workspace mouseDownAtX:115 y:115 shift:NO below:YES time:1000];
    [self.workspace mouseUp];
    XCTAssertEqual(self.workspace.selections[0], [self window:@"Panel"], @"the one below");
    [self.workspace mouseDownAtX:115 y:115 shift:NO below:YES time:2000];
    [self.workspace mouseUp];
    XCTAssertEqual(self.workspace.selections[0], [self window:@"Button"], @"the topmost again");
    XCTAssertEqualObjects([self.workspace windowsAtX:115 y:115], (@[[self window:@"Button"], [self window:@"Panel"]]));

    // a passed window, and its children, are not chosen
    self.workspace.passedWindows = [NSSet setWithObject:[self window:@"Panel"]];
    [self.workspace mouseDownAtX:115 y:115 shift:NO time:3000];
    [self.workspace mouseUp];
    XCTAssertEqual([self.workspace.selections num], 0, @"passed through to the desktop");
    XCTAssertEqual([self.workspace windowsUnderX:115 y:115].count, 1u, @"the Select menu has the desktop alone");
    XCTAssertEqual([self.workspace windowsAtX:115 y:115].count, 0u);
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

#pragma mark - Commands

/// The desktop's windows' names, in their order (back to front).
- (NSArray<NSString *> *)desktopOrder {
    idWindow *desktop = [self.workspace.interface getDesktop];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (int i = 0; i < [desktop getChildCount]; i++) {
        rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:[desktop getChild:i]];
        if (!wrapper.deleted) [names addObject:[[desktop getChild:i] getName]];
    }
    return names;
}

- (void)select:(NSArray<NSString *> *)names {
    [self.workspace.selections clear];
    for (NSString *name in names) [self.workspace.selections add:[self window:name]];
}

- (void)testANewWindowIsAddedAndUndone {
    idWindow *window = [self.workspace addWindow:WT_NORMAL];
    XCTAssertEqualObjects([window getName], @"unnamed");
    XCTAssertEqualObjects(self.desktopOrder.lastObject, @"unnamed", @"on the desktop, at the front");
    XCTAssertEqual(self.workspace.selections[0], window, @"and selected");
    XCTAssertTrue([self.workspace.text containsString:@"windowDef unnamed"]);
    idWindow *second = [self.workspace addWindow:WT_EDIT];
    XCTAssertEqualObjects([second getName], @"unnamed1", @"named apart from the first");
    XCTAssertTrue([self.workspace.text containsString:@"editDef unnamed1"]);
    [self.workspace.modifiers undo];
    [self.workspace.modifiers undo];
    XCTAssertFalse([self.desktopOrder containsObject:@"unnamed"]);
}

- (void)testDeletingTakesTheWindowOutOfTheFile {
    [self select:@[@"Label"]];
    [self.workspace deleteSelected];
    XCTAssertFalse([self.workspace.text containsString:@"windowDef Label"]);
    XCTAssertEqual([self.workspace.selections num], 0);
    [self.workspace.modifiers undo];
    XCTAssertTrue([self.workspace.text containsString:@"windowDef Label"]);
}

- (void)testTheOrderIsArranged {
    XCTAssertEqualObjects(self.desktopOrder, (@[@"Panel", @"Label", @"Moving"]));
    [self select:@[@"Panel"]];
    [self.workspace bringSelectedToFront];
    XCTAssertEqualObjects(self.desktopOrder, (@[@"Label", @"Moving", @"Panel"]));
    [self.workspace sendSelectedBackward];
    XCTAssertEqualObjects(self.desktopOrder, (@[@"Label", @"Panel", @"Moving"]));
    [self.workspace sendSelectedToBack];
    XCTAssertEqualObjects(self.desktopOrder, (@[@"Panel", @"Label", @"Moving"]));
    [self.workspace bringSelectedForward];
    XCTAssertEqualObjects(self.desktopOrder, (@[@"Label", @"Panel", @"Moving"]));
    [self.workspace.modifiers undo];
    XCTAssertEqualObjects(self.desktopOrder, (@[@"Panel", @"Label", @"Moving"]));
}

- (void)testAligningAndSizingFollowTheFirstSelected {
    [self select:@[@"Panel", @"Label"]];
    [self.workspace alignSelected:ALIGN_LEFTS];
    XCTAssertEqual([self rectOf:@"Label"].x, 100);
    [self.workspace alignSelected:ALIGN_BOTTOMS];
    XCTAssertEqual([self rectOf:@"Label"].y + [self rectOf:@"Label"].h, 200);
    [self.workspace makeSelectedSameSizeWidth:YES height:NO];
    XCTAssertEqual([self rectOf:@"Label"].w, 200);
    XCTAssertEqual([self rectOf:@"Label"].h, 30, @"its height as it was");
}

- (void)testMakeChildKeepsItWhereItIs {
    [self select:@[@"Panel", @"Label"]];
    XCTAssertTrue([self.workspace makeSelectedAChild]);
    idWindow *label = [self window:@"Label"];
    XCTAssertEqual([label getParent], [self window:@"Panel"]);
    XCTAssertEqual([rvGEWindowWrapper wrapperOf:label].screenRect.x, 400, @"where it was on the screen");
    XCTAssertEqual([self rectOf:@"Label"].x, 300, @"its rect now the panel's");
    [self.workspace.modifiers undo];
    XCTAssertEqual([label getParent], [self.workspace.interface getDesktop]);
    XCTAssertEqual([self rectOf:@"Label"].x, 400);
}

- (void)testCopiedWindowsArePastedAsNew {
    [self select:@[@"Button"]];
    [self.workspace copySelected];
    XCTAssertTrue([self.workspace canPaste]);
    [self.workspace paste];
    XCTAssertTrue([self.desktopOrder containsObject:@"Button1"], @"%@", self.desktopOrder);
    idWindow *pasted = self.workspace.selections[0];
    XCTAssertEqualObjects([pasted getName], @"Button1");
    XCTAssertNotNil([[rvGEWindowWrapper wrapperOf:pasted].scriptDict getString:@"onAction" defaultString:nil], @"its scripts with it");
    XCTAssertTrue([self.workspace.text containsString:@"windowDef Button1"]);
}

- (void)testTheArrowsNudge {
    [self select:@[@"Label"]];
    [self.workspace nudgeX:1 y:0 size:NO];
    [self.workspace nudgeX:0 y:-1 size:NO];
    XCTAssertEqual([self rectOf:@"Label"].x, 401);
    XCTAssertEqual([self rectOf:@"Label"].y, 49);
    [self.workspace nudgeX:2 y:0 size:YES];
    XCTAssertEqual([self rectOf:@"Label"].w, 102);
}

- (void)testTheWindowsUnderAPointAreOffered {
    NSArray<idWindow *> *under = [self.workspace windowsUnderX:115 y:115];
    NSArray *names = [under valueForKey:@"getName"];
    XCTAssertEqualObjects(names, (@[@"Button", @"Panel", @"Desktop"]), @"the child first, the desktop last");
}

#pragma mark - The options (GEOptions)

- (void)testTheOptionsAreKeptAsTheEnginesRegistry {
    rvGEOptions *options = [[rvGEOptions alloc] init];
    XCTAssertFalse(options.gridVisible, @"rvGEOptions::Init's defaults");
    XCTAssertEqual(options.gridWidth, 10);
    XCTAssertTrue(options.statusBarVisible);
    XCTAssertTrue(options.ignoreDesktopSelect);

    options.gridVisible = YES;
    options.gridSnap = YES;
    options.gridWidth = 16;
    options.gridHeight = 8;
    options.gridColor = idVec4_Make(1, 0.5f, 0.25f, 0.5f);
    options.selectionColor = idVec4_Make(0, 1, 0, 1);
    options.ignoreDesktopSelect = NO;
    options.statusBarVisible = NO;
    options.lastOptionsPage = 1;
    NSDictionary *registry = options.registry;
    XCTAssertEqualObjects(registry[@"gridWidth"], @16, @"the engine's registry keys");
    XCTAssertEqualObjects(registry[@"gridColor"], (@[@1, @0.5, @0.25, @1]), @"the grid's color saved opaque");

    rvGEOptions *loaded = [[rvGEOptions alloc] init];
    [loaded loadRegistry:registry];
    XCTAssertTrue(loaded.gridVisible);
    XCTAssertTrue(loaded.gridSnap);
    XCTAssertEqual(loaded.gridWidth, 16);
    XCTAssertEqual(loaded.gridHeight, 8);
    XCTAssertEqual(loaded.gridColor.y, 0.5f);
    XCTAssertEqual(loaded.gridColor.w, 1.0f);
    XCTAssertEqual(loaded.selectionColor.y, 1.0f);
    XCTAssertFalse(loaded.ignoreDesktopSelect);
    XCTAssertFalse(loaded.statusBarVisible);
    XCTAssertEqual(loaded.lastOptionsPage, 1);

    // what the registry lacks keeps its default
    rvGEOptions *partial = [[rvGEOptions alloc] init];
    [partial loadRegistry:@{ @"gridSnap": @YES, @"gridColor": @"not a color" }];
    XCTAssertTrue(partial.gridSnap);
    XCTAssertEqual(partial.gridWidth, 10);
    XCTAssertEqual(partial.gridColor.x, 0.2f);
    [partial loadRegistry:nil];
    XCTAssertTrue(partial.gridSnap);
}

#pragma mark - The transformer (GETransformer) and the item properties

- (void)testTheTransformerIsFromTheParentOfTheBottomMostSelected {
    rvGETransformer *transformer = [[rvGETransformer alloc] initWithWorkspace:self.workspace];
    idRectangle rect;
    XCTAssertFalse([transformer update:&rect], @"nothing selected: nothing to transform");

    [self.workspace.selections set:[self window:@"Button"]];
    XCTAssertTrue([transformer update:&rect]);
    XCTAssertEqual(rect.x, 10, @"from the panel it is in");
    XCTAssertEqual(rect.y, 10);
    XCTAssertEqual(rect.w, 50);
    XCTAssertEqual(rect.h, 20);

    [transformer setField:rvGETransformerX value:30];
    XCTAssertEqual([self rectOf:@"Button"].x, 30, @"moved by the difference");
    XCTAssertEqualObjects(self.workspace.modifiers.undoModifier.name, @"Transform Move");
    [transformer setField:rvGETransformerH value:25];
    XCTAssertEqual([self rectOf:@"Button"].h, 25, @"sized by it");
    XCTAssertEqualObjects(self.workspace.modifiers.undoModifier.name, @"Transform Size");
    rvGEModifier *last = self.workspace.modifiers.undoModifier;
    [transformer setField:rvGETransformerW value:50];
    XCTAssertEqual(self.workspace.modifiers.undoModifier, last, @"the same number is no edit");
}

- (void)testItemPropertiesAreOneEditOfTheSelectedWindow {
    XCTAssertFalse([self.workspace applyItemProperties:[[idDict alloc] init]], @"no window selected");
    idWindow *label = [self window:@"Label"];
    [self.workspace.selections set:label];
    idDict *dict = [[rvGEWindowWrapper wrapperOf:label].stateDict copy];
    [dict set:@"text" value:@"\"steady\""];
    [dict set:@"forecolor" value:rvGE_StringFromVec4(idVec4_Make(1, 0.5f, 0, 1))];
    XCTAssertTrue([self.workspace applyItemProperties:dict]);
    XCTAssertEqualObjects(self.workspace.modifiers.undoModifier.name, @"Item Properties");
    XCTAssertEqualObjects([[rvGEWindowWrapper wrapperOf:label].stateDict getString:@"forecolor"], @"1,0.5,0,1",
                          @"StringFromVec4: no trailing zeros");
    XCTAssertTrue([self.workspace.text containsString:@"\"steady\""], @"%@", self.workspace.text);
    [self.workspace.modifiers undo];
    XCTAssertTrue([self.workspace.text containsString:@"\"ready\""], @"undone");
}

#pragma mark - Scripts as statements

- (void)testAScriptIsReadAsItsStatements {
    NSString *text = @"{\n\tset \"gui::clicked\" \"1\" ;\n\ttransition \"Panel::rect\" \"0 0 10 10\" \"0 0 20 20\" \"500\" ;\n"
                      "\tif ( \"gui::x\" == 1 ) {\n\t\tresetTime \"Panel\" \"0\" ;\n\t} else if \"gui::y\" {\n\t\tshowCursor 0 ;\n\t}\n\tendGame ;\n}";
    NSString *message = nil;
    NSArray<rvGEScriptStatement *> *statements = [rvGEScript statementsFromText:text message:&message];
    XCTAssertNotNil(statements, @"%@", message);
    XCTAssertEqual(statements.count, 4U);
    XCTAssertEqualObjects(statements[0].command, @"set");
    XCTAssertEqualObjects(statements[0].arguments, (@[@"gui::clicked", @"1"]), @"its parameters, no quotes");
    XCTAssertEqualObjects(statements[1].arguments[3], @"500");
    rvGEScriptStatement *test = statements[2];
    XCTAssertTrue(test.isIf);
    XCTAssertEqualObjects(test.condition, @"( \"gui::x\" == 1 )");
    XCTAssertEqualObjects(test.statements[0].command, @"resetTime");
    XCTAssertEqual(test.elseStatements.count, 1U, @"else if: an if alone in the else block");
    XCTAssertEqualObjects(test.elseStatements[0].condition, @"\"gui::y\"");
    XCTAssertEqualObjects(test.elseStatements[0].statements[0].arguments, (@[@"0"]));
    XCTAssertEqualObjects(statements[3].command, @"endGame");
    XCTAssertEqualObjects(statements[0].summary, @"set \"gui::clicked\" \"1\"");

    // written back, it reads the same
    NSString *written = [rvGEScript textFromStatements:statements];
    XCTAssertTrue([written hasPrefix:@"{\n\tset \"gui::clicked\" \"1\" ;\n"], @"%@", written);
    NSArray<rvGEScriptStatement *> *again = [rvGEScript statementsFromText:written message:NULL];
    XCTAssertEqualObjects([rvGEScript textFromStatements:again], written);

    XCTAssertNil([rvGEScript statementsFromText:@"{ frobnicate 1 ; }" message:&message]);
    XCTAssertEqualObjects(message, @"Unknown script call frobnicate", @"idGuiScript::Parse's words");
    XCTAssertEqualObjects([rvGEScript parameterNamesOf:@"transition"], (@[@"Variable", @"From", @"To", @"Time", @"Accel", @"Decel"]));
    XCTAssertEqual([rvGEScriptStatement statementWithCommand:@"transition"].arguments.count, 4U, @"as many as it needs");
    XCTAssertEqualObjects([rvGEScript keyOfEvent:@"onTime" parameter:@"500"], @"onTime 500");
    XCTAssertEqualObjects([rvGEScript parameterOfKey:@"onNamedEvent NoIntro"], @"NoIntro");
}

- (void)testAScriptsEditIsOneUndo {
    idWindow *button = [self window:@"Button"];
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:button];
    NSString *action = [wrapper.scriptDict getString:@"onAction"];
    NSMutableArray<rvGEScriptStatement *> *statements = [rvGEScript statementsFromText:action message:NULL];
    XCTAssertEqual(statements.count, 1U);
    rvGEScriptStatement *sound = [rvGEScriptStatement statementWithCommand:@"localSound"];
    sound.arguments[0] = @"guisounds_click";
    [statements addObject:sound];
    idDict *scripts = [wrapper.scriptDict copy];
    [scripts set:@"onAction" value:[rvGEScript textFromStatements:statements]];
    [scripts set:@"onTime 100" value:@"{\n\tevalRegs ;\n}"];
    XCTAssertTrue([self.workspace setScripts:scripts variables:[wrapper.variableDict copy] of:button named:@"Add Statement" message:NULL]);
    XCTAssertEqualObjects(self.workspace.modifiers.undoModifier.name, @"Add Statement");
    XCTAssertTrue([self.workspace.text containsString:@"localSound \"guisounds_click\""], @"%@", self.workspace.text);
    XCTAssertTrue([self.workspace.text containsString:@"onTime 100"], @"%@", self.workspace.text);
    [self.workspace.modifiers undo];
    XCTAssertFalse([self.workspace.text containsString:@"guisounds_click"], @"undone");

    NSString *message = nil;
    [scripts set:@"onAction" value:@"{ set ; "];
    XCTAssertFalse([self.workspace setScripts:scripts variables:[wrapper.variableDict copy] of:button named:@"Statement Change" message:&message]);
    XCTAssertNotNil(message);
}

- (void)testAnExpressionIsCheckedAsTheWindowParsesIt {
    idWindow *button = [self window:@"Button"];
    XCTAssertNil([self.workspace problemWithExpression:@"\"Panel::visible\" == 1" in:button]);
    XCTAssertNil([self.workspace problemWithExpression:@"( time * 0.001 ) + 2" in:button]);
    XCTAssertNil([self.workspace problemWithExpression:@"" in:button], @"nothing: nothing wrong");
    XCTAssertNil([self.workspace problemWithExpression:@"1 +" in:button], @"as the engine reads it: an empty term at the end, said nothing of");
    XCTAssertEqualObjects([self.workspace problemWithExpression:@"( 1 + 2" in:button], @"line 1: couldn't find expected ')'", @"idParser's words");
    XCTAssertEqualObjects([self.workspace problemWithExpression:@"1 2" in:button], @"'2' after the expression");
}

@end
