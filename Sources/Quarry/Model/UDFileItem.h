#import "UDWorkspaceItem.h"

@class UDGameWorkspace;

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a leaf file node in the workspace tree.
 * fileUTI is used to dispatch the correct editor.
 */
@interface UDFileItem : UDWorkspaceItem

/** Uniform Type Identifier, e.g. "public.c-source", "public.plain-text", "public.image". */
@property (nonatomic, copy, nullable) NSString *fileUTI;

- (instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithName:(NSString *)name path:(nullable NSString *)path NS_UNAVAILABLE;
- (BOOL)matchesTextSearch:(NSString *)query inWorkspace:(UDGameWorkspace *)workspace;

@end

NS_ASSUME_NONNULL_END
