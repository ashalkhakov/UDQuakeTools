#import <XCTest/XCTest.h>
#import "idFileSystem.h"
#import "idDeclManager.h"
#import "UDWorkspaceManager.h"

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

#pragma mark - Basics

- (void)testDeclDiscoveryAndParsing {
    NSError *error = nil;

    // Ask for a material that was written to 'test_suite.mtr' during setUp.
    // The manager should locate it in its scanned directory tree, allocate an idDeclBase,
    // load the text, and trigger the parse() method.
    idDeclBase *parsedMat = [self.declManager findType:DECL_MATERIAL name:@"textures/test_valid" makeDefault:NO error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(parsedMat, @"DeclManager should find and parse 'textures/test_valid' from the loose file");
    XCTAssertTrue([[parsedMat name] caseInsensitiveCompare:@"textures/test_valid"] == NSOrderedSame);
}

- (void)testMakeDefaultFallback {
    NSError *error = nil;

    // Request a material that does NOT exist, but pass makeDefault:YES (true).
    // It should return the same material (defaulted) instead of nil.
    idDeclBase *fallbackMat = [self.declManager findType:DECL_MATERIAL name:@"textures/garbage_missing" makeDefault:YES error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(fallbackMat, @"DeclManager must return a fallback decl when makeDefault is YES");
    XCTAssertTrue([[fallbackMat name] caseInsensitiveCompare:@"textures/garbage_missing"] == NSOrderedSame, @"The fallback decl should be the actual material");
}

- (void)testMakeDefaultStrict {
    NSError *error = nil;

    // Request a material that does NOT exist, and pass makeDefault:NO (false).
    // It must return nil, which the engine uses to check if optional decls exist.
    idDeclBase *missingMat = [self.declManager findType:DECL_MATERIAL name:@"textures/garbage_missing" makeDefault:NO error:&error];

    XCTAssertNil(error);
    XCTAssertNil(missingMat, @"DeclManager must return nil for missing decls when makeDefault is NO");
}

- (void)testDeclCaching {
    NSError *error = nil;
    // Requesting the same decl twice should return the exact same memory pointer,
    // proving the manager is caching them in its array/hash table and not re-parsing.
    idDeclBase *firstCall = [self.declManager findType:DECL_MATERIAL name:@"textures/test_valid" makeDefault:NO error:&error];
    XCTAssertNil(error);

    idDeclBase *secondCall = [self.declManager findType:DECL_MATERIAL name:@"textures/test_valid" makeDefault:NO error:&error];
    XCTAssertNil(error);

    XCTAssertNotNil(firstCall);
    XCTAssertEqualObjects(firstCall, secondCall, @"DeclManager must return the identical cached pointer for subsequent lookups");
}

#pragma mark - Create / rename / remove

- (void)testCreateNewDecl {
    NSString *name = @"textures/editor_created";
    NSString *fileName = @"materials/editor_created.mtr";

    idDeclBase *created = [self.declManager createNewDecl:DECL_MATERIAL
                                                 name:name
                                             fileName:fileName];

    XCTAssertNotNil(created, @"createNewDecl must return a decl");
    XCTAssertTrue([[created name] caseInsensitiveCompare:name] == NSOrderedSame);

    // Must be findable by name (hash / registry)
    NSError *error = nil;
    idDeclBase *found = [self.declManager findType:DECL_MATERIAL
                                          name:name
                                   makeDefault:NO
                                         error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(created, found, @"Created decl must be the cached instance");

    // Must appear in type enumeration
    BOOL seen = NO;
    for (idDeclBase *d in [self.declManager declsOfType:DECL_MATERIAL]) {
        if (d == created || [[d name] caseInsensitiveCompare:name] == NSOrderedSame) {
            seen = YES;
            break;
        }
    }
    XCTAssertTrue(seen, @"Created decl must be visible in declsOfType:");
}

- (void)testCreateNewDeclDuplicateName {
    NSString *name = @"textures/dup_test";
    NSString *fileName = @"materials/dup_test.mtr";

    idDeclBase *first = [self.declManager createNewDecl:DECL_MATERIAL
                                               name:name
                                           fileName:fileName];
    XCTAssertNotNil(first);

    // Second create with same type+name: define expected policy and assert it.
    // Common policies: return existing, return nil, or replace.
    idDeclBase *second = [self.declManager createNewDecl:DECL_MATERIAL
                                                name:name
                                            fileName:fileName];

    // Prefer: refuse or return the same object — adjust if your API differs.
    XCTAssertTrue(second == nil || second == first,
                  @"Duplicate create should not insert a second registry entry");

    NSUInteger count = 0;
    for (idDeclBase *d in [self.declManager declsOfType:DECL_MATERIAL]) {
        if ([[d name] caseInsensitiveCompare:name] == NSOrderedSame)
            count++;
    }
    XCTAssertEqual(count, (NSUInteger)1, @"Only one decl may exist for a given type+name");
}

- (void)testRenameDecl {
    NSString *oldName = @"textures/rename_me";
    NSString *newName = @"textures/renamed";
    NSString *fileName = @"materials/rename_me.mtr";

    idDeclBase *created = [self.declManager createNewDecl:DECL_MATERIAL
                                                 name:oldName
                                             fileName:fileName];
    XCTAssertNotNil(created);

    BOOL ok = [self.declManager renameDecl:DECL_MATERIAL
                                  fromName:oldName
                                    toName:newName];
    XCTAssertTrue(ok, @"renameDecl should succeed for an existing decl");

    NSError *error = nil;

    idDeclBase *oldLookup = [self.declManager findType:DECL_MATERIAL
                                              name:oldName
                                       makeDefault:NO
                                             error:&error];
    XCTAssertNil(error);
    XCTAssertNil(oldLookup, @"Old name must no longer resolve");

    idDeclBase *newLookup = [self.declManager findType:DECL_MATERIAL
                                              name:newName
                                       makeDefault:NO
                                             error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(newLookup, @"New name must resolve");
    XCTAssertEqualObjects(created, newLookup, @"Rename should keep the same object identity");
    XCTAssertTrue([[newLookup name] caseInsensitiveCompare:newName] == NSOrderedSame);

    // Ordered enumeration should list new name only
    BOOL sawOld = NO, sawNew = NO;
    for (idDeclBase *d in [self.declManager declsOfType:DECL_MATERIAL]) {
        if ([[d name] caseInsensitiveCompare:oldName] == NSOrderedSame)
            sawOld = YES;
        if ([[d name] caseInsensitiveCompare:newName] == NSOrderedSame)
            sawNew = YES;
    }
    XCTAssertFalse(sawOld);
    XCTAssertTrue(sawNew);
}

- (void)testRenameDeclMissing {
    BOOL ok = [self.declManager renameDecl:DECL_MATERIAL
                                  fromName:@"textures/does_not_exist"
                                    toName:@"textures/whatever"];
    XCTAssertFalse(ok, @"Renaming a missing decl must fail");
}

- (void)testRenameDeclOntoExisting {
    NSString *a = @"textures/rename_a";
    NSString *b = @"textures/rename_b";

    XCTAssertNotNil([self.declManager createNewDecl:DECL_MATERIAL
                                               name:a
                                           fileName:@"materials/rename_a.mtr"]);
    XCTAssertNotNil([self.declManager createNewDecl:DECL_MATERIAL
                                               name:b
                                           fileName:@"materials/rename_b.mtr"]);

    BOOL ok = [self.declManager renameDecl:DECL_MATERIAL fromName:a toName:b];
    XCTAssertFalse(ok, @"Rename must not clobber an existing name");

    NSError *error = nil;
    XCTAssertNotNil([self.declManager findType:DECL_MATERIAL name:a makeDefault:NO error:&error]);
    XCTAssertNotNil([self.declManager findType:DECL_MATERIAL name:b makeDefault:NO error:&error]);
}

- (void)testRemoveDecl {
    NSString *name = @"textures/remove_me";
    NSString *fileName = @"materials/remove_me.mtr";

    idDeclBase *created = [self.declManager createNewDecl:DECL_MATERIAL
                                                 name:name
                                             fileName:fileName];
    XCTAssertNotNil(created);

    BOOL ok = [self.declManager removeDecl:DECL_MATERIAL name:name];
    XCTAssertTrue(ok);

    NSError *error = nil;
    idDeclBase *found = [self.declManager findType:DECL_MATERIAL
                                          name:name
                                   makeDefault:NO
                                         error:&error];
    XCTAssertNil(error);
    XCTAssertNil(found, @"Removed decl must not be findable");

    for (idDeclBase *d in [self.declManager declsOfType:DECL_MATERIAL]) {
        XCTAssertFalse([[d name] caseInsensitiveCompare:name] == NSOrderedSame,
                       @"Removed decl must not appear in enumeration");
    }
}

- (void)testRemoveDeclMissing {
    BOOL ok = [self.declManager removeDecl:DECL_MATERIAL name:@"textures/never_created"];
    XCTAssertFalse(ok, @"Removing a missing decl must fail");
}

- (void)testRemoveThenRecreate {
    NSString *name = @"textures/recycle";
    NSString *fileName = @"materials/recycle.mtr";

    idDeclBase *first = [self.declManager createNewDecl:DECL_MATERIAL
                                               name:name
                                           fileName:fileName];
    XCTAssertNotNil(first);
    XCTAssertTrue([self.declManager removeDecl:DECL_MATERIAL name:name]);

    idDeclBase *second = [self.declManager createNewDecl:DECL_MATERIAL
                                                name:name
                                            fileName:fileName];
    XCTAssertNotNil(second, @"Name must be reusable after remove");

    // After index removal, a new object is expected; pointer may differ
    NSError *error = nil;
    idDeclBase *found = [self.declManager findType:DECL_MATERIAL
                                          name:name
                                   makeDefault:NO
                                         error:&error];
    XCTAssertEqualObjects(second, found);
}

- (void)testCreateRenameRemoveRoundTrip {
    NSString *n1 = @"textures/round_one";
    NSString *n2 = @"textures/round_two";
    NSString *file = @"materials/round.mtr";

    idDeclBase *d = [self.declManager createNewDecl:DECL_MATERIAL name:n1 fileName:file];
    XCTAssertNotNil(d);
    XCTAssertTrue([self.declManager renameDecl:DECL_MATERIAL fromName:n1 toName:n2]);
    XCTAssertTrue([self.declManager removeDecl:DECL_MATERIAL name:n2]);

    NSError *error = nil;
    XCTAssertNil([self.declManager findType:DECL_MATERIAL name:n1 makeDefault:NO error:&error]);
    XCTAssertNil([self.declManager findType:DECL_MATERIAL name:n2 makeDefault:NO error:&error]);
}

@end
