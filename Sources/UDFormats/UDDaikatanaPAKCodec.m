#import "UDDaikatanaPAKCodec.h"
#import "UDArchive.h"

@implementation UDDaikatanaPAKCodec

- (NSString *)formatIdentifier {
    return @"com.udquake.daikatana-pak";
}

- (UDArchive *)readArchiveFromURL:(NSURL *)url error:(NSError **)error {
    UDArchive *base = [super readArchiveFromURL:url error:error];
    if (!base) {
        return nil;
    }

    NSMutableDictionary<NSString *, id> *meta = [base.metadata mutableCopy];
    [meta setObject:self.formatIdentifier forKey:@"formatIdentifier"];
    [meta setObject:@"daikatana" forKey:@"game"];

    return [[UDArchive alloc] initWithDisplayName:base.displayName
                                          entries:base.entries
                                         metadata:meta];
}

@end
