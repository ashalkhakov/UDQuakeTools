#import "UDWorkspaceItem.h"
#import "UDWorkspace.h"

@interface UDWorkspaceItem ()
@property (nonatomic, strong) NSMutableArray<UDWorkspaceItem *> *mutableChildren;
@end

@implementation UDWorkspaceItem

- (instancetype)initWithName:(NSString *)name path:(NSString *)path {
    self = [super init];
    if (self) {
        _name = [name copy];
        _path = [path copy];
        _mutableChildren = [NSMutableArray array];
    }
    return self;
}

- (NSArray<UDWorkspaceItem *> *)children {
    return [self.mutableChildren copy];
}

- (void)addChild:(UDWorkspaceItem *)child {
    child.parent = self;
    [self.mutableChildren addObject:child];
}

- (void)removeChild:(UDWorkspaceItem *)child {
    child.parent = nil;
    [self.mutableChildren removeObject:child];
}

- (BOOL)matchesTextSearch:(NSString *)query inWorkspace:(UDWorkspace *)workspace {
    return NO;
}

@end
