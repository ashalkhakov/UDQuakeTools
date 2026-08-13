#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UDWorkspace;

/** Workspace item kinds. */
typedef NS_ENUM(NSInteger, UDWorkspaceItemKind) {
    UDWorkspaceItemKindGroup,   // Project or Folder
    UDWorkspaceItemKindFile,    // Leaf file
    UDWorkspaceItemKindDecl,    // Leaf decl
};

/**
 * Base tree node for the workspace outline.
 * Subclassed by Project, Folder, and FileItem.
 */
@interface UDWorkspaceItem : NSObject

@property (nonatomic, copy)   NSString *name;
/** Absolute path on disk (may be nil for virtual group nodes). */
@property (nonatomic, copy, nullable) NSString *path;
@property (nonatomic, readonly) UDWorkspaceItemKind kind;
@property (nonatomic, readonly) NSArray<UDWorkspaceItem *> *children;
@property (nonatomic, weak, nullable) UDWorkspaceItem *parent;

- (instancetype)initWithName:(NSString *)name path:(nullable NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/** Add a child item (only valid for group nodes). */
- (void)addChild:(UDWorkspaceItem *)child;
/** Remove a child item. */
- (void)removeChild:(UDWorkspaceItem *)child;

- (BOOL)matchesTextSearch:(NSString *)query inWorkspace:(UDWorkspace *)workspace;

@end

NS_ASSUME_NONNULL_END
