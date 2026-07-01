#import <XCTest/XCTest.h>

#import "UDGuiEditorService.h"
#import "UDGuiEditorViewModel.h"

@interface UDGuiEditorTests : XCTestCase
@end

@implementation UDGuiEditorTests

- (void)testGuiDocumentCodecParsesNestedWindows {
    NSString *text =
        @"windowDef Desktop {\n"
         "    rect 0,0,640,480\n"
         "    windowDef Child {\n"
         "        text \"Hello\"\n"
         "    }\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/mainmenu.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDGuiWindowNode *desktop = [document.rootWindows objectAtIndex:0];
    XCTAssertEqualObjects(desktop.className, @"windowDef");
    XCTAssertEqualObjects(desktop.name, @"Desktop");
    XCTAssertEqual(desktop.children.count, 1U);

    UDGuiWindowNode *child = [desktop.children objectAtIndex:0];
    XCTAssertEqualObjects(child.name, @"Child");
    XCTAssertEqualObjects([[child propertyForKey:@"text"] value], @"Hello");
}

- (void)testGuiDocumentCodecNormalizesQuotedStringLiterals {
    NSString *text =
        @"windowDef Desktop {\n"
         "    text \"#str_00065\"\n"
         "    font \"fonts/bank\"\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDGuiWindowNode *window = [document.rootWindows objectAtIndex:0];
    XCTAssertEqualObjects(window.text, @"#str_00065");
    XCTAssertEqualObjects(window.font, @"fonts/bank");
}

- (void)testGuiDocumentCodecSerializesQuotesOnlyWhenNeeded {
    UDGuiDocument *document = [[UDGuiDocument alloc] initWithSourceVirtualPath:@"guis/test.gui"];
    UDGuiWindowNode *window = [[UDGuiWindowNode alloc] initWithClassName:@"windowDef" name:@"Desktop"];
    window.text = @"#str_00065";
    window.font = @"fonts/bank";
    [document addRootWindow:window];

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    NSString *serialized = [codec serializeDocument:document error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(serialized);
    XCTAssertTrue([serialized containsString:@"text \"#str_00065\""]);
    XCTAssertTrue([serialized containsString:@"font fonts/bank"]);
}

- (void)testGuiDocumentCodecParsesScriptBlocksAndOnTimeHandlers {
    NSString *text =
        @"windowDef Desktop {\n"
         "    onEvent {\n"
         "        if (\"gui::movestate\" == 1) {\n"
         "            resetTime \"pos1\" \"0\" ;\n"
         "        }\n"
         "    }\n"
         "    windowDef Extend {\n"
         "        onTime 0 {\n"
         "            set \"Status1::foreColor\" \"0 0.65 0.8 0.1\" ;\n"
         "        }\n"
         "    }\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/bridge.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDGuiWindowNode *desktop = [document.rootWindows objectAtIndex:0];
    XCTAssertTrue([[[desktop propertyForKey:@"onEvent"] value] containsString:@"resetTime \"pos1\" \"0\" ;"]);
    XCTAssertEqual(desktop.children.count, 1U);

    UDGuiWindowNode *extend = [desktop.children objectAtIndex:0];
    XCTAssertEqualObjects(extend.name, @"Extend");
    XCTAssertTrue([[[extend propertyForKey:@"onTime"] value] hasPrefix:@"0 {"]);
    XCTAssertTrue([[[extend propertyForKey:@"onTime"] value] containsString:@"Status1::foreColor"]);
}

- (void)testGuiEditorServiceUndoRedoPropertyEdits {
    UDGuiDocument *document = [[UDGuiDocument alloc] initWithSourceVirtualPath:@"guis/test.gui"];
    UDGuiWindowNode *root = [[UDGuiWindowNode alloc] initWithClassName:@"windowDef" name:@"Desktop"];
    [document addRootWindow:root];

    NSUndoManager *undoManager = [[NSUndoManager alloc] init];
    UDGuiEditorService *service = [[UDGuiEditorService alloc] initWithDocument:document undoManager:undoManager];

    [service updatePropertyForWindow:root key:@"text" value:@"Alpha"];
    XCTAssertEqualObjects([[root propertyForKey:@"text"] value], @"Alpha");

    [undoManager undo];
    XCTAssertNil([root propertyForKey:@"text"]);

    [undoManager redo];
    XCTAssertEqualObjects([[root propertyForKey:@"text"] value], @"Alpha");
}

- (void)testWindowCommonAttributeDefaultsAndProperties {
    UDGuiWindowNode *node = [UDGuiWindowNode windowNodeWithClassName:@"windowDef" name:@"Desktop"];

    XCTAssertFalse(node.showTime);
    XCTAssertFalse(node.showCoords);
    XCTAssertTrue(node.visible);
    XCTAssertFalse(node.noEvents);
    XCTAssertEqual(node.forceAspectWidth, 640.0);
    XCTAssertEqual(node.forceAspectHeight, 480.0);
    XCTAssertEqual(node.matScaleX, 1.0);
    XCTAssertEqual(node.matScaleY, 1.0);
    XCTAssertEqual(node.borderSize, 0.0);
    XCTAssertEqualObjects(node.foreColor, @"1, 1, 1, 1");
    XCTAssertEqualObjects(node.hoverColor, @"1, 1, 1, 1");
    XCTAssertEqualObjects(node.backColor, @"0, 0, 0, 0");
    XCTAssertEqualObjects(node.borderColor, @"0, 0, 0, 0");
    XCTAssertEqualObjects(node.matColor, @"1, 1, 1, 1");
    XCTAssertNil(node.scale);
    XCTAssertNil(node.translate);
    XCTAssertFalse(node.noWrap);
    XCTAssertFalse(node.shadow);
    XCTAssertEqual(node.textScale, 1.0);
    XCTAssertEqual(node.textAlign, 0);
    XCTAssertEqual(node.textAlignX, 0.0);
    XCTAssertEqual(node.textAlignY, 0.0);
    XCTAssertEqualObjects(node.shear, @"0, 0");
    XCTAssertFalse(node.wantEnter);
    XCTAssertFalse(node.naturalMatScale);
    XCTAssertFalse(node.noClip);
    XCTAssertFalse(node.noCursor);
    XCTAssertFalse(node.menuGUI);
    XCTAssertFalse(node.modal);
    XCTAssertFalse(node.invertRect);
    XCTAssertEqualObjects(node.nameOverride, @"Desktop");
    XCTAssertNil(node.text);
    XCTAssertNil(node.background);
    XCTAssertNil(node.varBackground);
    XCTAssertNil(node.runScript);
    XCTAssertNil(node.play);
    XCTAssertNil(node.comment);
    XCTAssertNil(node.font);

    node.showTime = YES;
    node.showCoords = YES;
    node.visible = NO;
    node.noEvents = YES;
    node.forceAspectWidth = 800.0;
    node.forceAspectHeight = 600.0;
    node.matScaleX = 0.5;
    node.matScaleY = 2.0;
    node.borderSize = 3.0;
    node.foreColor = @"0.8, 0.7, 0.6, 1";
    node.hoverColor = @"1, 0.5, 0.5, 1";
    node.backColor = @"0.1, 0.1, 0.1, 0.8";
    node.borderColor = @"0.2, 0.2, 0.2, 1";
    node.matColor = @"0.9, 0.9, 0.9, 1";
    node.scale = @"1, 1";
    node.translate = @"4, 8";
    node.noWrap = YES;
    node.shadow = YES;
    node.textScale = 0.75;
    node.textAlign = 2;
    node.textAlignX = 8.0;
    node.textAlignY = -4.0;
    node.shear = @"0.25, 0.75";
    node.wantEnter = YES;
    node.naturalMatScale = YES;
    node.noClip = YES;
    node.noCursor = YES;
    node.menuGUI = YES;
    node.modal = YES;
    node.invertRect = YES;
    node.nameOverride = @"DesktopOverride";
    node.text = @"Hello marine";
    node.background = @"guis/assets/main";
    node.varBackground = @"unusedVar";
    node.runScript = @"unusedScript";
    node.play = @"menu_open";
    node.comment = @"debug overlay";
    node.font = @"fonts/an";

    XCTAssertTrue(node.showTime);
    XCTAssertTrue(node.showCoords);
    XCTAssertFalse(node.visible);
    XCTAssertTrue(node.noEvents);
    XCTAssertEqual(node.forceAspectWidth, 800.0);
    XCTAssertEqual(node.forceAspectHeight, 600.0);
    XCTAssertEqual(node.matScaleX, 0.5);
    XCTAssertEqual(node.matScaleY, 2.0);
    XCTAssertEqual(node.borderSize, 3.0);
    XCTAssertEqualObjects(node.foreColor, @"0.8, 0.7, 0.6, 1");
    XCTAssertEqualObjects(node.hoverColor, @"1, 0.5, 0.5, 1");
    XCTAssertEqualObjects(node.backColor, @"0.1, 0.1, 0.1, 0.8");
    XCTAssertEqualObjects(node.borderColor, @"0.2, 0.2, 0.2, 1");
    XCTAssertEqualObjects(node.matColor, @"0.9, 0.9, 0.9, 1");
    XCTAssertEqualObjects(node.scale, @"1, 1");
    XCTAssertEqualObjects(node.translate, @"4, 8");
    XCTAssertTrue(node.noWrap);
    XCTAssertTrue(node.shadow);
    XCTAssertEqual(node.textScale, 0.75);
    XCTAssertEqual(node.textAlign, 2);
    XCTAssertEqual(node.textAlignX, 8.0);
    XCTAssertEqual(node.textAlignY, -4.0);
    XCTAssertEqualObjects(node.shear, @"0.25, 0.75");
    XCTAssertTrue(node.wantEnter);
    XCTAssertTrue(node.naturalMatScale);
    XCTAssertTrue(node.noClip);
    XCTAssertTrue(node.noCursor);
    XCTAssertTrue(node.menuGUI);
    XCTAssertTrue(node.modal);
    XCTAssertTrue(node.invertRect);
    XCTAssertEqualObjects(node.nameOverride, @"DesktopOverride");
    XCTAssertEqualObjects(node.text, @"Hello marine");
    XCTAssertEqualObjects(node.background, @"guis/assets/main");
    XCTAssertEqualObjects(node.varBackground, @"unusedVar");
    XCTAssertEqualObjects(node.runScript, @"unusedScript");
    XCTAssertEqualObjects(node.play, @"menu_open");
    XCTAssertEqualObjects(node.comment, @"debug overlay");
    XCTAssertEqualObjects(node.font, @"fonts/an");

    node.nameOverride = @"Desktop";
    node.text = @"   ";
    node.background = @"";
    node.varBackground = @"\n";
    node.runScript = @"\t";
    node.play = @"   ";
    node.comment = @"\n\t";
    node.font = @"";

    XCTAssertNil([node propertyForKey:@"name"]);
    XCTAssertNil(node.text);
    XCTAssertNil(node.background);
    XCTAssertNil(node.varBackground);
    XCTAssertNil(node.runScript);
    XCTAssertNil(node.play);
    XCTAssertNil(node.comment);
    XCTAssertNil(node.font);
}

- (void)testGuiDocumentCodecParsesCommonWindowAttributes {
    NSString *text =
        @"windowDef Desktop {\n"
         "    showtime 1\n"
         "    showcoords 1\n"
         "    visible 0\n"
         "    noevents 1\n"
         "    forceaspectwidth 800\n"
         "    forceaspectheight 600\n"
         "    forecolor 0.8, 0.7, 0.6, 1\n"
         "    hovercolor 1, 0.5, 0.5, 1\n"
         "    backcolor 0.1, 0.1, 0.1, 0.8\n"
         "    bordercolor 0.2, 0.2, 0.2, 1\n"
         "    matcolor 0.9, 0.9, 0.9, 1\n"
         "    scale 1, 1\n"
         "    translate 4, 8\n"
         "    matscalex 0.5\n"
         "    matscaley 2\n"
         "    bordersize 3\n"
         "    nowrap 1\n"
         "    shadow 1\n"
         "    textscale 0.75\n"
         "    textalign 2\n"
         "    textalignx 8\n"
         "    textaligny -4\n"
         "    shear 0.25, 0.75\n"
         "    wantenter 1\n"
         "    naturalmatscale 1\n"
         "    noclip 1\n"
         "    nocursor 1\n"
         "    menugui 1\n"
         "    modal 1\n"
         "    invertrect 1\n"
         "    name DesktopOverride\n"
         "    text Hello marine\n"
         "    background guis/assets/main\n"
         "    varbackground unusedVar\n"
         "    runscript unusedScript\n"
         "    play menu_open\n"
         "    comment debug_overlay\n"
         "    font fonts/an\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDGuiWindowNode *node = [document.rootWindows objectAtIndex:0];
    XCTAssertTrue(node.showTime);
    XCTAssertTrue(node.showCoords);
    XCTAssertFalse(node.visible);
    XCTAssertTrue(node.noEvents);
    XCTAssertEqual(node.forceAspectWidth, 800.0);
    XCTAssertEqual(node.forceAspectHeight, 600.0);
    XCTAssertEqualObjects(node.foreColor, @"0.8, 0.7, 0.6, 1");
    XCTAssertEqualObjects(node.hoverColor, @"1, 0.5, 0.5, 1");
    XCTAssertEqualObjects(node.backColor, @"0.1, 0.1, 0.1, 0.8");
    XCTAssertEqualObjects(node.borderColor, @"0.2, 0.2, 0.2, 1");
    XCTAssertEqualObjects(node.matColor, @"0.9, 0.9, 0.9, 1");
    XCTAssertEqualObjects(node.scale, @"1, 1");
    XCTAssertEqualObjects(node.translate, @"4, 8");
    XCTAssertEqual(node.matScaleX, 0.5);
    XCTAssertEqual(node.matScaleY, 2.0);
    XCTAssertEqual(node.borderSize, 3.0);
    XCTAssertTrue(node.noWrap);
    XCTAssertTrue(node.shadow);
    XCTAssertEqual(node.textScale, 0.75);
    XCTAssertEqual(node.textAlign, 2);
    XCTAssertEqual(node.textAlignX, 8.0);
    XCTAssertEqual(node.textAlignY, -4.0);
    XCTAssertEqualObjects(node.shear, @"0.25, 0.75");
    XCTAssertTrue(node.wantEnter);
    XCTAssertTrue(node.naturalMatScale);
    XCTAssertTrue(node.noClip);
    XCTAssertTrue(node.noCursor);
    XCTAssertTrue(node.menuGUI);
    XCTAssertTrue(node.modal);
    XCTAssertTrue(node.invertRect);
    XCTAssertEqualObjects(node.nameOverride, @"DesktopOverride");
    XCTAssertEqualObjects(node.text, @"Hello marine");
    XCTAssertEqualObjects(node.background, @"guis/assets/main");
    XCTAssertEqualObjects(node.varBackground, @"unusedVar");
    XCTAssertEqualObjects(node.runScript, @"unusedScript");
    XCTAssertEqualObjects(node.play, @"menu_open");
    XCTAssertEqualObjects(node.comment, @"debug_overlay");
    XCTAssertEqualObjects(node.font, @"fonts/an");
}

- (void)testEditDefTypedDefaultsAndProperties {
    UDEditDefWindowNode *node = (UDEditDefWindowNode *)[UDGuiWindowNode windowNodeWithClassName:@"editDef" name:@"Field"];

    XCTAssertEqual(node.maxChars, 128);
    XCTAssertFalse(node.numeric);
    XCTAssertFalse(node.wrap);
    XCTAssertFalse(node.readOnly);
    XCTAssertFalse(node.forceScroll);
    XCTAssertFalse(node.password);
    XCTAssertTrue(node.liveUpdate);

    node.cvar = @"gui::name";
    node.maxChars = 32;
    node.numeric = YES;
    node.wrap = YES;
    node.readOnly = YES;
    node.forceScroll = YES;
    node.source = @"guis/text/license.txt";
    node.password = YES;
    node.liveUpdate = NO;
    node.cvarGroup = @"audio";

    XCTAssertEqualObjects(node.cvar, @"gui::name");
    XCTAssertEqual(node.maxChars, 32);
    XCTAssertTrue(node.numeric);
    XCTAssertTrue(node.wrap);
    XCTAssertTrue(node.readOnly);
    XCTAssertTrue(node.forceScroll);
    XCTAssertEqualObjects(node.source, @"guis/text/license.txt");
    XCTAssertTrue(node.password);
    XCTAssertFalse(node.liveUpdate);
    XCTAssertEqualObjects(node.cvarGroup, @"audio");
}

- (void)testGuiDocumentCodecParsesEditDefAttributes {
    NSString *text =
        @"editDef NameField {\n"
         "    cvar gui::playername\n"
         "    maxchars 64\n"
         "    numeric 1\n"
         "    wrap 1\n"
         "    readonly 1\n"
         "    forcescroll 1\n"
         "    source guis/text/license.txt\n"
         "    password 1\n"
         "    liveupdate 0\n"
         "    cvargroup audio\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDEditDefWindowNode *node = (UDEditDefWindowNode *)[document.rootWindows objectAtIndex:0];
    XCTAssertTrue([node isKindOfClass:[UDEditDefWindowNode class]]);
    XCTAssertEqualObjects(node.cvar, @"gui::playername");
    XCTAssertEqual(node.maxChars, 64);
    XCTAssertTrue(node.numeric);
    XCTAssertTrue(node.wrap);
    XCTAssertTrue(node.readOnly);
    XCTAssertTrue(node.forceScroll);
    XCTAssertEqualObjects(node.source, @"guis/text/license.txt");
    XCTAssertTrue(node.password);
    XCTAssertFalse(node.liveUpdate);
    XCTAssertEqualObjects(node.cvarGroup, @"audio");
}

- (void)testChoiceDefTypedDefaultsAndProperties {
    UDChoiceDefWindowNode *node = (UDChoiceDefWindowNode *)[UDGuiWindowNode windowNodeWithClassName:@"choiceDef" name:@"Difficulty"];

    XCTAssertEqual(node.choiceType, 0);
    XCTAssertEqual(node.currentChoice, 0);
    XCTAssertNil(node.choices);
    XCTAssertNil(node.values);
    XCTAssertTrue(node.liveUpdate);

    node.choiceType = 1;
    node.currentChoice = 2;
    node.choices = @"Easy;Medium;Hard";
    XCTAssertEqualObjects(node.values, @"Easy;Medium;Hard");
    node.values = @"0;1;2";
    node.gui = @"gui::difficulty";
    node.cvar = @"g_skill";
    node.liveUpdate = NO;
    node.cvarGroup = @"gameplay";

    XCTAssertEqual(node.choiceType, 1);
    XCTAssertEqual(node.currentChoice, 2);
    XCTAssertEqualObjects(node.choices, @"Easy;Medium;Hard");
    XCTAssertEqualObjects(node.values, @"0;1;2");
    XCTAssertEqualObjects(node.gui, @"gui::difficulty");
    XCTAssertEqualObjects(node.cvar, @"g_skill");
    XCTAssertFalse(node.liveUpdate);
    XCTAssertEqualObjects(node.cvarGroup, @"gameplay");
}

- (void)testGuiDocumentCodecParsesChoiceDefAttributes {
    NSString *text =
        @"choiceDef Difficulty {\n"
         "    choicetype 1\n"
         "    currentchoice 2\n"
         "    choices Easy;Medium;Hard\n"
         "    gui gui::difficulty\n"
         "    cvar g_skill\n"
         "    liveupdate 0\n"
         "    cvargroup gameplay\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDChoiceDefWindowNode *node = (UDChoiceDefWindowNode *)[document.rootWindows objectAtIndex:0];
    XCTAssertTrue([node isKindOfClass:[UDChoiceDefWindowNode class]]);
    XCTAssertEqual(node.choiceType, 1);
    XCTAssertEqual(node.currentChoice, 2);
    XCTAssertEqualObjects(node.choices, @"Easy;Medium;Hard");
    XCTAssertEqualObjects(node.values, @"Easy;Medium;Hard");
    XCTAssertEqualObjects(node.gui, @"gui::difficulty");
    XCTAssertEqualObjects(node.cvar, @"g_skill");
    XCTAssertFalse(node.liveUpdate);
    XCTAssertEqualObjects(node.cvarGroup, @"gameplay");
}

- (void)testListDefTypedDefaultsAndProperties {
    UDListDefWindowNode *node = (UDListDefWindowNode *)[UDGuiWindowNode windowNodeWithClassName:@"listDef" name:@"ServerList"];

    XCTAssertFalse(node.horizontal);
    XCTAssertFalse(node.multipleSelection);
    XCTAssertNil(node.listName);
    XCTAssertNil(node.tabStops);
    XCTAssertNil(node.tabAligns);

    node.horizontal = YES;
    node.listName = @"serverBrowser";
    node.tabStops = @"0,120,240";
    node.tabAligns = @"0,1,2";
    node.multipleSelection = YES;

    XCTAssertTrue(node.horizontal);
    XCTAssertEqualObjects(node.listName, @"serverBrowser");
    XCTAssertEqualObjects(node.tabStops, @"0,120,240");
    XCTAssertEqualObjects(node.tabAligns, @"0,1,2");
    XCTAssertTrue(node.multipleSelection);
}

- (void)testGuiDocumentCodecParsesListDefAttributes {
    NSString *text =
        @"listDef ServerList {\n"
         "    horizontal 1\n"
         "    listname serverBrowser\n"
         "    tabstops 0,120,240\n"
         "    tabaligns 0,1,2\n"
         "    multiplesel 1\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDListDefWindowNode *node = (UDListDefWindowNode *)[document.rootWindows objectAtIndex:0];
    XCTAssertTrue([node isKindOfClass:[UDListDefWindowNode class]]);
    XCTAssertTrue(node.horizontal);
    XCTAssertEqualObjects(node.listName, @"serverBrowser");
    XCTAssertEqualObjects(node.tabStops, @"0,120,240");
    XCTAssertEqualObjects(node.tabAligns, @"0,1,2");
    XCTAssertTrue(node.multipleSelection);
}

- (void)testSliderDefTypedDefaultsAndProperties {
    UDSliderDefWindowNode *node = (UDSliderDefWindowNode *)[UDGuiWindowNode windowNodeWithClassName:@"sliderDef" name:@"Volume"];

    XCTAssertEqual(node.low, 0.0);
    XCTAssertEqual(node.high, 100.0);
    XCTAssertEqual(node.stepSize, 1.0);
    XCTAssertFalse(node.vertical);
    XCTAssertFalse(node.scrollBar);
    XCTAssertNil(node.thumbShader);
    XCTAssertTrue(node.liveUpdate);
    XCTAssertNil(node.cvarGroup);

    node.cvar = @"s_volume";
    node.low = 5.0;
    node.high = 90.0;
    node.stepSize = 2.5;
    node.vertical = YES;
    node.scrollBar = YES;
    node.thumbShader = @"guis/assets/slider_thumb";
    node.liveUpdate = NO;
    node.cvarGroup = @"audio";

    XCTAssertEqualObjects(node.cvar, @"s_volume");
    XCTAssertEqual(node.low, 5.0);
    XCTAssertEqual(node.high, 90.0);
    XCTAssertEqual(node.stepSize, 2.5);
    XCTAssertTrue(node.vertical);
    XCTAssertTrue(node.scrollBar);
    XCTAssertEqualObjects(node.thumbShader, @"guis/assets/slider_thumb");
    XCTAssertFalse(node.liveUpdate);
    XCTAssertEqualObjects(node.cvarGroup, @"audio");
}

- (void)testGuiDocumentCodecParsesSliderDefAttributes {
    NSString *text =
        @"sliderDef Volume {\n"
         "    cvar s_volume\n"
         "    low 5\n"
         "    high 90\n"
         "    step 2.5\n"
         "    vertical 1\n"
         "    scrollbar 1\n"
         "    thumbshader guis/assets/slider_thumb\n"
         "    liveupdate 0\n"
         "    cvargroup audio\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDSliderDefWindowNode *node = (UDSliderDefWindowNode *)[document.rootWindows objectAtIndex:0];
    XCTAssertTrue([node isKindOfClass:[UDSliderDefWindowNode class]]);
    XCTAssertEqualObjects(node.cvar, @"s_volume");
    XCTAssertEqual(node.low, 5.0);
    XCTAssertEqual(node.high, 90.0);
    XCTAssertEqual(node.stepSize, 2.5);
    XCTAssertTrue(node.vertical);
    XCTAssertTrue(node.scrollBar);
    XCTAssertEqualObjects(node.thumbShader, @"guis/assets/slider_thumb");
    XCTAssertFalse(node.liveUpdate);
    XCTAssertEqualObjects(node.cvarGroup, @"audio");
}

- (void)testRenderDefTypedDefaultsAndProperties {
    UDRenderDefWindowNode *node = (UDRenderDefWindowNode *)[UDGuiWindowNode windowNodeWithClassName:@"renderDef" name:@"Preview"];

    XCTAssertNil(node.model);
    XCTAssertNil(node.anim);
    XCTAssertNil(node.animClass);
    XCTAssertEqualObjects(node.lightOrigin, @"-128,0,0,1");
    XCTAssertEqualObjects(node.lightColor, @"1,1,1,1");
    XCTAssertEqualObjects(node.modelOrigin, @"0,0,0,0");
    XCTAssertEqualObjects(node.modelRotate, @"0,0,0,0");
    XCTAssertEqualObjects(node.viewOffset, @"-128,0,0,1");
    XCTAssertTrue(node.needsRender);

    node.model = @"models/mapobjects/terminal.lwo";
    node.anim = @"idle";
    node.animClass = @"monster_zsec";
    node.lightOrigin = @"-32,16,8,1";
    node.lightColor = @"0.8,0.7,1,1";
    node.modelOrigin = @"1,2,3,0";
    node.modelRotate = @"0,90,0,0";
    node.viewOffset = @"-64,0,24,1";
    node.needsRender = NO;

    XCTAssertEqualObjects(node.model, @"models/mapobjects/terminal.lwo");
    XCTAssertEqualObjects(node.anim, @"idle");
    XCTAssertEqualObjects(node.animClass, @"monster_zsec");
    XCTAssertEqualObjects(node.lightOrigin, @"-32,16,8,1");
    XCTAssertEqualObjects(node.lightColor, @"0.8,0.7,1,1");
    XCTAssertEqualObjects(node.modelOrigin, @"1,2,3,0");
    XCTAssertEqualObjects(node.modelRotate, @"0,90,0,0");
    XCTAssertEqualObjects(node.viewOffset, @"-64,0,24,1");
    XCTAssertFalse(node.needsRender);
}

- (void)testGuiDocumentCodecParsesRenderDefAttributes {
    NSString *text =
        @"renderDef Preview {\n"
         "    model models/mapobjects/terminal.lwo\n"
         "    anim idle\n"
         "    animclass monster_zsec\n"
         "    lightorigin -32,16,8,1\n"
         "    lightcolor 0.8,0.7,1,1\n"
         "    modelorigin 1,2,3,0\n"
         "    modelrotate 0,90,0,0\n"
         "    viewoffset -64,0,24,1\n"
         "    needsrender 0\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDRenderDefWindowNode *node = (UDRenderDefWindowNode *)[document.rootWindows objectAtIndex:0];
    XCTAssertTrue([node isKindOfClass:[UDRenderDefWindowNode class]]);
    XCTAssertEqualObjects(node.model, @"models/mapobjects/terminal.lwo");
    XCTAssertEqualObjects(node.anim, @"idle");
    XCTAssertEqualObjects(node.animClass, @"monster_zsec");
    XCTAssertEqualObjects(node.lightOrigin, @"-32,16,8,1");
    XCTAssertEqualObjects(node.lightColor, @"0.8,0.7,1,1");
    XCTAssertEqualObjects(node.modelOrigin, @"1,2,3,0");
    XCTAssertEqualObjects(node.modelRotate, @"0,90,0,0");
    XCTAssertEqualObjects(node.viewOffset, @"-64,0,24,1");
    XCTAssertFalse(node.needsRender);
}

- (void)testGuiDocumentCodecPreservesMultipleVariableDefinitions {
    // TODO: Add a coverage case for "$"-prefixed variable names and expression-valued
    // definevec4/definefloat entries after the parser grows explicit support for them.
    NSString *text =
        @"windowDef Desktop {\n"
         "    definefloat score 0\n"
         "    definevec4 tint 1, 1, 1, 1\n"
         "    definefloat speed 2\n"
         "    text \"Hello\"\n"
         "}\n";

    UDGuiDocumentCodec *codec = [[UDGuiDocumentCodec alloc] init];
    NSError *error = nil;
    UDGuiDocument *document = [codec parseDocumentFromText:text sourceVirtualPath:@"guis/test.gui" error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(document);
    XCTAssertEqual(document.rootWindows.count, 1U);

    UDGuiWindowNode *window = [document.rootWindows objectAtIndex:0];
    XCTAssertEqual(window.variableDefinitions.count, 3U);

    UDGuiVariableDefinition *first = [window.variableDefinitions objectAtIndex:0];
    XCTAssertEqual(first.type, UDGuiVariableDefinitionTypeFloat);
    XCTAssertEqualObjects(first.name, @"score");
    XCTAssertEqualObjects(first.value, @"0");

    UDGuiVariableDefinition *second = [window.variableDefinitions objectAtIndex:1];
    XCTAssertEqual(second.type, UDGuiVariableDefinitionTypeVec4);
    XCTAssertEqualObjects(second.name, @"tint");
    XCTAssertEqualObjects(second.value, @"1, 1, 1, 1");

    UDGuiVariableDefinition *third = [window.variableDefinitions objectAtIndex:2];
    XCTAssertEqual(third.type, UDGuiVariableDefinitionTypeFloat);
    XCTAssertEqualObjects(third.name, @"speed");
    XCTAssertEqualObjects(third.value, @"2");

    NSString *serialized = [codec serializeDocument:document error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(serialized);
    XCTAssertTrue([serialized containsString:@"definefloat score 0"]);
    XCTAssertTrue([serialized containsString:@"definevec4 tint 1, 1, 1, 1"]);
    XCTAssertTrue([serialized containsString:@"definefloat speed 2"]);
}

- (void)testGuiEditorViewModelAddAndDeleteWindow {
    UDGuiDocument *document = [[UDGuiDocument alloc] initWithSourceVirtualPath:@"guis/test.gui"];
    NSUndoManager *undoManager = [[NSUndoManager alloc] init];
    UDGuiEditorService *service = [[UDGuiEditorService alloc] initWithDocument:document undoManager:undoManager];
    UDGuiEditorViewModel *viewModel = [[UDGuiEditorViewModel alloc] initWithService:service];

    UDGuiWindowNode *created = [viewModel addChildWindowToSelectedWindowWithClassName:@"windowDef" name:@"Desktop"];
    XCTAssertNotNil(created);
    XCTAssertEqual(viewModel.rootWindows.count, 1U);

    [viewModel deleteSelectedWindow];
    XCTAssertEqual(viewModel.rootWindows.count, 0U);

    [undoManager undo];
    XCTAssertEqual(viewModel.rootWindows.count, 1U);
}

@end
