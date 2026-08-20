//
//  UDWorkspace.m
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "UDWorkspace.h"

#import <CoreData/CoreData.h>

#import "idFileSystem.h"
#import "idDeclManager.h"
#import "UDDeclIncrementalStore.h"

@implementation UDWorkspace {
    NSPersistentStoreCoordinator *_declStoreCoordinator;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict rootDirectory:(NSString *)rootDir {
    self = [super init];
    if (self) {
        _rootDirectory = [rootDir copy];
        [self applySettingsFromDictionary:dict];
    }
    return self;
}

- (void)applySettingsFromDictionary:(NSDictionary *)dict {
    self.pakFileExtension = dict[@"pakFileExtension"] ?: @"pk4";
    self.gamedir = dict[@"gamedir"] ?: @"base";

    self.fs_basepath  = dict[@"fs_basepath"] ?: @"";
    self.fs_homepath  = dict[@"fs_homepath"] ?: @"";
    self.fs_savepath  = dict[@"fs_savepath"] ?: @"";
    self.fs_cdpath    = dict[@"fs_cdpath"] ?: @"";
    self.fs_game      = dict[@"fs_game"] ?: @"";
    self.fs_game_base = dict[@"fs_game_base"] ?: @"";

    // Primitives
    self.fs_debug     = [dict[@"fs_debug"] boolValue];
    self.fs_restrict  = [dict[@"fs_restrict"] boolValue];
    self.fs_copyfiles = [dict[@"fs_copyfiles"] intValue];

    // For settings whose default is not the zero value, check if the key
    // exists first.
    if (dict[@"fs_caseSensitiveOS"] != nil) {
        self.fs_caseSensitiveOS = [dict[@"fs_caseSensitiveOS"] boolValue];
    } else {
        self.fs_caseSensitiveOS = YES; // Default value
    }

    self.decl_show = dict[@"decl_show"] != nil ? [dict[@"decl_show"] integerValue] : 0;
    self.com_SingleDeclFile = [dict[@"com_SingleDeclFile"] boolValue];
    self.com_singleDeclFileName = dict[@"com_singleDeclFileName"] ?: @"";

    if (dict[@"com_singleDeclFileWriteMode"] != nil) {
        self.com_singleDeclFileWriteMode = [dict[@"com_singleDeclFileWriteMode"] integerValue];
    } else {
        self.com_singleDeclFileWriteMode = 1; // default
    }
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

- (BOOL)startup:(NSError **)error {
    // Call this ONCE when you first load a workspace into your app.
    // They will live in memory until this UDWorkspace is destroyed.
    if (!self.fileSystem) {
        self.fileSystem = [[idFileSystem alloc] initWithWorkspace:self];
    }
    
    if (!self.declManager) {
        self.declManager = [[idDeclManager alloc] initWithWorkspace:self];
    }
    
    
    if (![self.fileSystem startup:error]) {
        return NO;
    }
    if (![self.declManager startup:error]) {
        return NO;
    }
    
    return YES;
}

-(void)shutdown {
    _declStoreCoordinator = nil;
    [self.declManager shutdown];
    [self.fileSystem shutdown:NO];
}

// ---------------------------------------------------------
// Decl editing (Core Data over idDeclManager)
// ---------------------------------------------------------

- (NSPersistentStoreCoordinator *)declStoreCoordinator {
    if (_declStoreCoordinator != nil) {
        return _declStoreCoordinator;
    }

    if (self.declManager == nil) {
        NSLog(@"UDWorkspace: workspace has no declManager; no decl store coordinator");
        return nil;
    }

    NSError *error = nil;
    _declStoreCoordinator = [UDDeclIncrementalStore newStoreCoordinatorForDeclManager:self.declManager error:&error];
    if (_declStoreCoordinator == nil) {
        NSLog(@"UDWorkspace: could not build decl store coordinator: %@", error);
    }
    return _declStoreCoordinator;
}

- (NSManagedObjectContext *)newDeclEditingContextWithError:(NSError **)error {
    NSPersistentStoreCoordinator *coordinator = self.declStoreCoordinator;
    if (coordinator == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"UDWorkspace"
                                          code:1
                                      userInfo:@{NSLocalizedDescriptionKey: @"Could not build the decl editing stack"}];
        }
        return nil;
    }
    return [UDDeclIncrementalStore newEditingContextForCoordinator:coordinator];
}

@end
