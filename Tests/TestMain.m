#import <Foundation/Foundation.h>

BOOL UDRunArchiveEntryTests(void);
BOOL UDRunPAKCodecTests(void);

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    BOOL success = YES;
    success = UDRunArchiveEntryTests() && success;
    success = UDRunPAKCodecTests() && success;

    [pool drain];

    if (success) {
        printf("All tests passed.\n");
        return 0;
    }

    return 1;
}
