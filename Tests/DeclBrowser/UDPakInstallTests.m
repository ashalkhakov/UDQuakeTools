#import "UDDeclBrowserTestCase.h"

#import "UDDeclManagedObjects.h"
#import "UDEditorTabManager.h"
#import "UDPDAEditorViewController.h"
#import "UDTextEditorViewController.h"
#import "UDWorkspace.h"
#import "UDWorkspaceDocument.h"
#import "UDBaseDocument.h"
#import "UDZipWriter.h"
#import "idDeclManager.h"
#import <UDCodeKit/UDCodeKit.h>

// A made-up idTech 4 game, laid out the way a retail install is: base/ with
// numbered pk4s holding the decl folders the decl manager scans. Everything
// in it is written for these tests.

static NSString *const UDHollisPDA =
    @"pda udfix_hollis {\n"
     "\tname\t\t\"Mara Hollis\"\n"
     "\tfullname\t\"Mara J. Hollis\"\n"
     "\ticon\t\t\"guis/assets/pda/udfix_portrait\"\n"
     "\tid\t\t\"7310-4C\"\n"
     "\tpost\t\t\"Hydroponics\"\n"
     "\ttitle\t\t\"Botanist\"\n"
     "\tsecurity\t\"Green\"\n"
     "\tpda_email\t\"udfix_hollis_email_1\"\n"
     "\tpda_email\t\"udfix_hollis_email_2\"\n"
     "\tpda_audio\t\"udfix_hollis_audio_1\"\n"
     "}\n\n"
     "email udfix_hollis_email_1 {\n"
     "\tdate\t\"03-02-2151\"\n"
     "\tto\t\"Mara Hollis\"\n"
     "\tfrom\t\"Facilities\"\n"
     "\tsubject\t\"Irrigation schedule\"\n"
     "\ttext {\n"
     "\"The misting cycle in hydroponic bay seven moves to the night shift.\"\n"
     "\t}\n"
     "}\n\n"
     "email udfix_hollis_email_2 {\n"
     "\tdate\t\"03-04-2151\"\n"
     "\tto\t\"Mara Hollis\"\n"
     "\tfrom\t\"Dr. Okafor\"\n"
     "\tsubject\t\"Seed vault\"\n"
     "\ttext {\n"
     "\"Please inventory the seed vault before Friday.\"\n"
     "\t}\n"
     "}\n\n"
     "audio udfix_hollis_audio_1 {\n"
     "\taudio\t\"pdas/udfix/hollis_log1\"\n"
     "\tname\t\"Growth Notes\"\n"
     "\tinfo\t\"Day forty of the trial crop.\"\n"
     "}\n";

static NSString *const UDOrtegaPDA =
    @"pda udfix_ortega {\n"
     "\tname\t\t\"Luis Ortega\"\n"
     "\tfullname\t\"Luis M. Ortega\"\n"
     "\ticon\t\t\"guis/assets/pda/udfix_portrait\"\n"
     "\tid\t\t\"5528-1A\"\n"
     "\tpost\t\t\"Monorail Station\"\n"
     "\ttitle\t\t\"Dispatcher\"\n"
     "\tsecurity\t\"\"\n"
     "\tpda_email\t\"udfix_ortega_email_1\"\n"
     "}\n\n"
     "email udfix_ortega_email_1 {\n"
     "\tdate\t\"02-27-2151\"\n"
     "\tto\t\"Luis Ortega\"\n"
     "\tfrom\t\"Transit Control\"\n"
     "\tsubject\t\"Line closure\"\n"
     "\ttext {\n"
     "\"Line two is closed for track inspection.\"\n"
     "\t}\n"
     "}\n";

static NSString *const UDWallsMaterialsV1 =
    @"textures/udfix/panel_a\n"
     "{\n"
     "\tqer_editorimage\ttextures/udfix/panel_a_ed\n"
     "\tdiffusemap\t\ttextures/udfix/panel_a_d\n"
     "\tbumpmap\t\t\ttextures/udfix/panel_a_local\n"
     "}\n\n"
     "textures/udfix/panel_b\n"
     "{\n"
     "\tdiffusemap\t\ttextures/udfix/panel_b_d\n"
     "}\n";

// pak001 ships the same file again, as a later patch pak would: it wins.
static NSString *const UDWallsMaterialsV2 =
    @"textures/udfix/panel_a\n"
     "{\n"
     "\tqer_editorimage\ttextures/udfix/panel_a_ed\n"
     "\tdiffusemap\t\ttextures/udfix/panel_a_d_v2\n"
     "\tbumpmap\t\t\ttextures/udfix/panel_a_local\n"
     "\tspecularmap\t\ttextures/udfix/panel_a_s\n"
     "}\n\n"
     "textures/udfix/panel_b\n"
     "{\n"
     "\tdiffusemap\t\ttextures/udfix/panel_b_d\n"
     "}\n";

static NSString *const UDLightsMaterials =
    @"table udfix_flicker { { 1, 0.25, 1, 0.75, 1 } }\n\n"
     "lights/udfix/strip\n"
     "{\n"
     "\tlightFalloffImage\tmakeintensity( lights/udfix/strip_falloff )\n"
     "\t{\n"
     "\t\tmap\tlights/udfix/strip\n"
     "\t\trgb\tudfix_flicker[ time ]\n"
     "\t}\n"
     "}\n";

static NSString *const UDSkins =
    @"skin skins/udfix/worker_orange {\n"
     "\tmodels/udfix/worker_body\tmodels/udfix/worker_body_orange\n"
     "}\n";

static NSString *const UDParticles =
    @"particle udfix_steam {\n"
     "\t{\n"
     "\t\tcount\t\t12\n"
     "\t\tmaterial\ttextures/udfix/steam\n"
     "\t\ttime\t\t1.5\n"
     "\t}\n"
     "}\n";

static NSString *const UDTerminalGUI =
    @"windowDef Desktop {\n"
     "\trect\t0, 0, 640, 480\n"
     "\twindowDef Greeting {\n"
     "\t\trect\t40, 40, 560, 40\n"
     "\t\ttext\t\"Terminal online\"\n"
     "\t}\n"
     "}\n";

static NSString *const UDMainScript =
    @"void udfix_main() {\n"
     "\tsys.println( \"udfix\" );\n"
     "}\n";

@interface UDPakInstallTests : UDDeclBrowserTestCase
@property (nonatomic, copy) NSString *installPath;
@property (nonatomic, copy) NSString *savePath;
@property (nonatomic, strong) NSDictionary<NSString *, NSData *> *installSnapshot;
@end

@implementation UDPakInstallTests

- (BOOL)writePak:(NSString *)name entries:(NSArray<NSArray *> *)entries {
    UDZipWriter *writer = [[UDZipWriter alloc] init];
    for (NSArray *entry in entries) {
        NSError *error = nil;
        if (![writer addEntryWithPath:entry[0]
                                 data:[entry[1] dataUsingEncoding:NSUTF8StringEncoding]
                               method:UDZipCompressionMethodAutomatic
                     modificationDate:nil
                                error:&error]) {
            XCTFail(@"could not add %@ to %@: %@", entry[0], name, error);
            return NO;
        }
    }
    NSString *path = [[self.installPath stringByAppendingPathComponent:@"base"] stringByAppendingPathComponent:name];
    NSError *error = nil;
    if (![writer writeToURL:[NSURL fileURLWithPath:path] error:&error]) {
        XCTFail(@"could not write %@: %@", path, error);
        return NO;
    }
    return YES;
}

/// Every file under the install, by relative path, with its bytes.
- (NSDictionary<NSString *, NSData *> *)snapshotOfInstall {
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *relative in [[NSFileManager defaultManager] subpathsAtPath:self.installPath]) {
        NSString *path = [self.installPath stringByAppendingPathComponent:relative];
        BOOL isDirectory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
            snapshot[relative] = [NSData dataWithContentsOfFile:path];
        }
    }
    return snapshot;
}

- (void)setUp {
    [super setUp];
    self.installPath = [self.scratchDirectory stringByAppendingPathComponent:@"install"];
    self.savePath = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    for (NSString *directory in @[[self.installPath stringByAppendingPathComponent:@"base"], self.savePath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
                                                   attributes:nil error:NULL];
    }

    [self writePak:@"pak000.pk4" entries:@[
        @[@"newpdas/udfix_hollis.pda", UDHollisPDA],
        @[@"newpdas/udfix_ortega.pda", UDOrtegaPDA],
        @[@"materials/udfix_walls.mtr", UDWallsMaterialsV1],
        @[@"materials/udfix_lights.mtr", UDLightsMaterials],
        @[@"particles/udfix.prt", UDParticles],
        @[@"guis/udfix_terminal.gui", UDTerminalGUI],
        @[@"script/udfix_main.script", UDMainScript],
    ]];
    [self writePak:@"pak001.pk4" entries:@[
        @[@"materials/udfix_walls.mtr", UDWallsMaterialsV2],
        @[@"skins/udfix.skin", UDSkins],
    ]];
    self.installSnapshot = [self snapshotOfInstall];
}

- (void)tearDown {
    // Before super's, which removes the scratch directory the install is in.
    XCTAssertEqualObjects([self snapshotOfInstall], self.installSnapshot,
                          @"the install must come out byte for byte as it went in");
    [super tearDown];
}

- (UDWorkspaceWindowController *)openInstall {
    return [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:self.installPath
                                                                      savePath:self.savePath]];
}

#pragma mark - Browsing

- (void)testTheOutlineListsTheDeclsInsideThePaks {
    UDWorkspaceWindowController *controller = [self openInstall];
    if (controller == nil) return;

    NSArray<NSString *> *paths = [self expandedOutlinePathsInController:controller];
    for (NSString *path in @[@"pda/udfix_hollis", @"pda/udfix_ortega",
                             @"email/udfix_hollis_email_1", @"email/udfix_hollis_email_2", @"email/udfix_ortega_email_1",
                             @"audio/udfix_hollis_audio_1",
                             @"material/textures/udfix/panel_a", @"material/textures/udfix/panel_b",
                             @"material/lights/udfix/strip", @"table/udfix_flicker",
                             @"skin/skins/udfix/worker_orange", @"particle/udfix_steam"]) {
        XCTAssertTrue([paths containsObject:path], @"the outline should list %@; it has %@", path, paths);
    }
    BOOL hasGUI = NO, hasScript = NO;
    for (NSString *path in paths) {
        hasGUI = hasGUI || ([path hasPrefix:@"guis/"] && [path containsString:@"udfix_terminal"]);
        hasScript = hasScript || ([path hasPrefix:@"script/"] && [path containsString:@"udfix_main"]);
    }
    XCTAssertTrue(hasGUI, @"the GUI in pak000 should be listed under guis: %@", paths);
    XCTAssertTrue(hasScript, @"the script in pak000 should be listed under script: %@", paths);

    // Each decl is listed once, though its file is in both paks.
    NSUInteger panels = [[paths filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"SELF == 'material/textures/udfix/panel_a'"]] count];
    XCTAssertEqual(panels, 1U, @"panel_a should be listed once");
}

- (void)testALaterPakOverridesAnEarlierOne {
    UDWorkspaceWindowController *controller = [self openInstall];
    if (controller == nil) return;

    UDBaseEditorViewController *editor = [self openOutlinePath:@"material/textures/udfix/panel_a" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDTextEditorViewController class]], @"a material opens in the text editor, not %@", editor);
    NSString *text = [[self firstSubviewOfClass:[NSTextView class] inView:editor.view] string];
    XCTAssertTrue([text containsString:@"panel_a_d_v2"], @"pak001's version of the material should win:\n%@", text);
    XCTAssertTrue([text containsString:@"specularmap"], @"%@", text);
}

- (void)testTheNameFilterNarrowsTheOutline {
    UDWorkspaceWindowController *controller = [self openInstall];
    if (controller == nil) return;

    NSUInteger everything = [self expandedOutlinePathsInController:controller].count;

    controller.nameFilterField.stringValue = @"*hollis*";
    [controller nameFilterChanged:controller.nameFilterField];
    NSArray<NSString *> *filtered = [self expandedOutlinePathsInController:controller];

    NSArray *expected = @[@"pda/udfix_hollis", @"email/udfix_hollis_email_1",
                          @"email/udfix_hollis_email_2", @"audio/udfix_hollis_audio_1"];
    for (NSString *path in expected) {
        XCTAssertTrue([filtered containsObject:path], @"%@ should survive the filter: %@", path, filtered);
    }
    for (NSString *path in filtered) {
        BOOL isGroup = ![path containsString:@"/"];
        XCTAssertTrue(isGroup || [path containsString:@"hollis"], @"%@ does not match *hollis*", path);
    }

    controller.nameFilterField.stringValue = @"";
    [controller nameFilterChanged:controller.nameFilterField];
    XCTAssertEqual([self expandedOutlinePathsInController:controller].count, everything,
                   @"clearing the filter should bring every row back");
}

- (void)testTheTextSearchFindsDeclsByContent {
    UDWorkspaceWindowController *controller = [self openInstall];
    if (controller == nil) return;

    controller.textFilterField.stringValue = @"hydroponic bay seven";
    [controller textContainsFilterChanged:controller.textFilterField];

    NSOutlineView *results = controller.searchOutlineView;
    [results expandItem:nil expandChildren:YES];
    NSMutableArray *names = [NSMutableArray array];
    for (NSInteger row = 0; row < results.numberOfRows; row++) {
        [names addObject:[results.dataSource outlineView:results
                               objectValueForTableColumn:results.tableColumns.firstObject
                                                  byItem:[results itemAtRow:row]]];
    }
    XCTAssertTrue([names containsObject:@"email/udfix_hollis_email_1"], @"the email with that text should be found: %@", names);
    XCTAssertFalse([names containsObject:@"email/udfix_hollis_email_2"], @"the other email does not have it: %@", names);
    XCTAssertFalse([names containsObject:@"email/udfix_ortega_email_1"], @"%@", names);
}

- (void)testAPDAInsideAPakOpensInThePDAEditor {
    UDWorkspaceWindowController *controller = [self openInstall];
    if (controller == nil) return;

    UDPDAEditorViewController *editor = [self openOutlinePath:@"pda/udfix_hollis" inController:controller];
    if (![editor isKindOfClass:[UDPDAEditorViewController class]]) {
        XCTFail(@"a pda decl should open in the PDA editor, not %@", editor);
        return;
    }
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:editor.view].stringValue, @"Mara J. Hollis");
    XCTAssertEqualObjects([self textFieldBoundTo:@"pdaName" inView:editor.view].stringValue, @"Mara Hollis");
    XCTAssertEqualObjects([self textFieldBoundTo:@"ident" inView:editor.view].stringValue, @"7310-4C");
    XCTAssertEqualObjects([self textFieldBoundTo:@"post" inView:editor.view].stringValue, @"Hydroponics");
    XCTAssertEqualObjects([self textFieldBoundTo:@"security" inView:editor.view].stringValue, @"Green");

    NSArray *subjects = [editor.emailArrayController.arrangedObjects valueForKey:@"subject"];
    XCTAssertEqualObjects([NSSet setWithArray:subjects], ([NSSet setWithObjects:@"Irrigation schedule", @"Seed vault", nil]));
    XCTAssertEqualObjects([editor.audioArrayController.arrangedObjects valueForKey:@"audioName"], @[@"Growth Notes"]);

    // Re-selecting the same decl re-uses its tab; another PDA gets its own.
    NSUInteger tabs = [[self tabManagerOf:controller] allEditors].count;
    [self openOutlinePath:@"pda/udfix_hollis" inController:controller];
    XCTAssertEqual([[self tabManagerOf:controller] allEditors].count, tabs, @"re-selecting a decl should not open a second tab");
    UDPDAEditorViewController *other = [self openOutlinePath:@"pda/udfix_ortega" inController:controller];
    XCTAssertEqual([[self tabManagerOf:controller] allEditors].count, tabs + 1);
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:other.view].stringValue, @"Luis M. Ortega");
}

/// The highlight class UDCodeKit gave the first occurrence of @a word, once
/// the highlighting has caught up; nil when it has none.
- (nullable NSString *)highlightOf:(NSString *)word inTextView:(NSTextView *)textView {
    if (![textView.textStorage isKindOfClass:[UDTextModelTextStorage class]]) return nil;
    UDTextModel *model = ((UDTextModelTextStorage *)textView.textStorage).textModel;
    NSRange range = [textView.string rangeOfString:word];
    if (range.location == NSNotFound) return nil;
    __block NSString *found = nil;
    [self spinUntil:^BOOL{
        for (UDIntervalNode *node in [model decorationNodesInOffsetRange:(NSInteger)range.location
                                                                     end:(NSInteger)NSMaxRange(range)]) {
            if ([node.owner isEqualToString:UDHighlightDecorationOwner]
                && node.start == (NSInteger)range.location && node.end == (NSInteger)NSMaxRange(range)) {
                found = node.options.className;
            }
        }
        return found != nil;
    } timeout:2.0];
    return found;
}

- (void)testScriptsAndGUIsInsideThePaksOpenAndSave {
    UDWorkspaceWindowController *controller = [self openInstall];
    if (controller == nil) return;

    UDBaseEditorViewController *gui = [self openOutlinePath:@"guis/udfix_terminal.gui" inController:controller];
    XCTAssertTrue([gui isKindOfClass:[UDTextEditorViewController class]], @"a GUI opens in the text editor, not %@", gui);
    XCTAssertTrue([[[self firstSubviewOfClass:[NSTextView class] inView:gui.view] string] containsString:@"windowDef Desktop"],
                  @"the GUI's text should be shown");

    UDBaseEditorViewController *script = [self openOutlinePath:@"script/udfix_main.script" inController:controller];
    XCTAssertTrue([script isKindOfClass:[UDTextEditorViewController class]], @"a script opens in the text editor, not %@", script);
    NSTextView *textView = [self firstSubviewOfClass:[NSTextView class] inView:script.view];
    XCTAssertTrue([textView.string containsString:@"void udfix_main()"], @"the script's text should be shown:\n%@", textView.string);
    XCTAssertEqualObjects([self highlightOf:@"void" inTextView:textView], @"type.builtin",
                          @"a script is highlighted as idScript");
    XCTAssertNil([self highlightOf:@"windowDef" inTextView:[self firstSubviewOfClass:[NSTextView class] inView:gui.view]],
                 @"a GUI's text stays plain");

    [self typeText:@"void udfix_main() {\n\tsys.println( \"edited\" );\n}\n" intoTextView:textView];
    [self finishEvent];
    XCTAssertTrue(script.editorDocument.isDocumentEdited, @"typing should dirty the tab");
    [NSApp sendAction:@selector(saveDocument:) to:controller from:nil];
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];

    NSString *saved = [NSString stringWithContentsOfFile:[self.savePath stringByAppendingPathComponent:@"base/script/udfix_main.script"]
                                                encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertTrue([saved containsString:@"\"edited\""], @"saving should write the script under fs_savepath: %@", saved);
}

#pragma mark - Editing

- (void)testEditingAPDAInsideAPakSavesAnOverrideOutsideThePaks {
    UDWorkspaceWindowController *controller = [self openInstall];
    if (controller == nil) return;

    UDPDAEditorViewController *editor = [self openOutlinePath:@"pda/udfix_hollis" inController:controller];
    if (![editor isKindOfClass:[UDPDAEditorViewController class]]) {
        XCTFail(@"a pda decl should open in the PDA editor, not %@", editor);
        return;
    }

    [self typeText:@"Mara K. Hollis" intoField:[self textFieldBoundTo:@"fullName" inView:editor.view]];
    [self typeText:@"Blue" intoField:[self textFieldBoundTo:@"security" inView:editor.view]];
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    [NSApp sendAction:@selector(saveDocument:) to:controller from:nil];
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];
    XCTAssertFalse(editor.editorDocument.isDocumentEdited, @"Save should leave the tab clean");

    // The PDA came out of pak000.pk4, so the save lands under fs_savepath
    // as a loose file the game loads ahead of the paks.
    NSString *override = [self.savePath stringByAppendingPathComponent:@"base/newpdas/udfix_hollis.pda"];
    NSString *text = [NSString stringWithContentsOfFile:override encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertNotNil(text, @"saving should write %@; the save path holds %@", override,
                    [[NSFileManager defaultManager] subpathsAtPath:self.savePath]);
    XCTAssertTrue([text containsString:@"Mara K. Hollis"], @"%@", text);
    XCTAssertTrue([text containsString:@"Blue"], @"%@", text);
    XCTAssertFalse([text containsString:@"Mara J. Hollis"], @"%@", text);
    for (NSString *child in @[@"udfix_hollis_email_1", @"udfix_hollis_email_2", @"udfix_hollis_audio_1",
                              @"Irrigation schedule", @"Growth Notes"]) {
        XCTAssertTrue([text containsString:child], @"the override must keep %@:\n%@", child, text);
    }
    XCTAssertNil([[NSFileManager defaultManager] subpathsAtPath:
                     [self.savePath stringByAppendingPathComponent:@"base/newpdas/udfix_ortega.pda"]],
                 @"the PDA that was not edited must not be written");

    // A fresh workspace over the same install and save path sees the edit,
    // and still reads the untouched PDA from the pak.
    [self closeWorkspace:controller];
    UDWorkspaceWindowController *reopened = [self openInstall];
    UDPDAEditorViewController *again = [self openOutlinePath:@"pda/udfix_hollis" inController:reopened];
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:again.view].stringValue, @"Mara K. Hollis");
    XCTAssertEqualObjects([self textFieldBoundTo:@"security" inView:again.view].stringValue, @"Blue");
    XCTAssertEqual([again.emailArrayController.arrangedObjects count], 2U, @"the emails come back with the PDA");
    UDPDAEditorViewController *ortega = [self openOutlinePath:@"pda/udfix_ortega" inController:reopened];
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:ortega.view].stringValue, @"Luis M. Ortega");
}

@end
