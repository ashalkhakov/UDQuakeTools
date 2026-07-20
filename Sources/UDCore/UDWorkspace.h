//
//  UDWorkspace.h
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import <Foundation/Foundation.h>

@interface UDWorkspace : NSObject

// The root folder on the user's drive (e.g., "/Users/bob/Games/Doom3/d3xp")
@property (nonatomic, copy) NSString *rootDirectory;

// variables
@property (copy, nonatomic) NSString *gamedir; // the default game dir
@property (assign, nonatomic) BOOL fs_debug;
@property (assign, nonatomic) BOOL fs_restrict;
@property (assign, nonatomic) int fs_copyfiles;
@property (copy, nonatomic) NSMutableString* fs_basepath;
@property (copy, nonatomic) NSMutableString* fs_homepath;
@property (copy, nonatomic) NSMutableString* fs_savepath;
@property (copy, nonatomic) NSMutableString* fs_cdpath;
@property (copy, nonatomic) NSMutableString* fs_game;
@property (copy, nonatomic) NSMutableString* fs_game_base;
@property (assign, nonatomic) BOOL fs_caseSensitiveOS;

// Serialization
- (instancetype)initWithDictionary:(NSDictionary *)dict rootDirectory:(NSString *)rootDir;
- (NSDictionary *)dictionaryRepresentation;

@end
