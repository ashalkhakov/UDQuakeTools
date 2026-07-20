//
//  UDFileSystemManager.m
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "UDFileSystemManager.h"
#import "UDWorkspaceManager.h"

@implementation UDFileSystemManager {
    NSMutableDictionary<NSString *, idFileSystem *> *_activeFileSystems;
}

+ (instancetype)sharedManager {
    static UDFileSystemManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _activeFileSystems = [[NSMutableDictionary alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleWorkspaceClosed:)
                                                     name:UDWorkspaceDidCloseNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (idFileSystem *)fileSystemForWorkspace:(UDWorkspace *)workspace {
    if (!workspace || !workspace.rootDirectory) return nil;
    
    // Check if we already spun up a VFS for this workspace
    idFileSystem *fs = _activeFileSystems[workspace.rootDirectory];
    
    if (!fs) {
        // First time accessing this workspace: Create and initialize the VFS
        fs = [[idFileSystem alloc] initWithWorkspace:workspace];
        
        // Cache it
        _activeFileSystems[workspace.rootDirectory] = fs;
    }
    
    return fs;
}

- (void)handleWorkspaceClosed:(NSNotification *)notification {
    UDWorkspace *closedWorkspace = notification.object;
    if (!closedWorkspace || !closedWorkspace.rootDirectory) return;

    // 1. Find the active file system for this workspace
    idFileSystem *fs = _activeFileSystems[closedWorkspace.rootDirectory];
    
    if (fs) {
        [fs shutdown:NO];
        
        [_activeFileSystems removeObjectForKey:closedWorkspace.rootDirectory];
    }
}

@end
