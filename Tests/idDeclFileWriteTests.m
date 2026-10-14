#import <XCTest/XCTest.h>
#import "idFileSystem.h"
#import "idDeclManager.h"
#import "UDWorkspaceManager.h"

// A decl file is written whole (a mod's copy replaces the base game's), but
// the way Doom 3 does it (idDeclLocal::ReplaceSourceFileText): splice the
// changed decls into the file as it was read, so everything else in it —
// other decls, their order, comments, blank lines — comes out byte for byte.

static NSString *const UDWallsFile =
    @"// Mars City lights\n"
     "// (written by hand)\n"
     "\n"
     "textures/udw/alpha\n"
     "{\n"
     "\tdiffusemap\ttextures/udw/alpha_d\n"
     "}\n"
     "\n"
     "/* the beta panel, used in delta labs */\n"
     "textures/udw/beta\n"
     "{\n"
     "\tdiffusemap\ttextures/udw/beta_d\n"
     "}\n"
     "\n"
     "material textures/udw/gamma\n"
     "{\n"
     "\tdiffusemap\ttextures/udw/gamma_d\t// trailing comment\n"
     "}\n"
     "// end of file\n";

@interface idDeclFileWriteTests : XCTestCase
@property (nonatomic, copy) NSString *root;
@property (nonatomic, copy) NSString *savePath;
@property (nonatomic, strong) UDWorkspace *workspace;
@end

@implementation idDeclFileWriteTests

- (void)setUp {
    [super setUp];
    self.root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                 [NSString stringWithFormat:@"declwrite-%@", [[NSUUID UUID] UUIDString]]];
    self.savePath = [self.root stringByAppendingPathComponent:@"save"];
    NSString *materials = [self.root stringByAppendingPathComponent:@"install/base/materials"];
    [[NSFileManager defaultManager] createDirectoryAtPath:materials withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.savePath withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDWallsFile writeToFile:[materials stringByAppendingPathComponent:@"udw.mtr"]
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self startWorkspace];
}

- (void)startWorkspace {
    NSString *install = [self.root stringByAppendingPathComponent:@"install"];
    NSDictionary *settings = @{
        @"fs_basepath": install, @"fs_savepath": self.savePath, @"fs_homepath": self.savePath,
        @"fs_cdpath": @"", @"fs_game": @"base", @"fs_game_base": @"", @"gamedir": @"base",
        @"fs_caseSensitiveOS": @YES,
    };
    [self.workspace shutdown];
    self.workspace = [[UDWorkspace alloc] initWithDictionary:settings rootDirectory:install];
    NSError *error = nil;
    XCTAssertTrue([self.workspace startup:&error], @"%@", error);
}

- (void)tearDown {
    [self.workspace shutdown];
    self.workspace = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.root error:NULL];
    [super tearDown];
}

- (idDeclManager *)declManager {
    return self.workspace.declManager;
}

/// The file the game would now load: the save path's copy.
- (NSString *)savedText {
    NSString *path = [self.savePath stringByAppendingPathComponent:@"base/materials/udw.mtr"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertNotNil(text, @"saving should write %@", path);
    return text ?: @"";
}

- (void)update:(NSString *)name text:(NSString *)text {
    // Touch the decl first so it is loaded, as an editor would.
    XCTAssertNotNil([self.declManager findType:DECL_MATERIAL name:name makeDefault:NO error:NULL]);
    // The manager takes NUL-terminated bytes, as the Core Data layer passes them.
    NSMutableData *bytes = [[text dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [bytes appendBytes:"" length:1];
    XCTAssertTrue([self.declManager updateDecl:DECL_MATERIAL name:name sourceText:bytes], @"updateDecl %@", name);
}

- (void)save {
    NSError *error = nil;
    XCTAssertTrue([self.declManager writeDecls:&error], @"writeDecls: %@", error);
}

#pragma mark -

- (void)testEditingOneDeclLeavesTheRestOfTheFileAsItWas {
    [self update:@"textures/udw/beta" text:@"{\n\tdiffusemap\ttextures/udw/beta_d2\n\tspecularmap\ttextures/udw/beta_s\n}"];
    [self save];

    NSString *expected = [UDWallsFile stringByReplacingOccurrencesOfString:
                          @"{\n\tdiffusemap\ttextures/udw/beta_d\n}"
                                                               withString:
                          @"{\n\tdiffusemap\ttextures/udw/beta_d2\n\tspecularmap\ttextures/udw/beta_s\n}"];
    XCTAssertEqualObjects([self savedText], expected);
}

- (void)testAnEditCarryingItsHeaderReplacesTheWholeDecl {
    // Text from the Core Data layer comes with its "type name" header.
    [self update:@"textures/udw/gamma" text:@"material textures/udw/gamma {\n\tdiffusemap\ttextures/udw/gamma_d2\n}\n"];
    [self save];

    NSString *expected = [UDWallsFile stringByReplacingOccurrencesOfString:
                          @"material textures/udw/gamma\n{\n\tdiffusemap\ttextures/udw/gamma_d\t// trailing comment\n}"
                                                               withString:
                          @"material textures/udw/gamma {\n\tdiffusemap\ttextures/udw/gamma_d2\n}"];
    XCTAssertEqualObjects([self savedText], expected);
}

- (void)testSuccessiveSavesKeepTheOtherDeclsInPlace {
    [self update:@"textures/udw/alpha" text:@"{\n\tdiffusemap\ttextures/udw/alpha_d_much_longer_than_before\n}"];
    [self save];
    [self update:@"textures/udw/gamma" text:@"{\n\tdiffusemap\ttextures/udw/gamma_d2\n}"];
    [self save];

    NSString *expected = [[UDWallsFile
        stringByReplacingOccurrencesOfString:@"alpha_d\n" withString:@"alpha_d_much_longer_than_before\n"]
        stringByReplacingOccurrencesOfString:@"\tdiffusemap\ttextures/udw/gamma_d\t// trailing comment\n"
                                  withString:@"\tdiffusemap\ttextures/udw/gamma_d2\n"];
    XCTAssertEqualObjects([self savedText], expected);
}

- (void)testNewDeclsAreAppendedInTheOrderTheyWereMade {
    XCTAssertNotNil([self.declManager createNewDecl:DECL_MATERIAL name:@"textures/udw/delta" fileName:@"materials/udw.mtr"]);
    XCTAssertNotNil([self.declManager createNewDecl:DECL_MATERIAL name:@"textures/udw/epsilon" fileName:@"materials/udw.mtr"]);
    [self save];

    NSString *text = [self savedText];
    XCTAssertTrue([text hasPrefix:UDWallsFile], @"the existing file must come first, unchanged:\n%@", text);
    NSString *tail = [text substringFromIndex:UDWallsFile.length];
    NSRange delta = [tail rangeOfString:@"textures/udw/delta"];
    NSRange epsilon = [tail rangeOfString:@"textures/udw/epsilon"];
    XCTAssertNotEqual(delta.location, (NSUInteger)NSNotFound, @"%@", tail);
    XCTAssertNotEqual(epsilon.location, (NSUInteger)NSNotFound, @"%@", tail);
    XCTAssertLessThan(delta.location, epsilon.location, @"appended in creation order:\n%@", tail);
}

- (void)testRemovingADeclTakesItsOwnCommentButNotTheFileHeader {
    XCTAssertNotNil([self.declManager findType:DECL_MATERIAL name:@"textures/udw/alpha" makeDefault:NO error:NULL]);
    XCTAssertTrue([self.declManager removeDecl:DECL_MATERIAL name:@"textures/udw/beta"]);
    XCTAssertTrue([self.declManager removeDecl:DECL_MATERIAL name:@"textures/udw/alpha"]);
    [self save];

    NSString *expected =
        @"// Mars City lights\n"
         "// (written by hand)\n"
         "\n"
         "material textures/udw/gamma\n"
         "{\n"
         "\tdiffusemap\ttextures/udw/gamma_d\t// trailing comment\n"
         "}\n"
         "// end of file\n";
    XCTAssertEqualObjects([self savedText], expected);
}

- (void)testRenamingChangesOnlyTheName {
    XCTAssertNotNil([self.declManager findType:DECL_MATERIAL name:@"textures/udw/gamma" makeDefault:NO error:NULL]);
    XCTAssertTrue([self.declManager renameDecl:DECL_MATERIAL fromName:@"textures/udw/gamma" toName:@"textures/udw/gamma2"]);
    [self save];

    NSString *expected = [UDWallsFile stringByReplacingOccurrencesOfString:@"material textures/udw/gamma\n"
                                                                withString:@"material textures/udw/gamma2\n"];
    XCTAssertEqualObjects([self savedText], expected);
}

- (void)testMovingADeclTakesItOutOfOneFileAndIntoAnother {
    XCTAssertNotNil([self.declManager findType:DECL_MATERIAL name:@"textures/udw/beta" makeDefault:NO error:NULL]);
    XCTAssertTrue([self.declManager moveDecl:DECL_MATERIAL name:@"textures/udw/beta" toFileName:@"materials/udw_moved.mtr"]);
    [self save];

    NSString *expected = [UDWallsFile stringByReplacingOccurrencesOfString:
                          @"\n/* the beta panel, used in delta labs */\ntextures/udw/beta\n{\n\tdiffusemap\ttextures/udw/beta_d\n}\n"
                                                               withString:@""];
    XCTAssertEqualObjects([self savedText], expected);
    NSString *moved = [NSString stringWithContentsOfFile:[self.savePath stringByAppendingPathComponent:@"base/materials/udw_moved.mtr"]
                                                encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertTrue([moved containsString:@"textures/udw/beta"], @"%@", moved);
    XCTAssertTrue([moved containsString:@"textures/udw/beta_d"], @"%@", moved);
}

- (void)testTheSavedFileReadsBackTheSame {
    [self update:@"textures/udw/beta" text:@"{\n\tdiffusemap\ttextures/udw/beta_d2\n}"];
    [self save];
    NSString *saved = [self savedText];

    // A fresh workspace reads the saved copy; saving it again unchanged after
    // an edit to another decl must keep the first edit exactly.
    [self startWorkspace];
    [self update:@"textures/udw/alpha" text:@"{\n\tdiffusemap\ttextures/udw/alpha_d2\n}"];
    [self save];
    NSString *expected = [saved stringByReplacingOccurrencesOfString:@"alpha_d\n" withString:@"alpha_d2\n"];
    XCTAssertEqualObjects([self savedText], expected);
}

- (void)testAFileChangedOnDiskIsNotOverwritten {
    [self update:@"textures/udw/beta" text:@"{\n\tdiffusemap\ttextures/udw/beta_d2\n}"];
    [self save];

    // Someone edits the saved copy behind the editor's back.
    NSString *path = [self.savePath stringByAppendingPathComponent:@"base/materials/udw.mtr"];
    NSString *external = [[self savedText] stringByAppendingString:@"// added in another editor\n"];
    XCTAssertTrue([external writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    [self update:@"textures/udw/alpha" text:@"{\n\tdiffusemap\ttextures/udw/alpha_d2\n}"];
    NSError *error = nil;
    XCTAssertFalse([self.declManager writeDecls:&error], @"saving over an outside change must fail");
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL], external,
                          @"the outside change must survive");
}

@end
