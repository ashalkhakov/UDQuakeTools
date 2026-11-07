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

@interface UQExtensionTests : XCTestCase
@end

@implementation UQExtensionTests {
    NSString *_root;        // the test's own: the game (base/), the mod's savepath (save/), the project
    NSString *_project;
    UQProject *_quarry;
}

static NSString *const UQMaterial =
    @"textures/test/wall\n{\n\tqer_editorimage textures/test/wall.tga\n\tdiffusemap textures/test/wall.tga\n}\n\n"
    @"textures/test/floor\n{\n\tdiffusemap textures/test/floor.tga\n}\n";

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

@end
