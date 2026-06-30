#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDVFSMountKind) {
    UDVFSMountKindDirectory = 1,
    UDVFSMountKindArchive = 2,
};

@interface UDVFSMount : NSObject {
    NSString *_identifier;
    UDVFSMountKind _kind;
    NSURL *_sourceURL;
    NSString *_virtualRoot;
    NSInteger _priority;
    NSUInteger _mountOrder;
}

@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly) UDVFSMountKind kind;
@property (nonatomic, readonly, strong) NSURL *sourceURL;
@property (nonatomic, readonly, copy) NSString *virtualRoot;
@property (nonatomic, readonly) NSInteger priority;
@property (nonatomic, readonly) NSUInteger mountOrder;

- (instancetype)initWithIdentifier:(NSString *)identifier
                              kind:(UDVFSMountKind)kind
                         sourceURL:(NSURL *)sourceURL
                       virtualRoot:(NSString *)virtualRoot
                          priority:(NSInteger)priority
                        mountOrder:(NSUInteger)mountOrder NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
