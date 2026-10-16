#import "UDDeclBrowserTestCase.h"

#import "UDDeclDocument.h"
#import "UDEditorTabManager.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDNewDeclWindowController.h"
#import "UDTextEditorViewController.h"
#import "UDWorkspaceWindowController.h"

static NSString *const UDFixtureDefs =
    @"entityDef udtest_lamp {\n"
     "\t// lit at spawn\n"
     "\t\"inherit\"\t\"func_static\"\n"
     "\t\"model\"\t\"models/udtest/lamp.lwo\"\n"
     "}\n";

static NSString *const UDFixtureSounds =
    @"udtest_hum {\n"
     "\tminDistance\t1\n"
     "\tmaxDistance\t12\n"
     "\tsound/udtest/hum.wav\n"
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
    for (NSString *folder in @[@"base/def", @"base/sound", @"base/particles"]) {
        [files createDirectoryAtPath:[self.basePath stringByAppendingPathComponent:folder]
         withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    [files createDirectoryAtPath:self.savePath withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDFixtureDefs writeToFile:[self.basePath stringByAppendingPathComponent:@"base/def/udtest.def"]
                    atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureParticles writeToFile:[self.basePath stringByAppendingPathComponent:@"base/particles/udtest.prt"]
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
    XCTAssertTrue([editor isKindOfClass:[UDTextEditorViewController class]], @"it opens as text, not %@", editor);
    NSString *text = ((UDDeclDocument *)editor.editorDocument).textContent;
    XCTAssertTrue([text containsString:@"entityDef udtest_fresh"], @"%@", text);
    XCTAssertTrue([text containsString:@"\"DEFAULTED\"\t\"1\""], @"idDeclEntityDef's default definition: %@", text);

    [self save:controller];
    NSString *saved = [self savedText:@"def/udtest_fresh.def"];
    XCTAssertTrue([saved containsString:@"entityDef udtest_fresh"], @"%@", saved);
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
    UDTextEditorViewController *editor = [self openOutlinePath:@"entityDef/udtest_lamp" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDTextEditorViewController class]], @"an entityDef opens as text, not %@", editor);
    NSTextView *textView = [editor valueForKeyPath:@"editor.textView"];

    // Its comments and strings, each in a colour of their own.
    BOOL highlighted = [self spinUntil:^BOOL{
        NSColor *comment = [self colorOf:@"// lit" inTextView:textView];
        NSColor *string = [self colorOf:@"\"inherit\"" inTextView:textView];
        return comment != nil && string != nil && ![comment isEqual:string] &&
               ![comment isEqual:textView.textColor] && ![string isEqual:textView.textColor];
    } timeout:5.0];
    XCTAssertTrue(highlighted, @"the decl grammar colours the decl: comment %@, string %@, text %@",
                  [self colorOf:@"// lit" inTextView:textView], [self colorOf:@"\"inherit\"" inTextView:textView],
                  textView.textColor);
}

- (NSArray<UDDiagnosticItem *> *)testFindingsOf:(UDTextEditorViewController *)editor {
    return [editor.diagnosticStore.allDiagnostics filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"source == 'test'"]];
}

- (void)testTestHasTheDeclsParserReadItsText {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    UDTextEditorViewController *editor = [self openOutlinePath:@"particle/udtest_spark" inController:controller];
    NSTextView *textView = [editor valueForKeyPath:@"editor.textView"];
    XCTAssertEqual([self testFindingsOf:editor].count, 0U);

    // A line the particle's parser does not know, typed above its depthHack.
    NSRange depthHack = [textView.string rangeOfString:@"\tdepthHack"];
    NSInteger line = [[textView.string substringToIndex:depthHack.location] componentsSeparatedByString:@"\n"].count;
    [textView setSelectedRange:NSMakeRange(depthHack.location, 0)];
    [textView insertText:@"\tsparkle\t1\n"];
    [NSApp sendAction:@selector(testDecl:) to:controller from:nil];
    NSArray<UDDiagnosticItem *> *findings = [self testFindingsOf:editor];
    XCTAssertEqual(findings.count, 1U, @"the parser's warning: %@", findings);
    XCTAssertEqual(findings.firstObject.line, line, @"on the line it is about");
    XCTAssertTrue([findings.firstObject.message containsString:@"sparkle"], @"%@", findings.firstObject.message);
    XCTAssertEqual(findings.firstObject.severity, UDDiagnosticSeverityWarning);

    [textView insertText:@" "];
    XCTAssertEqual([self testFindingsOf:editor].count, 0U, @"an edit takes what a Test found away");
}

- (void)testTestFindsABraceNeverClosed {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    UDTextEditorViewController *editor = [self openOutlinePath:@"particle/udtest_spark" inController:controller];
    NSTextView *textView = [editor valueForKeyPath:@"editor.textView"];
    NSRange last = [textView.string rangeOfString:@"}" options:NSBackwardsSearch];
    [textView setSelectedRange:last];
    [textView insertText:@""];
    [NSApp sendAction:@selector(testDecl:) to:controller from:nil];
    NSArray<UDDiagnosticItem *> *findings = [self testFindingsOf:editor];
    XCTAssertEqual(findings.count, 1U, @"the brace, and no parse of a decl that does not hold together: %@", findings);
    XCTAssertEqual(findings.firstObject.line, 1, @"where it opened");
    XCTAssertEqual(findings.firstObject.severity, UDDiagnosticSeverityError);
}

@end
