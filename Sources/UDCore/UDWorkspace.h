//
//  UDWorkspace.h
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class idFileSystem, idDeclManager;
@class NSManagedObjectContext, NSPersistentStoreCoordinator;

@interface UDWorkspace : NSObject

// The root folder on the user's drive (e.g., "/Users/bob/Games/Doom3/d3xp")
@property (nonatomic, copy) NSString *rootDirectory;

// variables
@property (strong, nonatomic) NSString *pakFileExtension; // "pk4"
@property (strong, nonatomic) NSString *gamedir; // the default game dir
@property (assign, nonatomic) BOOL fs_debug;
@property (assign, nonatomic) BOOL fs_restrict;
@property (assign, nonatomic) int fs_copyfiles;
@property (strong, nonatomic) NSString* fs_basepath;
@property (strong, nonatomic) NSString* fs_homepath;
@property (strong, nonatomic) NSString* fs_savepath;
@property (strong, nonatomic) NSString* fs_cdpath;
@property (strong, nonatomic) NSString* fs_game;
@property (strong, nonatomic) NSString* fs_game_base;
@property (assign, nonatomic) BOOL fs_caseSensitiveOS;

@property (assign, nonatomic) NSInteger decl_show; // set to 1 to print parses, 2 to also print references
@property (assign, nonatomic) BOOL com_SingleDeclFile; // load decls from a packed single .decls file instead of scanning loose decl folders
@property (strong, nonatomic) NSString *com_singleDeclFileName; // override packed decl file used by com_SingleDeclFile and writeDeclFile
@property (assign, nonatomic) NSInteger com_singleDeclFileWriteMode; // packed .decls writer policy: 0 = openQ4 extended game types, 1 = exact retail game types

// Engine Subsystems (Lifetimes are bound to the workspace, not the stack)
@property (nonatomic, strong) idFileSystem *fileSystem;
@property (nonatomic, strong) idDeclManager *declManager;

// The lazily-created shared persistent store coordinator (with a
// UDDeclIncrementalStore bound to this workspace's declManager). Every decl
// editing context of this workspace sits on top of this one coordinator.
// Returns nil (and logs) if the stack could not be built, e.g. when the
// workspace has no decl manager yet.
// (Requires CoreData; on GNUstep this is provided by FreeCoreData.)
@property (nonatomic, strong, readonly) NSPersistentStoreCoordinator *declStoreCoordinator;

// A FRESH editing context over declStoreCoordinator, with its own undo
// manager. Each open decl document creates one, giving VSCode-style
// per-document buffers: many decls can be modified at the same time, each
// document's -save: pushes only ITS changes down into idDeclManager (which
// then rewrites the affected decl files), and unsaved edits in one document
// are invisible to the others.
- (NSManagedObjectContext *)newDeclEditingContextWithError:(NSError **)error;

// Serialization
- (instancetype)initWithDictionary:(NSDictionary *)dict rootDirectory:(NSString *)rootDir;
- (NSDictionary *)dictionaryRepresentation;

// Initialization
- (BOOL)startup:(NSError **)error;
- (void)shutdown;

@end
