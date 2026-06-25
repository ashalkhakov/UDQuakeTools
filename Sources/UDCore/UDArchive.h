#import <Foundation/Foundation.h>

@class UDArchiveEntry;

NS_ASSUME_NONNULL_BEGIN

@interface UDArchive : NSObject {
    NSString *_displayName;
    NSArray<UDArchiveEntry *> *_entries;
    NSDictionary<NSString *, id> *_metadata;
}

@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, copy) NSArray<UDArchiveEntry *> *entries;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *metadata;

- (instancetype)initWithDisplayName:(NSString *)displayName
                            entries:(NSArray<UDArchiveEntry *> *)entries
                           metadata:(NSDictionary<NSString *, id> *)metadata NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
