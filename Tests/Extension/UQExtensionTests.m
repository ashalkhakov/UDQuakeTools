//
//  UQExtensionTests.m
//
//  UDCode's UDQuakeTools extension: a folder's .qworkspace is a Quarry
//  project, its game started; its tree, the decls by type and name, the
//  scripts and the GUIs, filtered with Quarry's wildcards; its quarry: URLs
//  a decl's or a game file's, read through the game and saved into its
//  savepath, the game's own files left as they are. On a made-up game:
//  loose files in a base folder of the test's own.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UQExtension.h"
#import "UQProject.h"
#import "UDWorkspace.h"
#import "UDWorkspaceItem.h"
#import "UQDeclDocument.h"
#import "UQEditorHost.h"
#import "UDDeclDocument.h"
#import "UDDeclTable.h"
#import "UDMaterialEditorViewController.h"
#import "UDTableEditorViewController.h"
#import "UQGuiDocument.h"
#import "UDGuiEditorViewController.h"
#import "UDTextFileDocument.h"

@interface UQExtensionTests : XCTestCase
@end

@implementation UQExtensionTests {
    NSString *_root;        // the test's own: the game (base/), the mod's savepath (save/), the project
    NSString *_project;
    UQProject *_quarry;
}

static NSString *const UQMaterial =
    @"textures/test/wall\n{\n\tqer_editorimage textures/test/wall.tga\n\tdiffusemap textures/test/wall.tga\n}\n\n"
    @"textures/test/floor\n{\n\tdiffusemap textures/test/floor.tga\n}\n\n"
    @"table testtable { { 0, 0.5, 1 } }\n";

- (void)write:(NSString *)text to:(NSString *)relative {
    NSString *path = [_root stringByAppendingPathComponent:relative];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (NSString *)contentsOf:(NSString *)relative {
    return [NSString stringWithContentsOfFile:[_root stringByAppendingPathComponent:relative] encoding:NSUTF8StringEncoding error:NULL];
}

- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];
    _root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [self write:UQMaterial to:@"game/base/materials/test.mtr"];
    [self write:@"void main() {\n}\n" to:@"game/base/script/doors.script"];
    [self write:@"windowDef Desktop\n{\n\trect 0, 0, 640, 480\n}\n" to:@"game/base/guis/test.gui"];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_root stringByAppendingPathComponent:@"save"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *settings = @{
        @"fs_basepath": [_root stringByAppendingPathComponent:@"game"],
        @"fs_savepath": [_root stringByAppendingPathComponent:@"save"],
        @"fs_homepath": [_root stringByAppendingPathComponent:@"save"],
        @"fs_cdpath": @"", @"fs_game": @"base", @"fs_game_base": @"", @"gamedir": @"base",
        @"pakFileExtension": @"pk4", @"fs_debug": @NO, @"fs_restrict": @NO, @"fs_copyfiles": @0,
        @"fs_caseSensitiveOS": @YES, @"decl_show": @0, @"com_SingleDeclFile": @NO,
        @"com_singleDeclFileName": @"", @"com_singleDeclFileWriteMode": @1,
    };
    _project = [_root stringByAppendingPathComponent:@"mod"];
    [[NSFileManager defaultManager] createDirectoryAtPath:_project withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSJSONSerialization dataWithJSONObject:settings options:0 error:NULL]
        writeToFile:[_project stringByAppendingPathComponent:@"mod.qworkspace"] atomically:YES];
}

- (void)tearDown {
    _quarry = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_root error:NULL];
    [super tearDown];
}

/// The project of the test's folder, its game started.
- (UQProject *)startedProject {
    _quarry = [[UQProject alloc] initWithFolder:[NSURL fileURLWithPath:_project] workbench:nil];
    __block BOOL started = NO;
    [_quarry whenStarted:^(UDWorkspace *workspace) { started = YES; }];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!started && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertTrue(started);
    XCTAssertNotNil(_quarry.workspace, @"%@", _quarry.startupError);
    return _quarry;
}

/// The labels of @a element's children in the tree.
- (NSArray<NSString *> *)labelsUnder:(id)element of:(UQProject *)project {
    NSMutableArray *labels = [NSMutableArray array];
    for (id child in [project treeView:(id)nil childrenOfElement:element]) {
        [labels addObject:[project treeView:(id)nil itemForElement:child].label];
    }
    return labels;
}

- (id)child:(NSString *)label under:(id)element of:(UQProject *)project {
    for (id child in [project treeView:(id)nil childrenOfElement:element]) {
        if ([[project treeView:(id)nil itemForElement:child].label isEqualToString:label]) return child;
    }
    return nil;
}

// ---------------------------------------------------------------------------

- (void)testAURLIsADeclsOrAGameFiles {
    NSURL *decl = [UQProject URLOfDeclType:@"material" name:@"textures/test/a wall"];
    XCTAssertEqualObjects(decl.absoluteString, @"quarry:/material/textures/test/a%20wall");
    NSString *type, *name, *path;
    XCTAssertTrue([UQProject parseURL:decl typeName:&type name:&name path:&path]);
    XCTAssertEqualObjects(type, @"material");
    XCTAssertEqualObjects(name, @"textures/test/a wall");
    XCTAssertNil(path);

    NSURL *file = [UQProject URLOfGamePath:@"script/doors.script"];
    XCTAssertEqualObjects(file.absoluteString, @"quarry:/file/script/doors.script");
    XCTAssertTrue([UQProject parseURL:file typeName:&type name:&name path:&path]);
    XCTAssertEqualObjects(path, @"script/doors.script");
    XCTAssertNil(type);

    XCTAssertFalse([UQProject parseURL:[NSURL fileURLWithPath:@"/tmp/a"] typeName:NULL name:NULL path:NULL]);
    XCTAssertFalse([UQProject parseURL:[NSURL URLWithString:@"quarry:/material"] typeName:NULL name:NULL path:NULL]);
}

- (void)testAFolderWithoutAQWorkspaceSaysSo {
    [[NSFileManager defaultManager] removeItemAtPath:[_project stringByAppendingPathComponent:@"mod.qworkspace"] error:NULL];
    UQProject *project = [[UQProject alloc] initWithFolder:[NSURL fileURLWithPath:_project] workbench:nil];
    XCTAssertNil(project.workspaceFileURL);
    XCTAssertNotNil(project.startupError);
    XCTAssertEqualObjects([self labelsUnder:nil of:project], @[ @"Not started" ]);
}

- (void)testTheTreeIsTheDeclsScriptsAndGUIs {
    UQProject *project = [self startedProject];
    XCTAssertEqualObjects(project.workspaceFileURL.lastPathComponent, @"mod.qworkspace");
    NSArray *top = [self labelsUnder:nil of:project];
    for (NSString *expected in @[ @"material", @"script", @"guis" ]) {
        XCTAssertTrue([top containsObject:expected], @"%@ in %@", expected, top);
    }
    id material = [self child:@"material" under:nil of:project];
    UDTreeItem *materialItem = [project treeView:(id)nil itemForElement:material];
    XCTAssertEqual(materialItem.collapsibleState, UDTreeItemCollapsibleStateCollapsed);
    XCTAssertNil(materialItem.resourceURL, @"a type opens nothing");
    id textures = [self child:@"textures" under:material of:project];
    id test = [self child:@"test" under:textures of:project];
    XCTAssertEqualObjects([self labelsUnder:test of:project], (@[ @"floor", @"wall" ]), @"by name");

    UDTreeItem *wall = [project treeView:(id)nil itemForElement:[self child:@"wall" under:test of:project]];
    XCTAssertEqualObjects(wall.resourceURL, [UQProject URLOfDeclType:@"material" name:@"textures/test/wall"]);
    XCTAssertEqualObjects(NSStringFromSelector(wall.action), @"openResource:", @"VS Code's vscode.open");
    XCTAssertEqual([project treeView:(id)nil parentOfElement:[self child:@"wall" under:test of:project]], test);
    XCTAssertNil([project treeView:(id)nil parentOfElement:material]);

    id script = [self child:@"script" under:nil of:project];
    UDTreeItem *doors = [project treeView:(id)nil itemForElement:[self child:@"doors.script" under:script of:project]];
    XCTAssertEqualObjects(doors.resourceURL, [UQProject URLOfGamePath:@"script/doors.script"]);
}

- (void)testTheFilterTakesQuarrysWildcards {
    UQProject *project = [self startedProject];
    [project treeView:(id)nil filterDidChange:@"fl*"];
    NSArray *top = [self labelsUnder:nil of:project];
    XCTAssertEqualObjects(top, @[ @"material" ], @"only what has a match");
    id test = [self child:@"test" under:[self child:@"textures" under:[self child:@"material" under:nil of:project] of:project] of:project];
    XCTAssertEqualObjects([self labelsUnder:test of:project], @[ @"floor" ]);
    // no wildcard: anywhere in the name
    [project treeView:(id)nil filterDidChange:@"oor"];
    XCTAssertTrue([[self labelsUnder:nil of:project] containsObject:@"script"], @"doors.script");
    [project treeView:(id)nil filterDidChange:@""];
    XCTAssertTrue([[self labelsUnder:nil of:project] containsObject:@"guis"]);
}

- (void)testADeclIsReadAndSavedIntoTheSavepath {
    UQProject *project = [self startedProject];
    NSURL *wall = [UQProject URLOfDeclType:@"material" name:@"textures/test/wall"];
    NSError *error = nil;
    NSData *data = [project contentsOfURL:wall error:&error];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertTrue([text containsString:@"textures/test/wall.tga"], @"%@ %@", text, error);
    XCTAssertFalse([text containsString:@"floor"], @"its own text, not its file's");
    XCTAssertEqualObjects([project languageModeOfURL:wall], @"iddecl");
    XCTAssertEqualObjects([project displayNameOfURL:wall], @"wall");

    NSString *edited = [text stringByReplacingOccurrencesOfString:@"wall.tga\n}" withString:@"wall.tga\n\tspecularmap textures/test/wall_s.tga\n}"];
    XCTAssertTrue([project writeContents:[edited dataUsingEncoding:NSUTF8StringEncoding] toURL:wall error:&error], @"%@", error);
    NSString *saved = [self contentsOf:@"save/base/materials/test.mtr"];
    XCTAssertTrue([saved containsString:@"wall_s.tga"], @"into the savepath: %@", saved);
    XCTAssertTrue([saved containsString:@"textures/test/floor"], @"the file's other decls kept");
    XCTAssertEqualObjects([self contentsOf:@"game/base/materials/test.mtr"], UQMaterial, @"the game's own file left as it is");
    // read again: as saved
    NSString *again = [[NSString alloc] initWithData:[project contentsOfURL:wall error:NULL] encoding:NSUTF8StringEncoding];
    XCTAssertTrue([again containsString:@"wall_s.tga"], @"%@", again);

    XCTAssertNil([project contentsOfURL:[UQProject URLOfDeclType:@"material" name:@"textures/none"] error:&error]);
    XCTAssertNotNil(error);
}

- (void)testAGameFileIsReadAndSavedIntoTheSavepath {
    UQProject *project = [self startedProject];
    NSURL *doors = [UQProject URLOfGamePath:@"script/doors.script"];
    XCTAssertEqualObjects([project languageModeOfURL:doors], @"idscript");
    XCTAssertEqualObjects([project displayNameOfURL:doors], @"doors.script");
    NSError *error = nil;
    NSString *text = [[NSString alloc] initWithData:[project contentsOfURL:doors error:&error] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(text, @"void main() {\n}\n", @"%@", error);
    XCTAssertTrue([project writeContents:[@"void main() {\n\tsys.wait(1);\n}\n" dataUsingEncoding:NSUTF8StringEncoding] toURL:doors error:&error], @"%@", error);
    XCTAssertEqualObjects([self contentsOf:@"save/base/script/doors.script"], @"void main() {\n\tsys.wait(1);\n}\n");
    XCTAssertEqualObjects([self contentsOf:@"game/base/script/doors.script"], @"void main() {\n}\n");
    XCTAssertNil([project contentsOfURL:[UQProject URLOfGamePath:@"script/none.script"] error:&error]);
}

- (void)testTheExtensionGivesAWindowItsProjectNavigatorAndProvider {
    UQExtension *extension = [[UQExtension alloc] init];
    [extension extensionDidLoad:[NSBundle bundleForClass:[UQExtension class]]];
    XCTAssertNotEqual([extension languageFuncForIdentifier:@"idscript"], NULL);
    XCTAssertNotEqual([extension languageFuncForIdentifier:@"iddecl"], NULL);
    XCTAssertEqual([extension languageFuncForIdentifier:@"json"], NULL);
    NSString *plist = [[NSBundle bundleForClass:[UQExtension class]] pathForResource:@"LanguageInfo" ofType:@"plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
    XCTAssertEqualObjects(info[@"activationEvents"], @[ @"workspaceContains:*.qworkspace" ]);
    NSDictionary *script = nil;
    for (NSDictionary *mode in info[@"languageModes"]) {
        if ([mode[@"identifier"] isEqualToString:@"idscript"]) script = mode;
    }
    XCTAssertEqualObjects(script[@"languageServerSchemes"], (@[ @"file", @"quarry" ]), @"a script in a pak has its server");
}

// ---------------------------------------------------------------------------
// MARK: - A decl as a custom document (its model Core Data's)
// ---------------------------------------------------------------------------

/// The main queue's work done, an event's undo group closed with it.
- (void)spin {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

- (void)testADeclWithAnEditorIsACustomDocumentOfItsObjects {
    UQProject *project = [self startedProject];
    XCTAssertTrue([UQDeclDocument isStructuredDeclType:@"table" inWorkspace:project.workspace]);
    XCTAssertTrue([UQDeclDocument isStructuredDeclType:@"material" inWorkspace:project.workspace]);
    XCTAssertFalse([UQDeclDocument isStructuredDeclType:@"email" inWorkspace:project.workspace], @"no editor of its own: text");
    XCTAssertFalse([UQDeclDocument isStructuredDeclType:@"nonsense" inWorkspace:project.workspace]);
    NSError *error = nil;
    UQDeclDocument *table = [[UQDeclDocument alloc] initWithDeclType:@"table" name:@"testtable" inWorkspace:project.workspace error:&error];
    XCTAssertNotNil(table, @"%@", error);
    UDDeclTable *object = table.declDocument.declObject;
    XCTAssertTrue([object isKindOfClass:[UDDeclTable class]]);
    XCTAssertEqual(object.values.count, 3u);
    XCTAssertTrue([[table textOfDocument] containsString:@"testtable"]);
    XCTAssertFalse(table.isEdited);

    // an edit of its objects: the document edited, its text the edit's, its undo the context's
    UDCodeDocument *document = [[UDCodeDocument alloc] initWithCustomDocument:table URL:[UQProject URLOfDeclType:@"table" name:@"testtable"]
                                                           fileSystemProvider:project languageMode:nil];
    object.clamp = YES;
    [self spin];
    XCTAssertTrue(table.isEdited);
    XCTAssertTrue(document.isModified);
    XCTAssertTrue([[document.textModel getValue] containsString:@"clamp"], @"%@", [document.textModel getValue]);
    XCTAssertEqual(table.undoManager, table.declDocument.editingContext.undoManager);
    [table.undoManager undo];
    [self spin];
    XCTAssertFalse(object.clamp);
    XCTAssertFalse([[document.textModel getValue] containsString:@"clamp"]);

    // its text, typed: one edit of its objects
    NSString *text = [document.textModel getValue];
    NSRange brace = [text rangeOfString:@"{"];
    text = [text stringByReplacingCharactersInRange:brace withString:@"{ snap"];
    XCTAssertTrue([table applyText:text error:&error], @"%@", error);
    XCTAssertTrue(object.snap);

    // saved: through the decl manager, into the savepath
    XCTAssertTrue([table saveCustomDocument:&error], @"%@", error);
    XCTAssertFalse(table.isEdited);
    NSString *saved = [self contentsOf:@"save/base/materials/test.mtr"];
    XCTAssertTrue([saved containsString:@"snap"], @"%@", saved);
    XCTAssertEqualObjects([self contentsOf:@"game/base/materials/test.mtr"], UQMaterial);

    // reverted: as saved
    object.clamp = YES;
    [self spin];
    XCTAssertTrue([table revertCustomDocument:&error], @"%@", error);
    XCTAssertFalse(table.isEdited);
    XCTAssertFalse(object.clamp);
}

- (void)testTheExtensionOpensItAndHostsItsEditorWithItsPanes {
    UQProject *project = [self startedProject];
    NSError *error = nil;
    UQDeclDocument *material = [[UQDeclDocument alloc] initWithDeclType:@"material" name:@"textures/test/wall"
                                                            inWorkspace:project.workspace error:&error];
    XCTAssertNotNil(material, @"%@", error);
    UDCodeDocument *document = [[UDCodeDocument alloc] initWithCustomDocument:material
                                                                          URL:[UQProject URLOfDeclType:@"material" name:@"textures/test/wall"]
                                                           fileSystemProvider:project languageMode:nil];
    UQExtension *extension = [[UQExtension alloc] init];
    [extension extensionDidLoad:[NSBundle bundleForClass:[UQExtension class]]];
    UQEditorHost *host = (UQEditorHost *)[extension workbench:(id)nil editorForDocument:document];
    XCTAssertTrue([host isKindOfClass:[UQEditorHost class]]);
    XCTAssertTrue([host.editor isKindOfClass:[UDMaterialEditorViewController class]]);
    XCTAssertNotNil(host.view);
    XCTAssertEqual(host.view, host.editor.view, @"the editor's own view in the tab");
    XCTAssertEqual([(UDDeclEditorViewController *)host.editor document], material.declDocument, @"the custom document's model");
    NSArray *titles = [host.inspectorViewControllers valueForKey:@"title"];
    XCTAssertEqualObjects(titles, (@[ @"Material", @"Stage" ]), @"its panes, the inspector's tabs");
    for (NSViewController *pane in host.inspectorViewControllers) XCTAssertNotNil([host imageForInspectorViewController:pane]);

    // a text decl, or a plain UDCode document: not the extension's
    UDCodeDocument *text = [[UDCodeDocument alloc] initWithText:@"x" fileURL:nil];
    XCTAssertNil([extension workbench:(id)nil editorForDocument:text]);
}

// ---------------------------------------------------------------------------
// MARK: - A GUI as a custom document, its Windows on the left
// ---------------------------------------------------------------------------

- (void)testAGuiIsACustomDocumentInQuarrysGuiEditorItsWindowsOnTheLeft {
    UQProject *project = [self startedProject];
    NSError *error = nil;
    XCTAssertTrue([UQGuiDocument isGuiPath:@"guis/test.gui"]);
    XCTAssertFalse([UQGuiDocument isGuiPath:@"script/doors.script"]);
    UQGuiDocument *gui = [[UQGuiDocument alloc] initWithPath:@"guis/test.gui" inWorkspace:project.workspace error:&error];
    XCTAssertNotNil(gui, @"%@", error);
    XCTAssertTrue([[gui textOfDocument] containsString:@"windowDef Desktop"]);
    UDCodeDocument *document = [[UDCodeDocument alloc] initWithCustomDocument:gui URL:[UQProject URLOfGamePath:@"guis/test.gui"]
                                                           fileSystemProvider:project languageMode:nil];
    UQExtension *extension = [[UQExtension alloc] init];
    [extension extensionDidLoad:[NSBundle bundleForClass:[UQExtension class]]];
    UQEditorHost *host = (UQEditorHost *)[extension workbench:(id)nil editorForDocument:document];
    XCTAssertTrue([host.editor isKindOfClass:[UDGuiEditorViewController class]]);
    XCTAssertEqual(gui.editor, host.editor);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 700) styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView = host.view;

    // its Windows pane on the left of its view, in the host's split (its XIB's, connected)
    XCTAssertNotNil(host.splitView);
    XCTAssertEqual(host.splitView.subviews.count, 2u);
    XCTAssertEqual(host.splitView.subviews.firstObject, (NSView *)host.navigatorTabs);
    XCTAssertEqualObjects([host.navigatorTabs.tabViewItems valueForKey:@"label"], @[ @"Windows" ]);
    XCTAssertEqual(host.editor.view.superview, host.editorHost);
    XCTAssertFalse([[host.inspectorViewControllers valueForKey:@"title"] containsObject:@"Windows"], @"not an inspector's tab");
    XCTAssertTrue([[host.inspectorViewControllers valueForKey:@"title"] containsObject:@"Properties"]);

    // typed in its text: one Edit Source of the GUI, undone as one
    NSString *before = [gui textOfDocument];
    NSString *typed = [before stringByReplacingOccurrencesOfString:@"640, 480" withString:@"320, 240"];
    XCTAssertTrue([gui applyText:typed error:&error]);
    XCTAssertTrue([[(UDGuiEditorViewController *)host.editor currentText] containsString:@"320, 240"]);
    [self spin];
    XCTAssertTrue(gui.isEdited);
    [gui.undoManager undo];
    XCTAssertTrue([[gui textOfDocument] containsString:@"640, 480"], @"%@", [gui textOfDocument]);

    // saved into the savepath
    XCTAssertTrue([gui applyText:typed error:&error]);
    [self spin];
    XCTAssertTrue([gui saveCustomDocument:&error], @"%@", error);
    XCTAssertTrue([[self contentsOf:@"save/base/guis/test.gui"] containsString:@"320, 240"], @"%@", [self contentsOf:@"save/base/guis/test.gui"]);
    XCTAssertTrue([[self contentsOf:@"game/base/guis/test.gui"] containsString:@"640, 480"]);
    XCTAssertFalse(gui.isEdited);
    [window close];
}

@end
