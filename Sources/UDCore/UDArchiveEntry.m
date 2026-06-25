#import "UDArchiveEntry.h"

@implementation UDArchiveEntry

@synthesize path = _path;
@synthesize name = _name;
@synthesize size = _size;
@synthesize contentType = _contentType;
@synthesize modifiedAt = _modifiedAt;
@synthesize source = _source;
@synthesize stagedSource = _stagedSource;

- (instancetype)initWithPath:(NSString *)path
                        size:(uint64_t)size
                 contentType:(NSString *)contentType
                  modifiedAt:(NSDate *)modifiedAt
                      source:(id<UDContentSource>)source {
    NSParameterAssert(path.length > 0);
    NSParameterAssert(contentType.length > 0);
    NSParameterAssert(modifiedAt != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    NSString *normalizedPath = [path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    _path = [normalizedPath copy];
    _name = [_path.lastPathComponent copy];
    _size = size;
    _contentType = [contentType copy];
    _modifiedAt = [modifiedAt copy];
    _source = source;

    return self;
}

@end
