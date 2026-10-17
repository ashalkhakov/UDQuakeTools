#import <XCTest/XCTest.h>
#import "UDArchiveEntry.h"

@interface UDArchiveEntryTests : XCTestCase
@end

@implementation UDArchiveEntryTests

- (void)testArchiveEntry {
    UDArchiveEntry *entry = [[UDArchiveEntry alloc] initWithPath:@"/maps/e1m1.bsp/"
                                                            size:123
                                                     contentType:@"application/octet-stream"
                                                      modifiedAt:[NSDate dateWithTimeIntervalSince1970:100]
                                                          source:nil];

    XCTAssertEqualObjects(entry.path, @"maps/e1m1.bsp", @"UDArchiveEntry should normalize path");
    XCTAssertEqualObjects(entry.name, @"e1m1.bsp", @"UDArchiveEntry should expose basename");
    XCTAssertEqual(entry.size, 123ULL, @"UDArchiveEntry should expose size");
}

@end

