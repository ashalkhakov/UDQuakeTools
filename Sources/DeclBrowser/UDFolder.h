#import "UDWorkspaceItem.h"

NS_ASSUME_NONNULL_BEGIN

/** Represents a folder (group) node in the workspace tree. */
@interface UDFolder : UDWorkspaceItem

- (instancetype)initWithName:(NSString *)name path:(nullable NSString *)path NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
