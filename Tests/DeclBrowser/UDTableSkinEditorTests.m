#import "UDDeclBrowserTestCase.h"

#import <UDCodeKit/UDErrorsViewController.h>
#import "UDDeclManagedObjects.h"
#import "UDDeclDocument.h"
#import "UDEditorTabManager.h"
#import "UDTableEditorViewController.h"
#import "UDSkinEditorViewController.h"
#import "UDWorkspaceWindowController.h"

static NSString *const UDFixtureMaterials =
    @"table udtest_ramp { snap { 0, 0.5, 1 } }\n"
     "\n"
     "textures/udtest/wall\n"
     "{\n"
     "\t{\n"
     "\t\tmap textures/udtest/wall\n"
     "\t}\n"
     "}\n";

static NSString *const UDFixtureSkin =
    @"skin udtest_skin {\n"
     "\tmodel models/udtest/crate.lwo\n"
     "\ttextures/udtest/old textures/udtest/wall\n"
     "\t* textures/udtest/missing\n"
     "}\n";

/**
 * The table and skin editors, driven against loose decl files written for
 * the test (no game data), as the PDA editor's are: opened from the outline,
 * edited through their own lists and buttons, saved with File > Save.
 */
@interface UDTableSkinEditorTests : UDDeclBrowserTestCase
@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, copy) NSString *savePath;
@end

@implementation UDTableSkinEditorTests

- (void)setUp {
    [super setUp];
    self.basePath = [self.scratchDirectory stringByAppendingPathComponent:@"install"];
    self.savePath = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *folder in @[@"base/materials", @"base/skins", @"base/models/udtest"]) {
        [files createDirectoryAtPath:[self.basePath stringByAppendingPathComponent:folder]
         withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    [files createDirectoryAtPath:self.savePath withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDFixtureMaterials writeToFile:[self.basePath stringByAppendingPathComponent:@"base/materials/udtest.mtr"]
                         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDFixtureSkin writeToFile:[self.basePath stringByAppendingPathComponent:@"base/skins/udtest.skin"]
                    atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"" writeToFile:[self.basePath stringByAppendingPathComponent:@"base/models/udtest/crate.lwo"]
          atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (UDWorkspaceWindowController *)openFixtureWorkspace {
    return [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:self.basePath savePath:self.savePath]];
}

- (NSString *)savedText:(NSString *)relativePath {
    for (NSString *root in @[self.savePath, self.basePath]) {
        NSString *text = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:[@"base" stringByAppendingPathComponent:relativePath]]
                                                   encoding:NSUTF8StringEncoding error:NULL];
        if (text != nil) return text;
    }
    XCTFail(@"no %@ after saving", relativePath);
    return @"";
}

- (void)save:(UDWorkspaceWindowController *)controller {
    [NSApp sendAction:@selector(saveDocument:) to:controller from:nil];
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];
}

/// Its +/- buttons, sent as a click on one segment sends them.
- (void)press:(NSInteger)segment ofButtonsWithAction:(SEL)action inView:(NSView *)view {
    NSSegmentedControl *buttons = [self segmentedControlWithAction:action inView:view];
    XCTAssertNotNil(buttons, @"the list has +/- buttons");
    [buttons setSelectedSegment:segment];
    [NSApp sendAction:buttons.action to:buttons.target from:buttons];
}

/// A cell edited in a table, as typing into it and Return do.
- (void)set:(NSString *)value row:(NSInteger)row column:(NSString *)identifier of:(NSTableView *)table {
    NSTableColumn *column = [table tableColumnWithIdentifier:identifier];
    XCTAssertNotNil(column, @"a %@ column", identifier);
    [table.dataSource tableView:table setObjectValue:value forTableColumn:column row:row];
}

- (id)valueAtRow:(NSInteger)row column:(NSString *)identifier of:(NSTableView *)table {
    return [table.dataSource tableView:table objectValueForTableColumn:[table tableColumnWithIdentifier:identifier] row:row];
}

#pragma mark - Tables

- (UDTableEditorViewController *)openTableIn:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:@"table/udtest_ramp" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDTableEditorViewController class]], @"a table opens in the table editor, not %@", editor);
    return (UDTableEditorViewController *)editor;
}

- (void)testATableOpensWithItsValues {
    UDTableEditorViewController *editor = [self openTableIn:[self openFixtureWorkspace]];
    if (![editor isKindOfClass:[UDTableEditorViewController class]]) return;

    XCTAssertEqual([self buttonTitled:@"Snap" inView:editor.view].state, NSControlStateValueOn);
    XCTAssertEqual([self buttonTitled:@"Clamp" inView:editor.view].state, NSControlStateValueOff);
    XCTAssertEqual(editor.valuesTable.numberOfRows, 3);
    XCTAssertEqualObjects([self valueAtRow:1 column:@"value" of:editor.valuesTable], @"0.5");
    XCTAssertEqualObjects(editor.graphView.values, (@[@0, @0.5, @1]), @"the curve shows them");
    XCTAssertTrue(editor.graphView.snap, @"in steps");
    XCTAssertFalse(editor.editorDocument.isDocumentEdited);
}

- (void)testEditingATablesValuesSavesThemAndUndoes {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDTableEditorViewController *editor = [self openTableIn:controller];
    if (![editor isKindOfClass:[UDTableEditorViewController class]]) return;

    [self set:@"0.25" row:1 column:@"value" of:editor.valuesTable];
    XCTAssertEqualObjects(editor.values, (@[@0, @0.25, @1]));
    [self set:@"high" row:2 column:@"value" of:editor.valuesTable];
    XCTAssertEqualObjects(editor.values, (@[@0, @0.25, @1]), @"not a number: refused");

    [editor.valuesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
    [self press:0 ofButtonsWithAction:@selector(addOrRemoveValue:) inView:editor.view];
    XCTAssertEqualObjects(editor.values, (@[@0, @0.25, @1, @1]), @"+ adds a copy after the selection");
    [self press:1 ofButtonsWithAction:@selector(addOrRemoveValue:) inView:editor.view];
    XCTAssertEqualObjects(editor.values, (@[@0, @0.25, @1]), @"- takes the selection off");

    [[self buttonTitled:@"Clamp" inView:editor.view] performClick:nil];
    XCTAssertTrue(editor.table.clamp);
    [self spinUntil:^BOOL{ return editor.editorDocument.isDocumentEdited; } timeout:1.0];   // the event's end
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    [self save:controller];
    NSString *text = [self savedText:@"materials/udtest.mtr"];
    XCTAssertTrue([text containsString:@"{ 0, 0.25, 1 }"], @"%@", text);
    XCTAssertTrue([text containsString:@"clamp"], @"%@", text);
    XCTAssertTrue([text containsString:@"textures/udtest/wall"], @"the material beside it stays:\n%@", text);

    [self set:@"0.75" row:1 column:@"value" of:editor.valuesTable];
    [editor.editingContext processPendingChanges];
    [[controller.window undoManager] undo];
    [self spinUntil:^BOOL{ return NO; } timeout:0.05];
    XCTAssertEqualObjects(editor.values, (@[@0, @0.25, @1]), @"Undo takes the edit back");
    XCTAssertEqualObjects([self valueAtRow:1 column:@"value" of:editor.valuesTable], @"0.25", @"and the list shows it");
}

- (void)testATablesLastValueStays {
    UDTableEditorViewController *editor = [self openTableIn:[self openFixtureWorkspace]];
    if (![editor isKindOfClass:[UDTableEditorViewController class]]) return;
    for (NSInteger i = 0; i < 3; i++) {
        [editor.valuesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self press:1 ofButtonsWithAction:@selector(addOrRemoveValue:) inView:editor.view];
    }
    XCTAssertEqual(editor.values.count, 1U, @"a table keeps a value: the engine reads one without as its default");
}

#pragma mark - Skins

- (UDSkinEditorViewController *)openSkinIn:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:@"skin/udtest_skin" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDSkinEditorViewController class]], @"a skin opens in the skin editor, not %@", editor);
    return (UDSkinEditorViewController *)editor;
}

- (void)testASkinOpensWithItsMappingsAndModels {
    UDSkinEditorViewController *editor = [self openSkinIn:[self openFixtureWorkspace]];
    if (![editor isKindOfClass:[UDSkinEditorViewController class]]) return;

    XCTAssertEqualObjects(editor.mappings, (@[@[@"textures/udtest/old", @"textures/udtest/wall"], @[@"*", @"textures/udtest/missing"]]));
    XCTAssertEqualObjects(editor.models, @[@"models/udtest/crate.lwo"]);
    XCTAssertEqual(editor.mappingsTable.numberOfRows, 2);
    XCTAssertEqualObjects([self valueAtRow:1 column:@"from" of:editor.mappingsTable], @"*");
    XCTAssertEqual(editor.modelsTable.numberOfRows, 1);
    XCTAssertFalse(editor.editorDocument.isDocumentEdited);
}

- (void)testEditingASkinSavesIt {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDSkinEditorViewController *editor = [self openSkinIn:controller];
    if (![editor isKindOfClass:[UDSkinEditorViewController class]]) return;

    [self set:@"textures/udtest/wall" row:1 column:@"to" of:editor.mappingsTable];
    [self set:@"two words" row:0 column:@"from" of:editor.mappingsTable];
    XCTAssertEqualObjects(editor.mappings[0][0], @"textures/udtest/old", @"a name with a space would break the decl: refused");

    [self press:0 ofButtonsWithAction:@selector(addOrRemoveMapping:) inView:editor.view];
    XCTAssertEqualObjects(editor.mappings.lastObject, (@[@"*", @"_default"]), @"+ adds the default skin's mapping");
    [editor.mappingsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self press:1 ofButtonsWithAction:@selector(addOrRemoveMapping:) inView:editor.view];
    XCTAssertEqual(editor.mappings.count, 2U, @"- takes the selection off");

    [self save:controller];
    NSString *text = [self savedText:@"skins/udtest.skin"];
    XCTAssertTrue([text containsString:@"* textures/udtest/wall"], @"%@", text);
    XCTAssertTrue([text containsString:@"* _default"], @"%@", text);
    XCTAssertFalse([text containsString:@"textures/udtest/old"], @"%@", text);
    XCTAssertTrue([text containsString:@"model models/udtest/crate.lwo"], @"%@", text);

    [self closeWorkspace:controller];
    UDSkinEditorViewController *again = [self openSkinIn:[self openFixtureWorkspace]];
    XCTAssertEqualObjects(again.mappings, (@[@[@"*", @"textures/udtest/wall"], @[@"*", @"_default"]]), @"and read back");
}

/// A material the skin maps to that is neither a decl nor an image, and a
/// model not found: in the Issues tab, before saving; a click shows the row.
- (void)testWhatASkinNamesThatIsNotThereIsAnIssue {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDSkinEditorViewController *editor = [self openSkinIn:controller];
    if (![editor isKindOfClass:[UDSkinEditorViewController class]]) return;

    NSArray<UDDiagnosticItem *> *issues = editor.diagnosticStore.allDiagnostics;
    XCTAssertEqualObjects([issues valueForKey:@"message"],
        (@[@"Material “textures/udtest/old” is neither a decl nor an image: the engine makes it a default material",
           @"Material “textures/udtest/missing” is neither a decl nor an image: the engine makes it a default material"]));
    XCTAssertEqual(issues.lastObject.line, 4, @"on the line naming it");
    XCTAssertEqual(issues.lastObject.severity, UDDiagnosticSeverityWarning);

    [self press:0 ofButtonsWithAction:@selector(addOrRemoveModel:) inView:editor.view];
    [self spinUntil:^BOOL{ return editor.diagnosticStore.allDiagnostics.count == 3; } timeout:1.0];
    UDDiagnosticItem *model = nil;
    for (UDDiagnosticItem *item in editor.diagnosticStore.allDiagnostics) {
        if ([item.message hasPrefix:@"Model"]) model = item;
    }
    XCTAssertEqualObjects(model.message, @"Model “models/” is not found", @"+ on the models: one to name");
    XCTAssertEqual(model.severity, UDDiagnosticSeverityError);

    UDErrorsViewController *issuesTab = [controller valueForKey:@"issuesNavigator"];
    [editor.modelsTable deselectAll:nil];
    [controller errorsViewController:issuesTab didSelectDiagnostic:model inStore:editor.diagnosticStore];
    XCTAssertEqual(editor.modelsTable.selectedRow, 1, @"a click shows the row");

    [self set:@"models/udtest/crate.lwo" row:1 column:@"model" of:editor.modelsTable];
    [self spinUntil:^BOOL{ return editor.diagnosticStore.allDiagnostics.count == 2; } timeout:1.0];
    XCTAssertEqual(editor.diagnosticStore.allDiagnostics.count, 2U, @"a model that is there is no issue");
}

- (void)testANewSkinGetsAFileOfItsOwn {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    if (controller == nil) return;
    __block BOOL asked = NO;
    [self whenModalWindowAppears:^(NSWindow *window) {
        asked = YES;
        NSTextField *field = nil;
        NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:window.contentView];
        while (queue.count > 0) {
            NSView *next = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([next isKindOfClass:[NSTextField class]] && [(NSTextField *)next isEditable]) field = (NSTextField *)next;
            [queue addObjectsFromArray:next.subviews];
        }
        [self typeText:@"udtest_fresh" intoField:field];
        [[self buttonTitled:@"Create" inView:window.contentView] performClick:nil];
    }];
    [NSApp sendAction:@selector(newSkin:) to:controller from:nil];
    XCTAssertTrue(asked, @"New Skin asks for its name");

    UDBaseEditorViewController *selected = [[self tabManagerOf:controller] selectedEditor];
    XCTAssertTrue([selected isKindOfClass:[UDSkinEditorViewController class]], @"and opens it in the skin editor, not %@", selected);
    UDSkinEditorViewController *editor = (UDSkinEditorViewController *)selected;
    [self press:0 ofButtonsWithAction:@selector(addOrRemoveMapping:) inView:editor.view];
    [self save:controller];

    NSString *text = [NSString stringWithContentsOfFile:[self.savePath stringByAppendingPathComponent:@"base/skins/udtest_fresh.skin"]
                                               encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertTrue([text containsString:@"skin udtest_fresh"], @"its own file is written:\n%@", text);
    XCTAssertTrue([text containsString:@"* _default"], @"%@", text);
}

@end
