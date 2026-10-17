//
//  UDWorkspace.h
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "UDGame.h"
#import "UDEngineSettings.h"

@class idFileSystem, idDeclManager;
@class NSManagedObjectContext, NSPersistentStoreCoordinator;

/// Posted when a tool's settings change (the object: the workspace; the
/// user info's "tool": the tool's name).
extern NSNotificationName const UDWorkspaceToolSettingsDidChangeNotification;

@interface UDWorkspace : NSObject <UDEngineSettings>

// The root folder on the user's drive (e.g., "/Users/bob/Games/Doom3/d3xp")
@property (nonatomic, copy) NSString *rootDirectory;

// The game whose files these are: it decides which decl types and folders
// the decl manager registers (Doom 3's materials, Quake 3's shaders, ...).
// Saved as UDGame's identifier; a workspace without one is Doom 3's.
@property (assign, nonatomic) UDGameType game;

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

// (not the engine's) The game the scripts are debugged in: its executable
// (an application bundle or a program) and the arguments it is started with
// besides the workspace's paths, as a command line has them ("+map game/mars_city1").
@property (strong, nonatomic) NSString *gameExecutable;
@property (strong, nonatomic) NSString *gameArguments;

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

/// The tools' own settings, kept with the workspace's (its
/// dictionaryRepresentation's "tools"), each a dictionary by the tool's
/// name: "GUIEditor" (rvGEOptions' registry). Set, it posts
/// UDWorkspaceToolSettingsDidChangeNotification. Read from the dictionary
/// the workspace is made with; applySettingsFromDictionary: leaves them.
- (nullable NSDictionary *)settingsForTool:(NSString *)tool;
- (void)setSettings:(nullable NSDictionary *)settings forTool:(NSString *)tool;
- (NSDictionary *)dictionaryRepresentation;

/// (not the engine's) The folders a file's game path ("script/lamp.script")
/// is relative to on disk, in the search paths' order: each of fs_savepath,
/// fs_basepath and fs_cdpath, with fs_game, fs_game_base and base. Read
/// from the settings alone (no -startup:).
@property (nonatomic, readonly) NSArray<NSString *> *gameFolders;
/// The file at @a gamePath on disk; one in a pak named where it would be in
/// the first of the gameFolders there is (a debugger's name for a script,
/// the same for its editor and its adapter). And back: nil for what no
/// game folder holds.
- (NSString *)diskPathOfGamePath:(NSString *)gamePath;
- (nullable NSString *)gamePathOfDiskPath:(NSString *)path;

// Re-applies a settings dictionary (same keys as dictionaryRepresentation)
// onto this workspace, filling in the usual defaults for missing keys. Used
// by the settings window: edits happen on a scratch UDWorkspace copy, and on
// OK its dictionaryRepresentation is applied back here. Changing paths/game
// settings on a RUNNING workspace requires a -shutdown / -startup: cycle
// afterwards to take effect.
- (void)applySettingsFromDictionary:(NSDictionary *)dict;

// Initialization
- (BOOL)startup:(NSError **)error;
- (void)shutdown;

// -startup: on a thread of its own, the paks and decls read off the main
// thread; then @a action goes to @a target on the main thread, with this
// workspace. Nothing else uses the workspace until then. -startupError says
// why it did not start, or is nil.
- (void)startupInBackgroundWithTarget:(id)target action:(SEL)action;
@property (nonatomic, readonly) NSError *startupError;

@end
