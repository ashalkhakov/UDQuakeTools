/*---------------------------------------------------------------------------------------------
 *  UQProject.h
 *
 *  A UDCode window's Quarry project (UDCode's project systems, its
 *  docs/extensions.md): the folder's .qworkspace, its game started (the
 *  file system over its paks, the decl manager), as the window's own.
 *  Its URLs, quarry:, are what UDCode opens of it —
 *
 *    quarry:/<type>/<name>     a decl (quarry:/material/textures/base_wall/a)
 *    quarry:/file/<path>       a game file, loose or in a pak (quarry:/file/script/doors.script)
 *
 *  read through the game's file system and written into its savepath, the
 *  mod's folder; the paks are never written (UDFileSystemProvider). And the
 *  tree of them, the Decls navigator (UDTreeDataProvider): each decl type
 *  and its decls by name, the scripts and the GUIs, Quarry's wildcard
 *  filter over their names.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>

@class UDWorkspace, UDWorkspaceItem;

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue when the project's game has started (or failed
/// to: its startupError); object = the project.
extern NSNotificationName const UQProjectDidStartNotification;

@interface UQProject : NSObject <UDFileSystemProvider, UDTreeDataProvider>

/// The project of @a folder (the window's), its game started from the first
/// .qworkspace in it, in the background.
- (instancetype)initWithFolder:(NSURL *)folder workbench:(nullable id<UDWorkbench>)workbench;

@property (nonatomic, readonly, copy) NSURL *folder;
@property (nonatomic, weak, readonly, nullable) id<UDWorkbench> workbench;
/// Its .qworkspace; nil: the folder has none.
@property (nonatomic, readonly, copy, nullable) NSURL *workspaceFileURL;
/// The game, once started (nil before, or when it couldn't be).
@property (nonatomic, readonly, nullable) UDWorkspace *workspace;
@property (nonatomic, readonly, nullable) NSError *startupError;
/// Its game started and its tree read, on the main queue (now when it is;
/// at once with the error when it can't be).
- (void)whenStarted:(void (^)(UDWorkspace *_Nullable workspace))block;

/// The tree's view, once the navigator is made.
@property (nonatomic, weak, nullable) UDTreeViewController *treeView;
/// The tree read again from the game (a decl added, a file saved).
- (void)reloadTree;

/// The decls, scripts and GUIs whose text has @a query (any case), each
/// with its URL: Quarry's Find.
- (NSArray<UDWorkspaceItem *> *)itemsContainingText:(NSString *)query;
/// A tree item's URL: its decl's, its file's; nil for a folder.
- (nullable NSURL *)URLOfItem:(UDWorkspaceItem *)item;

/// The URL of a decl, of a game file.
+ (NSURL *)URLOfDeclType:(NSString *)typeName name:(NSString *)name;
+ (NSURL *)URLOfGamePath:(NSString *)path;
/// What @a url names: a decl's type and name, or a game file's path (the
/// other nil); NO when it is no quarry: URL of either.
+ (BOOL)parseURL:(NSURL *)url typeName:(NSString *_Nullable *_Nullable)typeName name:(NSString *_Nullable *_Nullable)name
            path:(NSString *_Nullable *_Nullable)path;

@end

NS_ASSUME_NONNULL_END
