#import <Foundation/Foundation.h>

BOOL UDRunArchiveEntryTests(void);
BOOL UDRunPAKCodecTests(void);
BOOL UDRunPK3CodecTests(void);
BOOL UDRunGameDetectionTests(void);

int main(void) {
    @autoreleasepool {
        BOOL success = YES;
        success = UDRunArchiveEntryTests() && success;
        success = UDRunPAKCodecTests() && success;
        success = UDRunPK3CodecTests() && success;
        success = UDRunGameDetectionTests() && success;

        if (success) {
            printf("All tests passed.\n");
            return 0;
        }

        return 1;
    }
}
