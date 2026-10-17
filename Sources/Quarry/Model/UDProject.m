#import "UDProject.h"

@implementation UDProject

- (instancetype)initWithName:(NSString *)name path:(NSString *)path {
    self = [super initWithName:name path:path];
    return self;
}

- (UDWorkspaceItemKind)kind {
    return UDWorkspaceItemKindGroup;
}

- (void)removeAllChildren {
    for (UDWorkspaceItem *child in self.children) {
        [self removeChild:child];
    }
}

@end
