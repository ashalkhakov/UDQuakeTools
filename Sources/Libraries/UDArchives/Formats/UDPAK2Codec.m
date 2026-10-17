#import "UDPAK2Codec.h"
#import "UDArchive.h"

@implementation UDPAK2Codec

- (NSString *)formatIdentifier {
    return @"com.udquake.pak2";
}

- (UDArchive *)readArchiveFromURL:(NSURL *)url error:(NSError **)error {
    UDArchive *base = [super readArchiveFromURL:url error:error];
    if (!base) {
        return nil;
    }

    NSMutableDictionary<NSString *, id> *meta = [base.metadata mutableCopy];
    [meta setObject:self.formatIdentifier forKey:@"formatIdentifier"];
    [meta setObject:@"quake2" forKey:@"game"];

    return [[UDArchive alloc] initWithDisplayName:base.displayName
                                          entries:base.entries
                                         metadata:meta];
}

@end
