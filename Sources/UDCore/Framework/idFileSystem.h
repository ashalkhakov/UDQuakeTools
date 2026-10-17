/*
===========================================================================

Doom 3 GPL Source Code
Copyright (C) 1999-2011 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 GPL Source Code (?Doom 3 Source Code?).

Doom 3 Source Code is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Doom 3 Source Code is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Doom 3 Source Code.  If not, see <http://www.gnu.org/licenses/>.

In addition, the Doom 3 Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the Doom 3 Source Code.  If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/

#import "UDWorkspace.h"

#define MAX_STRING_CHARS        1024        // max length of a string
#define PATHSEPERATOR_CHAR      '/'
#define PATHSEPERATOR_STR       "/"

/*
===============================================================================

    File System

    No stdio calls should be used by any part of the game, because of all sorts
    of directory and separator char issues. Throughout the game a forward slash
    should be used as a separator. The file system takes care of the conversion
    to an OS specific separator. The file system treats all file and directory
    names as case insensitive.

    The following cvars store paths used by the file system:

    "fs_basepath"        path to local install, read-only
    "fs_homepath"        user-writable home path root
    "fs_savepath"        path to config, save game, etc. files, read & write
    "fs_cdpath"            locked path to the executable current working directory

    The base path for file saving can be set to "fs_savepath" or "fs_cdpath".

===============================================================================
*/

@class idFile;

static const unsigned int        FILE_NOT_FOUND_TIMESTAMP    = 0xFFFFFFFF;
static const int        MAX_PURE_PAKS                = 128;
static const int        MAX_OSPATH                    = 256;

typedef NS_ENUM(NSInteger, UDFileSystemPortErrorCode) {
    UDFileSystemPortErrorCodeNotInitialized = 2001,
    UDFileSystemPortErrorCodeInvalidArgument = 2002,
    UDFileSystemPortErrorCodeInvalidPath = 2003,
    UDFileSystemPortErrorCodeReadFailed = 2004,
    UDFileSystemPortErrorCodeWriteFailed = 2005,
};

// modes for OpenFileByMode. used as bit mask internally
typedef enum {
    FS_READ        = 0,
    FS_WRITE    = 1,
    FS_APPEND    = 2
} fsMode_t;

typedef enum {
    FILE_EXEC,
    FILE_OPEN
} dlMime_t;

typedef enum {
    FIND_NO,
    FIND_YES,
    FIND_ADDON
} findFile_t;

// file list for directory listings
@interface idFileList : NSObject

@property (strong, nonatomic) NSString *basePath;
@property (strong, nonatomic) NSArray<NSString *> *list;

-(instancetype)initWithBasePath:(NSString *)basePath list:(NSArray *)array;

-(int)numFiles;
-(NSString *)fileByIndex:(int)index;
@end

@interface idFileSystem : NSObject

// the workspace that owns this file system instance
@property (nonatomic, weak, readonly) UDWorkspace *workspace;

// variables
@property (readonly, nonatomic) NSString *gamedir; // the default game dir
@property (readonly, nonatomic) BOOL fs_debug;
@property (readonly, nonatomic) BOOL fs_restrict;
@property (readonly, nonatomic) int fs_copyfiles;
@property (readonly, nonatomic) NSString* fs_basepath;
@property (readonly, nonatomic) NSString* fs_homepath;
@property (readonly, nonatomic) NSString* fs_savepath;
@property (readonly, nonatomic) NSString* fs_cdpath;
@property (readonly, nonatomic) NSString* fs_game;
@property (readonly, nonatomic) NSString* fs_game_base;
@property (readonly, nonatomic) BOOL fs_caseSensitiveOS;

-(void)resetReadCount;
-(void)addToReadCount:(int)c;
-(int)readCount;

// Initializes the file system.
- (instancetype)initWithWorkspace:(UDWorkspace *)workspace;

-(BOOL)startup:(NSError **)error;
// Restarts the file system.
-(void)restart;
// Shutdown the file system.
-(void)shutdown:(BOOL)reloading;
// Returns true if the file system is initialized.
-(BOOL)isInitialized;
// Returns true if we are doing an fs_copyfiles.
-(BOOL)performingCopyFiles;

// Lists files with the given extension in the given directory.
// Directory should not have either a leading or trailing '/'
// The returned files will not include any directories or '/' unless fullRelativePath is set.
// The extension must include a leading dot and may not contain wildcards.
// If extension is "/", only subdirectories will be returned.
-(idFileList *)listFiles:(NSString *)relativePath extension:(NSString*)extension sorted:(BOOL)sort fullRelativePath:(BOOL)fullRelativePath inGameDir:(NSString *)gamedir error:(NSError **)error;

// sorted=NO, fullRelativePath=NO, inGameDir=nil
- (idFileList *)listFiles:(NSString *)relativePath extension:(NSString *)extension error:(NSError **)error;

// fullRelativePath=NO, inGameDir=nil
- (idFileList *)listFiles:(NSString *)relativePath extension:(NSString *)extension sorted:(BOOL)sorted error:(NSError **)error;

// inGameDir=nil
- (idFileList *)listFiles:(NSString *)relativePath extension:(NSString *)extension sorted:(BOOL)sorted fullRelativePath:(BOOL)fullRelativePath error:(NSError **)error;

// Lists files in the given directory and all subdirectories with the given extension.
// Directory should not have either a leading or trailing '/'
// The returned files include a full relative path.
// The extension must include a leading dot and may not contain wildcards.
-(idFileList *)listFilesTree:(NSString *)relativePath extension:(NSString *)extension sorted:(BOOL)sort inGameDir:(NSString *)gamedir error:(NSError **)error;
// Frees the given file list.
-(void)freeFileList:(idFileList *)fileList;
// Converts a relative path to a full OS path.
-(NSString *)osPathToRelativePath:(NSString *)osPath;
// Converts a full OS path to a relative path.
-(NSString *)relativePathToOSPath:(NSString *)relativePath basePath:(NSString *)basePath;
// Builds a full OS path from the given components.
-(NSString *)buildOSPath:(NSString *)base game:(NSString *)game relativePath:(NSString *)relativePath;
// Creates the given OS path for as far as it doesn't exist already.
-(BOOL)createOSPath:(NSString *)osPath error:(NSError **)error;
// Returns true if a file is in a pak file.
-(BOOL)fileIsInPAK:(NSString *)relativePath error:(NSError **)error;

// Reads a complete file.
// Returns the length of the file, or -1 on failure.
// A null buffer will just return the file length without loading.
// A null timestamp will be ignored.
// As a quick check for existance. -1 length == not present.
// A 0 byte will always be appended at the end, so string ops are safe.
// The buffer should be considered read-only, because it may be cached for other uses.
-(int)readFile:(NSString *)relativePath buffer:(void **)buffer timestamp:(unsigned int *)timestamp error:(NSError **)error;
// Frees the memory allocated by ReadFile.
-(BOOL)freeFile:(void *)buffer error:(NSError **)error;
// Writes a complete file, will create any needed subdirectories.
// Returns the length of the file, or -1 on failure.
-(int)writeFile:(NSString *)relativePath buffer:(const void *)buffer size:(int)size basePath:(NSString *)basePath error:(NSError **)error;

// Removes the given file.
-(void)removeFile:(NSString *)relativePath basePath:(NSString *)basePath;
// Removes the given explicit OS file and returns the OS remove result.
-(int)removeExplicitFile:(NSString *)osSPath;

-(idFile *)newFileMemory;
-(idFile *)newFilePermanent;
// Opens a file for reading.
-(idFile *)openFileRead:(NSString *)relativePath allowCopyFiles:(BOOL)allowCopyFiles gamedir:(NSString *)gamedir error:(NSError **)error;
// Opens a file for reading from pak files only.
-(idFile *)openFileReadFromPak:(NSString *)relativePath allowCopyFiles:(BOOL)allowCopyFiles gamedir:(NSString *)gamedir error:(NSError **)error;
// Opens a file for writing, will create any needed subdirectories.
-(idFile *)openFileWrite:(NSString *)relativePath basePath:(NSString *)basePath error:(NSError **)error;
// Opens a file for writing at the end.
-(idFile *)openFileAppend:(NSString *)filename sync:(BOOL)sync basePath:(NSString *)basePath error:(NSError **)error;
// Opens a file for reading, writing, or appending depending on the value of mode.
-(idFile *)openFileByMode:(NSString *)relativePath mode:(fsMode_t)mode error:(NSError **)error;
// Opens a file for reading from a full OS path.
-(idFile *)openExplicitFileRead:(NSString *)osPath;
// Opens a file for writing to a full OS path.
-(idFile *)openExplicitFileWrite:(NSString *)osPath;
// Closes a file.
-(BOOL)closeFile:(idFile *)f error:(NSError **)error;

-(idFile *)makeTemporaryFile;

// look for a file in the loaded paks or the addon paks
// if the file is found in addons, FS's internal structures are ready for a reloadEngine
-(findFile_t)findFile:(NSString *)path scheduleAddons:(BOOL)scheduleAddons error:(NSError **)error;

// ignore case and seperator char distinctions
-(BOOL)filenameCompare:(NSString *)s1 to:(NSString *)s2;

@end
