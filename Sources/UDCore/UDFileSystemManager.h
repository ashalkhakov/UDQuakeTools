//
//  UDFileSystemManager.h
//  PakManager
//
//  Created by artyom on 7/20/26.
//

#import "idFileSystem.h"

@interface UDFileSystemManager : NSObject
+ (instancetype)sharedManager;
- (idFileSystem *)fileSystemForWorkspace:(UDWorkspace *)workspace;
@end
