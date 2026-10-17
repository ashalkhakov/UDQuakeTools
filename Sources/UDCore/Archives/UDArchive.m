#import "UDArchive.h"
#import "UDDirectoryNode.h"

@implementation UDArchive

@synthesize displayName = _displayName;
@synthesize rootNode = _rootNode;
@synthesize metadata = _metadata;

- (NSArray *)entries {
    return [self.rootNode allEntries];
}

- (instancetype)initWithDisplayName:(NSString *)displayName
                           rootNode:(UDDirectoryNode *)rootNode
                           metadata:(NSDictionary *)metadata {
    NSParameterAssert(displayName.length > 0);
    NSParameterAssert(rootNode != nil);
    NSParameterAssert(metadata != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _displayName = [displayName copy];
    _rootNode = rootNode;
    _metadata = [metadata copy];
    return self;
}

- (instancetype)initWithDisplayName:(NSString *)displayName
                            entries:(NSArray *)entries
                           metadata:(NSDictionary *)metadata {
    UDDirectoryNode *rootNode = [UDDirectoryNode rootNodeFromEntries:entries ?: @[]];
    return [self initWithDisplayName:displayName rootNode:rootNode metadata:metadata];
}

@end
