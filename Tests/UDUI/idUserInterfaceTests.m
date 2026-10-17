#import <XCTest/XCTest.h>
#import "idUserInterface.h"
#import "idWindow.h"
#import "idWinVar.h"
#import "idChoiceWindow.h"
#import "idGuiModel.h"
#import "idStrPool.h"
#import "idDict.h"
#import "idStr.h"

// The GUIs here are original: a desktop, a box that fades, a label the
// scripts rename, a button, a choice bound to a cvar.
static NSString *const UDTestGui =
    @"windowDef Desktop {\n"
     "    rect 0, 0, 640, 480\n"
     "    backcolor 0, 0, 0, 1\n"
     "    menugui 1\n"
     "    windowDef Box {\n"
     "        rect 10, 20, 100, 50\n"
     "        backcolor 1, 0, 0, 1\n"
     "        visible (\"gui::hidebox\" == 0)\n"
     "    }\n"
     "    windowDef Label {\n"
     "        rect 0, 0, 200, 20\n"
     "        text \"start\"\n"
     "    }\n"
     "    windowDef Button {\n"
     "        rect 300, 200, 100, 40\n"
     "        backcolor 0, 0, 1, 1\n"
     "        onAction {\n"
     "            set \"gui::clicked\" \"1\" ;\n"
     "        }\n"
     "    }\n"
     "    choiceDef Toggle {\n"
     "        rect 300, 300, 100, 20\n"
     "        choices \"Off;On\"\n"
     "        cvar \"in_freeLook\"\n"
     "        choiceType 0\n"
     "    }\n"
     "    onNamedEvent rename {\n"
     "        set \"Label::text\" \"renamed\" ;\n"
     "        set \"gui::result\" \"done\" ;\n"
     "    }\n"
     "    onNamedEvent fade {\n"
     "        transition \"Box::backcolor\" \"1 0 0 1\" \"0 0 1 1\" \"1000\" ;\n"
     "    }\n"
     "    onTime 0 {\n"
     "        set \"gui::tick\" \"0\" ;\n"
     "    }\n"
     "    onTime 500 {\n"
     "        set \"gui::tick\" \"500\" ;\n"
     "    }\n"
     "}\n";

@interface idUserInterfaceTests : XCTestCase
@property (nonatomic, strong) idUserInterfaceManager *manager;
@end

@implementation idUserInterfaceTests

- (void)setUp {
    [super setUp];
    self.manager = [[idUserInterfaceManager alloc] initWithFileSystem:nil declManager:nil];
    [self.manager managerInit];
    // no file system, so no fonts: managerInit says so
    [self.manager.warnings removeAllObjects];
}

- (void)tearDown {
    [self.manager shutdown];
    self.manager = nil;
    [super tearDown];
}

- (idUserInterfaceLocal *)loadGui:(NSString *)text {
    idUserInterfaceLocal *gui = [self.manager allocGui];
    XCTAssertTrue([gui initFromText:text path:@"guis/test.gui"]);
    return gui;
}

/// A child's var, whichever kind of window the child became.
- (idWinVar *)var:(NSString *)var of:(NSString *)window in:(idUserInterfaceLocal *)gui {
    idDrawWin *dw = [[gui getDesktop] findChildByName:window];
    XCTAssertNotNil(dw, @"%@", window);
    return dw.win ? [dw.win getWinVarByName:var] : [dw.simp getWinVarByName:var];
}

#pragma mark - Parse

- (void)testParsesTheWindowTree {
    idUserInterfaceLocal *gui = [self loadGui:UDTestGui];
    XCTAssertEqual(gui.diagnostics.count, 0u, @"%@", gui.diagnostics);
    XCTAssertEqual(self.manager.warnings.count, 0u, @"%@", self.manager.warnings);
    idWindow *desktop = [gui getDesktop];
    XCTAssertEqualObjects([desktop getName], @"Desktop");
    XCTAssertTrue([gui isInteractive]);
    XCTAssertEqualObjects([gui getSourceFile], @"guis/test.gui");

    // id compares names ignoring the case of A-Z
    XCTAssertNotNil([desktop findChildByName:@"BOX"]);
    XCTAssertNotNil([desktop findChildByName:@"label"]);
    XCTAssertNil([desktop findChildByName:@"Missing"]);

    idWinRectangle *rect = (idWinRectangle *)[self var:@"rect" of:@"Box" in:gui];
    XCTAssertEqual(rect.x, 10);
    XCTAssertEqual(rect.y, 20);
    XCTAssertEqual(rect.w, 100);
    XCTAssertEqual(rect.h, 50);
    XCTAssertEqualObjects([[self var:@"text" of:@"Label" in:gui] string], @"start");

    idDrawWin *toggle = [desktop findChildByName:@"Toggle"];
    XCTAssertTrue([toggle.win isKindOfClass:[idChoiceWindow class]]);
}

- (void)testExpressionsFollowTheState {
    idUserInterfaceLocal *gui = [self loadGui:UDTestGui];
    [gui activate:YES time:0];
    idWinVar *visible = [self var:@"visible" of:@"Box" in:gui];
    [gui redraw:0];
    XCTAssertEqual(visible.x, 1);
    [gui setStateBool:@"hidebox" value:YES];
    [gui stateChanged:0 redraw:NO];
    [gui redraw:16];
    XCTAssertEqual(visible.x, 0);
}

#pragma mark - Scripts

- (void)testNamedEventSetsOtherWindowsVars {
    idUserInterfaceLocal *gui = [self loadGui:UDTestGui];
    [gui activate:YES time:0];
    [gui handleNamedEvent:@"rename"];
    XCTAssertEqualObjects([[self var:@"text" of:@"Label" in:gui] string], @"renamed");
    XCTAssertEqualObjects([gui getStateString:@"result" defaultString:@""], @"done");
}

- (void)testTimelineRunsWithTheClock {
    idUserInterfaceLocal *gui = [self loadGui:UDTestGui];
    [gui activate:YES time:0];
    [gui redraw:100];
    XCTAssertEqualObjects([gui getStateString:@"tick" defaultString:@""], @"0");
    [gui redraw:600];
    XCTAssertEqualObjects([gui getStateString:@"tick" defaultString:@""], @"500");
}

- (void)testTransitionMovesTheDestination {
    idUserInterfaceLocal *gui = [self loadGui:UDTestGui];
    XCTAssertEqual(self.manager.warnings.count, 0u, @"%@", self.manager.warnings);
    [gui activate:YES time:0];
    [gui redraw:0];
    [gui handleNamedEvent:@"fade"];
    idWinVec4 *color = (idWinVec4 *)[self var:@"backcolor" of:@"Box" in:gui];
    [gui redraw:500];
    idVec4 middle = [color data];
    XCTAssertGreaterThan(middle.x, 0.0f);
    XCTAssertLessThan(middle.x, 1.0f);
    [gui redraw:2000];
    idVec4 end = [color data];
    XCTAssertEqualWithAccuracy(end.x, 0.0f, 1e-4);
    XCTAssertEqualWithAccuracy(end.z, 1.0f, 1e-4);
}

- (void)testClickRunsTheAction {
    idUserInterfaceLocal *gui = [self loadGui:UDTestGui];
    [gui activate:YES time:0];
    [gui redraw:0];
    [gui setCursor:320 y:220];
    sysEvent_t down = { SE_KEY, K_MOUSE1, 1 };
    sysEvent_t up = { SE_KEY, K_MOUSE1, 0 };
    [gui handleEvent:&down time:16 updateVisuals:NULL];
    [gui handleEvent:&up time:32 updateVisuals:NULL];
    XCTAssertEqualObjects([gui getStateString:@"clicked" defaultString:@""], @"1");
}

- (void)testChoiceReadsItsCvar {
    idUserInterfaceLocal *gui = [self loadGui:UDTestGui];
    [self.manager.cvars set:@"in_freeLook" value:@"0"];
    [gui activate:YES time:0];
    [gui redraw:0];
    idChoiceWindow *toggle = (idChoiceWindow *)[[gui getDesktop] findChildByName:@"Toggle"].win;
    XCTAssertEqual(toggle->choices.count, 2u);
    XCTAssertEqual(toggle->currentChoice, 0);
    [self.manager.cvars set:@"in_freeLook" value:@"1"];
    [gui redraw:16];
    XCTAssertEqual(toggle->currentChoice, 1);
}

#pragma mark - Drawing

- (void)testRedrawEmitsSurfaces {
    idUserInterfaceLocal *gui = [self loadGui:UDTestGui];
    [gui activate:YES time:0];
    [self.manager.guiModel clear];
    [gui redraw:0];
    NSArray *surfaces = [self.manager.guiModel emitFullScreen];
    XCTAssertGreaterThan(surfaces.count, 0u);
}

#pragma mark - Errors

- (void)testBadTextIsReportedWithItsLine {
    NSString *text =
        @"windowDef Desktop {\n"
         "    rect 0, 0, 640, 480\n"
         "    text \"no end\n"
         "}\n";
    idUserInterfaceLocal *gui = [self.manager allocGui];
    [gui initFromText:text path:@"guis/broken.gui"];
    XCTAssertGreaterThan(gui.diagnostics.count, 0u);
    NSDictionary *first = gui.diagnostics.firstObject;
    XCTAssertEqualObjects(first[@"file"], @"guis/broken.gui");
    XCTAssertGreaterThan([first[@"line"] intValue], 0);
}

#pragma mark - What the GUIs stand on

- (void)testComparesIgnoreOnlyTheCaseOfAToZ {
    XCTAssertTrue([@"Desktop" ud_iequals:@"DESKTOP"]);
    XCTAssertFalse([@"Desktop" ud_iequals:@"Desktops"]);
    XCTAssertEqual([@"abc" ud_icmp:@"ABD"], -1);
    XCTAssertEqual([@"abd" ud_icmp:@"ABC"], 1);
    XCTAssertEqual([@"ab" ud_icmp:@"abc"], -1);
    XCTAssertEqual([@"abcx" ud_icmpn:@"ABCY" length:3], 0);
    // 0xC9 and 0xE9 (E acute) are not folded
    XCTAssertFalse([@"É" ud_iequals:@"é"]);
}

- (void)testPoolSharesStrings {
    idStrPool *pool = [[idStrPool alloc] init];
    pool.caseSensitive = NO;
    idPoolStr *a = [pool allocString:@"Name"];
    idPoolStr *b = [pool allocString:@"NAME"];
    XCTAssertEqual(a, b);
    XCTAssertEqual(a.numUsers, 2);
    XCTAssertEqual([pool num], 1);
    [pool freeString:a];
    [pool freeString:b];
    XCTAssertEqual([pool num], 0);
}

- (void)testDictKeysIgnoreCase {
    idDict *dict = [[idDict alloc] init];
    [dict set:@"Model" value:@"a"];
    [dict set:@"model" value:@"b"];
    XCTAssertEqual([dict numKeyVals], 1);
    XCTAssertEqualObjects([dict getString:@"MODEL"], @"b");
    [dict setVec4:@"color" value:(idVec4){ 1, 0.5f, 0, 1 }];
    idVec4 v = [dict getVec4:@"Color"];
    XCTAssertEqual(v.y, 0.5f);
}

- (void)testDictLookupsFollowDeletesCopiesAndClears {
    idDict *dict = [[idDict alloc] init];
    for (NSString *key in @[@"a", @"B", @"c", @"D"]) {
        [dict set:key value:[key stringByAppendingString:@"!"]];
    }
    [dict deleteKey:@"b"];
    XCTAssertEqual([dict numKeyVals], 3);
    XCTAssertEqualObjects([dict getString:@"B" defaultString:@"none"], @"none");
    XCTAssertEqualObjects([dict getString:@"d"], @"D!", @"found after a delete moved it");
    idDict *copy = [dict copy];
    [dict set:@"d" value:@"changed"];
    XCTAssertEqualObjects([copy getString:@"D"], @"D!", @"the copy its own");
    XCTAssertEqualObjects([dict keyAtIndex:2], @"D", @"the first spelling kept");
    [copy clear];
    XCTAssertEqualObjects([copy getString:@"a" defaultString:@"none"], @"none");
    [copy set:@"A" value:@"again"];
    XCTAssertEqualObjects([copy getString:@"a"], @"again");
    XCTAssertEqualObjects([@"MixedCase_Ä" ud_foldedAZ], @"mixedcase_Ä", @"A-Z alone, as idStr::Icmp");
}

@end
