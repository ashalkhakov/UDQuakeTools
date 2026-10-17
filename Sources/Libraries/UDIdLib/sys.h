//
//  sys.h
//  PakManager
//
//  Created by artyom on 7/19/26.
//

#import <Foundation/Foundation.h>

extern NSString *Sys_DefaultCDPath(void);
extern NSString *Sys_DefaultBasePath(void);
extern NSString *Sys_DefaultSavePath(void);
extern void Sys_Mkdir( const char *path );
int Sys_ListFiles(NSString *directory, NSString *extension, NSMutableArray<NSString *> *list);
extern BOOL Sys_ExactFileEntryMatches(const char *path, BOOL directoryOnly);
extern unsigned int Sys_FileTimeStamp(FILE *fp);
