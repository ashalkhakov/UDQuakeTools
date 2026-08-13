#import "UDFolder.h"

@implementation UDFolder

- (instancetype)initWithName:(NSString *)name path:(NSString *)path {
    self = [super initWithName:name path:path];
    return self;
}

- (UDWorkspaceItemKind)kind {
    return UDWorkspaceItemKindGroup;
}

@end
