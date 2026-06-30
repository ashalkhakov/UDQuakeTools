#import <XCTest/XCTest.h>

#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveEntry.h"
#import "UDContentSource.h"

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

- (void)testAddReplaceMoveRemoveFlow {
    UDArchiveEditor *editor = [self makeEditor];

    NSData *replacementData = [@"new-alpha" dataUsingEncoding:NSASCIIStringEncoding];
    NSError *replaceError = nil;
    BOOL replaced = [editor replaceEntryAtPath:@"a.txt"
                                    withSource:[[UDInMemoryContentSource alloc] initWithData:replacementData]
                                         error:&replaceError];
    XCTAssertTrue(replaced, @"replace should succeed");
    XCTAssertNil(replaceError, @"replace should not set error");

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
                          @"replace should use staged source");

    XCTAssertTrue(editor.isDirty, @"editor should be marked dirty after edits");
    XCTAssertEqual(editor.pendingMutations.count, 4U, @"all operations should be tracked");
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

@end
