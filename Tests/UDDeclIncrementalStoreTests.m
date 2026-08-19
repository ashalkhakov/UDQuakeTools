/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclIncrementalStoreTests.m
 *
 * Exercises the Core Data decl editing stack end to end: managed objects are
 * fetched from a workspace-backed context, mutated, and saved — and every
 * test asserts against the decl file actually written to disk. PDAs cover
 * the child-decl relationship fixup (pda_email/pda_audio/pda_video lines),
 * particles cover the transient structured `stages` attribute.
 */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "UDDeclManagedObjects.h"
#import "UDDeclIncrementalStore.h"

@interface UDDeclIncrementalStoreTests : XCTestCase
@property (nonatomic, strong) NSString *rootDir;
@property (nonatomic, strong) NSString *fullGameDirPath;
@property (nonatomic, strong) UDWorkspace *workspace;
@property (nonatomic, strong) NSManagedObjectContext *context;
@end

@implementation UDDeclIncrementalStoreTests

- (void)setUp {
    [super setUp];

    // A unique root per test keeps runs independent of each other.
    self.rootDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"UDDeclStoreTests-%@", [NSUUID UUID].UUIDString]];
    NSString *gameDir = @"base";
    self.fullGameDirPath = [self.rootDir stringByAppendingPathComponent:gameDir];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:[self.fullGameDirPath stringByAppendingPathComponent:@"newpdas"]
           withIntermediateDirectories:YES attributes:nil error:nil];
    [fileManager createDirectoryAtPath:[self.fullGameDirPath stringByAppendingPathComponent:@"particles"]
           withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *pdaFixture =
        @"pda test/pda1 {\n"
         "\tname \"Test PDA\"\n"
         "\tfullname \"Testy McTest\"\n"
         "\ticon \"icon1\"\n"
         "\tid \"1234-AB\"\n"
         "\tpost \"Tester\"\n"
         "\ttitle \"PDA Title\"\n"
         "\tsecurity \"none\"\n"
         "\tpda_email test/email1\n"
         "\tpda_audio test/audio1\n"
         "\tpda_video test/video1\n"
         "}\n"
         "\n"
         "email test/email1 {\n"
         "\tsubject \"Hello\"\n"
         "\tto \"you\"\n"
         "\tfrom \"me\"\n"
         "\tdate \"3/11/2145\"\n"
         "\ttext {\n"
         "\t\t\"line one\"\n"
         "\t}\n"
         "\timage \"pic\"\n"
         "}\n"
         "\n"
         "audio test/audio1 {\n"
         "\tname \"Audio One\"\n"
         "\taudio \"sound/test.wav\"\n"
         "\tinfo \"info text\"\n"
         "\tpreview \"prev\"\n"
         "}\n"
         "\n"
         "video test/video1 {\n"
         "\tname \"Video One\"\n"
         "\tpreview \"p\"\n"
         "\tvideo \"video/test.roq\"\n"
         "\tinfo \"i\"\n"
         "\taudio \"sound/v.wav\"\n"
         "}\n"
         "\n"
         // Real game data routinely omits optional fields (no date, no
         // image); regression coverage for the NSNull-in-attribute crash.
         "email test/email_sparse {\n"
         "\tsubject \"Sparse\"\n"
         "\tto \"a\"\n"
         "\tfrom \"b\"\n"
         "\ttext {\n"
         "\t\t\"x\"\n"
         "\t}\n"
         "}\n";
    [self writeGameFile:@"newpdas/test.pda" contents:pdaFixture];

    NSString *particleFixture =
        @"particle testfx {\n"
         "\tdepthHack\t1\n"
         "\t{\n"
         "\t\tcount\t\t\t\t10\n"
         "\t\tmaterial\t\t\ttextures/particles/dust\n"
         "\t\ttime\t\t\t\t2.000\n"
         "\t\tcycles\t\t\t\t0.000\n"
         "\t\tbunching\t\t\t1.000\n"
         "\t\tdistribution\t\trect 4.000 4.000 0.000 \n"
         "\t\tdirection\t\t\tcone \"90.000\" \n"
         "\t\torientation\t\t\tview \n"
         "\t\tspeed\t\t\t\t \"150.000\" \n"
         "\t\tsize\t\t\t\t \"4.000\" \n"
         "\t\taspect\t\t\t\t \"1.000\" \n"
         "\t\trandomDistribution\t\t\t\t1\n"
         "\t\tboundsExpansion\t\t\t\t0.000\n"
         "\t\tfadeIn\t\t\t\t0.100\n"
         "\t\tfadeOut\t\t\t\t0.250\n"
         "\t\tfadeIndex\t\t\t\t0.000\n"
         "\t\tcolor \t\t\t\t1.000 1.000 1.000 1.000\n"
         "\t\tfadeColor \t\t\t0.000 0.000 0.000 0.000\n"
         "\t\toffset \t\t\t\t0.000 0.000 0.000\n"
         "\t\tgravity \t\t\t1.000\n"
         "\t}\n"
         "}\n";
    [self writeGameFile:@"particles/test.prt" contents:particleFixture];

    NSDictionary *dict = @{
        @"fs_basepath": self.rootDir,
        @"fs_savepath": self.rootDir,
        @"fs_cdpath": self.rootDir,
        @"fs_game": gameDir,
        @"fs_debug": @"0",
        @"fs_restrict": @"0",
        @"fs_copyfiles": @"0",
        @"fs_caseSensitiveOS": @"1",
    };
    self.workspace = [[UDWorkspace alloc] initWithDictionary:dict rootDirectory:self.rootDir];

    NSError *error = nil;
    XCTAssertTrue([self.workspace startup:&error], @"workspace startup failed: %@", error);

    // Editing contexts are per-document now: each one comes fresh off the
    // workspace's shared store coordinator.
    self.context = [self.workspace newDeclEditingContextWithError:&error];
    XCTAssertNotNil(self.context, @"the decl editing context (model, coordinator, store) must come up: %@", error);
}

- (void)tearDown {
    [self.workspace shutdown];
    self.workspace = nil;
    self.context = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.rootDir error:nil];
    [super tearDown];
}

#pragma mark - Helpers

- (void)writeGameFile:(NSString *)relativePath contents:(NSString *)contents {
    NSString *path = [self.fullGameDirPath stringByAppendingPathComponent:relativePath];
    XCTAssertTrue([contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil],
                  @"could not write fixture %@", relativePath);
}

- (NSString *)contentsOfGameFile:(NSString *)relativePath {
    NSString *path = [self.fullGameDirPath stringByAppendingPathComponent:relativePath];
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    XCTAssertNotNil(contents, @"could not read %@", relativePath);
    return contents ?: @"";
}

- (__kindof UDDeclBase *)declWithTypeName:(NSString *)typeName name:(NSString *)name {
    NSError *error = nil;
    UDDeclBase *object = [UDDeclBase ud_declWithTypeName:typeName name:name inContext:self.context error:&error];
    XCTAssertNil(error);
    return object;
}

- (UDDeclFile *)declFileNamed:(NSString *)fileName {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"DeclFile"];
    request.predicate = [NSPredicate predicateWithFormat:@"fileName ==[c] %@", fileName];
    NSArray *results = [self.context executeFetchRequest:request error:nil];
    return results.firstObject;
}

- (BOOL)saveContext {
    NSError *error = nil;
    BOOL saved = [self.context save:&error];
    XCTAssertTrue(saved, @"context save failed: %@", error);
    return saved;
}

#pragma mark - Fetching

- (void)testFetchPDAWithRelationships {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    XCTAssertNotNil(pda);
    XCTAssertEqualObjects(pda.pdaName, @"Test PDA");
    XCTAssertEqualObjects(pda.fullName, @"Testy McTest");
    XCTAssertEqualObjects(pda.ident, @"1234-AB");

    XCTAssertEqual(pda.emails.count, (NSUInteger)1);
    XCTAssertEqual(pda.audios.count, (NSUInteger)1);
    XCTAssertEqual(pda.videos.count, (NSUInteger)1);

    UDDeclEmail *email = pda.emails.anyObject;
    XCTAssertEqualObjects(email.name, @"test/email1");
    XCTAssertEqualObjects(email.subject, @"Hello");
    XCTAssertEqualObjects(email.from, @"me");
    XCTAssertEqualObjects(email.body, @"line one");
}

- (void)testFetchParticleStages {
    UDDeclParticle *particle = [self declWithTypeName:@"particle" name:@"testfx"];
    XCTAssertNotNil(particle);
    XCTAssertEqualWithAccuracy(particle.depthHack, 1.0f, 0.0001f);

    XCTAssertEqual(particle.stages.count, (NSUInteger)1);
    UDParticleStage *stage = particle.stages.firstObject;
    XCTAssertEqual(stage.totalParticles, 10);
    XCTAssertEqualObjects(stage.material, @"textures/particles/dust");
    XCTAssertEqualWithAccuracy(stage.particleLife, 2.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(stage.speedFrom, 150.0f, 0.0001f);
    XCTAssertEqualWithAccuracy(stage.gravity, 1.0f, 0.0001f);
    XCTAssertTrue(stage.randomDistribution);
}

#pragma mark - Update

- (void)testUpdatePDAFieldWritesToDisk {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    pda.post = @"Chief Tester";
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"newpdas/test.pda"];
    XCTAssertTrue([onDisk containsString:@"post \"Chief Tester\""]);
    // The relationship fixup must survive an attribute edit.
    XCTAssertTrue([onDisk containsString:@"pda_email \"test/email1\""]);
    XCTAssertTrue([onDisk containsString:@"pda_audio \"test/audio1\""]);
    XCTAssertTrue([onDisk containsString:@"pda_video \"test/video1\""]);
}

// Decls parsed from real game data often lack optional fields entirely. The
// store must materialize those attributes as nil (omitted from the incremental
// store node) — NOT as NSNull, which used to sit in the row cache until the
// first save's validateForUpdate: crashed with -[NSNull length].
- (void)testUpdateDeclWithMissingOptionalFieldsSaves {
    UDDeclEmail *email = [self declWithTypeName:@"email" name:@"test/email_sparse"];
    XCTAssertNotNil(email);
    XCTAssertNil(email.image, @"a missing field must come back as nil, not NSNull");
    XCTAssertNil(email.date, @"a missing field must come back as nil, not NSNull");

    email.subject = @"Sparse Edited";
    [self saveContext]; // must not throw in validation

    NSString *onDisk = [self contentsOfGameFile:@"newpdas/test.pda"];
    XCTAssertTrue([onDisk containsString:@"subject \"Sparse Edited\""]);
}

- (void)testUpdateParticleStageWritesToDisk {
    UDDeclParticle *particle = [self declWithTypeName:@"particle" name:@"testfx"];
    UDParticleStage *stage = particle.stages.firstObject;
    XCTAssertNotNil(stage);

    stage.gravity = 2.5f;
    stage.totalParticles = 42;
    // Transient structured attribute: replace the array wholesale so the
    // object registers as changed.
    particle.stages = @[stage];
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"particles/test.prt"];
    XCTAssertTrue([onDisk containsString:@"count\t\t\t\t42"]);
    XCTAssertTrue([onDisk containsString:@"2.500"]);
    XCTAssertTrue([onDisk containsString:@"particle testfx {"]);
}

#pragma mark - Rename

- (void)testRenamePDAWritesToDisk {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    pda.name = @"test/pda2";
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"newpdas/test.pda"];
    XCTAssertTrue([onDisk containsString:@"pda test/pda2 {"]);
    XCTAssertFalse([onDisk containsString:@"pda test/pda1 {"]);

    XCTAssertNotNil([self declWithTypeName:@"pda" name:@"test/pda2"]);
}

- (void)testRenameParticleWritesToDisk {
    UDDeclParticle *particle = [self declWithTypeName:@"particle" name:@"testfx"];
    particle.name = @"renamedfx";
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"particles/test.prt"];
    XCTAssertTrue([onDisk containsString:@"particle renamedfx {"]);
    XCTAssertFalse([onDisk containsString:@"particle testfx {"]);
}

#pragma mark - Create

- (void)testCreateEmailAndAttachToPDAWritesToDisk {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];

    UDDeclEmail *email = [NSEntityDescription insertNewObjectForEntityForName:@"DeclEmail"
                                                       inManagedObjectContext:self.context];
    email.name = @"test/email2";
    email.subject = @"Second";
    email.to = @"someone";
    email.from = @"someone else";
    email.date = @"4/1/2146";
    email.body = @"second body";
    email.sourceFile = pda.sourceFile; // same .pda file as the pda itself
    email.pda = pda;
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"newpdas/test.pda"];
    XCTAssertTrue([onDisk containsString:@"email test/email2 {"]);
    XCTAssertTrue([onDisk containsString:@"subject \"Second\""]);
    XCTAssertTrue([onDisk containsString:@"pda_email \"test/email2\""]);
    // The pre-existing reference must still be there too.
    XCTAssertTrue([onDisk containsString:@"pda_email \"test/email1\""]);
}

- (void)testCreateParticleWritesToDisk {
    UDDeclParticle *particle = [NSEntityDescription insertNewObjectForEntityForName:@"DeclParticle"
                                                             inManagedObjectContext:self.context];
    particle.name = @"newfx";
    particle.stages = @[[[UDParticleStage alloc] init]];
    particle.sourceFile = [self declFileNamed:@"particles/test.prt"];
    XCTAssertNotNil(particle.sourceFile);
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"particles/test.prt"];
    XCTAssertTrue([onDisk containsString:@"particle newfx {"]);
    XCTAssertTrue([onDisk containsString:@"material\t\t\t_default"]);
    // The fixture particle must survive alongside the new one.
    XCTAssertTrue([onDisk containsString:@"particle testfx {"]);
}

- (void)testCreateWithoutNameFailsValidation {
    UDDeclEmail *email = [NSEntityDescription insertNewObjectForEntityForName:@"DeclEmail"
                                                       inManagedObjectContext:self.context];
    email.subject = @"nameless";

    NSError *error = nil;
    XCTAssertFalse([self.context save:&error], @"a decl without a name must fail validation");
    XCTAssertNotNil(error);
    [self.context deleteObject:email]; // clean up so tearDown's save-free teardown is quiet
}

#pragma mark - Detach / delete

- (void)testDetachEmailKeepsDeclOnDisk {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    UDDeclEmail *email = pda.emails.anyObject;
    XCTAssertNotNil(email);

    email.pda = nil; // detach only; the email decl itself stays
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"newpdas/test.pda"];
    XCTAssertFalse([onDisk containsString:@"pda_email"]);
    XCTAssertTrue([onDisk containsString:@"email test/email1 {"]);
}

- (void)testDeleteEmailRemovesDeclFromDisk {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    UDDeclEmail *email = pda.emails.anyObject;
    XCTAssertNotNil(email);

    [self.context deleteObject:email];
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"newpdas/test.pda"];
    XCTAssertFalse([onDisk containsString:@"email test/email1 {"]);
    // Deleting the email nullified the inverse, so the pda's reference line
    // must be gone as well.
    XCTAssertFalse([onDisk containsString:@"pda_email \"test/email1\""]);
}

- (void)testDeleteParticleRemovesDeclFromDisk {
    UDDeclParticle *particle = [self declWithTypeName:@"particle" name:@"testfx"];
    [self.context deleteObject:particle];
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"particles/test.prt"];
    XCTAssertFalse([onDisk containsString:@"particle testfx {"]);
}

#pragma mark - Per-document context isolation (Save vs Save All)

// Two contexts over the same coordinator model the VSCode buffers: saving
// one document must write ONLY its changes to disk, leaving the other
// document's unsaved edits alone (and invisible on disk) until it is saved
// itself.
- (void)testSavingOneContextDoesNotSaveTheOther {
    NSError *error = nil;
    NSManagedObjectContext *otherContext = [self.workspace newDeclEditingContextWithError:&error];
    XCTAssertNotNil(otherContext, @"second editing context must come up: %@", error);
    XCTAssertNotEqual(otherContext, self.context);

    // Document 1 edits the PDA; document 2 edits the particle.
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    pda.post = @"Chief Tester";

    UDDeclParticle *particle = [UDDeclBase ud_declWithTypeName:@"particle" name:@"testfx"
                                                       inContext:otherContext error:&error];
    XCTAssertNotNil(particle);
    UDParticleStage *stage = particle.stages.firstObject;
    stage.totalParticles = 42;
    particle.stages = @[stage];

    // Save document 1 only.
    [self saveContext];

    NSString *pdaOnDisk = [self contentsOfGameFile:@"newpdas/test.pda"];
    NSString *prtOnDisk = [self contentsOfGameFile:@"particles/test.prt"];
    XCTAssertTrue([pdaOnDisk containsString:@"post \"Chief Tester\""],
                  @"the saved document's change must hit the disk");
    XCTAssertFalse([prtOnDisk containsString:@"count\t\t\t\t42"],
                   @"the OTHER document's unsaved change must NOT hit the disk");
    XCTAssertTrue(otherContext.hasChanges, @"the other document must still be dirty");

    // Now save document 2 (this is what Save All does for every dirty tab).
    XCTAssertTrue([otherContext save:&error], @"second context save failed: %@", error);
    prtOnDisk = [self contentsOfGameFile:@"particles/test.prt"];
    XCTAssertTrue([prtOnDisk containsString:@"count\t\t\t\t42"]);

    // And document 1's earlier save must not have been clobbered.
    XCTAssertTrue([[self contentsOfGameFile:@"newpdas/test.pda"] containsString:@"post \"Chief Tester\""]);
}

#pragma mark - Undo

- (void)testUndoRevertsUnsavedEdit {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    XCTAssertEqualObjects(pda.post, @"Tester");

    pda.post = @"Mistake";
    [self.context processPendingChanges];
    XCTAssertNotNil(self.context.undoManager);
    XCTAssertTrue(self.context.undoManager.canUndo);

    [self.context.undoManager undo];
    XCTAssertEqualObjects(pda.post, @"Tester");
}

- (void)testUndoAfterSaveRevertsAndResaves {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    pda.post = @"Chief Tester";
    [self.context processPendingChanges];
    [self saveContext];

    [self.context.undoManager undo];
    XCTAssertEqualObjects(pda.post, @"Tester");
    [self saveContext];

    NSString *onDisk = [self contentsOfGameFile:@"newpdas/test.pda"];
    XCTAssertTrue([onDisk containsString:@"post \"Tester\""]);
    XCTAssertFalse([onDisk containsString:@"post \"Chief Tester\""]);
}

@end
