//
//  UDWorkspaceManager.h
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "Foundation/Foundation.h"

// Define the notification name at the top of the header
extern NSString * const UDWorkspaceDidCloseNotification;

@class UDWorkspace;

@interface UDWorkspaceManager : NSObject

+(instancetype)sharedManager;

-(instancetype)init;
-(void)registerWorkspace:(UDWorkspace *)workspace;
-(UDWorkspace *)workspaceForDirectory:(NSString *)directoryPath;
-(UDWorkspace *)workspaceOwningFilePath:(NSString *)filePath;
-(void)closeWorkspace:(UDWorkspace *)workspace;

@end
