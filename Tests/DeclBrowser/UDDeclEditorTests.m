#import "UDDeclBrowserTestCase.h"

#import "UDDeclDocument.h"
#import "UDEditorTabManager.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDNewDeclWindowController.h"
#import "UDTextEditorViewController.h"
#import "UDEntityDefEditorViewController.h"
#import "UDSoundEditorViewController.h"
#import "UDParticleEditorViewController.h"
#import "UDFXEditorViewController.h"
#import "UDAFEditorViewController.h"
#import "UDMaterialEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspaceWindowController.h"

static NSString *const UDFixtureDefs =
    @"entityDef udtest_fixture {\n"
     "\t\"editor_usage\"\t\t\"Something fixed to a wall.\"\n"
     "\t\"editor_var model\"\t\"The model it shows.\"\n"
     "\t\"editor_bool solid\"\t\"Whether it blocks.\"\n"
     "\t\"solid\"\t\t\t\"1\"\n"
     "\t\"spawnclass\"\t\t\"idStaticEntity\"\n"
     "}\n"
     "\n"
     "entityDef udtest_lamp {\n"
     "\t\"inherit\"\t\"udtest_fixture\"\n"
     "\t\"model\"\t\"models/udtest/lamp.lwo\"\n"
     "}\n"
     "\n"
     "mapDef udtest/yard {\n"
     "\t\"name\"\t\"Yard\"\n"
     "}\n";

static NSString *const UDFixtureFX =
    @"fx fx/udtest_spark {\n"
     "\t{\n"
     "\t\tname\t\"spark\"\n"
     "\t\tduration\t0.5\n"
     "\t\tlight\t\"lights/udtest_missing\", 1, 0.5, 0, 64\n"
     "\t}\n"
     "\t{\n"
     "\t\tdelay\t0.1\n"
     "\t\tuseLight\t\"spark\"\n"
     "\t\tfadeOut\t0.2\n"
     "\t}\n"
     "\t{\n"
     "\t\tduration\t1\n"
     "\t\tparticle\t\"udtest_missing.prt\"\n"
     "\t}\n"
     "}\n";

// A crate with a lid: its mesh's joints only, and the modelDef that gives it.
static NSString *const UDFixtureCrateMesh =
    @"MD5Version 10\n"
     "commandline \"\"\n"
     "numJoints 2\n"
     "numMeshes 0\n"
     "joints {\n"
     "\t\"origin\"\t-1 ( 0 0 0 ) ( 0 0 0 )\n"
     "\t\"Lid\"\t0 ( 0 0 16 ) ( 0 0 0 )\n"
     "}\n";

static NSString *const UDFixtureCrateDef =
    @"model udtest_crate {\n"
     "\t// the crate\n"
     "\tskin\t\"skins/udtest/crate\"\n"
     "\tmesh\tmodels/udtest/crate.md5mesh\n"
     "}\n";

static NSString *const UDFixtureAF =
    @"articulatedFigure udtest_crate {\n"
     "settings {\n\tmodel \"udtest_crate\"\n\ttotalMass 40\n}\n"
     "body \"crate\" {\n\tjoint \"origin\"\n\tmodel box( ( -8, -8, 0 ), ( 8, 8, 16 ) )\n}\n"
     "body \"lid\" {\n\tjoint \"lid\"\n\tmodel box( ( -8, -8, 16 ), ( 8, 8, 18 ) )\n}\n"
     "body \"latch\" {\n\tjoint \"latch\"\n\tmodel box( ( 7, -1, 14 ), ( 8, 1, 16 ) )\n}\n"
     "hinge \"hinge\" {\n\tbody1 \"lid\"\n\tbody2 \"crate\"\n\tanchor ( -8, 0, 16 )\n\taxis ( 0, 1, 0 )\n}\n"
     "fixed \"strap\" {\n\tbody1 \"latch\"\n\tbody2 \"post\"\n}\n"
     "}\n";

static NSString *const UDFixtureMaterials =
    @"textures/udtest/glow\n"
     "{\n"
     "\t// glows\n"
     "\tdescription\t\"Glow\"\n"
     "\t{\n"
     "\t\tblend\tadd\n"
     "\t\tmap\ttextures/udtest/glow.tga\n"
     "\t}\n"
     "}\n"
     "\n"
     "textures/udtest/lost\n"
     "{\n"
     "\t{\n"
     "\t\tblend\tadd\n"
     "\t\tmap\ttextures/udtest/missing\n"
     "\t}\n"
     "}\n";

static NSString *const UDFixtureSounds =
    @"udtest_hum {\n"
     "\tdescription\t\"Low hum\"\n"
     "\tminDistance\t1\n"
     "\tmaxDistance\t12\n"
     "\tsound/udtest/hum.wav\n"
     "\tsound/udtest/gone.wav\n"
     "}\n"
     "\n"
     "udtest_broken {\n"
     "\tminDistance\t1\n"
     "\twobble\n"
     "}\n";

static NSString *const UDFixtureParticles =
    @"particle udtest_spark {\n"
     "\tdepthHack\t0.001\n"
     "\t{\n"
     "\t\tcount\t\t4\n"
     "\t\tmaterial\ttextures/udtest/spark\n"
     "\t}\n"
     "}\n";

/**
 * The decl editor, MFC's DialogDeclEditor and DialogDeclNew, driven against
 * loose decl files written for the test (no game data).
 */
@interface UDDeclEditorTests : UDDeclBrowserTestCase
@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, copy) NSString *savePath;
@end

@implementation UDDeclEditorTests

- (void)setUp {
    [super setUp];
    self.basePath = [self.scratchDirectory stringByAppendingPathComponent:@"install"];
    self.savePath = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *folder in @[@"base/def", @"base/sound/udtest", @"base/particles", @"base/fx", @"base/materials",
                               @"base/af", @"base/models/udtest",
                               @"base/textures/udtest"]) {
        [files createDirectoryAtPath:[self.basePath stringByAppendingPathComponent:folder]
         withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    [files createDirectoryAtPath:self.savePath withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDFixtureDefs writeToFile:[self.basePath stringByAppendingPathComponent:@"base/def/udtest.def"]
                    atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureParticles writeToFile:[self.basePath stringByAppendingPathComponent:@"base/particles/udtest.prt"]
                         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureMaterials writeToFile:[self.basePath stringByAppendingPathComponent:@"base/materials/udtest.mtr"]
                         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureFX writeToFile:[self.basePath stringByAppendingPathComponent:@"base/fx/udtest.fx"]
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureCrateMesh writeToFile:[self.basePath stringByAppendingPathComponent:@"base/models/udtest/crate.md5mesh"]
                         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureCrateDef writeToFile:[self.basePath stringByAppendingPathComponent:@"base/def/udtest_crate.def"]
                        atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureAF writeToFile:[self.basePath stringByAppendingPathComponent:@"base/af/udtest.af"]
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    // The glow's image: a 2 × 2 TGA, red over green.
    uint8_t tga[18 + 2 * 2 * 3] = { 0, 0, 2 };
    tga[12] = 2; tga[14] = 2; tga[16] = 24;
    const uint8_t green[3] = { 0, 255, 0 }, red[3] = { 0, 0, 255 };   // BGR, the bottom row first
    memcpy(tga + 18, green, 3); memcpy(tga + 21, green, 3); memcpy(tga + 24, red, 3); memcpy(tga + 27, red, 3);
    [[NSData dataWithBytes:tga length:sizeof(tga)] writeToFile:[self.basePath stringByAppendingPathComponent:@"base/textures/udtest/glow.tga"]
                                                    atomically:YES];
    // One of its samples, as an .ogg: the engine finds it by the .wav's name.
    [@"" writeToFile:[self.basePath stringByAppendingPathComponent:@"base/sound/udtest/hum.ogg"]
          atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureSounds writeToFile:[self.basePath stringByAppendingPathComponent:@"base/sound/udtest.sndshd"]
                      atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (UDWorkspaceWindowController *)openFixtureWorkspace {
    return [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:self.basePath savePath:self.savePath]];
}

- (NSString *)savedText:(NSString *)relativePath {
    NSString *text = [NSString stringWithContentsOfFile:[self.savePath stringByAppendingPathComponent:[@"base" stringByAppendingPathComponent:relativePath]]
                                               encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertNotNil(text, @"%@ is written", relativePath);
    return text ?: @"";
}

- (void)save:(UDWorkspaceWindowController *)controller {
    [NSApp sendAction:@selector(saveDocument:) to:controller from:nil];
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];
}

/// File > New Declaration…, filled in as given; nil for what is left as it is.
- (void)newDeclOfType:(NSString *)typeName name:(NSString *)name file:(nullable NSString *)file
         inController:(UDWorkspaceWindowController *)controller
         defaultFile:(NSString *_Nullable *_Nullable)defaultFile {
    __block BOOL asked = NO;
    __block NSString *shownFile = nil;
    [self whenModalWindowAppears:^(NSWindow *window) {
        asked = YES;
        NSPopUpButton *type = [self viewWithToolTip:@"type" inView:window.contentView];
        XCTAssertTrue([type.itemTitles containsObject:@"entityDef"], @"every type: %@", type.itemTitles);
        NSInteger index = [type indexOfItemWithTitle:typeName];
        [type.menu performActionForItemAtIndex:index];
        XCTAssertEqualObjects(((UDNewDeclWindowController *)window.windowController).typeName, typeName,
                              @"choosing the type is the dialog's");
        [self typeText:name intoField:[self viewWithToolTip:@"name" inView:window.contentView]];
        NSTextField *fileField = [self viewWithToolTip:@"file" inView:window.contentView];
        shownFile = fileField.stringValue;
        if (file != nil) [self typeText:file intoField:fileField];
        [[self buttonTitled:@"Create" inView:window.contentView] performClick:nil];
    }];
    [NSApp sendAction:@selector(newDecl:) to:controller from:nil];
    XCTAssertTrue(asked, @"New Declaration asks for its type, name and file");
    if (defaultFile != NULL) *defaultFile = shownFile;
}

#pragma mark - New Declaration (DialogDeclNew)

- (void)testANewDeclStartsAsItsTypesDefaultInItsFolder {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    NSString *shownFile = nil;
    [self newDeclOfType:@"entityDef" name:@"udtest_fresh" file:nil inController:controller defaultFile:&shownFile];
    XCTAssertEqualObjects(shownFile, @"def/udtest_fresh.def", @"the file follows the type's folder and the name");

    UDBaseEditorViewController *editor = [[self tabManagerOf:controller] selectedEditor];
    XCTAssertTrue([editor isKindOfClass:[UDEntityDefEditorViewController class]], @"it opens in its editor, not %@", editor);
    UDDeclEntityDef *entityDef = ((UDEntityDefEditorViewController *)editor).entityDef;
    XCTAssertEqualObjects([entityDef.keyValues valueForKey:@"key"], (@[@"DEFAULTED"]), @"idDeclEntityDef's default definition");

    [self save:controller];
    NSString *saved = [self savedText:@"def/udtest_fresh.def"];
    XCTAssertTrue([saved containsString:@"entityDef udtest_fresh"], @"%@", saved);
    XCTAssertTrue([saved containsString:@"\"DEFAULTED\""], @"%@", saved);
}

- (void)testANewDeclGoesInTheFileItIsGiven {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    [self newDeclOfType:@"sound" name:@"udtest_buzz" file:@"sound/udtest.sndshd" inController:controller defaultFile:NULL];
    [self save:controller];

    NSString *saved = [self savedText:@"sound/udtest.sndshd"];
    XCTAssertTrue([saved containsString:@"udtest_hum"], @"the file's decls stay: %@", saved);
    XCTAssertTrue([saved containsString:@"sound udtest_buzz"], @"%@", saved);
    XCTAssertTrue([saved containsString:@"_default.wav"], @"idSoundShader's default definition: %@", saved);
}

- (void)testCancellingNewDeclarationCreatesNothing {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    [self whenModalWindowAppears:^(NSWindow *window) {
        [[self buttonTitled:@"Cancel" inView:window.contentView] performClick:nil];
    }];
    [NSApp sendAction:@selector(newDecl:) to:controller from:nil];
    XCTAssertEqual([[self tabManagerOf:controller] allEditors].count, 0U);
}

#pragma mark - The decl's text (DialogDeclEditor)

- (nullable NSColor *)colorOf:(NSString *)word inTextView:(NSTextView *)textView {
    NSRange range = [textView.string rangeOfString:word];
    if (range.location == NSNotFound) return nil;
    return [textView.textStorage attribute:NSForegroundColorAttributeName atIndex:range.location effectiveRange:NULL];
}

- (void)testADeclIsHighlightedAsADecl {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    UDTextEditorViewController *editor = [self openOutlinePath:@"model/udtest_crate" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDTextEditorViewController class]], @"a modelDef opens as text, not %@", editor);
    NSTextView *textView = [editor valueForKeyPath:@"editor.textView"];

    // Its comments and strings, each in a colour of their own.
    BOOL highlighted = [self spinUntil:^BOOL{
        NSColor *comment = [self colorOf:@"// the crate" inTextView:textView];
        NSColor *string = [self colorOf:@"\"skins/udtest/crate\"" inTextView:textView];
        return comment != nil && string != nil && ![comment isEqual:string] &&
               ![comment isEqual:textView.textColor] && ![string isEqual:textView.textColor];
    } timeout:5.0];
    XCTAssertTrue(highlighted, @"the decl grammar colours the decl: comment %@, string %@, text %@",
                  [self colorOf:@"// the crate" inTextView:textView], [self colorOf:@"\"skins/udtest/crate\"" inTextView:textView],
                  textView.textColor);
}

- (NSArray<UDDiagnosticItem *> *)testFindingsOf:(UDTextEditorViewController *)editor {
    return [editor.diagnosticStore.allDiagnostics filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"source == 'test'"]];
}

- (void)testTestReportsWhatTheLexerSays {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    UDTextEditorViewController *editor = [self openOutlinePath:@"model/udtest_crate" inController:controller];
    NSTextView *textView = [editor valueForKeyPath:@"editor.textView"];
    XCTAssertEqual([self testFindingsOf:editor].count, 0U);

    // A string left open, typed above its blend.
    NSRange duration = [textView.string rangeOfString:@"\tmesh"];
    NSInteger line = [[textView.string substringToIndex:duration.location] componentsSeparatedByString:@"\n"].count;
    [textView setSelectedRange:NSMakeRange(duration.location, 0)];
    [textView insertText:@"\t\tname\t\"oops\n"];
    [NSApp sendAction:@selector(testDecl:) to:controller from:nil];
    // The lexer's error, at its line (and the braces it leaves open after it).
    NSArray<UDDiagnosticItem *> *findings = [[self testFindingsOf:editor] filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"message CONTAINS 'newline inside string'"]];
    XCTAssertEqual(findings.count, 1U, @"the lexer's error: %@", [self testFindingsOf:editor]);
    XCTAssertEqual(findings.firstObject.line, line, @"on the line it is about");

    [textView insertText:@" "];
    XCTAssertEqual([self testFindingsOf:editor].count, 0U, @"an edit takes what a Test found away");
}

- (void)testTestFindsABraceNeverClosed {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    UDTextEditorViewController *editor = [self openOutlinePath:@"model/udtest_crate" inController:controller];
    NSTextView *textView = [editor valueForKeyPath:@"editor.textView"];
    NSRange last = [textView.string rangeOfString:@"}" options:NSBackwardsSearch];
    [textView setSelectedRange:last];
    [textView insertText:@""];
    [NSApp sendAction:@selector(testDecl:) to:controller from:nil];
    NSArray<UDDiagnosticItem *> *findings = [self testFindingsOf:editor];
    XCTAssertEqual(findings.count, 1U, @"the brace: %@", findings);
    XCTAssertEqual(findings.firstObject.line, 1, @"where it opened");
    XCTAssertEqual(findings.firstObject.severity, UDDiagnosticSeverityError);
}

#pragma mark - The entityDef editor (DialogEntityDefEditor)

- (UDEntityDefEditorViewController *)openLampIn:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:@"entityDef/udtest_lamp" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDEntityDefEditorViewController class]], @"an entityDef opens in its editor, not %@", editor);
    return [editor isKindOfClass:[UDEntityDefEditorViewController class]] ? (UDEntityDefEditorViewController *)editor : nil;
}

- (void)testAnEntityDefOpensWithItsOwnAndInheritedPairs {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDEntityDefEditorViewController *editor = [self openLampIn:controller];
    if (editor == nil) return;

    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"inherit" inView:editor.view]).stringValue, @"udtest_fixture");
    XCTAssertEqualObjects([editor.keyValuesController.arrangedObjects valueForKey:@"key"], (@[@"model"]),
                          @"its own pairs, inherit in its field");
    XCTAssertEqual(editor.keyValuesTable.numberOfRows, 1);
    NSArray *inheritedKeys = [editor.inheritedController.arrangedObjects valueForKey:@"key"];
    XCTAssertTrue([inheritedKeys containsObject:@"solid"], @"%@", inheritedKeys);
    XCTAssertTrue([inheritedKeys containsObject:@"spawnclass"], @"%@", inheritedKeys);
    XCTAssertFalse([inheritedKeys containsObject:@"model"], @"what it sets is not inherited");
    XCTAssertEqualObjects([[editor.inheritedController.arrangedObjects firstObject] valueForKey:@"from"], @"udtest_fixture");
    XCTAssertEqualObjects(editor.usage, @"Something fixed to a wall.", @"editor_usage, inherited");

    [editor.keyValuesController setSelectionIndex:0];
    XCTAssertEqualObjects(editor.selectedKeyHelp, @"model: The model it shows.", @"editor_var model");
    XCTAssertEqual(editor.diagnosticStore.allDiagnostics.count, 0U);
}

- (void)testEditingAnEntityDefsPairsSavesThem {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDEntityDefEditorViewController *editor = [self openLampIn:controller];
    if (editor == nil) return;

    UDEntityKeyValue *model = [editor.keyValuesController.arrangedObjects firstObject];
    NSString *value = @"models/udtest/lamp2.lwo";
    XCTAssertTrue([model validateValue:&value forKey:@"value" error:NULL]);
    [model setValue:value forKey:@"value"];
    [editor.editingContext processPendingChanges];
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    [editor.inheritedController setSelectedObjects:[editor.inheritedController.arrangedObjects filteredArrayUsingPredicate:
                                                    [NSPredicate predicateWithFormat:@"key == 'solid'"]]];
    [[self buttonTitled:@"Override" inView:editor.view] performClick:nil];
    [editor.view.window endEditingFor:nil];
    [editor.editingContext processPendingChanges];
    XCTAssertEqualObjects([editor.keyValuesController.arrangedObjects valueForKey:@"key"], (@[@"model", @"solid"]), @"overridden");
    XCTAssertFalse([[editor.inheritedController.arrangedObjects valueForKey:@"key"] containsObject:@"solid"], @"and no longer inherited");

    [self save:controller];
    NSString *saved = [self savedText:@"def/udtest.def"];
    XCTAssertTrue([saved containsString:@"\"model\"\t\t\t\"models/udtest/lamp2.lwo\""], @"%@", saved);
    XCTAssertTrue([saved containsString:@"\"solid\"\t\t\t\"1\""], @"%@", saved);
    XCTAssertTrue([saved containsString:@"\"inherit\"\t\t\t\"udtest_fixture\""], @"%@", saved);
    XCTAssertTrue([saved containsString:@"entityDef udtest_fixture {"], @"the others as they were: %@", saved);

    [editor.keyValuesController setSelectedObjects:@[[editor.keyValuesController.arrangedObjects lastObject]]];
    NSSegmentedControl *buttons = [self segmentedControlWithAction:@selector(addOrRemovePair:) inView:editor.view];
    [buttons setSelectedSegment:1];
    [NSApp sendAction:buttons.action to:buttons.target from:buttons];
    XCTAssertEqualObjects([editor.keyValuesController.arrangedObjects valueForKey:@"key"], (@[@"model"]), @"- takes it off");
}

- (void)testAnUnknownInheritIsAnIssue {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDEntityDefEditorViewController *editor = [self openLampIn:controller];
    if (editor == nil) return;
    editor.entityDef.inherit = @"udtest_nothing";
    [editor.editingContext processPendingChanges];
    NSArray<UDDiagnosticItem *> *issues = editor.diagnosticStore.allDiagnostics;
    XCTAssertEqual(issues.count, 1U, @"%@", issues);
    XCTAssertEqualObjects(issues.firstObject.message, @"Unknown entityDef 'udtest_nothing' inherited by 'udtest_lamp'");
    XCTAssertEqual([editor.inheritedController.arrangedObjects count], 0U);
}

- (void)testAMapDefOpensInTheEntityDefEditor {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDBaseEditorViewController *editor = [self openOutlinePath:@"mapDef/udtest/yard" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDEntityDefEditorViewController class]], @"%@", editor);
    XCTAssertEqualObjects([((UDEntityDefEditorViewController *)editor).keyValuesController.arrangedObjects valueForKey:@"value"], (@[@"Yard"]));
}

#pragma mark - The sound shader editor

- (UDSoundEditorViewController *)openSound:(NSString *)name in:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:[@"sound/" stringByAppendingString:name] inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDSoundEditorViewController class]], @"a sound shader opens in its editor, not %@", editor);
    return [editor isKindOfClass:[UDSoundEditorViewController class]] ? (UDSoundEditorViewController *)editor : nil;
}

- (void)testASoundShaderOpensWithItsParametersAndSamples {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDSoundEditorViewController *editor = [self openSound:@"udtest_hum" in:controller];
    if (editor == nil) return;

    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"soundDescription" inView:editor.view]).stringValue, @"Low hum");
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"maxDistance" inView:editor.view]).stringValue, @"12");
    NSTextField *volume = [self viewWithToolTip:@"volume" inView:editor.view];
    XCTAssertEqualObjects(volume.stringValue, @"", @"what it does not set is empty");
    XCTAssertEqualObjects(volume.placeholderString, @"1", @"the engine's default, as the field's placeholder");
    XCTAssertEqualObjects([editor.samplesController.arrangedObjects valueForKey:@"path"],
                          (@[@"sound/udtest/hum.wav", @"sound/udtest/gone.wav"]));

    NSArray<UDDiagnosticItem *> *issues = editor.diagnosticStore.allDiagnostics;
    XCTAssertEqual(issues.count, 1U, @"hum.wav is there as hum.ogg; gone.wav is not: %@", issues);
    XCTAssertEqualObjects(issues.firstObject.message, @"Couldn't load sound 'sound/udtest/gone.wav' using default");
    [controller errorsViewController:nil didSelectDiagnostic:issues.firstObject inStore:editor.diagnosticStore];
    XCTAssertEqual(editor.samplesController.selectionIndex, 1U, @"a click shows the row");
}

- (void)testEditingASoundShaderSavesIt {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDSoundEditorViewController *editor = [self openSound:@"udtest_hum" in:controller];
    if (editor == nil) return;

    id value = @"-6";
    XCTAssertTrue([editor.sound validateValue:&value forKey:@"volume" error:NULL]);
    editor.sound.volume = value;
    value = @"loud";
    XCTAssertFalse([editor.sound validateValue:&value forKey:@"volume" error:NULL], @"not a number: refused");
    value = @"7";
    XCTAssertFalse([editor.sound validateValue:&value forKey:@"soundClass" error:NULL], @"SOUND_MAX_CLASSES");
    value = @"";
    XCTAssertTrue([editor.sound validateValue:&value forKey:@"maxDistance" error:NULL]);
    editor.sound.maxDistance = value;
    [[self buttonTitled:@"Looping" inView:editor.view] performClick:nil];

    [editor.samplesController setSelectionIndex:1];
    NSSegmentedControl *buttons = [self segmentedControlWithAction:@selector(addOrRemoveSample:) inView:editor.view];
    [buttons setSelectedSegment:1];
    [NSApp sendAction:buttons.action to:buttons.target from:buttons];
    [editor.editingContext processPendingChanges];
    XCTAssertEqual(editor.diagnosticStore.allDiagnostics.count, 0U, @"the missing sample taken off");
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    [self save:controller];
    NSString *saved = [self savedText:@"sound/udtest.sndshd"];
    XCTAssertTrue([saved containsString:@"sound udtest_hum\n{\n\tdescription\t\t\"Low hum\"\n\tminDistance\t\t1\n\tvolume\t\t-6\n\tlooping\n\tsound/udtest/hum.wav\n}"], @"%@", saved);
}

- (void)testWhereTheEngineGivesUpOnAShaderIsAnIssue {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDSoundEditorViewController *editor = [self openSound:@"udtest_broken" in:controller];
    if (editor == nil) return;
    NSArray *messages = [editor.diagnosticStore.allDiagnostics valueForKey:@"message"];
    XCTAssertTrue([messages containsObject:@"unknown token 'wobble'"], @"%@", messages);
}

#pragma mark - The particle editor (DialogParticleEditor)

- (UDParticleEditorViewController *)openSparkIn:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:@"particle/udtest_spark" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDParticleEditorViewController class]], @"a particle opens in its editor, not %@", editor);
    return [editor isKindOfClass:[UDParticleEditorViewController class]] ? (UDParticleEditorViewController *)editor : nil;
}

- (void)testAParticleOpensWithItsStages {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDParticleEditorViewController *editor = [self openSparkIn:controller];
    if (editor == nil) return;

    XCTAssertEqual(editor.stagesTable.numberOfRows, 1);
    NSTableColumn *stageColumn = [editor.stagesTable tableColumnWithIdentifier:@"stage"];
    XCTAssertEqualObjects([editor tableView:editor.stagesTable objectValueForTableColumn:stageColumn row:0], @"stage 0",
                          @"numbered as DialogParticleEditor listed them");
    XCTAssertEqual(editor.stagesController.selectionIndex, 0U, @"its first stage shown");
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"totalParticles" inView:editor.view]).stringValue, @"4");
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"material" inView:editor.view]).stringValue, @"textures/udtest/spark");
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"depthHack" inView:editor.view]).stringValue, @"0.001");
    XCTAssertEqual(((NSSlider *)[self viewWithToolTip:@"totalParticles slider" inView:editor.view]).doubleValue, 4.0, @"its slider too");

    NSArray *messages = [editor.diagnosticStore.allDiagnostics valueForKey:@"message"];
    XCTAssertEqualObjects(messages, (@[@"Stage 0: material “textures/udtest/spark” is neither a decl nor an image: the engine makes it a default material"]));
}

- (void)testEditingAStageIsAnEditOfTheParticle {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDParticleEditorViewController *editor = [self openSparkIn:controller];
    if (editor == nil) return;

    id selection = editor.stagesController.selection;
    id value = @"many";
    XCTAssertFalse([selection validateValue:&value forKey:@"totalParticles" error:NULL], @"not a number: refused");
    value = @"8";
    XCTAssertTrue([selection validateValue:&value forKey:@"totalParticles" error:NULL]);
    [selection setValue:value forKey:@"totalParticles"];
    [editor.editingContext processPendingChanges];
    XCTAssertEqual(editor.particle.stages.firstObject.totalParticles, 8);
    XCTAssertTrue(editor.editorDocument.isDocumentEdited, @"the particle is edited");
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"totalParticles" inView:editor.view]).stringValue, @"8");

    [editor.editorDocument.undoManager undo];
    XCTAssertEqual(editor.particle.stages.firstObject.totalParticles, 4, @"and undone");
    [editor.editorDocument.undoManager redo];

    NSSegmentedControl *buttons = [self segmentedControlWithAction:@selector(addOrRemoveStage:) inView:editor.view];
    [buttons setSelectedSegment:0];
    [NSApp sendAction:buttons.action to:buttons.target from:buttons];
    XCTAssertEqual(editor.particle.stages.count, 2U);
    XCTAssertEqual(editor.stagesTable.numberOfRows, 2);
    XCTAssertEqual(editor.stagesController.selectionIndex, 1U, @"the new stage shown");
    XCTAssertEqual(editor.particle.stages[1].totalParticles, 100, @"idParticleStage::Default's");

    [self save:controller];
    NSString *saved = [self savedText:@"particles/udtest.prt"];
    XCTAssertTrue([saved containsString:@"particle udtest_spark {\n\tdepthHack\t0.001000\n\t{\n\t\tcount\t\t\t\t8\n\t\tmaterial\t\t\ttextures/udtest/spark\n"],
                  @"as idDeclParticle::WriteStage writes it: %@", saved);
    XCTAssertTrue([saved containsString:@"\t\tcount\t\t\t\t100\n\t\tmaterial\t\t\t_default\n"], @"%@", saved);
}

- (void)testTheDepthHackStaysUnderTheStagesAsTheEditorResizes {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDParticleEditorViewController *editor = [self openSparkIn:controller];
    if (editor == nil) return;
    NSView *field = [self viewWithToolTip:@"depthHack" inView:editor.view];
    NSView *list = editor.stagesTable.enclosingScrollView;
    for (NSNumber *height in @[@400, @900, @640]) {
        NSRect frame = editor.view.frame;
        frame.size.height = height.doubleValue;
        editor.view.frame = frame;
        XCTAssertLessThanOrEqual(NSMaxY(field.frame), NSMinY(list.frame), @"at %@ high", height);
        XCTAssertGreaterThanOrEqual(NSMinY(field.frame), 0.0, @"and in the view at %@ high", height);
    }
}

#pragma mark - The FX editor

- (UDFXEditorViewController *)openFXIn:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:@"fx/fx/udtest_spark" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDFXEditorViewController class]], @"an fx opens in its editor, not %@", editor);
    return [editor isKindOfClass:[UDFXEditorViewController class]] ? (UDFXEditorViewController *)editor : nil;
}

- (void)testAnFXOpensWithItsActions {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDFXEditorViewController *editor = [self openFXIn:controller];
    if (editor == nil) return;

    XCTAssertEqual(editor.actionsTable.numberOfRows, 3);
    XCTAssertEqual(editor.actionsController.selectionIndex, 0U, @"its first action shown");
    XCTAssertEqualObjects(((NSPopUpButton *)[self viewWithToolTip:@"kind" inView:editor.view]).titleOfSelectedItem, @"light");
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"data" inView:editor.view]).stringValue, @"lights/udtest_missing");
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"lightRadius" inView:editor.view]).stringValue, @"64");

    NSArray *messages = [editor.diagnosticStore.allDiagnostics valueForKey:@"message"];
    XCTAssertEqualObjects(messages, (@[
        @"Action 0: Material “lights/udtest_missing” is neither a decl nor an image: the engine makes it a default material",
        @"Action 2: No particle “udtest_missing.prt”"]), @"its uselight finds the action named spark");
    UDDiagnosticItem *particle = editor.diagnosticStore.allDiagnostics.lastObject;
    [controller errorsViewController:nil didSelectDiagnostic:particle inStore:editor.diagnosticStore];
    XCTAssertEqual(editor.actionsController.selectionIndex, 2U, @"a click shows the action");
}

- (void)testEditingAnActionIsAnEditOfTheFX {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDFXEditorViewController *editor = [self openFXIn:controller];
    if (editor == nil) return;

    id selection = editor.actionsController.selection;
    id value = @"soon";
    XCTAssertFalse([selection validateValue:&value forKey:@"duration" error:NULL], @"not a number: refused");
    value = @"";
    XCTAssertTrue([selection validateValue:&value forKey:@"restart" error:NULL]);
    XCTAssertNil(value, @"nothing is no restart");
    value = @"0.75";
    XCTAssertTrue([selection validateValue:&value forKey:@"duration" error:NULL]);
    // As a binding sets them: through the controller's selection each time.
    [editor.actionsController setValue:value forKeyPath:@"selection.duration"];
    [editor.actionsController setValue:@"lights/udtest_other" forKeyPath:@"selection.data"];
    [editor.editingContext processPendingChanges];
    XCTAssertEqualObjects(editor.fx.actions.firstObject.duration, @0.75f);
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    [editor.actionsController setSelectionIndex:2];
    NSSegmentedControl *buttons = [self segmentedControlWithAction:@selector(addOrRemoveAction:) inView:editor.view];
    [buttons setSelectedSegment:1];
    [NSApp sendAction:buttons.action to:buttons.target from:buttons];
    [buttons setSelectedSegment:0];
    [NSApp sendAction:buttons.action to:buttons.target from:buttons];
    XCTAssertEqual(editor.fx.actions.count, 3U);
    UDFXAction *added = editor.actionsController.selectedObjects.firstObject;
    XCTAssertEqualObjects(added.kind, @"model", @"idDeclFX::DefaultDefinition's action, shown");
    XCTAssertEqualObjects(added.data, @"_default");

    [self save:controller];
    NSString *saved = [self savedText:@"fx/udtest.fx"];
    XCTAssertTrue([saved containsString:@"\t\tname \"spark\"\n\t\tduration 0.75\n\t\tlight \"lights/udtest_other\", 1, 0.5, 0, 64\n"], @"%@", saved);
    XCTAssertTrue([saved containsString:@"\t\tdelay 0.1\n\t\tuseLight \"spark\"\n\t\tfadeOut 0.2\n"], @"%@", saved);
    XCTAssertTrue([saved containsString:@"\t\tduration 5\n\t\tmodel \"_default\"\n"], @"%@", saved);
    XCTAssertFalse([saved containsString:@"udtest_missing.prt"], @"the action taken off: %@", saved);
}

#pragma mark - The AF editor

- (UDAFEditorViewController *)openCrateIn:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:@"articulatedFigure/udtest_crate" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDAFEditorViewController class]], @"a figure opens in its editor, not %@", editor);
    return [editor isKindOfClass:[UDAFEditorViewController class]] ? (UDAFEditorViewController *)editor : nil;
}

- (void)testAnArticulatedFigureOpensWithItsBodiesAndConstraints {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDAFEditorViewController *editor = [self openCrateIn:controller];
    if (editor == nil) return;

    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"totalMass" inView:editor.view]).stringValue, @"40");
    XCTAssertEqual(editor.bodiesTable.numberOfRows, 3);
    XCTAssertEqual(editor.constraintsTable.numberOfRows, 2);
    XCTAssertEqual(editor.bodiesController.selectionIndex, 0U, @"its first body shown");
    [editor.tabView selectTabViewItemWithIdentifier:@"bodies"];
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"jointName" inView:editor.view]).stringValue, @"origin");
    [editor.tabView selectTabViewItemWithIdentifier:@"constraints"];
    XCTAssertEqualObjects(((NSPopUpButton *)[self viewWithToolTip:@"type" inView:editor.view]).titleOfSelectedItem, @"hinge");

    // The mesh has a "Lid": idAnimator finds a joint by Icmp.
    NSArray *messages = [editor.diagnosticStore.allDiagnostics valueForKey:@"message"];
    XCTAssertEqualObjects(messages, (@[
        @"Body 'latch' modifies unknown joint 'latch'",
        @"Constraint 'strap' binds to the world: no body 'post'"]));
    UDDiagnosticItem *latch = editor.diagnosticStore.allDiagnostics.firstObject;
    XCTAssertEqual(latch.severity, UDDiagnosticSeverityError, @"idAF::AddBody's is a gameLocal.Error");
    [controller errorsViewController:nil didSelectDiagnostic:latch inStore:editor.diagnosticStore];
    XCTAssertEqualObjects(editor.tabView.selectedTabViewItem.identifier, @"bodies");
    XCTAssertEqual(editor.bodiesController.selectionIndex, 2U, @"a click shows the body");
}

- (void)testEditingBodiesAndConstraintsIsAnEditOfTheFigure {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDAFEditorViewController *editor = [self openCrateIn:controller];
    if (editor == nil) return;

    id value = @"heavy";
    XCTAssertFalse([editor.figure validateValue:&value forKey:@"totalMass" error:NULL], @"not a number: refused");
    value = @" 50";
    XCTAssertTrue([editor.figure validateValue:&value forKey:@"totalMass" error:NULL]);
    XCTAssertEqualObjects(value, @50.0f);
    // As a binding sets them: through the controller's selection each time.
    [editor.objectController setValue:value forKeyPath:@"selection.totalMass"];
    [editor.bodiesController setSelectionIndex:1];
    [editor.bodiesController setValue:@"Lid" forKeyPath:@"selection.jointName"];
    XCTAssertEqual(editor.bodiesController.selectionIndex, 1U, @"the body edited stays shown");
    [editor.bodiesController setValue:@"door" forKeyPath:@"selection.name"];
    [editor.editingContext processPendingChanges];
    XCTAssertEqualObjects(editor.figure.constraints.firstObject.body1, @"door", @"RenameBody: its constraints follow");
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    // The latch off, and the strap on it with it; a body and a constraint on.
    [editor.bodiesController setSelectionIndex:2];
    [editor.tabView selectTabViewItemWithIdentifier:@"bodies"];
    NSSegmentedControl *bodyButtons = [self segmentedControlWithAction:@selector(addOrRemoveBody:) inView:editor.view];
    [bodyButtons setSelectedSegment:1];
    [NSApp sendAction:bodyButtons.action to:bodyButtons.target from:bodyButtons];
    XCTAssertEqualObjects([editor.figure.bodies valueForKey:@"name"], (@[@"crate", @"door"]));
    XCTAssertEqualObjects([editor.figure.constraints valueForKey:@"name"], (@[@"hinge"]), @"DeleteBody takes its constraints off");
    [bodyButtons setSelectedSegment:0];
    [NSApp sendAction:bodyButtons.action to:bodyButtons.target from:bodyButtons];
    XCTAssertEqualObjects(editor.figure.bodies.lastObject.name, @"body1");
    XCTAssertEqual(editor.bodiesController.selectionIndex, 2U, @"the new body shown");
    [editor.tabView selectTabViewItemWithIdentifier:@"constraints"];
    NSSegmentedControl *constraintButtons = [self segmentedControlWithAction:@selector(addOrRemoveConstraint:) inView:editor.view];
    [constraintButtons setSelectedSegment:0];
    [NSApp sendAction:constraintButtons.action to:constraintButtons.target from:constraintButtons];
    XCTAssertEqualObjects(editor.figure.constraints.lastObject.name, @"constraint1");
    [editor.editingContext processPendingChanges];
    XCTAssertEqual(editor.diagnosticStore.allDiagnostics.count, 0U, @"%@", [editor.diagnosticStore.allDiagnostics valueForKey:@"message"]);

    [self save:controller];
    NSString *saved = [self savedText:@"af/udtest.af"];
    XCTAssertTrue([saved containsString:@"\ttotalMass 50.000000\n"], @"%@", saved);
    XCTAssertTrue([saved containsString:@"body \"door\" {\n\tjoint \"Lid\"\n"], @"%@", saved);
    XCTAssertTrue([saved containsString:@"hinge \"hinge\" {\n\tbody1 \"door\"\n\tbody2 \"crate\"\n"], @"%@", saved);
    XCTAssertTrue([saved containsString:@"universalJoint \"constraint1\" {\n\tbody1 \"crate\"\n\tbody2 \"world\"\n"], @"%@", saved);
    XCTAssertFalse([saved containsString:@"latch"], @"%@", saved);
}

#pragma mark - The material editor

- (UDMaterialEditorViewController *)openMaterial:(NSString *)name in:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:[@"material/" stringByAppendingString:name] inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDMaterialEditorViewController class]], @"a material opens in its editor, not %@", editor);
    return [editor isKindOfClass:[UDMaterialEditorViewController class]] ? (UDMaterialEditorViewController *)editor : nil;
}

- (void)testAMaterialOpensWithItsKeywordsStagesAndImages {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDMaterialEditorViewController *editor = [self openMaterial:@"textures/udtest/glow" in:controller];
    if (editor == nil) return;

    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"materialDescription" inView:editor.view]).stringValue, @"Glow");
    [editor.tabView selectTabViewItemWithIdentifier:@"stages"];
    XCTAssertEqual(editor.stagesTable.numberOfRows, 1);
    XCTAssertEqual(editor.stagesController.selectionIndex, 0U, @"its first stage shown");
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"map" inView:editor.view]).stringValue, @"textures/udtest/glow.tga");
    XCTAssertEqualObjects([editor tableView:editor.stagesTable objectValueForTableColumn:[editor.stagesTable tableColumnWithIdentifier:@"stage"] row:0],
                          @"stage 0");

    // Its image, as the renderer loads it.
    XCTAssertNotNil(editor.previewView.image);
    XCTAssertEqualObjects(editor.previewLabel.stringValue, @"textures/udtest/glow.tga (2 × 2)");
    XCTAssertEqual(editor.diagnosticStore.allDiagnostics.count, 0U, @"%@", [editor.diagnosticStore.allDiagnostics valueForKey:@"message"]);

    UDMaterialEditorViewController *lost = [self openMaterial:@"textures/udtest/lost" in:controller];
    XCTAssertEqualObjects([lost.diagnosticStore.allDiagnostics valueForKey:@"message"], (@[@"Couldn't load image: textures/udtest/missing"]));
    XCTAssertEqualObjects(lost.previewLabel.stringValue, @"Couldn't load image: textures/udtest/missing");
}

- (void)testEditingAMaterialChangesOnlyWhatIsEdited {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDMaterialEditorViewController *editor = [self openMaterial:@"textures/udtest/glow" in:controller];
    if (editor == nil) return;

    // As a binding sets them: through the controllers' selections.
    [editor.objectController setValue:@"Bright glow" forKeyPath:@"selection.materialDescription"];
    [editor.objectController setValue:@YES forKeyPath:@"selection.twoSided"];
    [editor.objectController setValue:@"metal" forKeyPath:@"selection.surfaceType"];
    [editor.stagesController setValue:@"textures/udtest/glow2" forKeyPath:@"selection.map"];
    [editor.stagesController setValue:@"(default)" forKeyPath:@"selection.clampMode"];
    [editor.stagesController setValue:@"time, 0" forKeyPath:@"selection.scroll"];
    [editor.editingContext processPendingChanges];
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);
    XCTAssertEqualObjects([editor.diagnosticStore.allDiagnostics valueForKey:@"message"], (@[@"Couldn't load image: textures/udtest/glow2"]),
                          @"the Issues follow the edits");

    // A bump map, the stage copied and pasted after it, moved up.
    [editor.tabView selectTabViewItemWithIdentifier:@"stages"];
    NSPopUpButton *lighting = [self viewWithToolTip:@"add lighting stage" inView:editor.view];
    [lighting selectItemWithTag:1];
    [NSApp sendAction:@selector(addLightingStage:) to:editor from:lighting];
    XCTAssertEqual(editor.material.stages.count, 2U);
    XCTAssertEqual(editor.stagesController.selectionIndex, 1U, @"the new stage shown");
    [NSApp sendAction:@selector(copy:) to:controller from:nil];
    [NSApp sendAction:@selector(paste:) to:controller from:nil];
    XCTAssertEqual(editor.material.stages.count, 3U, @"Edit ▸ Paste: the bump map again");
    [editor.stagesController setSelectionIndex:0];
    NSSegmentedControl *move = [self viewWithToolTip:@"move stage" inView:editor.view];
    [move setSelectedSegment:1];
    [NSApp sendAction:move.action to:move.target from:move];
    XCTAssertEqual(editor.stagesController.selectionIndex, 1U);
    [editor.stagesController setSelectionIndex:2];
    NSSegmentedControl *buttons = [self segmentedControlWithAction:@selector(addOrRemoveStage:) inView:editor.view];
    [buttons setSelectedSegment:1];
    [NSApp sendAction:buttons.action to:buttons.target from:buttons];
    XCTAssertEqual(editor.material.stages.count, 2U);

    [self save:controller];
    NSString *saved = [self savedText:@"materials/udtest.mtr"];
    XCTAssertTrue([saved containsString:
        @"textures/udtest/glow\n"
         "{\n"
         "\t// glows\n"
         "\tdescription\t\"Bright glow\"\n"
         "\ttwoSided\n"
         "\tmetal\n"
         "\tbumpmap\t_flat\n"
         "\t{\n"
         "\t\tblend\tadd\n"
         "\t\tmap\ttextures/udtest/glow2\n"
         "\t\tscroll\ttime, 0\n"
         "\t}\n"
         "}\n"], @"the comment kept, the edits made:\n%@", saved);
    XCTAssertTrue([saved containsString:@"textures/udtest/lost\n{\n\t{\n\t\tblend\tadd\n"], @"the other material untouched:\n%@", saved);
}

@end
