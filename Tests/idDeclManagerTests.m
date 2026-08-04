#import <XCTest/XCTest.h>
#import "idFileSystem.h"
#import "idDeclManager.h"
#import "UDWorkspaceManager.h"
#import "idDeclMaterial.h"

@interface idDeclManagerTests : XCTestCase
@property (nonatomic, strong) NSString *rootDir;
@property (nonatomic, strong) NSString *gameDir;
@property (nonatomic, strong) NSString *fullGameDirPath;
@property (nonatomic, strong) UDWorkspace *workspace;
@property (nonatomic, strong) idFileSystem *fileSystem;
@property (nonatomic, strong) idDeclManager *declManager;
@end

@implementation idDeclManagerTests

- (void)setUp {
    [super setUp];
    self.rootDir = NSTemporaryDirectory();
    self.gameDir = @"base";
    self.fullGameDirPath = [self.rootDir stringByAppendingPathComponent:self.gameDir];

    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                          self.rootDir, @"fs_basepath",
                          self.rootDir, @"fs_savepath",
                          self.rootDir, @"fs_cdpath",
                          self.gameDir, @"fs_game",
                          @"1", @"fs_debug",
                          @"0", @"fs_restrict",
                          @"0", @"fs_copyfiles",
                          @"1", @"fs_caseSensitiveOS",
                          nil];
        
    // Create the base game directory
    [[NSFileManager defaultManager] createDirectoryAtPath:self.fullGameDirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
                                                    
    // 1. Create a "materials" folder for our test decls
    NSString *materialsDir = [self.fullGameDirPath stringByAppendingPathComponent:@"materials"];
    [[NSFileManager defaultManager] createDirectoryAtPath:materialsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
                                                    
    // 2. Write a loose .mtr file to the disk before booting the workspace
    // This allows the DeclManager to discover it during its initialization scan
    NSString *testDeclPath = [materialsDir stringByAppendingPathComponent:@"test_suite.mtr"];
    NSString *testDeclContent =
        @"material textures/test_valid { \n"
         "    noShadows \n"
         "    map _default \n"
         "} \n";

    [testDeclContent writeToFile:testDeclPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // 3. Boot the subsystems
    self.workspace = [[UDWorkspace alloc] initWithDictionary:dict rootDirectory:self.rootDir];
    [self.workspace startup:nil];
    
    self.fileSystem = self.workspace.fileSystem;
    
    // 4. Grab the manager (Assuming it was initialized inside bootSubsystems)
    self.declManager = self.workspace.declManager;
}

- (void)tearDown {
    // Clean up the generated materials directory
    [[NSFileManager defaultManager] removeItemAtPath:[self.fullGameDirPath stringByAppendingPathComponent:@"materials"] error:nil];
    
    self.workspace = nil;
    self.fileSystem = nil;
    self.declManager = nil;
    [super tearDown];
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

- (void)testDeclDiscoveryAndParsing {
    NSError *error = nil;

    // Ask for a material that was written to 'test_suite.mtr' during setUp.
    // The manager should locate it in its scanned directory tree, allocate an idDeclBase,
    // load the text, and trigger the parse() method.
    idDecl *parsedMat = [self.declManager findType:DECL_MATERIAL name:@"textures/test_valid" makeDefault:NO error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(parsedMat, @"DeclManager should find and parse 'textures/test_valid' from the loose file");
    XCTAssertTrue([[parsedMat name] caseInsensitiveCompare:@"textures/test_valid"] == NSOrderedSame);
}

- (void)testMakeDefaultFallback {
    NSError *error = nil;

    // Request a material that does NOT exist, but pass makeDefault:YES (true).
    // It should return the same material (defaulted) instead of nil.
    idDecl *fallbackMat = [self.declManager findType:DECL_MATERIAL name:@"textures/garbage_missing" makeDefault:YES error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(fallbackMat, @"DeclManager must return a fallback decl when makeDefault is YES");
    XCTAssertTrue([[fallbackMat name] caseInsensitiveCompare:@"textures/garbage_missing"] == NSOrderedSame, @"The fallback decl should be the actual material");
}

- (void)testMakeDefaultStrict {
    NSError *error = nil;

    // Request a material that does NOT exist, and pass makeDefault:NO (false).
    // It must return nil, which the engine uses to check if optional decls exist.
    idDecl *missingMat = [self.declManager findType:DECL_MATERIAL name:@"textures/garbage_missing" makeDefault:NO error:&error];

    XCTAssertNil(error);
    XCTAssertNil(missingMat, @"DeclManager must return nil for missing decls when makeDefault is NO");
}

- (void)testDeclCaching {
    NSError *error = nil;
    // Requesting the same decl twice should return the exact same memory pointer,
    // proving the manager is caching them in its array/hash table and not re-parsing.
    idDecl *firstCall = [self.declManager findType:DECL_MATERIAL name:@"textures/test_valid" makeDefault:NO error:&error];
    XCTAssertNil(error);

    idDecl *secondCall = [self.declManager findType:DECL_MATERIAL name:@"textures/test_valid" makeDefault:NO error:&error];
    XCTAssertNil(error);

    XCTAssertNotNil(firstCall);
    XCTAssertEqualObjects(firstCall, secondCall, @"DeclManager must return the identical cached pointer for subsequent lookups");
}

@end
