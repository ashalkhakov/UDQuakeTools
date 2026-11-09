//
//  UDWorkspaceManager.h
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "Foundation/Foundation.h"

// Define the notification name at the top of the header
extern NSString * const UDWorkspaceDidCloseNotification;

@class UDGameWorkspace;

@interface UDWorkspaceManager : NSObject

+(instancetype)sharedManager;

-(instancetype)init;
-(void)registerWorkspace:(UDGameWorkspace *)workspace;
-(UDGameWorkspace *)workspaceForDirectory:(NSString *)directoryPath;
-(UDGameWorkspace *)workspaceOwningFilePath:(NSString *)filePath;
-(void)closeWorkspace:(UDGameWorkspace *)workspace;

@end
