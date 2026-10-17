#import "UDArchiveEntry.h"

@implementation UDArchiveEntry

@synthesize path = _path;
@synthesize name = _name;
@synthesize size = _size;
@synthesize contentType = _contentType;
@synthesize modifiedAt = _modifiedAt;
@synthesize parent = _parent;

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
    _contentSource = source;

    return self;
}

- (id<UDContentSource>)contentSource {
    return _contentSource;
}

- (void)setContentSource:(id<UDContentSource>)contentSource {
    _contentSource = contentSource;
}

- (id<UDContentSource>)source {
    return self.contentSource;
}

- (void)setSource:(id<UDContentSource>)source {
    self.contentSource = source;
}

- (id<UDContentSource>)stagedSource {
    return self.contentSource;
}

- (void)setStagedSource:(id<UDContentSource>)stagedSource {
    self.contentSource = stagedSource;
}

- (instancetype)entryByCopyingWithPath:(NSString *)path
                         contentSource:(id<UDContentSource>)contentSource
                            modifiedAt:(NSDate *)modifiedAt {
    id<UDContentSource> effectiveSource = contentSource ?: self.contentSource;
    uint64_t effectiveSize = effectiveSource ? effectiveSource.length : self.size;
    return [[UDArchiveEntry alloc] initWithPath:path
                                           size:effectiveSize
                                    contentType:self.contentType
                                     modifiedAt:modifiedAt ?: self.modifiedAt
                                         source:effectiveSource];
}

@end
