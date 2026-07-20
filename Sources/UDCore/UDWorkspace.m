//
//  UDWorkspace.m
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "UDWorkspace.h"

@implementation UDWorkspace

- (instancetype)initWithDictionary:(NSDictionary *)dict rootDirectory:(NSString *)rootDir {
    self = [super init];
    if (self) {
        _rootDirectory = [rootDir copy];
        
        // Strings
        _gamedir = dict[@"gamedir"] ?: @"base";
        
        // Mutable Strings (Ensuring they are actually mutable and never nil)
        _fs_basepath  = [dict[@"fs_basepath"] mutableCopy] ?: [[NSMutableString alloc] init];
        _fs_homepath  = [dict[@"fs_homepath"] mutableCopy] ?: [[NSMutableString alloc] init];
        _fs_savepath  = [dict[@"fs_savepath"] mutableCopy] ?: [[NSMutableString alloc] init];
        _fs_cdpath    = [dict[@"fs_cdpath"] mutableCopy] ?: [[NSMutableString alloc] init];
        _fs_game      = [dict[@"fs_game"] mutableCopy] ?: [[NSMutableString alloc] init];
        _fs_game_base = [dict[@"fs_game_base"] mutableCopy] ?: [[NSMutableString alloc] init];
        
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
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
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
        @"fs_caseSensitiveOS": @(self.fs_caseSensitiveOS)
    };
}

@end
