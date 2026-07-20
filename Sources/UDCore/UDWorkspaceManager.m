//
//  UDWorkspaceManager.m
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "UDWorkspaceManager.h"
#import "UDWorkspace.h"

NSString * const UDWorkspaceDidCloseNotification = @"UDWorkspaceDidCloseNotification";

@implementation UDWorkspaceManager {
    NSMutableDictionary<NSString *, UDWorkspace *> *_workspaces; // Keyed by rootDirectory
    NSString *_registryFilePath;
}

+ (instancetype)sharedManager {
    static UDWorkspaceManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _workspaces = [[NSMutableDictionary alloc] init];
        
        // 1. Resolve Application Support Path
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString *appSupport = paths.firstObject;
        NSString *myAppSupport = [appSupport stringByAppendingPathComponent:@"OpenQ4Editor"];
        
        // Ensure the directory exists
        [[NSFileManager defaultManager] createDirectoryAtPath:myAppSupport 
                                  withIntermediateDirectories:YES 
                                                   attributes:nil 
                                                        error:nil];
        
        // 2. Define the plist file path
        _registryFilePath = [myAppSupport stringByAppendingPathComponent:@"Workspaces.plist"];
        
        // 3. Load existing workspaces
        [self loadRegistry];
    }
    return self;
}

- (void)loadRegistry {
    NSDictionary *savedData = [NSDictionary dictionaryWithContentsOfFile:_registryFilePath];
    if (!savedData) return;
    
    for (NSString *rootDir in savedData) {
        NSDictionary *workspaceDict = savedData[rootDir];
        UDWorkspace *workspace = [[UDWorkspace alloc] initWithDictionary:workspaceDict rootDirectory:rootDir];
        _workspaces[rootDir] = workspace;
    }
}

- (void)saveWorkspace:(UDWorkspace *)workspace {
    // 1. Update memory
    _workspaces[workspace.rootDirectory] = workspace;
    
    // 2. Build a dictionary of all workspaces to write to disk
    NSMutableDictionary *plistData = [[NSMutableDictionary alloc] init];
    for (NSString *rootDir in _workspaces) {
        plistData[rootDir] = [_workspaces[rootDir] dictionaryRepresentation];
    }
    
    // 3. Write to disk
    [plistData writeToFile:_registryFilePath atomically:YES];
}

- (UDWorkspace *)workspaceForDirectory:(NSString *)directoryPath {
    return _workspaces[directoryPath];
}

- (UDWorkspace *)workspaceOwningFilePath:(NSString *)filePath {
    UDWorkspace *bestMatch = nil;
    NSUInteger longestMatchLength = 0;
    
    for (NSString *rootDir in _workspaces) {
        // Ensure we match whole directories (add trailing slash for safety)
        NSString *prefix = [rootDir hasSuffix:@"/"] ? rootDir : [rootDir stringByAppendingString:@"/"];
        
        if ([filePath hasPrefix:prefix]) {
            // Find the most specific (longest) registered path
            if (prefix.length > longestMatchLength) {
                longestMatchLength = prefix.length;
                bestMatch = _workspaces[rootDir];
            }
        }
    }
    
    return bestMatch;
}

- (void)closeWorkspace:(UDWorkspace *)workspace {
    if (!workspace || !workspace.rootDirectory) return;
    
    // 1. Remove it from the active workspaces dictionary
    [_workspaces removeObjectForKey:workspace.rootDirectory];
    
    // 2. Broadcast that this workspace is closing so the File System Manager
    // (and your UI, like open document windows) can clean themselves up.
    [[NSNotificationCenter defaultCenter] postNotificationName:UDWorkspaceDidCloseNotification
                                                        object:workspace];
}

@end
