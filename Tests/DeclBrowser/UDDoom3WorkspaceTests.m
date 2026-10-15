#import "UDDeclBrowserTestCase.h"

#import "UDDeclManagedObjects.h"
#import "UDEditorTabManager.h"
#import "UDPDAEditorViewController.h"
#import "UDTextEditorViewController.h"
#import "UDWorkspace.h"
#import "UDWorkspaceDocument.h"
#import "UDBaseDocument.h"
#import "idDeclManager.h"

/**
 * The Decl Browser against a real Doom 3 install (see UDDoom3InstallPath:
 * $UD_DOOM3_PATH, defaulting to /Volumes/ExtraSSD/games/DOOM 3). Every decl
 * here comes out of the retail pk4s through the ported file system.
 *
 * The install is only ever read: fs_savepath is a scratch directory, and
 * every case checks that base/ is byte-for-byte as it found it (in docker
 * the install is also mounted read-only). Where no install is present the
 * cases log that and return, as they do on CI.
 */
@interface UDDoom3WorkspaceTests : UDDeclBrowserTestCase
@property (nonatomic, copy) NSString *installPath;
@property (nonatomic, copy) NSString *savePath;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray *> *baseSnapshot;
@end

@implementation UDDoom3WorkspaceTests

/// Name -> [size, modification date] of everything directly in base/.
- (NSDictionary<NSString *, NSArray *> *)snapshotOfBase {
    NSString *base = [self.installPath stringByAppendingPathComponent:@"base"];
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:base error:NULL]) {
        NSDictionary *attributes = [[NSFileManager defaultManager]
            attributesOfItemAtPath:[base stringByAppendingPathComponent:name] error:NULL];
        snapshot[name] = @[attributes[NSFileSize] ?: @0, attributes[NSFileModificationDate] ?: [NSNull null]];
    }
    return snapshot;
}

- (void)setUp {
    [super setUp];
    self.installPath = UDDoom3InstallPath();
    if (self.installPath == nil) {
        NSLog(@"UDDoom3WorkspaceTests: no Doom 3 install (set UD_DOOM3_PATH); these cases check nothing here");
        return;
    }
    self.savePath = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.savePath
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    self.baseSnapshot = [self snapshotOfBase];
}

- (void)tearDown {
    if (self.installPath != nil) {
        [super tearDown];
        XCTAssertEqualObjects([self snapshotOfBase], self.baseSnapshot,
                              @"the Doom 3 install must come out exactly as it went in");
        return;
    }
    [super tearDown];
}

- (UDWorkspaceWindowController *)openDoom3 {
    return [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:self.installPath
                                                                      savePath:self.savePath]];
}

#pragma mark - Browsing

- (void)testTheOutlineListsTheRetailDecls {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    NSOutlineView *outline = controller.outlineView;
    NSMutableSet *topLevel = [NSMutableSet set];
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        [topLevel addObject:[[outline itemAtRow:row] name]];
    }
    for (NSString *group in @[@"material", @"table", @"skin", @"particle", @"pda", @"email", @"audio", @"video", @"script", @"guis"]) {
        XCTAssertTrue([topLevel containsObject:group], @"the outline should have a %@ group; it has %@", group, topLevel);
    }

    NSArray<NSString *> *paths = [self expandedOutlinePathsInController:controller];
    NSUInteger pdas = [[paths filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'pda/'"]] count];
    XCTAssertGreaterThanOrEqual(pdas, 60U, @"pak000.pk4 ships 68 PDA files; the outline lists %lu PDAs", (unsigned long)pdas);
    for (NSString *path in @[@"pda/admin_moses", @"email/admin_moses_email_1", @"material/textures/base_wall/lfwall27d"]) {
        XCTAssertTrue([paths containsObject:path], @"the outline should list %@", path);
    }

    idDeclManager *declManager = ((UDWorkspaceDocument *)controller.document).workspace.declManager;
    NSUInteger materials = 0;
    for (id decl in [declManager declsOfType:DECL_MATERIAL forceParse:NO]) {
        (void)decl;
        materials++;
    }
    XCTAssertGreaterThan(materials, 1000U, @"the retail materials should all be indexed");
}

- (void)testTheNameFilterNarrowsTheOutline {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    NSUInteger everything = [self expandedOutlinePathsInController:controller].count;

    controller.nameFilterField.stringValue = @"*moses*";
    [controller nameFilterChanged:controller.nameFilterField];
    NSArray<NSString *> *filtered = [self expandedOutlinePathsInController:controller];

    XCTAssertLessThan(filtered.count, everything / 100, @"filtering on *moses* should leave a handful of rows");
    XCTAssertTrue([filtered containsObject:@"pda/admin_moses"], @"%@", filtered);
    XCTAssertTrue([filtered containsObject:@"email/admin_moses_email_3"], @"%@", filtered);
    for (NSString *path in filtered) {
        BOOL isLeafMatch = [path.lastPathComponent rangeOfString:@"moses" options:NSCaseInsensitiveSearch].location != NSNotFound;
        BOOL isGroup = ![path containsString:@"/"];
        XCTAssertTrue(isLeafMatch || isGroup, @"%@ does not match *moses*", path);
    }

    controller.nameFilterField.stringValue = @"";
    [controller nameFilterChanged:controller.nameFilterField];
    XCTAssertEqual([self expandedOutlinePathsInController:controller].count, everything,
                   @"clearing the filter should bring every row back");
}

- (void)testTheTextSearchFindsDeclsByContent {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    controller.textFilterField.stringValue = @"Martian Buddy";
    [controller textContainsFilterChanged:controller.textFilterField];

    NSOutlineView *results = controller.searchOutlineView;
    [results expandItem:nil expandChildren:YES];
    NSMutableArray *names = [NSMutableArray array];
    for (NSInteger row = 0; row < results.numberOfRows; row++) {
        id item = [results itemAtRow:row];
        [names addObject:[results.dataSource outlineView:results objectValueForTableColumn:results.tableColumns.firstObject byItem:item]];
    }
    XCTAssertTrue([names containsObject:@"email/admin_moses_email_1"],
                  @"the email that mentions Martian Buddy should be found; got %@", names);
}

- (void)testAMaterialOpensInTheTextEditor {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDBaseEditorViewController *editor = [self openOutlinePath:@"material/textures/base_wall/lfwall27d" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDTextEditorViewController class]], @"a material opens in the text editor, not %@", editor);
    NSTextView *textView = [self firstSubviewOfClass:[NSTextView class] inView:editor.view];
    XCTAssertTrue([textView.string containsString:@"textures/base_wall/lfwall27d"], @"the editor should show the material's source:\n%@", textView.string);
    XCTAssertTrue([textView.string containsString:@"{"], @"%@", textView.string);
}

- (void)testAPDAOpensInThePDAEditor {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDPDAEditorViewController *editor = [self openOutlinePath:@"pda/admin_moses" inController:controller];
    if (![editor isKindOfClass:[UDPDAEditorViewController class]]) {
        XCTFail(@"a pda decl should open in the PDA editor, not %@", editor);
        return;
    }
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:editor.view].stringValue, @"Jonathan A. Moses");
    XCTAssertEqualObjects([self textFieldBoundTo:@"pdaName" inView:editor.view].stringValue, @"Jonathan Moses");
    XCTAssertEqualObjects([self textFieldBoundTo:@"ident" inView:editor.view].stringValue, @"2463-21");
    XCTAssertEqualObjects([self textFieldBoundTo:@"post" inView:editor.view].stringValue, @"Administration");

    NSArray *subjects = [editor.emailArrayController.arrangedObjects valueForKey:@"subject"];
    XCTAssertEqual(subjects.count, 3U, @"admin_moses has three emails");
    XCTAssertTrue([subjects containsObject:@"Free Stuff!!"], @"%@", subjects);
    XCTAssertTrue([subjects containsObject:@"Storage Cabinet"], @"%@", subjects);

    // Opening the same decl again re-uses its tab.
    NSUInteger tabs = [[self tabManagerOf:controller] allEditors].count;
    [self openOutlinePath:@"pda/admin_moses" inController:controller];
    XCTAssertEqual([[self tabManagerOf:controller] allEditors].count, tabs, @"re-selecting a decl should not open a second tab");
}

#pragma mark - Editing

- (void)testEditingARetailPDASavesAnOverrideOutsideThePaks {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDPDAEditorViewController *editor = [self openOutlinePath:@"pda/admin_moses" inController:controller];
    if (![editor isKindOfClass:[UDPDAEditorViewController class]]) {
        XCTFail(@"a pda decl should open in the PDA editor, not %@", editor);
        return;
    }

    [self typeText:@"Jonathan Q. Moses" intoField:[self textFieldBoundTo:@"fullName" inView:editor.view]];
    XCTAssertEqualObjects(editor.pda.fullName, @"Jonathan Q. Moses");
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    [NSApp sendAction:@selector(saveDocument:) to:controller from:nil];
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];
    XCTAssertFalse(editor.editorDocument.isDocumentEdited, @"Save should leave the tab clean");

    // The decl came out of pak000.pk4, so the save lands under fs_savepath
    // as a loose file the game loads ahead of the pak.
    NSString *override = [self.savePath stringByAppendingPathComponent:@"base/newpdas/admin_moses.pda"];
    NSString *text = [NSString stringWithContentsOfFile:override encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertNotNil(text, @"saving should write %@; the save path holds %@", override,
                    [[NSFileManager defaultManager] subpathsAtPath:self.savePath]);
    XCTAssertTrue([text containsString:@"Jonathan Q. Moses"], @"%@", text);
    XCTAssertFalse([text containsString:@"Jonathan A. Moses"], @"%@", text);
    for (NSString *email in @[@"admin_moses_email_1", @"admin_moses_email_2", @"admin_moses_email_3"]) {
        XCTAssertTrue([text containsString:email], @"the override must keep %@:\n%@", email, text);
    }

    // A fresh workspace over the same install and save path sees the edit.
    [self closeWorkspace:controller];
    UDWorkspaceWindowController *reopened = [self openDoom3];
    UDPDAEditorViewController *again = [self openOutlinePath:@"pda/admin_moses" inController:reopened];
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:again.view].stringValue, @"Jonathan Q. Moses");
    XCTAssertEqual([again.emailArrayController.arrangedObjects count], 3U, @"the emails come back with the PDA");
}

@end
