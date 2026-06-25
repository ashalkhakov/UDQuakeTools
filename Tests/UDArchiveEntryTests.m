#import <Foundation/Foundation.h>
#import "UDArchiveEntry.h"

static BOOL UDCheck(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        return NO;
    }
    return YES;
}

BOOL UDRunArchiveEntryTests(void) {
    BOOL ok = YES;

    UDArchiveEntry *entry = [[UDArchiveEntry alloc] initWithPath:@"/maps/e1m1.bsp/"
                                                            size:123
                                                     contentType:@"application/octet-stream"
                                                      modifiedAt:[NSDate dateWithTimeIntervalSince1970:100]
                                                          source:nil];

    ok = UDCheck([entry.path isEqualToString:@"maps/e1m1.bsp"], @"UDArchiveEntry should normalize path") && ok;
    ok = UDCheck([entry.name isEqualToString:@"e1m1.bsp"], @"UDArchiveEntry should expose basename") && ok;
    ok = UDCheck(entry.size == 123ULL, @"UDArchiveEntry should expose size") && ok;

    if (ok) {
        printf("UDArchiveEntryTests passed.\n");
    }

    return ok;
}
