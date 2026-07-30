//
//  UDWorkspaceManager.h
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "Foundation/Foundation.h"

@class UDWorkspace;

// Define the notification name at the top of the header
extern NSString * const UDWorkspaceDidCloseNotification;

@interface UDWorkspaceManager : NSObject

+ (instancetype)sharedManager;

// Create or update a workspace setting
- (void)saveWorkspace:(UDWorkspace *)workspace;

// Exact match lookup (when the user opens a specific folder)
- (UDWorkspace *)workspaceForDirectory:(NSString *)directoryPath;

// Reverse lookup: Given an arbitrary file path, find which workspace owns it
- (UDWorkspace *)workspaceOwningFilePath:(NSString *)filePath;

// Open the workspace. Pass in the settings if needed.
- (UDWorkspace *)openWorkspace:(NSString *)rootDirectory withDictionary:(NSDictionary *)dictionary;

// Close the workspace
- (void)closeWorkspace:(UDWorkspace *)workspace;

@end
