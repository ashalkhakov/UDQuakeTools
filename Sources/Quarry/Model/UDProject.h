#import "UDWorkspaceItem.h"

NS_ASSUME_NONNULL_BEGIN

/** Represents a top-level project node in the workspace tree. */
@interface UDProject : UDWorkspaceItem

- (instancetype)initWithName:(NSString *)name path:(nullable NSString *)path NS_DESIGNATED_INITIALIZER;

- (void)removeAllChildren;

@end

NS_ASSUME_NONNULL_END
