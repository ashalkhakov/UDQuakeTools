#import <XCTest/XCTest.h>

#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveEntry.h"
#import "UDContentSource.h"
#import "UDArchiveMutation.h"
#import "UDDirectoryNode.h"

@interface UDInMemoryContentSource : NSObject <UDContentSource>
@property (nonatomic, strong, readonly) NSData *data;
- (instancetype)initWithData:(NSData *)data;
@end

@implementation UDInMemoryContentSource

- (instancetype)initWithData:(NSData *)data {
    NSParameterAssert(data != nil);
    self = [super init];
    if (!self) {
        return nil;
    }
    _data = data;
    return self;
}

- (uint64_t)length {
    return (uint64_t)self.data.length;
}

- (NSData *)readRange:(NSRange)range error:(NSError **)error {
    if (range.location > self.data.length || range.length > (self.data.length - range.location)) {
        if (error) {
            *error = [NSError errorWithDomain:@"UDInMemoryContentSource"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Out of bounds."}];
        }
        return nil;
    }
    return [self.data subdataWithRange:range];
}

- (NSData *)readAll:(NSError **)error {
    (void)error;
    return self.data;
}

@end

@interface UDArchiveEditorTests : XCTestCase
@end

@implementation UDArchiveEditorTests

- (nullable UDArchiveMutation *)mutationOfKind:(NSString *)kind inMutations:(NSArray<UDArchiveMutation *> *)mutations {
    for (UDArchiveMutation *mutation in mutations) {
        if ([mutation.kind isEqualToString:kind]) {
            return mutation;
        }
    }
    return nil;
}

- (UDArchiveEditor *)makeEditor {
    NSData *alphaData = [@"alpha" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *betaData = [@"beta" dataUsingEncoding:NSASCIIStringEncoding];

    UDArchiveEntry *first = [[UDArchiveEntry alloc] initWithPath:@"a.txt"
                                                            size:alphaData.length
                                                     contentType:@"text/plain"
                                                      modifiedAt:[NSDate date]
                                                          source:[[UDInMemoryContentSource alloc] initWithData:alphaData]];

    UDArchiveEntry *second = [[UDArchiveEntry alloc] initWithPath:@"dir/b.txt"
                                                             size:betaData.length
                                                      contentType:@"text/plain"
                                                       modifiedAt:[NSDate date]
                                                           source:[[UDInMemoryContentSource alloc] initWithData:betaData]];

    UDArchive *archive = [[UDArchive alloc] initWithDisplayName:@"test.pak"
                                                         entries:@[first, second]
                                                        metadata:@{}];
    return [[UDArchiveEditor alloc] initWithArchive:archive];
}

- (void)testInitialTreeBuildsParentBacklinks {
    UDArchiveEditor *editor = [self makeEditor];

    XCTAssertEqual(editor.originalRoot.parent, nil, @"original root should not have a parent");
    XCTAssertEqual(editor.currentRoot.parent, nil, @"current root should not have a parent");

    UDDirectoryNode *dir = [editor.currentRoot directoryAtRelativePath:@"dir"];
    XCTAssertNotNil(dir, @"nested directory should exist in current tree");
    XCTAssertEqualObjects(dir.parent.path, @"", @"directory parent should be root");

    UDArchiveEntry *entry = [editor.currentRoot entryAtRelativePath:@"dir/b.txt"];
    XCTAssertNotNil(entry, @"entry should be addressable from tree");
    XCTAssertEqualObjects(entry.parent.path, @"dir", @"entry parent backlink should point to owning directory");

    XCTAssertFalse(editor.isDirty, @"fresh editor should not be dirty");
    XCTAssertEqual(editor.currentDiff.count, 0U, @"fresh editor should have empty diff");
}

- (void)testAddReplaceMoveRemoveFlow {
    UDArchiveEditor *editor = [self makeEditor];

    NSData *replacementData = [@"new-alpha" dataUsingEncoding:NSASCIIStringEncoding];
    NSError *replaceError = nil;
    BOOL replaced = [editor replaceEntryAtPath:@"a.txt"
                                    withSource:[[UDInMemoryContentSource alloc] initWithData:replacementData]
                                         error:&replaceError];
    XCTAssertTrue(replaced, @"replace should succeed");
    XCTAssertNil(replaceError, @"replace should not set error");

    UDArchiveEntry *replacedEntry = nil;
    for (UDArchiveEntry *entry in editor.currentEntries) {
        if ([entry.path isEqualToString:@"a.txt"]) {
            replacedEntry = entry;
            break;
        }
    }
    XCTAssertNotNil(replacedEntry, @"replaced entry should still be present");
    XCTAssertEqual(replacedEntry.size, (uint64_t)replacementData.length,
                   @"replaced entry size should reflect staged content");

    NSData *addedData = [@"added" dataUsingEncoding:NSASCIIStringEncoding];
    NSError *addError = nil;
    BOOL added = [editor addSource:[[UDInMemoryContentSource alloc] initWithData:addedData]
                            atPath:@"new.txt"
                             error:&addError];
    XCTAssertTrue(added, @"add should succeed");
    XCTAssertNil(addError, @"add should not set error");

    NSError *moveError = nil;
    BOOL moved = [editor moveNodeFromPath:@"new.txt" toPath:@"moved/new.txt" error:&moveError];
    XCTAssertTrue(moved, @"move should succeed");
    XCTAssertNil(moveError, @"move should not set error");

    NSError *removeError = nil;
    BOOL removed = [editor removeNodeAtPath:@"dir" error:&removeError];
    XCTAssertTrue(removed, @"remove directory should succeed");
    XCTAssertNil(removeError, @"remove should not set error");

    NSArray<UDArchiveEntry *> *entries = editor.currentEntries;
    XCTAssertEqual(entries.count, 2U, @"two entries should remain");

    BOOL hasA = NO;
    BOOL hasMoved = NO;
    BOOL hasRemoved = NO;
    for (UDArchiveEntry *entry in entries) {
        hasA = hasA || [entry.path isEqualToString:@"a.txt"];
        hasMoved = hasMoved || [entry.path isEqualToString:@"moved/new.txt"];
        hasRemoved = hasRemoved || [entry.path isEqualToString:@"dir/b.txt"];
    }
    XCTAssertTrue(hasA, @"a.txt should still exist");
    XCTAssertTrue(hasMoved, @"moved/new.txt should exist");
    XCTAssertFalse(hasRemoved, @"dir/b.txt should be removed");

    NSError *contentError = nil;
    NSData *updated = [editor contentForEntryAtPath:@"a.txt"
                                              range:NSMakeRange(0, replacementData.length)
                                              error:&contentError];
    XCTAssertNotNil(updated, @"updated content should be readable");
    XCTAssertNil(contentError, @"content read should not set error");
    XCTAssertEqualObjects([[NSString alloc] initWithData:updated encoding:NSASCIIStringEncoding],
                          @"new-alpha",
                          @"replace should use current tree content source");

    XCTAssertTrue(editor.isDirty, @"editor should be marked dirty after edits");
    XCTAssertEqual(editor.pendingMutations.count, 3U, @"pendingMutations should expose the net tree diff, not transient operations");

    UDDirectoryNode *movedDir = [editor.currentRoot directoryAtRelativePath:@"moved"];
    XCTAssertNotNil(movedDir, @"move should materialize the destination directory in the tree");
    UDArchiveEntry *movedEntry = [editor.currentRoot entryAtRelativePath:@"moved/new.txt"];
    XCTAssertNotNil(movedEntry, @"moved entry should be reachable through the tree");
    XCTAssertEqualObjects(movedEntry.parent.path, @"moved", @"moved entry should have updated parent backlink");

    NSArray<UDArchiveMutation *> *diff = editor.currentDiff;
    XCTAssertEqual(diff.count, 3U, @"net diff should collapse transient add+move into final state changes");

    UDArchiveMutation *replaceMutation = [self mutationOfKind:@"replace" inMutations:diff];
    XCTAssertNotNil(replaceMutation, @"net diff should include replace");
    XCTAssertEqualObjects(replaceMutation.payload[@"path"], @"a.txt");

    UDArchiveMutation *addMutation = [self mutationOfKind:@"add" inMutations:diff];
    XCTAssertNotNil(addMutation, @"net diff should include add for the moved-in new file");
    XCTAssertEqualObjects(addMutation.payload[@"path"], @"moved/new.txt");

    UDArchiveMutation *removeMutation = [self mutationOfKind:@"remove" inMutations:diff];
    XCTAssertNotNil(removeMutation, @"net diff should include removal of the original dir entry");
    XCTAssertEqualObjects(removeMutation.payload[@"path"], @"dir/b.txt");
}

- (void)testMutationFailures {
    UDArchiveEditor *editor = [self makeEditor];

    NSError *duplicateError = nil;
    BOOL duplicate = [editor addSource:[[UDInMemoryContentSource alloc] initWithData:[NSData data]]
                                atPath:@"a.txt"
                                 error:&duplicateError];
    XCTAssertFalse(duplicate, @"adding duplicate path should fail");
    XCTAssertNotNil(duplicateError, @"duplicate add should set error");

    NSError *missingError = nil;
    BOOL replaced = [editor replaceEntryAtPath:@"missing.txt"
                                    withSource:[[UDInMemoryContentSource alloc] initWithData:[NSData data]]
                                         error:&missingError];
    XCTAssertFalse(replaced, @"replacing missing entry should fail");
    XCTAssertNotNil(missingError, @"missing replace should set error");

    NSError *moveConflictError = nil;
    BOOL moved = [editor moveNodeFromPath:@"a.txt" toPath:@"dir/b.txt" error:&moveConflictError];
    XCTAssertFalse(moved, @"moving to an existing path should fail");
    XCTAssertNotNil(moveConflictError, @"move conflict should set error");

    NSError *contentError = nil;
    NSData *content = [editor contentForEntryAtPath:@"missing.txt" range:NSMakeRange(0, 1) error:&contentError];
    XCTAssertNil(content, @"missing content request should fail");
    XCTAssertNotNil(contentError, @"missing content request should set error");
}

- (void)testDiffDetectsMoveOfOriginalEntry {
    UDArchiveEditor *editor = [self makeEditor];

    NSError *moveError = nil;
    BOOL moved = [editor moveNodeFromPath:@"dir/b.txt" toPath:@"renamed/b.txt" error:&moveError];
    XCTAssertTrue(moved, @"moving an original entry should succeed");
    XCTAssertNil(moveError, @"move should not set error");

    NSArray<UDArchiveMutation *> *diff = editor.currentDiff;
    XCTAssertEqual(diff.count, 1U, @"net diff should collapse pure rename into one move mutation");

    UDArchiveMutation *moveMutation = diff.firstObject;
    XCTAssertEqualObjects(moveMutation.kind, @"move");
    XCTAssertEqualObjects(moveMutation.payload[@"fromPath"], @"dir/b.txt");
    XCTAssertEqualObjects(moveMutation.payload[@"toPath"], @"renamed/b.txt");

    UDArchiveEntry *movedEntry = [editor.currentRoot entryAtRelativePath:@"renamed/b.txt"];
    XCTAssertNotNil(movedEntry, @"moved entry should be present in destination tree");
    XCTAssertEqualObjects(movedEntry.parent.path, @"renamed", @"moved entry should report its new parent directory");
}

- (void)testRevertRestoresOriginalTreeAndClearsDiff {
    UDArchiveEditor *editor = [self makeEditor];

    NSError *err = nil;
    XCTAssertTrue([editor addSource:[[UDInMemoryContentSource alloc] initWithData:[@"added" dataUsingEncoding:NSASCIIStringEncoding]]
                              atPath:@"new.txt"
                               error:&err]);
    XCTAssertNil(err);
    XCTAssertTrue(editor.isDirty, @"editor should be dirty after add");
    XCTAssertGreaterThan(editor.currentDiff.count, 0U, @"diff should contain net changes before revert");

    [editor revertAll];

    XCTAssertFalse(editor.isDirty, @"revert should clear dirty state");
    XCTAssertEqual(editor.pendingMutations.count, 0U, @"revert should clear net diff");
    XCTAssertEqual(editor.currentDiff.count, 0U, @"revert should clear net diff");
    XCTAssertNil([editor.currentRoot entryAtRelativePath:@"new.txt"], @"revert should remove added entries from current tree");
    XCTAssertNotNil([editor.currentRoot entryAtRelativePath:@"a.txt"], @"revert should restore original entries");
    XCTAssertNotNil([editor.currentRoot entryAtRelativePath:@"dir/b.txt"], @"revert should restore nested original entries");
}

@end
