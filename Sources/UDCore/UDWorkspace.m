//
//  UDWorkspace.m
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "UDWorkspace.h"
#import "idFileSystem.h"
#import "idDeclManager.h"

@implementation UDWorkspace

- (instancetype)initWithDictionary:(NSDictionary *)dict rootDirectory:(NSString *)rootDir {
    self = [super init];
    if (self) {
        _rootDirectory = [rootDir copy];
        
        _pakFileExtension = dict[@"pakFileExtension"] ?: @"pk4";
        _gamedir = dict[@"gamedir"] ?: @"base";
        
        _fs_basepath  = dict[@"fs_basepath"] ?: @"";
        _fs_homepath  = dict[@"fs_homepath"] ?: @"";
        _fs_savepath  = dict[@"fs_savepath"] ?: @"";
        _fs_cdpath    = dict[@"fs_cdpath"] ?: @"";
        _fs_game      = dict[@"fs_game"] ?: @"";
        _fs_game_base = dict[@"fs_game_base"] ?: @"";
        
        // Primitives
        _fs_debug           = [dict[@"fs_debug"] boolValue];
        _fs_restrict        = [dict[@"fs_restrict"] boolValue];
        _fs_copyfiles       = [dict[@"fs_copyfiles"] intValue];
        
        // For boolean properties that might default to YES, check if the key exists first
        if (dict[@"fs_caseSensitiveOS"] != nil) {
            _fs_caseSensitiveOS = [dict[@"fs_caseSensitiveOS"] boolValue];
        } else {
            _fs_caseSensitiveOS = YES; // Default value
        }
        
        if (dict[@"decl_show"] != nil) {
            _decl_show = [dict[@"decl_show"] integerValue];
        } else {
            _decl_show = NO; // default
        }
        
        if (dict[@"com_SingleDeclFile"] != nil) {
            _com_SingleDeclFile = [dict[@"com_SingleDeclFile"] boolValue];
        } else {
            _com_SingleDeclFile = NO;
        }
        
        _com_singleDeclFileName = dict[@"com_singleDeclFileName"] ?: @"";
        
        if (dict[@"com_singleDeclFileWriteMode"] != nil) {
            _com_singleDeclFileWriteMode = [dict[@"com_singleDeclFileWriteMode"] integerValue];
        } else {
            _com_singleDeclFileWriteMode = 1; // default
        }
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"pakFileExtension": self.pakFileExtension ?: @"",
        @"gamedir": self.gamedir ?: @"",
        @"fs_basepath": self.fs_basepath ?: @"",
        @"fs_homepath": self.fs_homepath ?: @"",
        @"fs_savepath": self.fs_savepath ?: @"",
        @"fs_cdpath": self.fs_cdpath ?: @"",
        @"fs_game": self.fs_game ?: @"",
        @"fs_game_base": self.fs_game_base ?: @"",
        @"fs_debug": @(self.fs_debug),
        @"fs_restrict": @(self.fs_restrict),
        @"fs_copyfiles": @(self.fs_copyfiles),
        @"fs_caseSensitiveOS": @(self.fs_caseSensitiveOS),
        @"decl_show": @(self.decl_show),
        @"com_SingleDeclFile": @(self.com_SingleDeclFile),
        @"com_singleDeclFileName": self.com_singleDeclFileName,
        @"com_singleDeclFileWriteMode": @(self.com_singleDeclFileWriteMode)
    };
}

// ---------------------------------------------------------
// Lifetime Management
// ---------------------------------------------------------

- (void)startup {
    // Call this ONCE when you first load a workspace into your app.
    // They will live in memory until this UDWorkspace is destroyed.
    if (!self.fileSystem) {
        self.fileSystem = [[idFileSystem alloc] initWithWorkspace:self];
    }
    
    if (!self.declManager) {
        self.declManager = [[idDeclManager alloc] initWithWorkspace:self];
    }
    
    
    [self.fileSystem startup];
    [self.declManager startup];
}

@end
