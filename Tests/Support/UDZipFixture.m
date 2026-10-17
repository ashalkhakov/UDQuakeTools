#import "UDZipFixture.h"

NSData *UDZipFixtureData(NSArray<NSArray *> *entries) {
    UDZipWriter *writer = [[UDZipWriter alloc] init];
    for (NSArray *entry in entries) {
        NSData *payload = [entry[1] dataUsingEncoding:NSUTF8StringEncoding];
        if (![writer addEntryWithPath:entry[0]
                                 data:payload
                               method:(UDZipCompressionMethod)[entry[2] integerValue]
                     modificationDate:nil
                                error:NULL]) {
            return nil;
        }
    }
    return [writer archiveData];
}
