//
//  sys.m
//  PakManager
//
//  Created by artyom on 7/19/26.
//

#include <sys/stat.h>
#import "sys.h"

// Define your app's save folder name.
// Change this to whatever your editor or openQ4 project uses.
static NSString * const kAppName = @"GuiEd";

NSString *Sys_DefaultCDPath(void) {
    return [[NSBundle mainBundle] resourcePath];
}
NSString *Sys_DefaultBasePath(void) {
    return [[NSBundle mainBundle] resourcePath];
}
NSString *Sys_DefaultSavePath(void) {
    // This dynamically finds the correct "Application Support" directory for the current user.
    // On macOS: ~/Library/Application Support
    // On GNUstep: ~/GNUstep/Library/Application Support
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    
    if (paths.count > 0) {
        NSString *baseAppSupport = paths[0];
        return [baseAppSupport stringByAppendingPathComponent:kAppName];
    }
    
    // Absolute fallback just in case the OS fails to resolve the directory
    return [NSHomeDirectory() stringByAppendingPathComponent:kAppName];
}

void Sys_Mkdir(const char *path) {
    if ( path == NULL || path[0] == '\0' ) {
        return;
    }
    if ( mkdir( path, 0777 ) == -1 && errno != EEXIST ) {
        NSLog(@"Sys_Mkdir: mkdir '%s' failed: %s\n", path, strerror(errno));
    }
}

int Sys_ListFiles(NSString *directory, NSString *extension, NSMutableArray<NSString *> *list) {
    // Replicates list.Clear()
    [list removeAllObjects];

    if (!directory || directory.length == 0) {
        NSLog(@"Sys_ListFiles: empty directory");
        return -1;
    }

    if (!extension) {
        extension = @"";
    }

    BOOL dirOnly = NO;
    // passing a slash as extension will find directories
    if ([extension isEqualToString:@"/"]) {
        dirOnly = YES;
        extension = @"";
    }

    NSString *targetExt = extension;
    if ([targetExt hasPrefix:@"."]) {
        targetExt = [targetExt substringFromIndex:1];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // contentsOfDirectoryAtPath automatically skips "." and ".." navigation entries!
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:directory error:&error];

    if (!contents) {
        NSLog(@"Sys_ListFiles: opendir %@ failed: %@", directory, error.localizedDescription);
        return -1;
    }

    for (NSString *filename in contents) {
        NSString *fullPath = [directory stringByAppendingPathComponent:filename];
        BOOL isDir = NO;

        // Equivalent to stat(search.c_str(), &st)
        if (![fm fileExistsAtPath:fullPath isDirectory:&isDir]) {
            continue;
        }

        if (dirOnly && !isDir) {
            continue;
        }
        
        if (!dirOnly && isDir) {
            continue;
        }

        // Check for extension match (if one was provided)
        if (!dirOnly && targetExt.length > 0) {
            NSString *fileExt = [filename pathExtension];
            if ([fileExt caseInsensitiveCompare:targetExt] != NSOrderedSame) {
                continue;
            }
        }

        [list addObject:filename];
    }

    // if (fs_debug) {
    //     NSLog(@"Sys_ListFiles: %lu entries in %@", (unsigned long)list.count, directory);
    // }

    return (int)list.count;
}

BOOL Sys_ExactFileEntryMatches(const char *path, BOOL directoryOnly) {
    struct stat exactStat;
    const BOOL exactEntryMatches = stat(path, &exactStat) == 0 && (directoryOnly ? S_ISDIR(exactStat.st_mode) : !S_ISDIR(exactStat.st_mode));
    return exactEntryMatches;
}

unsigned int Sys_FileTimeStamp(FILE * fp) {
    if ( fp == NULL ) {
        return -1;
    }
    struct stat st;
    if ( fstat(fileno(fp), &st) == -1 ) {
        return -1;
    }
    return st.st_mtime;
}
