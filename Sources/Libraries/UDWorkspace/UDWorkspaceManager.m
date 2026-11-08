//
//  UDWorkspaceManager.m
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "UDWorkspaceManager.h"
#import "UDGameWorkspace.h"

NSString * const UDWorkspaceDidCloseNotification = @"UDWorkspaceDidCloseNotification";

@implementation UDWorkspaceManager {
    NSMutableDictionary<NSString *, UDGameWorkspace *> *_workspaces; // Keyed by rootDirectory
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
    }
    return self;
}

// Registers an already-created workspace into the active session
- (void)registerWorkspace:(UDGameWorkspace *)workspace {
    if (workspace.rootDirectory) {
        _workspaces[workspace.rootDirectory] = workspace;
    }
}

- (UDGameWorkspace *)workspaceForDirectory:(NSString *)directoryPath {
    return _workspaces[directoryPath];
}

- (UDGameWorkspace *)workspaceOwningFilePath:(NSString *)filePath {
    UDGameWorkspace *bestMatch = nil;
    NSUInteger longestMatchLength = 0;
    
    for (NSString *rootDir in _workspaces) {
        NSString *prefix = [rootDir hasSuffix:@"/"] ? rootDir : [rootDir stringByAppendingString:@"/"];
        if ([filePath hasPrefix:prefix] && prefix.length > longestMatchLength) {
            longestMatchLength = prefix.length;
            bestMatch = _workspaces[rootDir];
        }
    }
    return bestMatch;
}

- (void)closeWorkspace:(UDGameWorkspace *)workspace {
    if (!workspace || !workspace.rootDirectory) return;
    [_workspaces removeObjectForKey:workspace.rootDirectory];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDWorkspaceDidCloseNotification
                                                        object:workspace];
}

@end
