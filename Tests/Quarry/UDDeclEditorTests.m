#import "UDTransportController.h"
#import "UDWorkspace.h"
#import "UDQuarryTestCase.h"

#import "UDDeclDocument.h"
#import "UDEditorTabManager.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDNewDeclWindowController.h"
#import "UDTextEditorViewController.h"
#import "UDEntityDefEditorViewController.h"
#import "UDSoundEditorViewController.h"
#import "UDParticleEditorViewController.h"
#import "UDReferencePicker.h"
#import "UDExpressionEditor.h"
#import "UDExpressionTextStorage.h"
#import "UDFXEditorViewController.h"
#import "UDAFEditorViewController.h"
#import "UDMaterialEditorViewController.h"
#import "UDParticlePreview.h"
#import "UDFXTimelineView.h"
#import "UDFXModel.h"
#import "UDDeclManagedObjects.h"
#import "idDeclManager.h"
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
@interface UDDeclEditorTests : UDQuarryTestCase
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
                               @"base/textures/udtest", @"base/env", @"base/glprogs"]) {
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
    // A cube map's first side, a camera's, a program (only their names matter)
    for (NSString *file in @[@"base/env/udtest_px.tga", @"base/env/udsky_forward.tga", @"base/glprogs/udtest.vfp"]) {
        [@"" writeToFile:[self.basePath stringByAppendingPathComponent:file] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
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

/// The selected pair's value in the entry its type takes: the editor_*
/// key's type, else the key's, else the value's; each edit its text.
- (void)testASpawnArgIsEnteredAsItsType {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDEntityDefEditorViewController *editor = [self openLampIn:controller];
    if (editor == nil) return;
    NSMutableArray *pairs = [editor.entityDef.keyValues mutableCopy];
    for (NSArray<NSString *> *pair in @[@[@"solid", @"1"], @[@"size", @"16 16 32"], @[@"_color", @"1 0.5 0"],
                                        @[@"snd_hum", @""], @[@"health", @"100"], @[@"spawnclass", @"idLight"]]) {
        [pairs addObject:[UDEntityKeyValue keyValueWithKey:pair[0] value:pair[1]]];
    }
    editor.entityDef.keyValues = pairs;
    [editor.editingContext processPendingChanges];
    UDEntityKeyValue *(^select)(NSString *) = ^UDEntityKeyValue *(NSString *key) {
        UDEntityKeyValue *pair = [editor.keyValuesController.arrangedObjects filteredArrayUsingPredicate:
                                  [NSPredicate predicateWithFormat:@"key == %@", key]].firstObject;
        [editor.keyValuesController setSelectedObjects:@[pair]];
        return pair;
    };
    NSDictionary<NSString *, NSString *> *pages = @{@"model": @"reference", @"solid": @"bool", @"size": @"vector", @"_color": @"color",
                                                    @"snd_hum": @"reference", @"health": @"number", @"spawnclass": @"text"};
    for (NSString *key in pages) {
        select(key);
        XCTAssertEqualObjects(editor.valuePages.selectedTabViewItem.identifier, pages[key], @"%@", key);
        XCTAssertEqualObjects(editor.keyLabel.stringValue, key);
    }
    XCTAssertEqualObjects((select(@"solid"), editor.kindLabel.stringValue), @"On (1) or off (0) (editor_bool)", @"the inherited editor_bool's");

    // each entry's edit, as the value's text
    NSString *(^valueOf)(NSString *) = ^NSString *(NSString *key) {
        return [[editor.entityDef.keyValues filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key == %@", key]].firstObject value];
    };
    select(@"solid");
    [editor.boolCheckbox performClick:nil];
    XCTAssertEqualObjects(valueOf(@"solid"), @"0");
    select(@"size");
    editor.vectorZField.stringValue = @"64";
    [editor valueEdited:editor.vectorZField];
    XCTAssertEqualObjects(valueOf(@"size"), @"16 16 64");
    editor.vectorXField.stringValue = @"wide";
    [editor valueEdited:editor.vectorXField];
    XCTAssertEqualObjects(valueOf(@"size"), @"16 16 64", @"not a number: as it was");
    XCTAssertEqualObjects(editor.vectorXField.stringValue, @"16");
    select(@"health");
    editor.numberField.stringValue = @"250";
    [editor valueEdited:editor.numberField];
    XCTAssertEqualObjects(valueOf(@"health"), @"250");
    select(@"_color");
    editor.colorWell.color = [NSColor colorWithCalibratedRed:0.25 green:0.5 blue:1 alpha:1];
    [editor valueEdited:editor.colorWell];
    XCTAssertEqualObjects(valueOf(@"_color"), @"0.25 0.5 1");

    // a reference picked
    select(@"snd_hum");
    UDReferenceField *field = [editor referenceFieldForTag:2];
    XCTAssertEqual(field.kind, UDReferenceDecls);
    XCTAssertEqual(field.declType, (int)DECL_SOUND);
    select(@"model");
    XCTAssertEqual([editor referenceFieldForTag:2].kind, UDReferenceEntityModels);

    [editor.editingContext processPendingChanges];
    [editor.editorDocument.undoManager undo];
    [editor.editingContext processPendingChanges];
    XCTAssertNotEqualObjects(valueOf(@"_color"), @"0.25 0.5 1", @"undone");
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
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"totalParticles" inView:editor.inspectorView]).stringValue, @"4");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"material" inView:editor.inspectorView]).stringValue, @"textures/udtest/spark");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"depthHack" inView:editor.inspectorView]).stringValue, @"0.001");
    XCTAssertEqual(((NSSlider *)[self viewBoundTo:@"totalParticles" ofClass:[NSSlider class] inView:editor.inspectorView]).doubleValue, 4.0, @"its slider too");

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
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"totalParticles" inView:editor.inspectorView]).stringValue, @"8");

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

- (void)testTheParticleInspectorFollowsTheStages {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDParticleEditorViewController *editor = [self openSparkIn:controller];
    if (editor == nil) return;
    XCTAssertEqualObjects([editor.inspectorPanes valueForKey:@"title"], (@[@"Particle", @"Stage"]));
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"stage", @"its first stage's parameters");
    XCTAssertNil([self viewBoundTo:@"totalParticles" inView:editor.view], @"in the inspector, not the centre");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"depthHack" inView:editor.documentInspectorView]).stringValue, @"0.001",
                          @"the particle's own, in its pane, a stage chosen or not");

    [editor.stagesController setSelectionIndexes:[NSIndexSet indexSet]];
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"none", @"no stage: No Stage Selected");

    // a second stage, dragged before the first
    [editor.stagesController setSelectionIndex:0];
    NSSegmentedControl *buttons = [self segmentedControlWithAction:@selector(addOrRemoveStage:) inView:editor.view];
    [buttons setSelectedSegment:0];
    [NSApp sendAction:buttons.action to:buttons.target from:buttons];
    XCTAssertEqual(editor.particle.stages[1].totalParticles, 100);
    XCTAssertFalse([editor moveStageAtIndex:1 toRow:2], @"where it is");
    XCTAssertTrue([editor moveStageAtIndex:1 toRow:0]);
    XCTAssertEqual(editor.particle.stages[0].totalParticles, 100, @"the new stage first");
    XCTAssertEqual(editor.stagesController.selectionIndex, 0U, @"and chosen");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"totalParticles" inView:editor.inspectorView]).stringValue, @"100");
    [editor.editingContext processPendingChanges];
    [editor.editorDocument.undoManager undo];
    [editor.editingContext processPendingChanges];
    XCTAssertEqual(editor.particle.stages[0].totalParticles, 4, @"undone");
}

- (void)testTheParticlePreviewDrawsTheSystemAsTheEngineDoes {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDParticleEditorViewController *editor = [self openSparkIn:controller];
    if (editor == nil) return;
    XCTAssertNotNil(editor.preview);

    // Its material made the glow's: "blend add", a red and green image.
    [editor.stagesController setValue:@"textures/udtest/glow" forKeyPath:@"selection.material"];
    [editor.editingContext processPendingChanges];
    [editor.preview renderAtTime:300];
    NSBitmapImageRep *rep = (NSBitmapImageRep *)editor.previewView.image.representations.firstObject;
    XCTAssertNotNil(rep);
    NSUInteger lit = 0;
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
        for (NSInteger x = 0; x < rep.pixelsWide; x++) {
            NSUInteger pixel[4];
            [rep getPixel:pixel atX:x y:y];
            if (pixel[0] > 60 || pixel[1] > 60) lit++;
        }
    }
    XCTAssertGreaterThan(lit, 0U, @"its particles added onto the background");
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
    XCTAssertEqualObjects([editor.inspectorPanes valueForKey:@"title"], (@[@"FX", @"Action"]));
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"none", @"no action chosen");
    XCTAssertNotNil([self viewBoundTo:@"bindTo" inView:editor.documentInspectorView], @"the FX's keywords, in their pane");
    [editor.actionsController setSelectionIndex:0];
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"action", @"an action chosen: its keywords");
    XCTAssertEqualObjects(((NSPopUpButton *)[self viewBoundTo:@"kind" inView:editor.inspectorView]).titleOfSelectedItem, @"light");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"data" inView:editor.inspectorView]).stringValue, @"lights/udtest_missing");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"lightRadius" inView:editor.inspectorView]).stringValue, @"64");

    // dragged last
    XCTAssertTrue([editor moveActionAtIndex:0 toRow:3]);
    XCTAssertEqualObjects([editor.fx.actions valueForKey:@"kind"], (@[@"uselight", @"particle", @"light"]));
    XCTAssertEqual(editor.actionsController.selectionIndex, 2U);
    [editor.editingContext processPendingChanges];
    [editor.editorDocument.undoManager undo];
    [editor.editingContext processPendingChanges];
    XCTAssertEqualObjects([editor.fx.actions valueForKey:@"kind"], (@[@"light", @"uselight", @"particle"]), @"undone");

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
    [editor.actionsController setSelectionIndex:0];

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

    XCTAssertEqualObjects([editor.inspectorPanes valueForKey:@"title"], (@[@"Figure", @"Body", @"Constraint"]));
    XCTAssertEqualObjects([self paneShownIn:controller], @"Figure", @"nothing chosen: the figure's settings");
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"none");
    XCTAssertEqualObjects(editor.constraintInspectorTabs.selectedTabViewItem.identifier, @"none");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"totalMass" inView:editor.documentInspectorView]).stringValue, @"40");
    XCTAssertEqual(editor.bodiesTable.numberOfRows, 3);
    XCTAssertEqual(editor.constraintsTable.numberOfRows, 2);
    [editor.bodiesController setSelectionIndex:0];
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"body");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"jointName" inView:editor.inspectorView]).stringValue, @"origin");
    [editor.constraintsController setSelectionIndex:0];
    XCTAssertEqualObjects(editor.constraintInspectorTabs.selectedTabViewItem.identifier, @"constraint");
    XCTAssertEqual(editor.bodiesController.selectionIndexes.count, 0U, @"one list chosen at a time");
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"none", @"no body: No Body Selected");
    XCTAssertEqualObjects(((NSPopUpButton *)[self viewBoundTo:@"type" inView:editor.constraintInspectorView]).titleOfSelectedItem, @"hinge");
    XCTAssertNil([self viewBoundTo:@"totalMass" inView:editor.view], @"the keywords in the inspector, not the centre");

    // The mesh has a "Lid": idAnimator finds a joint by Icmp.
    NSArray *messages = [editor.diagnosticStore.allDiagnostics valueForKey:@"message"];
    XCTAssertEqualObjects(messages, (@[
        @"Body 'latch' modifies unknown joint 'latch'",
        @"Constraint 'strap' binds to the world: no body 'post'"]));
    UDDiagnosticItem *latch = editor.diagnosticStore.allDiagnostics.firstObject;
    XCTAssertEqual(latch.severity, UDDiagnosticSeverityError, @"idAF::AddBody's is a gameLocal.Error");
    [controller errorsViewController:nil didSelectDiagnostic:latch inStore:editor.diagnosticStore];
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"body");
    XCTAssertEqual(editor.bodiesController.selectionIndex, 2U, @"a click shows the body");
    XCTAssertEqualObjects([self paneShownIn:controller], @"Body", @"in its pane");
}

- (void)testTheInspectorIsLaidOutFromTheTop {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDAFEditorViewController *editor = [self openCrateIn:controller];
    if (editor == nil) return;
    NSView *inspector = editor.documentInspectorView;
    for (NSNumber *height in @[@600, @1000]) {
        [inspector setFrameSize:NSMakeSize(280, height.doubleValue)];
        [inspector layoutSubtreeIfNeeded];
        NSView *model = [self viewBoundTo:@"model" inView:inspector];
        NSRect frame = [inspector convertRect:model.bounds fromView:model];
        CGFloat fromTop = inspector.isFlipped ? NSMinY(frame) : height.doubleValue - NSMaxY(frame);
        XCTAssertLessThan(fromTop, 80.0, @"the figure's first field at the top, %@ high", height);
    }
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
    NSSegmentedControl *bodyButtons = [self segmentedControlWithAction:@selector(addOrRemoveBody:) inView:editor.view];
    [bodyButtons setSelectedSegment:1];
    [NSApp sendAction:bodyButtons.action to:bodyButtons.target from:bodyButtons];
    XCTAssertEqualObjects([editor.figure.bodies valueForKey:@"name"], (@[@"crate", @"door"]));
    XCTAssertEqualObjects([editor.figure.constraints valueForKey:@"name"], (@[@"hinge"]), @"DeleteBody takes its constraints off");
    [bodyButtons setSelectedSegment:0];
    [NSApp sendAction:bodyButtons.action to:bodyButtons.target from:bodyButtons];
    XCTAssertEqualObjects(editor.figure.bodies.lastObject.name, @"body1");
    XCTAssertEqual(editor.bodiesController.selectionIndex, 2U, @"the new body shown");
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

#pragma mark - Pickers

- (void)testAPickerChoosesWhatAFieldNames {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDParticleEditorViewController *particle = [self openSparkIn:controller];
    if (particle == nil) return;
    [self pick:1 in:particle under:particle.inspectorView with:^(UDReferencePicker *picker) {
        XCTAssertTrue([picker.shownNames containsObject:@"textures/udtest/glow"], @"the material decls: %@", picker.shownNames);
        picker.filterField.stringValue = @"GLOW";
        [picker filterChanged:picker.filterField];
        XCTAssertGreaterThan(picker.shownNames.count, 0U);
        for (NSString *name in picker.shownNames) {
            XCTAssertTrue([name.lowercaseString containsString:@"glow"], @"only the names containing it, in any case: %@", name);
        }
        [self choose:@"textures/udtest/glow" in:picker];
    }];
    XCTAssertEqualObjects(particle.particle.stages.firstObject.material, @"textures/udtest/glow", @"the stage's material, as chosen");
    [particle.editingContext processPendingChanges];
    [particle.editorDocument.undoManager undo];
    [particle.editingContext processPendingChanges];
    XCTAssertEqualObjects(particle.particle.stages.firstObject.material, @"textures/udtest/spark", @"one Undo");

    // Cancel changes nothing
    [particle.stagesController setSelectionIndex:0];
    [self pick:2 in:particle under:particle.inspectorView with:^(UDReferencePicker *picker) {
        [picker cancel:nil];
    }];
    XCTAssertEqual(particle.particle.stages.firstObject.speedTable.length, 0U);

    // the AF's joints are its model's
    UDAFEditorViewController *af = [self openCrateIn:controller];
    [af.bodiesController setSelectionIndex:1];
    [self pick:3 in:af under:af.inspectorView with:^(UDReferencePicker *picker) {
        [self choose:@"Lid" in:picker];
    }];
    XCTAssertEqualObjects([af.figure.bodies[1] jointName], @"Lid");

    // an FX light's: materials
    UDFXEditorViewController *fx = [self openFXIn:controller];
    [fx.actionsController setSelectionIndex:0];
    [self pick:1 in:fx under:fx.inspectorView with:^(UDReferencePicker *picker) {
        XCTAssertTrue([picker.shownNames containsObject:@"textures/udtest/glow"], @"%@", picker.shownNames);
        [picker cancel:nil];
    }];
}

#pragma mark - Expressions

- (void)testAnExpressionIsHighlightedAsItIsTyped {
    NSArray<NSArray *> *tokens = [UDExpressionTextStorage tokensOf:@"flicker[ time * 2.5 ] + parm0 \"x\" nobody"
                                                             known:[NSSet setWithObject:@"parm0"] tables:[NSSet setWithObject:@"flicker"]];
    NSMutableArray<NSString *> *kinds = [NSMutableArray array];
    for (NSArray *token in tokens) [kinds addObject:token.lastObject];
    XCTAssertEqualObjects(kinds, (@[@"table", @"operator", @"operator", @"number", @"operator", @"operator", @"name", @"string"]),
                          @"a table before [, numbers, a known name, a string; an unknown name left as it is");
}

- (void)testAStagesRegisterIsEditedAsAnExpression {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDMaterialEditorViewController *editor = [self openMaterial:@"textures/udtest/glow" in:controller];
    if (editor == nil) return;
    [editor.stagesController setSelectionIndex:0];
    [self click:@selector(editExpression:) tag:1 under:editor.inspectorView sheetOver:editor.view.window with:^(UDExpressionEditor *expression) {
        XCTAssertTrue([expression isKindOfClass:[UDExpressionEditor class]]);
        [expression setText:@"time * nosuchname, 0"];
        XCTAssertTrue([expression.status containsString:@"Bad term"], @"idMaterial::ParseTerm's warning: %@", expression.status);
        [expression setText:@"time * 0.1, "];
        [expression selectCategoryNamed:@"Parms"];
        XCTAssertTrue([expression insertEntryNamed:@"parm4"]);
        XCTAssertEqualObjects(expression.text, @"time * 0.1, parm4", @"inserted at the caret");
        XCTAssertEqualObjects(expression.status, @"Reads as the engine reads it.");
        [expression ok:nil];
    }];
    [editor.editingContext processPendingChanges];
    XCTAssertEqualObjects([editor.stagesController valueForKeyPath:@"selection.scroll"], @"time * 0.1, parm4", @"the stage's scroll, as edited");
    [editor.editorDocument.undoManager undo];
    [editor.editingContext processPendingChanges];
    [editor.stagesController setSelectionIndex:0];
    XCTAssertNotEqualObjects([editor.stagesController valueForKeyPath:@"selection.scroll"], @"time * 0.1, parm4", @"one Undo");
}

/// The keywords a field takes offered beside it; a cube map and a
/// program picked by the names the engine looks them up by.
- (void)testAStagesKeywordsAreOfferedAndItsCubeMapAndProgramPicked {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDMaterialEditorViewController *editor = [self openMaterial:@"textures/udtest/glow" in:controller];
    if (editor == nil) return;
    NSComboBox *sort = [self viewBoundTo:@"sort" ofClass:[NSComboBox class] inView:editor.documentInspectorView];
    XCTAssertTrue([sort.objectValues containsObject:@"postProcess"], @"%@", sort.objectValues);
    XCTAssertNotNil([self viewBoundTo:@"deform" ofClass:[NSComboBox class] inView:editor.documentInspectorView]);
    [editor.stagesController setSelectionIndex:0];
    NSComboBox *texGen = [self viewBoundTo:@"texGen" ofClass:[NSComboBox class] inView:editor.inspectorView];
    XCTAssertNotNil(texGen);
    XCTAssertTrue([texGen.objectValues containsObject:@"reflect"], @"%@", texGen.objectValues);

    [self pick:6 in:editor under:editor.inspectorView with:^(UDReferencePicker *picker) {
        XCTAssertEqualObjects(picker.shownNames, (@[@"env/udsky", @"env/udtest"]), @"the cube maps by their names, not their sides'");
        [self choose:@"env/udtest" in:picker];
    }];
    [self pick:7 in:editor under:editor.inspectorView with:^(UDReferencePicker *picker) {
        XCTAssertEqualObjects(picker.shownNames, @[@"udtest.vfp"], @"the programs as R_FindARBProgram names them");
        [self choose:@"udtest.vfp" in:picker];
    }];
    [editor.editingContext processPendingChanges];
    XCTAssertEqualObjects([editor.stagesController valueForKeyPath:@"selection.cubeMap"], @"env/udtest");
    XCTAssertEqualObjects([editor.stagesController valueForKeyPath:@"selection.program"], @"udtest.vfp");
}

#pragma mark - Help

/// Every control of @a view that edits a key has help as its tooltip.
- (void)checkHelpUnder:(NSView *)view of:(NSString *)editor {
    __block NSUInteger checked = 0;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        for (NSString *binding in @[NSValueBinding, NSSelectedValueBinding, NSSelectedIndexBinding]) {
            NSString *keyPath = [candidate infoForBinding:binding][NSObservedKeyPathKey];
            if (![keyPath hasPrefix:@"selection."]) continue;
            checked++;
            XCTAssertTrue([candidate.toolTip containsString:@" "], @"%@: %@ has help, not %@", editor, keyPath, candidate.toolTip);
        }
        return YES;
    }];
    XCTAssertGreaterThan(checked, 0U, @"%@", editor);
}

/// The title of the inspector pane the window shows.
- (nullable NSString *)paneShownIn:(UDWorkspaceWindowController *)controller {
    for (UDEditorPane *pane in [controller valueForKey:@"inspectorPanes"]) {
        if (pane.view.superview == controller.inspectorHost) return pane.title;
    }
    return nil;
}

/// A click in @a table, as its action has it.
- (void)click:(NSTableView *)table row:(NSInteger)row {
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [NSApp sendAction:table.action to:table.target from:table];
}

/// A declaration's own keywords in a pane of their own, beside its selected
/// stage's (action's, body's), as Xcode has a file's (issue #22: with a
/// stage chosen, they were out of reach where the list can't be emptied, as
/// on GNUstep); a click in the list shows the stage's pane.
- (void)testTheDeclarationsOwnKeywordsHaveAPaneOfTheirOwn {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    NSArray *cases = @[@[@"Material", @"Stage", @"materialDescription", @"Glow"], @[@"FX", @"Action", @"bindTo", @""],
                       @[@"Particle", @"Stage", @"depthHack", @"0.001"], @[@"Figure", @"Body", @"totalMass", @"40"]];
    for (NSArray *one in cases) {
        // each opened, so the window's inspector is its
        UDDeclEditorViewController *editor = [one[0] isEqual:@"Material"] ? [self openMaterial:@"textures/udtest/glow" in:controller]
                                           : [one[0] isEqual:@"FX"] ? [self openFXIn:controller]
                                           : [one[0] isEqual:@"Particle"] ? [self openSparkIn:controller] : [self openCrateIn:controller];
        if (editor == nil) continue;
        NSTableView *table = [editor respondsToSelector:@selector(stagesTable)] ? [(id)editor stagesTable]
                           : [editor respondsToSelector:@selector(actionsTable)] ? [(id)editor actionsTable] : [(id)editor bodiesTable];
        [self click:table row:0];
        XCTAssertEqualObjects([self paneShownIn:controller], one[1], @"a click on a %@: its pane", one[1]);

        [controller showInspectorPaneTitled:one[0]];
        XCTAssertEqualObjects([self paneShownIn:controller], one[0]);
        XCTAssertEqual(table.selectedRow, 0, @"the %@ still chosen", one[1]);
        NSTextField *field = (NSTextField *)[self viewBoundTo:one[2] inView:controller.inspectorHost];
        XCTAssertNotNil(field, @"the %@'s own keywords, shown", one[0]);
        XCTAssertEqualObjects(field.stringValue, one[3]);
        XCTAssertTrue(field.isEnabled && field.isEditable, @"and edited there");

        [self click:table row:0];
        XCTAssertEqualObjects([self paneShownIn:controller], one[1], @"the %@'s again", one[1]);
    }
}

- (void)testEveryInspectorControlHasHelp {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDParticleEditorViewController *particle = [self openSparkIn:controller];
    [self checkHelpUnder:particle.documentInspectorView of:@"particle"];
    [self checkHelpUnder:particle.inspectorView of:@"particle stage"];
    UDFXEditorViewController *fx = [self openFXIn:controller];
    [self checkHelpUnder:fx.documentInspectorView of:@"fx"];
    [fx.actionsController setSelectionIndex:0];
    [self checkHelpUnder:fx.inspectorView of:@"fx action"];
    UDAFEditorViewController *af = [self openCrateIn:controller];
    [self checkHelpUnder:af.documentInspectorView of:@"af figure"];
    [af.inspectorTabs selectTabViewItemWithIdentifier:@"body"];
    [self checkHelpUnder:af.inspectorView of:@"af body"];
    [af.constraintInspectorTabs selectTabViewItemWithIdentifier:@"constraint"];
    [self checkHelpUnder:af.constraintInspectorView of:@"af constraint"];
    UDMaterialEditorViewController *material = [self openMaterial:@"textures/udtest/glow" in:controller];
    [self checkHelpUnder:material.documentInspectorView of:@"material"];
    [material.stagesController setSelectionIndex:0];
    [self checkHelpUnder:material.inspectorView of:@"material stage"];
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

    // the material's keywords in a pane of their own; no stage chosen
    XCTAssertEqualObjects([editor.inspectorPanes valueForKey:@"title"], (@[@"Material", @"Stage"]));
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"none", @"No Stage Selected");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"materialDescription" inView:editor.documentInspectorView]).stringValue, @"Glow");
    XCTAssertEqual(editor.stagesTable.numberOfRows, 1);
    XCTAssertEqual(editor.stagesController.selectionIndex, (NSUInteger)NSNotFound);
    // a stage chosen in the centre: its keywords there instead
    [editor.stagesController setSelectionIndex:0];
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"stage");
    XCTAssertEqualObjects(((NSTextField *)[self viewBoundTo:@"map" inView:editor.inspectorView]).stringValue, @"textures/udtest/glow.tga");
    // the color keywords, one row each in their group, each with its help
    for (NSString *key in @[@"color", @"red", @"green", @"blue", @"alpha", @"rgb", @"rgba"]) {
        NSView *row = [self viewBoundTo:key inView:editor.inspectorView];
        XCTAssertNotNil(row, @"%@", key);
        XCTAssertTrue([row.toolTip hasPrefix:key], @"%@'s help: %@", key, row.toolTip);
    }
    XCTAssertTrue([[[self viewBoundTo:@"rgb" inView:editor.inspectorView] toolTip] containsString:@"one expression for the three"]);
    XCTAssertEqualObjects([editor tableView:editor.stagesTable objectValueForTableColumn:[editor.stagesTable tableColumnWithIdentifier:@"stage"] row:0],
                          @"stage 0");

    // Its image, as the renderer loads it.
    XCTAssertNotNil(editor.previewView.image);
    XCTAssertEqualObjects(editor.previewLabel.stringValue, @"textures/udtest/glow.tga (2 × 2)");
    XCTAssertEqual(editor.diagnosticStore.allDiagnostics.count, 0U, @"%@", [editor.diagnosticStore.allDiagnostics valueForKey:@"message"]);

    UDMaterialEditorViewController *lost = [self openMaterial:@"textures/udtest/lost" in:controller];
    XCTAssertEqualObjects([lost.diagnosticStore.allDiagnostics valueForKey:@"message"], (@[@"Couldn't load image: textures/udtest/missing"]));
    [lost.stagesController setSelectionIndex:0];
    XCTAssertEqualObjects(lost.previewLabel.stringValue, @"Couldn't load image: textures/udtest/missing");
}

- (void)testAStageIsDraggedToAnotherPlace {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDMaterialEditorViewController *editor = [self openMaterial:@"textures/udtest/glow" in:controller];
    if (editor == nil) return;
    NSPopUpButton *lighting = [self viewWithToolTip:@"add lighting stage" inView:editor.view];
    for (NSInteger tag = 1; tag <= 2; tag++) {
        [lighting selectItemWithTag:tag];
        [NSApp sendAction:@selector(addLightingStage:) to:editor from:lighting];
    }
    NSTableColumn *names = [editor.stagesTable tableColumnWithIdentifier:@"stage"];
    XCTAssertEqualObjects([editor tableView:editor.stagesTable objectValueForTableColumn:names row:1], @"bumpmap");
    // the first, dropped above the last row's end: last
    XCTAssertTrue([editor moveStageAtIndex:0 toRow:3]);
    XCTAssertEqualObjects([editor tableView:editor.stagesTable objectValueForTableColumn:names row:0], @"bumpmap");
    XCTAssertEqualObjects([editor tableView:editor.stagesTable objectValueForTableColumn:names row:1], @"diffusemap");
    XCTAssertEqual(editor.stagesController.selectionIndex, 2U, @"the moved stage chosen");
    XCTAssertEqualObjects(editor.inspectorTabs.selectedTabViewItem.identifier, @"stage");
    XCTAssertFalse([editor moveStageAtIndex:2 toRow:3], @"where it is");
    [editor.editingContext processPendingChanges];
    [editor.editorDocument.undoManager undo];
    [editor.editingContext processPendingChanges];
    XCTAssertEqualObjects([editor tableView:editor.stagesTable objectValueForTableColumn:names row:0], @"stage 0", @"undone");
}

- (void)testEditingAMaterialChangesOnlyWhatIsEdited {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDMaterialEditorViewController *editor = [self openMaterial:@"textures/udtest/glow" in:controller];
    if (editor == nil) return;

    // As a binding sets them: through the controllers' selections.
    [editor.stagesController setSelectionIndex:0];
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

- (void)testTheFXPreviewPlaysItsActions {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDFXEditorViewController *editor = [self openFXIn:controller];
    if (editor == nil) return;
    XCTAssertNotNil(editor.preview);
    XCTAssertEqual(editor.preview.fxDuration, 1000, @"the latest delay + duration: the particle's 1 s");
    XCTAssertEqual(editor.timelineView.actions.count, 3U);

    [editor.preview renderAtTime:200];
    XCTAssertNotNil(editor.previewView.image);
    XCTAssertEqual(editor.timelineView.time, 200, @"the timeline at the frame drawn");
    XCTAssertEqual(editor.timelineView.states.count, 3U);
    XCTAssertTrue(editor.timelineView.states[0].hasLight, @"its spark light, added");
    XCTAssertTrue(editor.timelineView.states[2].running, @"its particle running");
    [editor.preview renderAtTime:1100];
    XCTAssertEqual(editor.preview.time, 1100 % 1016, @"a test fx: from its start again after its duration");
}

- (void)testThePreviewsTimeCanBeScrubbed {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDFXEditorViewController *editor = [self openFXIn:controller];
    if (editor == nil) return;

    // The slider over the FX's loop once the preview has it (until then the
    // slider's range is its own, and 600 is past its end)
    XCTAssertTrue([self spinUntil:^BOOL{ return editor.transport.timeSlider.maxValue >= 1000; } timeout:10],
                  @"the slider over the FX: %g", editor.transport.timeSlider.maxValue);

    // The slider dragged: paused there, that frame drawn.
    editor.transport.timeSlider.intValue = 600;
    [NSApp sendAction:editor.transport.timeSlider.action to:editor.transport.timeSlider.target from:editor.transport.timeSlider];
    XCTAssertFalse(editor.preview.playing);
    XCTAssertEqual(editor.preview.time, 600);
    XCTAssertEqual(editor.timelineView.time, 600);
    XCTAssertEqualObjects(editor.transport.timeLabel.stringValue, @"0.60 s");
    XCTAssertEqualObjects(editor.transport.playButton.title, @"Play");
    XCTAssertEqual((int)editor.transport.timeSlider.maxValue, editor.preview.span, @"the slider over the FX's loop");

    // An edit while paused: the same time, drawn again.
    [editor.actionsController setValue:@"0.25" forKeyPath:@"selection.duration"];
    [editor.editingContext processPendingChanges];
    XCTAssertEqual(editor.preview.time, 600);

    // Play: on from where it was.
    [NSApp sendAction:editor.transport.playButton.action to:editor.transport.playButton.target from:editor.transport.playButton];
    XCTAssertTrue(editor.preview.playing);
    XCTAssertEqualObjects(editor.transport.playButton.title, @"Pause");

    // Step: a frame on, paused.
    [NSApp sendAction:editor.transport.playButton.action to:editor.transport.playButton.target from:editor.transport.playButton];
    XCTAssertFalse(editor.preview.playing);
    int before = editor.preview.time;
    [NSApp sendAction:editor.transport.stepButton.action to:editor.transport.stepButton.target from:editor.transport.stepButton];
    XCTAssertFalse(editor.preview.playing);
    XCTAssertEqual(editor.preview.time, before + 16);
}

- (void)testTheMaterialPreviewDrawsItAsTheEngineDoes {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDMaterialEditorViewController *editor = [self openMaterial:@"textures/udtest/glow" in:controller];
    if (editor == nil) return;
    XCTAssertNotNil(editor.materialPreview);
    [editor.materialPreview renderAtTime:0];
    XCTAssertEqualObjects(editor.lightingLabel.stringValue, @"glprogs/interaction.vfp: File not found",
                          @"no game program here: not lit, and why");
    // Its ambient stage: "blend add" of the red and green glow, on the square.
    NSBitmapImageRep *rep = (NSBitmapImageRep *)editor.materialPreviewView.image.representations.firstObject;
    NSUInteger pixel[4];
    [rep getPixel:pixel atX:rep.pixelsWide / 2 y:rep.pixelsHigh / 4];
    XCTAssertGreaterThan(pixel[0] + pixel[1], 200U, @"the glow added onto the background");

    // An unsaved edit: drawn as edited.
    [editor.stagesController setSelectionIndex:0];
    [editor.stagesController setValue:@"none" forKeyPath:@"selection.blend"];
    [editor.editingContext processPendingChanges];
    [editor.materialPreview renderAtTime:0];
    rep = (NSBitmapImageRep *)editor.materialPreviewView.image.representations.firstObject;
    [rep getPixel:pixel atX:rep.pixelsWide / 2 y:rep.pixelsHigh / 4];
    XCTAssertLessThan(pixel[0] + pixel[1], 120U, @"blend none: the ambient pass skips it");
}

@end
