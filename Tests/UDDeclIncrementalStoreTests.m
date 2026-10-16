/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclIncrementalStoreTests.m
 *
 * Exercises the Core Data decl editing stack end to end: managed objects are
 * fetched from a workspace-backed context, mutated, and saved — and every
 * test asserts against the decl file actually written to disk. PDAs cover
 * the child-decl relationship fixup (pda_email/pda_audio/pda_video lines),
 * particles cover the transient structured `stages` attribute.
 */

#import <XCTest/XCTest.h>
#ifdef GNUSTEP
#import <AppKit/AppKit.h>
#endif
#import <CoreData/CoreData.h>

#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "UDDeclManagedObjects.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"

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
    // A PDA naming an email no file defines.
    [self writeGameFile:@"newpdas/dangling.pda"
               contents:@"pda test/dangling {\n\tname \"Dangling\"\n\tpda_email test/no_such_email\n}\n"];

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

    // A sound shader using most of what ParseShader reads.
    [fileManager createDirectoryAtPath:[self.fullGameDirPath stringByAppendingPathComponent:@"sound"]
           withIntermediateDirectories:YES attributes:nil error:nil];
    [self writeGameFile:@"sound/test.sndshd" contents:
        @"test_door {\n"
         "\tdescription \"Door opening\"\n"
         "\tminDistance 2\n"
         "\tmaxDistance 30\n"
         "\tvolume -4\n"
         "\tshakes\n"
         "\treverb 1, 2\n"
         "\tno_dups\n"
         "\tmask_left\n"
         "\tleadin sound/test/door_start.wav\n"
         "\tsound\\test\\door1.wav\n"
         "\tsound/test/door2.ogg\n"
         "}\n"
         "\n"
         "test_hum {\n"
         "\tsound/test/hum.wav\n"
         "}\n"];

    // An entityDef inheriting from one that inherits in turn.
    [fileManager createDirectoryAtPath:[self.fullGameDirPath stringByAppendingPathComponent:@"def"]
           withIntermediateDirectories:YES attributes:nil error:nil];
    [self writeGameFile:@"def/test.def" contents:
        @"entityDef test_base {\n"
         "\t\"editor_usage\"\t\t\"Something that stands.\"\n"
         "\t\"editor_var health\"\t\"How much it takes.\"\n"
         "\t\"editor_bool solid\"\t\"Whether it blocks.\"\n"
         "\t\"health\"\t\t\"100\"\n"
         "\t\"solid\"\t\t\t\"1\"\n"
         "}\n"
         "\n"
         "entityDef test_crate {\n"
         "\t\"inherit\"\t\t\"test_base\"\n"
         "\t\"health\"\t\t\"50\"\n"
         "\t\"model\"\t\t\t\"models/test/crate.lwo\"\n"
         "}\n"
         "\n"
         "entityDef test_small_crate {\n"
         "\t\"inherit\"\t\t\"test_crate\"\n"
         "\t\"model\"\t\t\t\"models/test/small_crate.lwo\"\n"
         "}\n"];

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

/// A child decl another names but no file defines: its name, and nothing
/// else — not a fault that cannot be fulfilled (Apple's Core Data raises on
/// one) — and the reference can be taken off and saved.
- (void)testAChildNoFileDefinesHasOnlyItsName {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/dangling"];
    XCTAssertNotNil(pda);
    XCTAssertEqual(pda.emails.count, (NSUInteger)1);
    UDDeclEmail *missing = nil;
    for (UDDeclEmail *email in pda.emails) {
        if ([email.name isEqualToString:@"test/no_such_email"]) missing = email;
    }
    XCTAssertNotNil(missing, @"%@", [pda.emails valueForKey:@"name"]);
    XCTAssertNil(missing.subject);

    [[pda mutableSetValueForKey:@"emails"] removeObject:missing];
    NSError *error = nil;
    XCTAssertTrue([self.context save:&error], @"%@", error);
    NSString *written = [NSString stringWithContentsOfFile:[self.fullGameDirPath stringByAppendingPathComponent:@"newpdas/dangling.pda"]
                                                  encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertFalse([written containsString:@"no_such_email"], @"%@", written);
    XCTAssertTrue([written containsString:@"Dangling"], @"the rest of the PDA stays:\n%@", written);
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

#pragma mark - A decl object's text, both ways

- (void)testADeclsTextHasItsUnsavedEdits {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    pda.title = @"Unsaved Title";
    NSError *error = nil;
    NSString *text = [[NSString alloc] initWithData:[pda ud_currentText:&error] encoding:NSUTF8StringEncoding];
    XCTAssertTrue([text containsString:@"Unsaved Title"], @"%@ %@", text, error);
    XCTAssertTrue([text containsString:@"test/email1"], @"its children too: %@", text);
}

- (void)testTextReadIntoADeclIsOneEditOfItsContext {
    UDDeclPDA *pda = [self declWithTypeName:@"pda" name:@"test/pda1"];
    NSManagedObject *email = pda.emails.anyObject;
    NSString *text = [[NSString alloc] initWithData:[pda ud_currentText:NULL] encoding:NSUTF8StringEncoding];
    text = [text stringByReplacingOccurrencesOfString:@"PDA Title" withString:@"Read Title"];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (![line containsString:@"pda_audio"]) [lines addObject:line];
    }

    [self.context.undoManager beginUndoGrouping];
    NSError *error = nil;
    XCTAssertTrue([pda ud_applyText:[[lines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] error:&error], @"%@", error);
    [self.context processPendingChanges];
    [self.context.undoManager endUndoGrouping];
    XCTAssertEqualObjects(pda.title, @"Read Title");
    XCTAssertEqual(pda.audios.count, 0U, @"the child it no longer names is taken off");
    XCTAssertEqualObjects(pda.emails.anyObject, email, @"the one it still names is the same object");
    XCTAssertTrue(self.context.hasChanges);

    [self.context.undoManager undo];
    XCTAssertEqualObjects(pda.title, @"PDA Title", @"one undo takes it back");
    XCTAssertEqual(pda.audios.count, 1U);
}

#pragma mark - entityDefs

- (void)testAnEntityDefsPairsAreItsOwnInOrder {
    UDDeclEntityDef *crate = [self declWithTypeName:@"entityDef" name:@"test_crate"];
    XCTAssertEqualObjects([crate.keyValues valueForKey:@"key"], (@[@"inherit", @"health", @"model"]));
    XCTAssertEqualObjects(crate.inherit, @"test_base");
}

- (void)testWhatItInheritsIsResolvedAsTheEngineDoes {
    UDDeclEntityDef *small = [self declWithTypeName:@"entityDef" name:@"test_small_crate"];
    NSArray<NSString *> *unknown = nil;
    NSArray<UDInheritedKeyValue *> *inherited = [small ud_inheritedKeyValuesUnknown:&unknown];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSMutableDictionary *from = [NSMutableDictionary dictionary];
    for (UDInheritedKeyValue *pair in inherited) {
        values[pair.key] = pair.value;
        from[pair.key] = pair.from;
    }
    XCTAssertNil(values[@"model"], @"its own model is not inherited");
    XCTAssertEqualObjects(values[@"health"], @"50", @"the parent's, over the grandparent's");
    XCTAssertEqualObjects(from[@"health"], @"test_crate");
    XCTAssertEqualObjects(values[@"solid"], @"1");
    XCTAssertEqualObjects(from[@"solid"], @"test_base", @"from where it is set");
    XCTAssertEqual(unknown.count, 0U);

    XCTAssertEqualObjects([small ud_helpForKey:@"health"], @"How much it takes.", @"editor_var, inherited");
    XCTAssertEqualObjects([small ud_helpForKey:@"solid"], @"Whether it blocks.", @"editor_bool");
    XCTAssertNil([small ud_helpForKey:@"model"]);
    XCTAssertEqualObjects([small ud_usage], @"Something that stands.");

    small.inherit = @"test_nothing";
    [small ud_inheritedKeyValuesUnknown:&unknown];
    XCTAssertEqualObjects(unknown, (@[@"test_nothing"]), @"an entityDef no file defines");
}

- (void)testAnEditedEntityDefIsWrittenAsTheEditorWroteIt {
    UDDeclEntityDef *crate = [self declWithTypeName:@"entityDef" name:@"test_crate"];
    NSMutableArray *pairs = [crate.keyValues mutableCopy];
    [pairs addObject:[UDEntityKeyValue keyValueWithKey:@"mass" value:@"20"]];
    crate.keyValues = pairs;
    crate.keyValues[1].value = @"75";
    crate.inherit = nil;
    XCTAssertTrue([self saveContext]);

    NSString *text = [self contentsOfGameFile:@"def/test.def"];
    XCTAssertTrue([text containsString:@"entityDef test_crate\n{\n\"health\"\t\t\t\"75\"\n\"model\"\t\t\t\"models/test/crate.lwo\"\n\"mass\"\t\t\t\"20\"\n}"], @"%@", text);
    XCTAssertTrue([text containsString:@"entityDef test_small_crate {"], @"the others as they were: %@", text);
}

- (void)testAKeyIsAQuotableString {
    UDEntityKeyValue *pair = [UDEntityKeyValue keyValueWithKey:@"model" value:@""];
    id value = @"";
    XCTAssertFalse([pair validateValue:&value forKey:@"key" error:NULL], @"not empty");
    value = @"say \"hi\"";
    XCTAssertFalse([pair validateValue:&value forKey:@"value" error:NULL], @"no quote in it");
    value = @"";
    XCTAssertTrue([pair validateValue:&value forKey:@"value" error:NULL], @"a value may be empty");
}

#pragma mark - Sound shaders

- (void)testASoundShaderIsReadAsParseShaderReadsIt {
    UDDeclSound *door = [self declWithTypeName:@"sound" name:@"test_door"];
    XCTAssertEqualObjects(door.soundDescription, @"Door opening");
    XCTAssertEqualObjects(door.minDistance, @2);
    XCTAssertEqualObjects(door.maxDistance, @30);
    XCTAssertEqualObjects(door.volume, @-4);
    XCTAssertEqualObjects(door.shakes, @1, @"a bare shakes is 1");
    XCTAssertNil(door.soundClass, @"what it does not set is unset");
    XCTAssertEqualObjects(door.reverb, @"1, 2");
    XCTAssertTrue(door.noDups);
    XCTAssertTrue(door.maskLeft);
    XCTAssertFalse(door.looping);
    XCTAssertEqualObjects([door.leadins valueForKey:@"path"], (@[@"sound/test/door_start.wav"]));
    XCTAssertEqualObjects([door.samples valueForKey:@"path"], (@[@"sound/test/door1.wav", @"sound/test/door2.ogg"]),
                          @"backslashes to slashes");
}

- (void)testAnEditedSoundShaderIsWrittenBack {
    UDDeclSound *hum = [self declWithTypeName:@"sound" name:@"test_hum"];
    hum.looping = YES;
    hum.volume = @-10;
    NSMutableArray *samples = [hum.samples mutableCopy];
    [samples addObject:[UDSoundSample sampleWithPath:@"sound/test/hum2.wav"]];
    hum.samples = samples;
    XCTAssertTrue([self saveContext]);

    NSString *text = [self contentsOfGameFile:@"sound/test.sndshd"];
    XCTAssertTrue([text containsString:@"sound test_hum\n{\n\tvolume\t\t-10\n\tlooping\n\tsound/test/hum.wav\n\tsound/test/hum2.wav\n}"], @"%@", text);
    XCTAssertTrue([text containsString:@"test_door {"], @"the others as they were: %@", text);

    UDDeclSound *door = [self declWithTypeName:@"sound" name:@"test_door"];
    door.looping = YES;
    XCTAssertTrue([self saveContext]);
    text = [self contentsOfGameFile:@"sound/test.sndshd"];
    XCTAssertTrue([text containsString:@"\treverb\t\t\t1, 2\n"], @"what the engine no longer reads is kept: %@", text);
    XCTAssertTrue([text containsString:@"\tleadin sound/test/door_start.wav\n"], @"%@", text);
}

- (void)testWhatParseShaderGivesUpOnIsAProblem {
    NSArray<UDDeclTextProblem *> *problems = [UDDeclSound ud_problemsParsingText:@"{\n\tminDistance 1\n\twobble\n}\n" name:@"test" fileSystem:nil];
    XCTAssertEqual(problems.count, 1U);
    XCTAssertEqual(problems.firstObject.line, 3);
    XCTAssertTrue([problems.firstObject.message containsString:@"unknown token 'wobble'"], @"%@", problems.firstObject.message);
}

#pragma mark - FX

- (void)testAnFXIsReadAsParseSingleFXActionReadsItAndWrittenBackTheSame {
    NSString *text =
        @"fx fx/test_burst\n{\n"
         "\tbindto \"muzzle\"\n"
         "\t{\n\t\tname \"flash\"\n\t\tdelay 0\n\t\tduration 0.05\n\t\trestart 0\n"
         "\t\tlight \"lights/test_flash\", 1, 0.5, 0, 240\n\t\tnoshadows\n\t}\n"
         "\t{\n\t\tdelay 0.1\n\t\tduration 2\n\t\tuseLight \"flash\"\n\t\tfadeOut 0.5\n\t}\n"
         "\t{\n\t\trandom 0.1, 0.4\n\t\tduration 1\n\t\tparticle \"test_sparks.prt\"\n"
         "\t\toffset 0, 0, -16\n\t\taxis 0, 0, 1\n\t\tparticleTrackVelocity\n\t}\n"
         "\t{\n\t\tduration 0.5\n\t\tshake 0.5, 2, 300, 1, 0.1\n\t\tignoreMaster\n\t}\n"
         "\t{\n\t\tsound \"test_boom\"\n\t}\n"
         "}";
    NSArray<UDDeclTextProblem *> *problems = [UDDeclFX ud_problemsParsingText:text name:@"fx/test_burst" fileSystem:nil];
    XCTAssertEqual(problems.count, 0U, @"%@", problems);

    NSDictionary *values = [UDDeclFX ud_parseValuesFromText:[text dataUsingEncoding:NSUTF8StringEncoding]
                                                       name:@"fx/test_burst" fileName:nil lineNum:1 fileSystem:nil error:NULL];
    XCTAssertEqualObjects(values[@"bindTo"], @"muzzle");
    NSArray<UDFXAction *> *actions = values[@"actions"];
    XCTAssertEqual(actions.count, 5U);
    XCTAssertEqualObjects(actions[0].kind, @"light");
    XCTAssertEqualObjects(actions[0].data, @"lights/test_flash");
    XCTAssertEqualObjects(actions[0].lightColor, @"1 0.5 0");
    XCTAssertEqualObjects(actions[0].lightRadius, @240);
    XCTAssertEqualObjects(actions[0].delay, @0, @"a delay written is kept, 0 or not");
    XCTAssertTrue(actions[0].noshadows);
    XCTAssertEqualObjects(actions[1].kind, @"uselight");
    XCTAssertEqualObjects(actions[1].data, @"flash");
    XCTAssertNil(actions[1].restart, @"one not written is not set");
    XCTAssertEqualObjects(actions[2].random2, @0.4f);
    XCTAssertNil(actions[2].delay, @"random leaves no delay");
    XCTAssertEqualObjects(actions[2].offset, @"0 0 -16");
    XCTAssertEqualObjects(actions[3].shakeDistance, @300);
    XCTAssertTrue(actions[3].shakeFalloff);
    XCTAssertEqualObjects(actions[4].kind, @"sound");

    NSData *written = [UDDeclFX ud_textByUnparsingName:@"fx/test_burst" values:values error:NULL];
    NSDictionary *again = [UDDeclFX ud_parseValuesFromText:written name:@"fx/test_burst" fileName:nil lineNum:1 fileSystem:nil error:NULL];
    NSArray<NSString *> *keys = [UDFXAction ud_valueKeys];
    for (NSUInteger i = 0; i < actions.count; i++) {
        XCTAssertEqualObjects([again[@"actions"][i] dictionaryWithValuesForKeys:keys], [actions[i] dictionaryWithValuesForKeys:keys],
                              @"action %lu written and read back the same:\n%@", (unsigned long)i,
                              [[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding]);
    }
    XCTAssertEqualObjects(again[@"bindTo"], @"muzzle");
}

#pragma mark - Articulated figures

- (void)testAnArticulatedFigureIsReadAsIdDeclAFParseReadsIt {
    NSString *text =
        @"articulatedFigure test_crate {\n"
         "settings {\n\tmodel \"test_crate\"\n\tfriction 0.02, 0.03, 0.7, 0.4\n\ttotalMass 80\n\tcontents corpse, body\n}\n"
         "body \"lid\" {\n\tjoint \"lid\"\n\tmod both\n\tmodel bone( joint( \"lid\" ), bonedir( \"lid\", \"hinge\" ), 4 )\n"
         "\torigin -bonecenter( \"lid\", \"hinge\" )\n\tdensity 0.3\n}\n"
         "body \"crate\" {\n\tjoint \"origin\"\n\tmodel cylinder( ( -8, -8, 0 ), ( 8, 8, 16 ), 6 )\n\tangles ( 0, 90, 0 )\n\tclipMask solid\n}\n"
         "ballAndSocketJoint \"hinge\" {\n\tbody1 \"lid\"\n\tbody2 \"crate\"\n\tanchor joint( \"hinge\" )\n"
         "\tpyramidLimit ( 0, 0, 1 ), 30, 40, 50, ( 1, 0, 0 )\n}\n"
         "spring \"strap\" {\n\tbody1 \"lid\"\n\tbody2 \"world\"\n\tanchor1 ( 0, 0, 8 )\n\tanchor2 ( 0, 0, 32 )\n\tstretch 50\n\tmaxLength 40\n}\n"
         "}";
    XCTAssertEqual([UDDeclAF ud_problemsParsingText:text name:@"test_crate" fileSystem:nil].count, 0U);
    NSDictionary *values = [UDDeclAF ud_parseValuesFromText:[text dataUsingEncoding:NSUTF8StringEncoding]
                                                       name:@"test_crate" fileName:nil lineNum:1 fileSystem:nil error:NULL];
    XCTAssertEqualObjects(values[@"model"], @"test_crate");
    XCTAssertEqualObjects(values[@"defaultConstraintFriction"], @0.4f);
    XCTAssertEqualObjects(values[@"contents"], @"body, corpse", @"as ContentsToString writes it");
    XCTAssertEqualObjects(values[@"noMoveTime"], @1.0f, @"FreeData's, unset");

    NSArray<UDAFBody *> *bodies = values[@"bodies"];
    XCTAssertEqualObjects([bodies valueForKey:@"name"], (@[@"crate", @"lid"]), @"the body on the origin first");
    XCTAssertEqualObjects(bodies[0].modelType, @"cylinder");
    XCTAssertEqual(bodies[0].numSides, 6);
    XCTAssertEqualObjects(bodies[0].v2, @"( 8, 8, 16 )");
    XCTAssertEqualObjects(bodies[0].linearFriction == 0.02f ? @YES : @NO, @YES, @"SetDefault's: the figure's friction");
    XCTAssertEqualObjects(bodies[0].clipMask, @"solid");
    XCTAssertEqualObjects(bodies[1].jointMod, @"both");
    XCTAssertEqualObjects(bodies[1].v1, @"joint( \"lid\" )");
    XCTAssertEqualObjects(bodies[1].v2, @"bonedir( \"lid\", \"hinge\" )");
    XCTAssertEqualObjects(bodies[1].origin, @"-bonecenter( \"lid\", \"hinge\" )");
    XCTAssertEqual(bodies[1].width, 4.0f);

    NSArray<UDAFConstraint *> *constraints = values[@"constraints"];
    XCTAssertEqualObjects(constraints[0].type, @"ballAndSocketJoint");
    XCTAssertEqualObjects(constraints[0].limit, @"pyramid");
    XCTAssertEqual(constraints[0].limitAngle3, 50.0f);
    XCTAssertEqualObjects(constraints[0].shaft1, @"( 1, 0, 0 )");
    XCTAssertEqual(constraints[0].friction, 0.5f, @"the parser's own default");
    XCTAssertEqualObjects(constraints[1].type, @"spring");
    XCTAssertEqual(constraints[1].maxLength, 40.0f);

    NSString *written = [[NSString alloc] initWithData:[UDDeclAF ud_textByUnparsingName:@"test_crate" values:values error:NULL]
                                              encoding:NSUTF8StringEncoding];
    XCTAssertTrue([written containsString:@"\tmodel bone( joint( \"lid\" ), bonedir( \"lid\", \"hinge\" ), 4.000000 )\n"], @"%@", written);
    XCTAssertTrue([written containsString:@"\tangles ( 0.000000, 90.000000, 0.000000 )\n"], @"%@", written);
    XCTAssertTrue([written containsString:@"\tpyramidLimit ( 0.000000, 0.000000, 1.000000 ), 30.000000, 40.000000, 50.000000, ( 1.000000, 0.000000, 0.000000 )\n"], @"%@", written);
    XCTAssertTrue([written containsString:@"\tcontents body, corpse\n"], @"%@", written);
}

- (void)testAVectorAndContentsAreValidatedAsTheEngineReadsThem {
    XCTAssertEqualObjects([UDDeclAF ud_normalizedVector:@"(1,2,3)"], @"( 1, 2, 3 )");
    XCTAssertEqualObjects([UDDeclAF ud_normalizedVector:@"bonecenter(\"a\", \"b\")"], @"bonecenter( \"a\", \"b\" )");
    XCTAssertNil([UDDeclAF ud_normalizedVector:@"elbow"], @"not a vector");
    XCTAssertEqualObjects([UDDeclAF ud_normalizedContents:@"monsterclip solid"], @"solid, monsterclip");
    XCTAssertEqualObjects([UDDeclAF ud_normalizedContents:@""], @"none");
}

- (void)testABodyRenamedOrDeletedTakesItsConstraintsWithIt {
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.fullGameDirPath stringByAppendingPathComponent:@"af"]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [self writeGameFile:@"af/test.af" contents:
        @"articulatedFigure test_pair {\n"
         "body \"a\" {\n\tjoint \"origin\"\n\tmodel box( ( -1, -1, -1 ), ( 1, 1, 1 ) )\n}\n"
         "body \"b\" {\n\tjoint \"b\"\n\tmodel box( ( -1, -1, -1 ), ( 1, 1, 1 ) )\n}\n"
         "fixed \"ab\" {\n\tbody1 \"a\"\n\tbody2 \"b\"\n}\n"
         "fixed \"aw\" {\n\tbody1 \"a\"\n\tbody2 \"world\"\n}\n"
         "}\n"];
    [self.workspace shutdown];
    XCTAssertTrue([self.workspace startup:NULL]);
    self.context = [self.workspace newDeclEditingContextWithError:NULL];
    UDDeclAF *figure = [self declWithTypeName:@"articulatedFigure" name:@"test_pair"];

    // A binding's rename of a body: RenameBody's.
    [figure.bodies[1] setValue:@"lid" forKey:@"name"];
    XCTAssertEqualObjects([figure.bodies valueForKey:@"name"], (@[@"a", @"lid"]));
    XCTAssertEqualObjects(figure.constraints[0].body2, @"lid", @"the constraint on it renamed too");

    [figure ud_deleteBodyNamed:@"A"];
    XCTAssertEqualObjects([figure.bodies valueForKey:@"name"], (@[@"lid"]));
    XCTAssertEqual(figure.constraints.count, 0U, @"DeleteBody takes the constraints on it off");

    [figure ud_newBodyNamed:@"base"];
    XCTAssertEqualObjects(figure.bodies.lastObject.name, @"base");
    XCTAssertEqualObjects(figure.bodies.lastObject.contents, @"corpse", @"SetDefault: the figure's contents");
    [figure ud_newConstraintNamed:@"hold"];
    XCTAssertEqualObjects(figure.constraints.lastObject.body1, @"lid", @"SetDefault: the first body");
    XCTAssertEqualObjects(figure.constraints.lastObject.type, @"universalJoint");
}

@end
