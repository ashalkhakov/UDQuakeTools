#import <Foundation/Foundation.h>

@class UDArchiveEntry;
@class UDDirectoryNode;

NS_ASSUME_NONNULL_BEGIN

@interface UDArchive : NSObject {
    NSString *_displayName;
    UDDirectoryNode *_rootNode;
    NSDictionary<NSString *, id> *_metadata;
}

@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, strong) UDDirectoryNode *rootNode;
@property (nonatomic, readonly, copy) NSArray<UDArchiveEntry *> *entries;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *metadata;

- (instancetype)initWithDisplayName:(NSString *)displayName
                           rootNode:(UDDirectoryNode *)rootNode
                           metadata:(NSDictionary<NSString *, id> *)metadata;

- (instancetype)initWithDisplayName:(NSString *)displayName
                            entries:(NSArray<UDArchiveEntry *> *)entries
                           metadata:(NSDictionary<NSString *, id> *)metadata;

@end

NS_ASSUME_NONNULL_END
