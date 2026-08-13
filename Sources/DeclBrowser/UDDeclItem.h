#import "UDWorkspaceItem.h"
#import "idDeclManager.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a leaf decl node in the workspace tree.
 */
@interface UDDeclItem : UDWorkspaceItem

@property (nonatomic, readonly) declType_t type;

- (instancetype)initWithType:(declType_t)type path:(NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithName:(NSString *)name path:(nullable NSString *)path NS_UNAVAILABLE;

- (BOOL)matchesTextSearch:(NSString *)query inWorkspace:(UDWorkspace *)workspace;

@end

NS_ASSUME_NONNULL_END
