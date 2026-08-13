//
//  UDWorkspace.h
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class idFileSystem, idDeclManager;

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

// Serialization
- (instancetype)initWithDictionary:(NSDictionary *)dict rootDirectory:(NSString *)rootDir;
- (NSDictionary *)dictionaryRepresentation;

// Initialization
- (BOOL)startup:(NSError **)error;
- (void)shutdown;

@end
