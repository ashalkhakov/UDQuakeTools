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

#import "idStr.h"
#import "idFile.h"
#import "idFileSystem.h"
#import "unzip.h"
#import "sys.h"

extern NSString * const UDFileSystemErrorDomain;

/*
=============================================================================

DOOM FILESYSTEM

All of Doom's data access is through a hierarchical file system, but the contents of
the file system can be transparently merged from several sources.

A "relativePath" is a reference to game file data, which must include a terminating zero.
"..", "\\", and ":" are explicitly illegal in qpaths to prevent any references
outside the Doom directory system.

The "base path" is the path to the directory holding all the game directories and
usually the executable. It defaults to the current directory, but can be overridden
with "+set fs_basepath c:\doom" on the command line. The base path cannot be modified
at all after startup.

The "home path" is the user-writable root path for openQ4 data. It can be overridden
with "+set fs_homepath c:\users\you\saved games\openq4" on the command line.

The "save path" is the path to the directory where game files will be saved. It defaults
to the home path, but can be overridden with a "+set fs_savepath c:\doom" on the
command line. Any files that are created during the game (demos, screenshots, etc.) will
be created reletive to the save path.

The "cd path" is the path to an alternate hierarchy that will be searched if a file
is not located in the base path. A user can do a partial install that copies some
data to a base path created on their hard drive and leave the rest on the cd. It defaults
to the process current directory and is locked at startup.

If a user runs the game directly from a CD, the base path would be on the CD. This
should still function correctly, but all file writes will fail (harmlessly).

The "base game" is the directory under the paths where data comes from by default, and
can be either "base" or "demo".

The "current game" may be the same as the base game, or it may be the name of another
directory under the paths that should be searched for files before looking in the base
game. The game directory is set with "+set fs_game myaddon" on the command line. This is
the basis for addons.

No other directories outside of the base game and current game will ever be referenced by
filesystem functions.

To save disk space and speed up file loading, directory trees can be collapsed into zip
files. The files use a ".pk4" extension to prevent users from unzipping them accidentally,
but otherwise they are simply normal zip files. A game directory can have multiple zip
files of the form "pak0.pk4", "pak1.pk4", etc. Zip files are searched in decending order
from the highest number to the lowest, and will always take precedence over the filesystem.
This allows a pk4 distributed as a patch to override all existing data.

Because we will have updated executables freely available online, there is no point to
trying to restrict demo / oem versions of the game with code changes. Demo / oem versions
should be exactly the same executables as release versions, but with different data that
automatically restricts where game media can come from to prevent add-ons from working.

After the paths are initialized, Doom will look for the product.txt file. If not found
and verified, the game will run in restricted mode. In restricted mode, only files
contained in demo/pak0.pk4 will be available for loading, and only if the zip header is
verified to not have been modified. A single exception is made for DoomConfig.cfg. Files
can still be written out in restricted mode, so screenshots and demos are allowed.
Restricted mode can be tested by setting "+set fs_restrict 1" on the command line, even
if there is a valid product.txt under the basepath or cdpath.

If the "fs_copyfiles" cvar is set to 1, then every time a file is sourced from the cd
path, it will be copied over to the save path. This is a development aid to help build
test releases and to copy working sets of files.

If the "fs_copyfiles" cvar is set to 2, any file found in fs_cdpath that is newer than
it's fs_savepath version will be copied to fs_savepath (in addition to the fs_copyfiles 1
behaviour).

If the "fs_copyfiles" cvar is set to 3, files from both basepath and cdpath will be copied
over to the save path. This is useful when copying working sets of files mainly from base
path with an additional cd path (which can be a slower network drive for instance).

If the "fs_copyfiles" cvar is set to 4, files that exist in the cd path but NOT the base path
will be copied to the save path

NOTE: fs_copyfiles and case sensitivity. On fs_caseSensitiveOS 0 filesystems ( win32 ), the
copied files may change casing when copied over.

The relative path "sound/newstuff/test.wav" would be searched for in the following places:

for save path, base path, cd path:
    for current game, base game:
        search directory
        search zip files

downloaded files, to be written to save path + current game's directory

The filesystem can be safely shutdown and reinitialized with different
basedir / cddir / game combinations, but all other subsystems that rely on it
(sound, video) must also be forced to restart.


"fs_caseSensitiveOS":
This cvar is set on operating systems that use case sensitive filesystems (Linux and OSX)
It is a common situation to have the media reference filenames, whereas the file on disc
only matches in a case-insensitive way. When "fs_caseSensitiveOS" is set, the filesystem
will always do a case insensitive search.
Directory segments are also resolved case-insensitively when they already exist on disk.
When "com_developer" is 1, the filesystem will warn when it catches bad directory
situations (regardless of the "fs_caseSensitiveOS" setting). Missing directories are
left unchanged so write paths can still create new content and failed reads report the
unresolved segment in debug output instead of relying on lowercase assumptions.

"additional mod path search":
fs_game_base can be used to set an additional search path
in search order, fs_game, fs_game_base, BASEGAME
for instance to base a mod of openQ4 + D3XP assets, fs_game mymod, fs_game_base baseoq4

=============================================================================
*/

@implementation idFileList

-(instancetype)initWithBasePath:(NSString *)basePath list:(NSArray *)array {
    self = [super init];
    if (self) {
        self.basePath = basePath;
        self.list = array;
    }
    return self;
}

-(int)numFiles {
    return (int)self.list.count;
}

-(NSString *)fileByIndex:(int)index {
    if (index < 0 || index >= self.list.count) {
        return @"";
    }
    return [self.list objectAtIndex:index];
}

@end

// define to fix special-cases for GetPackStatus so that files that shipped in
// the wrong place for openQ4 don't break pure servers.
#define DOOM3_PURE_SPECIAL_CASES

@interface UDExclusionManager : NSObject

+ (instancetype)sharedManager;

- (BOOL)excludeName:(NSString *)name length:(int)l;

@end

typedef struct pureExclusion_s pureExclusion_t;

typedef BOOL (*pureExclusionFunc_t)(const struct pureExclusion_s *excl, int l, NSString *name);

struct pureExclusion_s {
    int                    nameLen;
    int                    extLen;
    NSString               *name;
    NSString               *ext;
    pureExclusionFunc_t    func;
};

BOOL excludeExtension(const pureExclusion_t *excl, int l, NSString *name) {
    if (l > excl->extLen &&
        [excl->ext compare:[name pathExtension] options:NSCaseInsensitiveSearch range:NSMakeRange(1, excl->extLen - 1)] == NSOrderedSame) {
        return YES;
    }
    return NO;
}

BOOL excludePathPrefixAndExtension(const pureExclusion_t *excl, int l, NSString *name) {
    NSString *prefix = excl->name;
    NSString *extension = excl->ext;
    if (l > excl->nameLen &&
        [extension compare:[name pathExtension] options:NSCaseInsensitiveSearch range:NSMakeRange(1, excl->extLen - 1)] == NSOrderedSame &&
        [name rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound) {
        return YES;
    }
    return NO;
}

BOOL excludeFullName(const pureExclusion_t *excl, int l, NSString *name) {
    if (l == excl->nameLen && [name caseInsensitiveCompare:excl->name] == NSOrderedSame) {
        return YES;
    }
    return NO;
}

static struct pureExclusion_s pureExclusions[] = {
    { 0,    0,    nil,                                              @"/",        excludeExtension },
    { 0,    0,    nil,                                              @"\\",       excludeExtension },
    { 0,    0,    nil,                                              @".pda",     excludeExtension },
    { 0,    0,    nil,                                              @".gui",     excludeExtension },
    { 0,    0,    nil,                                              @".pd",      excludeExtension },
    { 0,    0,    nil,                                              @".lang",    excludeExtension },
    { 0,    0,    @"sound/VO",                                      @".ogg",     excludePathPrefixAndExtension },
    { 0,    0,    @"sound/VO",                                      @".wav",     excludePathPrefixAndExtension },
#if    defined DOOM3_PURE_SPECIAL_CASES
    // add any special-case files or paths for pure servers here
    { 0,    0,    @"sound/ed/marscity/vo_intro_cutscene.ogg",       nil,         excludeFullName },
    { 0,    0,    @"sound/weapons/soulcube/energize_01.ogg",        nil,         excludeFullName },
    { 0,    0,    @"sound/xian/creepy/vocal_fx",                    @".ogg",     excludePathPrefixAndExtension },
    { 0,    0,    @"sound/xian/creepy/vocal_fx",                    @".wav",     excludePathPrefixAndExtension },
    { 0,    0,    @"sound/feedback",                                @".ogg",     excludePathPrefixAndExtension },
    { 0,    0,    @"sound/feedback",                                @".wav",     excludePathPrefixAndExtension },
    { 0,    0,    @"guis/assets/mainmenu/chnote.tga",               nil,         excludeFullName },
    { 0,    0,    @"sound/levels/alphalabs2/uac_better_place.ogg",  nil,         excludeFullName },
    { 0,    0,    @"textures/bigchars.tga",                         nil,         excludeFullName },
    { 0,    0,    @"dds/textures/bigchars.dds",                     nil,         excludeFullName },
    { 0,    0,    @"fonts",                                         @".tga",     excludePathPrefixAndExtension },
    { 0,    0,    @"dds/fonts",                                     @".dds",     excludePathPrefixAndExtension },
    { 0,    0,    @"default.cfg",                                   nil,         excludeFullName },
    // russian zpak001.pk4
    { 0,    0,    @"fonts",                                         @".dat",     excludePathPrefixAndExtension },
    { 0,    0,    @"guis/temp.guied",                               nil,         excludeFullName },
#endif
    { 0,    0,    nil,                                              nil,         nil }
};

@implementation UDExclusionManager

+(instancetype)sharedManager {
    static UDExclusionManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    // Guarantees thread-safe, one-time initialization
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Calculate all string lengths exactly once upon singleton creation
        for (int i = 0; pureExclusions[i].func != NULL; i++) {
            if (pureExclusions[i].name) {
                pureExclusions[i].nameLen = (int)pureExclusions[i].name.length;
            }
            if (pureExclusions[i].ext) {
                pureExclusions[i].extLen = (int)pureExclusions[i].ext.length;
            }
        }
    }
    return self;
}

- (BOOL)excludeName:(NSString *)name length:(int)l {
    // Iterate through the static C array
    for (int i = 0; pureExclusions[i].func != nil; i++) {
        // Execute the assigned function pointer
        if (pureExclusions[i].func(&pureExclusions[i], l, name)) {
            return YES;
        }
    }
    return NO;
}

@end

@interface UDOfficialPk4Manager : NSObject

+ (instancetype)sharedManager;

- (BOOL)isIgnoredOfficialGameBinaryPk4:(const char *)pakName;
- (BOOL)isOfficialPk4:(const char *)pakName;

@end

@implementation UDOfficialPk4Manager

typedef struct {
    NSString *      name;
    unsigned int    checksum;
    BOOL            required;
    BOOL            pureBase;
} officialPk4Info_t;

static officialPk4Info_t officialPk4s[] = {
    // core retail media baseline for Quake 4
    { @"pak001.pk4",                0xf2cbc998,    YES,    YES },
    { @"pak002.pk4",                0x7f8d80d1,    YES,    YES },
    { @"pak003.pk4",                0x1b57b207,    YES,    YES },
    { @"pak004.pk4",                0x385aa578,    YES,    YES },
    { @"pak005.pk4",                0x60d50a1d,    YES,    YES },
    { @"pak006.pk4",                0x9099ed11,    YES,    YES },
    { @"pak007.pk4",                0xaf301fff,    YES,    YES },
    { @"pak008.pk4",                0x4ac6f6d9,    YES,    YES },
    { @"pak009.pk4",                0x36030c7d,    YES,    YES },
    { @"pak010.pk4",                0x4b80fbda,    YES,    YES },
    { @"pak011.pk4",                0x8acf4cfa,    YES,    YES },
    { @"pak012.pk4",                0xbe4120b0,    YES,    YES },
    { @"pak013.pk4",                0x6ad67f40,    YES,    YES },
    { @"pak014.pk4",                0xee51cd59,    YES,    YES },
    { @"pak015.pk4",                0xf5bf4e0c,    YES,    YES },
    { @"pak016.pk4",                0x2196f58c,    YES,    YES },
    { @"pak017.pk4",                0x91118a35,    YES,    YES },
    { @"pak018.pk4",                0x98a14f03,    YES,    YES },
    { @"pak019.pk4",                0xbc82ac79,    YES,    YES },
    { @"pak020.pk4",                0xce74cda5,    YES,    YES },
    { @"pak021.pk4",                0x2ba6e70c,    YES,    YES },
    { @"pak022.pk4",                0x4e390eec,    YES,    YES },

    // official patch/menu media, but not required by openQ4 startup
    { @"pak023.pk4",                0x7c1fd3a5,    NO,    YES },
    { @"pak024.pk4",                0x5546d551,    NO,    YES },
    { @"pak025.pk4",                0xcaeec1fd,    NO,    YES },

    // official but optional
    { @"q4cmp_pak001.pk4",        0xd0813943,    NO,    NO },
    { @"zpak_english.pk4",        0x5868f530,    NO,    NO },
    { @"zpak_english_01.pk4",    0xd9f04b8b,    NO,    NO },
    { @"zpak_english_02.pk4",    0x9dbd91fd,    NO,    NO },
    { @"zpak_english_03.pk4",    0x02eb6ad8,    NO,    NO },
    { @"zpak_english_04.pk4",    0xd3fefaa1,    NO,    NO },
    { @"zpak_english_05.pk4",    0x8596af60,    NO,    NO },
    { @"zpak_spanish.pk4",        0xb706e2b8,    NO,    NO },

    { nil,                        0,            NO,    NO }
};

+ (instancetype)sharedManager {
    static UDOfficialPk4Manager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

- (BOOL)isIgnoredOfficialGameBinaryPk4:(const char *)pakName {
    if (!pakName || !pakName[0]) {
        return NO;
    }

    NSString *name = [[NSString stringWithUTF8String:pakName] lastPathComponent];
    if ([name caseInsensitiveCompare:@"game000.pk4"] == NSOrderedSame ||
        [name caseInsensitiveCompare:@"game100.pk4"] == NSOrderedSame ||
        [name caseInsensitiveCompare:@"game200.pk4"] == NSOrderedSame ||
        [name caseInsensitiveCompare:@"game300.pk4"] == NSOrderedSame) {
        return YES;
    }

    return ([name rangeOfString:@"gamex" options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound &&
            [[name pathExtension] caseInsensitiveCompare:@"pk4"] == NSOrderedSame);
}

- (BOOL)isOfficialPk4:(const char *)pakName {
    if (!pakName || !pakName[0]) {
        return NO;
    }

    NSString *pakNameString = [NSString stringWithUTF8String:pakName];

    for (int i = 0; officialPk4s[i].name != nil; i++) {
        if ([officialPk4s[i].name caseInsensitiveCompare:pakNameString] == NSOrderedSame) {
            return officialPk4s[i].pureBase ? YES : NO;
        }
    }
    
    return NO;
}

@end

typedef struct {
    int        number;
    int        digitCount;
} numberedPakName_t;

static BOOL FS_ParseNumberedPakName(NSString *pakName, numberedPakName_t *numberedPak) {
    NSString      *baseName;
    int           number;
    int           digitCount;
    NSUInteger    index;

    numberedPak->number = 0;
    numberedPak->digitCount = 0;

    if (!pakName || pakName.length == 0) {
        return NO;
    }

    baseName = [pakName lastPathComponent];
    if (baseName.length < 4) {
        return NO;
    }

    if ([[baseName substringToIndex:3] caseInsensitiveCompare:@"pak"] != NSOrderedSame) {
        return NO;
    }

    number = 0;
    digitCount = 0;
    index = 3;
    while (index < baseName.length) {
        unichar c = [baseName characterAtIndex:index];
        if (c < '0' || c > '9') {
            break;
        }
        if (number < 1000000) {
            number = (number * 10) + (int)(c - '0');
        }
        digitCount++;
        index++;
    }

    if (digitCount == 0) {
        return NO;
    }

    if ([[baseName substringFromIndex:index] caseInsensitiveCompare:@".pk4"] != NSOrderedSame) {
        return NO;
    }

    numberedPak->number = number;
    numberedPak->digitCount = digitCount;
    return YES;
}

static NSInteger FS_ComparePk4LoadOrder(NSString *aName, NSString *bName, void *ctx) {
    numberedPakName_t    aPak;
    numberedPakName_t    bPak;
    const BOOL           aNumberedPak = FS_ParseNumberedPakName(aName, &aPak);
    const BOOL           bNumberedPak = FS_ParseNumberedPakName(bName, &bPak);

    if (aNumberedPak && bNumberedPak) {
        // addGameDirectory inserts each later-loaded archive closer to the head of
        // the search path. Process wider numbered forms first so pak1.pk4 wins over
        // pak01.pk4/pak001.pk4 when both naming schemes are present.
        if (aPak.digitCount != bPak.digitCount) {
            return bPak.digitCount - aPak.digitCount;
        }
        if (aPak.number != bPak.number) {
            return aPak.number - bPak.number;
        }
    }

    if (aNumberedPak != bNumberedPak) {
        NSString *aKey = aNumberedPak ? @"pak" : aName;
        NSString *bKey = bNumberedPak ? @"pak" : bName;
        NSComparisonResult cmp = [aKey caseInsensitiveCompare:bKey];
        if (cmp != NSOrderedSame) {
            return cmp == NSOrderedAscending ? -1 : 1;
        }
        return aNumberedPak ? -1 : 1;
    }

    return [aName caseInsensitiveCompare:bName];
}

static void FS_SortPk4FilesForLoadOrder(NSArray<NSString *> *pakfiles) {
    [pakfiles sortedArrayUsingFunction:FS_ComparePk4LoadOrder context:NULL];
}

#define MAX_ZIPPED_FILE_NAME    2048
#define FILE_HASH_SIZE            1024

typedef enum {
    BINARY_UNKNOWN = 0,
    BINARY_YES,
    BINARY_NO
} binaryStatus_t;

typedef enum {
    PURE_UNKNOWN = 0,    // need to run the pak through GetPackStatus
    PURE_NEUTRAL,    // neutral regarding pureness. gets in the pure list if referenced
    PURE_ALWAYS,    // always referenced - for pak* named files, unless NEVER
    PURE_NEVER        // VO paks. may be referenced, won't be in the pure lists
} pureStatus_t;

@class UDPackFileEntry;
@class UDPack;
@class UDDirectory;
@class UDSearchPath;

typedef UDPackFileEntry fileInPack_t;
typedef UDPack pack_t;
typedef UDDirectory directory_t;
typedef UDSearchPath searchpath_t;

@interface UDPackFileEntry : NSObject {
@public
    NSMutableString     *name;                        // name of the file
    unsigned long       pos;                         // file info position in zip
    fileInPack_t        *next;                       // next file in the hash
}

- (instancetype)initWithName:(NSString *)name;

@end

@interface UDPack : NSObject {
@public
    NSMutableString     *pakFilename;                // c:\doom\base\pak0.pk4
    unzFile             handle;
    int                 checksum;
    int                 numfiles;
    int                 length;
    bool                referenced;
    binaryStatus_t      binary;
    pureStatus_t        pureStatus;
    BOOL                isNew;                        // for downloaded paks
    fileInPack_t        *__unsafe_unretained hashTable[FILE_HASH_SIZE];
    NSMutableArray<fileInPack_t *> *buildBuffer;
}

- (instancetype)initWithPakFilename:(NSString *)pakFilename;

@end

@interface UDDirectory : NSObject {
@public
    NSMutableString     *path;                        // c:\doom
    NSMutableString     *gamedir;                    // base
}

- (instancetype)initWithPath:(NSString *)path gameDir:(NSString *)gameDir;

@end

@interface UDSearchPath : NSObject {
@public
    pack_t              *pack;                        // only one of pack / dir will be non NULL
    directory_t         *dir;
    searchpath_t        *next;
}

@end

@implementation UDPackFileEntry

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (!self) {
        return nil;
    }

    self->name = [name mutableCopy];
    if (self->name.length) {
        CFStringLowercase((CFMutableStringRef)self->name, NULL);
        [self->name replaceOccurrencesOfString:@"\\" withString:@"/" options:0 range:NSMakeRange(0, name.length)];
    }
    pos = 0;
    next = nil;
    return self;
}

@end

@implementation UDPack

- (instancetype)initWithPakFilename:(NSString *)pakFilename {
    self = [super init];
    if (!self) {
        return nil;
    }

    self->pakFilename = [pakFilename mutableCopy];
    handle = NULL;
    checksum = 0;
    numfiles = 0;
    length = 0;
    referenced = NO;
    binary = BINARY_UNKNOWN;
    pureStatus = PURE_UNKNOWN;
    isNew = NO;
    buildBuffer = [[NSMutableArray alloc] init];
    for (int i = 0; i < FILE_HASH_SIZE; i++) {
        hashTable[i] = nil;
    }
    return self;
}

@end

@implementation UDDirectory

- (instancetype)initWithPath:(NSString *)path gameDir:(NSString *)gameDir {
    self = [super init];
    if (!self) {
        return nil;
    }

    self->path = [path mutableCopy];
    self->gamedir = [gameDir mutableCopy];

    return self;
}


@end

@implementation UDSearchPath
@end

// search flags when opening a file
#define FSFLAG_SEARCH_DIRS        ( 1 << 0 )
#define FSFLAG_SEARCH_PAKS        ( 1 << 1 )
#define FSFLAG_PURE_NOREF        ( 1 << 2 )
#define FSFLAG_BINARY_ONLY        ( 1 << 3 )

// 3 search path (fs_savepath fs_basepath fs_cdpath)
// + .jpg and .tga
#define MAX_CACHED_DIRS 6

// how many OSes to handle game paks for ( we don't have to know them precisely )
#define MAX_GAME_OS    6
#define BINARY_CONFIG "binary.conf"

@interface idDEntry : NSMutableArray

@property (strong, nonatomic) NSString *directory;
@property (strong, nonatomic) NSString *extension;
@property (strong, nonatomic) NSMutableArray<NSString *> *files;

-(instancetype)initWithDirectory:(NSString *)directory extension:(NSString *)extension list:(NSArray<NSString *> *)list;

-(BOOL)matchesDirectory:(NSString *)directory withExtension:(NSString *)extension;

-(void)clear;

@end

@implementation idDEntry

-(instancetype)initWithDirectory:(NSString *)directory extension:(NSString *)extension list:(NSArray<NSString *> *)list {
    self = [super init];
    if (self) {
        self.directory = directory;
        self.extension = extension;
        self.files = [list mutableCopy];
    }
    return self;
}

-(BOOL)matchesDirectory:(NSString *)directory withExtension:(NSString *)extension {
    if ([self.directory caseInsensitiveCompare:directory] == NSOrderedSame && [self.extension caseInsensitiveCompare:extension] == NSOrderedSame) {
        return YES;
    }

    return NO;
}

-(void)clear {
    self.directory = nil;
    self.extension = nil;
    [self.files removeAllObjects];
}

@end

typedef enum modManifestStatus_s {
    MOD_MANIFEST_MISSING,
    MOD_MANIFEST_VALID,
    MOD_MANIFEST_INVALID
} modManifestStatus_t;

static void UDFileSystemAssignError(NSError **error, NSInteger code, NSString *format, ...) {
    if (!error) {
        return;
    }

    va_list args;
    va_start(args, format);
    NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                 code:code
                             userInfo:@{ NSLocalizedDescriptionKey: description }];
}

@interface NSMutableString (UDIdStrCompat)

- (void)ud_stripTrailingCharacter:(unichar)character;
- (void)ud_appendPathComponent:(NSString *)component;
- (void)ud_stripLastPathComponentCompat;
- (void)ud_keepLastPathComponentCompat;
- (void)ud_replaceSeparatorsWithString:(NSString *)separator;

@end

@implementation NSMutableString (UDIdStrCompat)

- (void)ud_stripTrailingCharacter:(unichar)character {
    while (self.length > 0 && [self characterAtIndex:self.length - 1] == character) {
        [self deleteCharactersInRange:NSMakeRange(self.length - 1, 1)];
    }
}

- (void)ud_appendPathComponent:(NSString *)component {
    if (component.length == 0) {
        return;
    }

    NSUInteger start = 0;
    while (start < component.length) {
        unichar character = [component characterAtIndex:start];
        if (character != '/' && character != '\\') {
            break;
        }
        start++;
    }

    if (self.length > 0) {
        unichar lastCharacter = [self characterAtIndex:self.length - 1];
        if (lastCharacter != '/' && lastCharacter != '\\') {
            [self appendString:@"/"];
        }
    }

    if (start < component.length) {
        [self appendString:[component substringFromIndex:start]];
    }
}

- (void)ud_stripLastPathComponentCompat {
    NSRange range = [self rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"] options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        [self setString:@""];
        return;
    }
    [self deleteCharactersInRange:NSMakeRange(range.location, self.length - range.location)];
}

- (void)ud_keepLastPathComponentCompat {
    NSRange range = [self rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"] options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        return;
    }
    [self deleteCharactersInRange:NSMakeRange(0, NSMaxRange(range))];
}

- (void)ud_replaceSeparatorsWithString:(NSString *)separator {
    [self replaceOccurrencesOfString:@"\\" withString:separator options:0 range:NSMakeRange(0, self.length)];
    if (![separator isEqualToString:@"/"]) {
        [self replaceOccurrencesOfString:@"/" withString:separator options:0 range:NSMakeRange(0, self.length)];
    }
}

@end

static int ud_comparePath(NSString *s1, NSString *s2) {
    // 1. Exact same object pointer in memory
    if (s1 == s2) return 0;
    
    // Safety fallback
    if (!s1) return -1;
    if (!s2) return 1;
    
    NSUInteger len1 = s1.length;
    NSUInteger len2 = s2.length;
    NSUInteger i1 = 0;
    NSUInteger i2 = 0;
    
    while (YES) {
        // Read next character, or 0 (NULL) if at end of string
        unichar c1 = (i1 < len1) ? [s1 characterAtIndex:i1++] : 0;
        unichar c2 = (i2 < len2) ? [s2 characterAtIndex:i2++] : 0;
        
        int d = c1 - c2;
        
        if (d != 0) {
            // Normalize c1 (lowercase and path separator)
            if (c1 >= 'A' && c1 <= 'Z') c1 += ('a' - 'A');
            if (c1 == '\\') c1 = '/';
            
            // Normalize c2 (lowercase and path separator)
            if (c2 >= 'A' && c2 <= 'Z') c2 += ('a' - 'A');
            if (c2 == '\\') c2 = '/';
            
            d = c1 - c2;
            
            // If they STILL differ after normalization, determine sort order
            if (d != 0) {
                // Fast-forward s1 to make sure folders come first
                while (c1 != 0 && c1 != '/' && c1 != '\\') {
                    c1 = (i1 < len1) ? [s1 characterAtIndex:i1++] : 0;
                }
                
                // Fast-forward s2
                while (c2 != 0 && c2 != '/' && c2 != '\\') {
                    c2 = (i2 < len2) ? [s2 characterAtIndex:i2++] : 0;
                }
                
                if (c1 != 0 && c2 == 0) {
                    return -1; // s1 is a folder, s2 is a file. s1 comes first.
                } else if (c1 == 0 && c2 != 0) {
                    return 1;  // s2 is a folder, s1 is a file. s2 comes first.
                }
                
                // Same folder depth, so use the regular alphabetical compare result
                return (d >= 0) ? 1 : -1;
            }
        }
        
        // If c1 reached 0, both reached 0 because d == 0
        if (c1 == 0) {
            break;
        }
    }
    
    return 0; // Strings are equal
}

static BOOL UDStringHasUppercase(NSString *value) {
    NSCharacterSet *uppercaseSet = [NSCharacterSet uppercaseLetterCharacterSet];
    return [value rangeOfCharacterFromSet:uppercaseSet].location != NSNotFound;
}

@implementation idFileSystem {
    searchpath_t *            searchPaths;
    int                       readCount;            // total bytes read
    int                       loadCount;            // total files read
    int                       loadStack;            // total files in memory
    NSMutableString           *gameFolder;            // this will be a single name without separators
    
    __weak UDWorkspace *     _workspace;

    //idDict                    mapDict;            // for GetMapDecl
/*
    friend dword             BackgroundDownloadThread( void *parms );
    backgroundDownload_t *    backgroundDownloads;
    backgroundDownload_t    defaultBackgroundDownload;
    xthreadInfo                backgroundThread;

    idList<pack_t *>            serverPaks;
 */
    BOOL                        loadedFileFromDir;        // set to YES once a file was loaded from a directory - can't switch to pure anymore
    /*
    idList<int>                restartChecksums;        // used during a restart to set things in right order
    int                        restartGamePakChecksum;
    int                        gameDLLChecksum;        // the checksum of the last loaded game DLL
    int                        gamePakChecksum;        // the checksum of the pak holding the loaded game DLL
     */
    BOOL                    isFileLoadingAllowed;
    /*
    idStr                    currentAssetLog;
    idStr                    currentAssetLogUnfiltered;
    idStrList                assetLog;

    int                        gamePakForOS[ MAX_GAME_OS ];*/

    idDEntry*                  dir_cache[MAX_CACHED_DIRS]; // fifo
    int                        dir_cache_index;
    int                        dir_cache_count;
}

-(NSString *)cvarString:(NSString *)name {
    if ([name isEqualToString:@"fs_basepath"]) {
        return self.fs_basepath;
    } else if ([name isEqualToString:@"fs_homepath"]) {
        return self.fs_homepath;
    } else if ([name isEqualToString:@"fs_savepath"]) {
        return self.fs_savepath;
    } else if ([name isEqualToString:@"fs_cdpath"]) {
        return self.fs_cdpath;
    } else {
        return @"";
    }
}

-(void)resetReadCount { self->readCount = 0; }
-(void)addToReadCount:(int)c {
    if (c <= 0) {
        return;
    }

    self->readCount += c;
}
-(int)readCount {
    return self->readCount;
}

static inline char toLower(char c) {
    if (c <= 'Z' && c >= 'A') {
        return (c + ('a' - 'A'));
    }
    return c;
}

- (long)hashFileName:(NSString *)fname {
    long hash = 0;
    
    // Safety check for nil strings
    if (!fname || fname.length == 0) {
        return 0;
    }
    
    NSUInteger len = fname.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar letter = [fname characterAtIndex:i];
        
        // Custom toLower: convert ASCII uppercase to lowercase
        if (letter >= 'A' && letter <= 'Z') {
            letter += ('a' - 'A');
        }
        
        if (letter == '.') {
            break;                // don't include extension
        }
        
        if (letter == '\\') {
            letter = '/';         // damn path names
        }
        
        hash += (long)(letter) * (i + 119);
    }
    
    hash &= (FILE_HASH_SIZE - 1);
    return hash;
}

- (BOOL)filenameCompare:(NSString *)s1 to:(NSString *)s2 {
    // 1. Cocoa optimization: If they are the exact same object in memory, they are equal.
    if (s1 == s2) {
        return NO;
    }
    
    // Safeguard against nil strings
    if (!s1 || !s2) {
        return YES; // One is nil, the other isn't (or both are nil, but let's assume not equal for safety)
    }
    
    // 2. Cocoa optimization: Normalization doesn't change character count.
    // If lengths differ, they instantly cannot be equal. (C-strings can't do this without a slow strlen() pass).
    NSUInteger len = s1.length;
    if (len != s2.length) {
        return YES;
    }
    
    // 3. Character-by-character comparison
    for (NSUInteger i = 0; i < len; i++) {
        unichar c1 = [s1 characterAtIndex:i];
        unichar c2 = [s2 characterAtIndex:i];

        // Uppercase conversion for ASCII a-z
        if (c1 >= 'a' && c1 <= 'z') {
            c1 -= ('a' - 'A');
        }
        if (c2 >= 'a' && c2 <= 'z') {
            c2 -= ('a' - 'A');
        }

        // Path separator normalization
        if (c1 == '\\' || c1 == ':') {
            c1 = '/';
        }
        if (c2 == '\\' || c2 == ':') {
            c2 = '/';
        }
        
        if (c1 != c2) {
            return YES; // strings not equal
        }
    }
    
    return NO; // strings are equal
}

-(FILE *)openOSFile:(NSString *)fileName mode:(const char *)mode caseSensitiveName:(NSMutableString *)caseSensitiveName {
    int i;
    FILE *fp;
    NSMutableArray<NSString *> *list;

    /*
#ifndef __MWERKS__
#ifndef WIN32
    // some systems will let you fopen a directory
    struct stat buf;
    if (stat(fileName, &buf) != -1 && !S_ISREG(buf.st_mode)) {
        return NULL;
    }
#endif
#endif
     */

    fp = fopen([fileName UTF8String], mode);
    if (!fp && self.fs_caseSensitiveOS) {
        {
            NSMutableString *resolvedFileName = [[NSMutableString alloc] init];

            if ([self resolveCaseInsensitiveOSPath:fileName resolvedPath:resolvedFileName finalSegmentIsFile:YES]) {
                fp = fopen([resolvedFileName UTF8String], mode);
                if (fp) {
                    if (caseSensitiveName) {
                        [caseSensitiveName setString:resolvedFileName];
                        [caseSensitiveName ud_keepLastPathComponentCompat];
                    }
                    if (self.fs_debug) {
                        NSLog(@"openFileRead: changed %@ to %@", fileName, resolvedFileName);
                    }
                    return fp;
                } else {
                    NSLog(@"WARN: openFileRead: fs_caseSensitiveOS 1 resolved %@ to %@ but could not open it", fileName, resolvedFileName);
                }
            }
        }

        NSMutableString *fpath = [fileName mutableCopy];
        [fpath ud_stripLastPathComponentCompat];
        [fpath ud_stripTrailingCharacter:PATHSEPERATOR_CHAR];

        {
            NSMutableString *resolvedPath = [[NSMutableString alloc] init];
            if ([self resolveCaseInsensitiveOSPath:fpath resolvedPath:resolvedPath finalSegmentIsFile:NO]) {
                [fpath setString:resolvedPath];
            }
        }
        
        list = [[NSMutableArray alloc] init];

        if ([self listOSFiles:fpath extension:nil list:list] == -1) {
            return NULL;
        }

        for (i = 0; i < [list count]; i++) {
            NSMutableString *entry = [[NSMutableString alloc] init];
            [entry appendFormat:@"%c", PATHSEPERATOR_CHAR];
            [entry appendString:[list objectAtIndex:i]];

            NSString *requestedFileName = fileName;
            if ([entry caseInsensitiveCompare:requestedFileName] == NSOrderedSame) {
                fp = fopen([entry UTF8String], mode);
                if (fp) {
                    if (caseSensitiveName) {
                        [caseSensitiveName setString:entry];
                        [caseSensitiveName ud_keepLastPathComponentCompat];
                    }
                    if (self.fs_debug) {
                        NSLog(@"openFileRead: changed %@ to %@", fileName, entry);
                    }
                    break;
                } else {
                    // not supposed to happen if ListOSFiles is doing it's job correctly
                    NSLog(@"WARN: openFileRead: fs_caseSensitiveOS 1 could not open %@", entry);
                }
            }
        }
    } else if ( caseSensitiveName ) {
        [caseSensitiveName setString:@""];
        [caseSensitiveName appendString:fileName];
        [caseSensitiveName ud_keepLastPathComponentCompat];
    }
    return fp;
}

-(FILE *)openOSFileCorrectName:(NSMutableString *)path mode:(const char *)mode {
    NSMutableString *caseName = [[NSMutableString alloc] init];

    FILE *f = [self openOSFile:path mode:mode caseSensitiveName:caseName];
    if (f) {
        [path ud_stripLastPathComponentCompat];
        [path ud_appendPathComponent:caseName];
    }

    return f;
}

static int directFileLength(FILE *o) {
    int        pos;
    int        end;

    pos = ftell(o);
    fseek(o, 0, SEEK_END);
    end = ftell(o);
    fseek(o, pos, SEEK_SET);

    return end;
}

- (BOOL)createOSPath:(NSString *)OSPath error:(NSError **)error {
    // make absolutely sure that it can't back up the path
    // FIXME: what about c: ?
    if (!OSPath || OSPath.length == 0) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"Filesystem createOSPath called with an empty OS path.");
        return NO;
    }

    // Security check to prevent directory traversal
    if ([OSPath rangeOfString:@".."].location != NSNotFound ||
        [OSPath rangeOfString:@"::"].location != NSNotFound) {
#ifdef _DEBUG
        // NSLog(@"refusing to create relative path \"%@\"", OSPath);
#endif
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidPath,
                                @"Refusing to create unsafe OS path '%@'.",
                                OSPath);
        return NO;
    }

    NSString *directoryPath = [OSPath stringByDeletingLastPathComponent];
    
    if (directoryPath.length == 0 || [directoryPath isEqualToString:OSPath]) {
        return YES;
    }

    NSError *directoryError = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&directoryError];
    if (!created) {
        if (error) {
            *error = directoryError;
        }
        return NO;
    }
    return YES;
}

-(BOOL)copyFileFrom:(NSString *)fromOSPath to:(NSString *)toOSPath error:(NSError **)error {
    FILE            *f;
    int             len;
    unsigned char   *buf;

    NSLog(@"copy %@ to %@", fromOSPath, toOSPath);
    f = [self openOSFile:fromOSPath mode:"rb" caseSensitiveName:nil];
    if (!f) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeReadFailed,
                                @"Failed to open source file '%s' for copy.",
                                fromOSPath);
        return NO;
    }
    fseek(f, 0, SEEK_END);
    len = ftell(f);
    fseek(f, 0, SEEK_SET);

    buf = (unsigned char *)malloc( len );
    if (fread(buf, 1, len, f) != (unsigned int)len) {
        fclose(f);
        free(buf);
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeReadFailed,
                                @"Short read while copying '%s'.",
                                fromOSPath);
        return NO;
    }
    fclose(f);

    if (![self createOSPath:toOSPath error:error]) {
        free(buf);
        return NO;
    }
    f = [self openOSFile:toOSPath mode:"wb" caseSensitiveName:nil];
    if (!f) {
        free(buf);
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeWriteFailed,
                                @"Failed to open destination file '%s' for copy.",
                                toOSPath);
        return NO;
    }
    if (fwrite(buf, 1, len, f) != (unsigned int)len) {
        fclose(f);
        free(buf);
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeWriteFailed,
                                @"Short write while copying to '%s'.",
                                toOSPath);
        return NO;
    }
    fclose(f);
    free(buf);
    return YES;
}

-(BOOL)copyFile:(idFile *)src to:(NSString *)toOSPath error:(NSError **)error {
    FILE            *f;
    int             len;
    unsigned char    *buf;

    NSLog(@"copy %@ to %@", [src name], toOSPath);
    [src seek:0 origin:FS_SEEK_END];
    len = [src tell];
    [src seek:0 origin:FS_SEEK_SET];

    buf = (unsigned char *)malloc(len);
    NSError *readError = nil;
    if ([src read:buf length:len error:&readError] != len) {
        free(buf);
        if (readError && error) {
            *error = readError;
        } else {
            UDFileSystemAssignError(error,
                                    UDFileSystemPortErrorCodeReadFailed,
                                    @"Short read while copying file '%@'.",
                                    [src name]);
        }
        return NO;
    }

    if (![self createOSPath:toOSPath error:error]) {
        free(buf);
        return NO;
    }
    f = [self openOSFile:toOSPath mode:"wb" caseSensitiveName:nil];
    if (!f) {
        free(buf);
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeWriteFailed,
                                @"Failed to open destination file '%s' for copy.",
                                toOSPath);
        return NO;
    }
    if (fwrite(buf, 1, len, f) != (unsigned int)len) {
        fclose(f);
        free(buf);
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeWriteFailed,
                                @"Short write while copying to '%s'.",
                                toOSPath);
        return NO;
    }
    fclose(f);
    free(buf);
    return YES;
}

-(BOOL)findCaseInsensitiveOSPathEntry:(NSString *)directory segment:(NSString *)segment directoryOnly:(BOOL)directoryOnly resolvedSegment:(NSMutableString *)resolvedSegment {
    NSMutableArray *entries;
    NSString *listDirectory = directory;
    NSString *extension = directoryOnly ? @"/" : @"";

    if (!listDirectory || !listDirectory.length) {
        listDirectory = @".";
    }

    if (!segment || segment.length == 0) {
        return NO;
    }
    
    entries = [[NSMutableArray alloc] init];

    if (Sys_ListFiles(listDirectory, extension, entries) == -1) {
        return NO;
    }

    for ( int i = 0; i < [entries count]; i++ ) {
        NSString *str = [entries objectAtIndex:i];

        if ([str compare:segment options:NSLiteralSearch] == NSOrderedSame) {
            [resolvedSegment setString:str];
            return YES;
        }
    }

    return NO;
}

-(BOOL)resolveCaseInsensitiveOSPath:(NSString *)path resolvedPath:(NSMutableString *)resolvedPath finalSegmentIsFile:(BOOL)finalSegmentIsFile {
    if (!path || !path.length) {
        [resolvedPath setString:@""];
        return NO;
    }

    NSMutableString *normalized = [path mutableCopy];
    [normalized ud_replaceSeparatorsWithString:@"/"];
    while (normalized.length > 1 && [normalized characterAtIndex:normalized.length - 1] == '/') {
        [normalized deleteCharactersInRange:NSMakeRange(normalized.length - 1, 1)];
    }

    const BOOL absolutePath = ([normalized characterAtIndex:0] == '/') ? YES : NO;
    const int pathLength = (int)normalized.length;
    int index = absolutePath ? 1 : 0;
    BOOL changed = NO;

    [resolvedPath setString:@""];
    if (absolutePath == YES) {
        [resolvedPath appendString:@"/"];
    }

    while (index < pathLength) {
        while (index < pathLength && [normalized characterAtIndex:index] == '/') {
            index++;
        }
        if (index >= pathLength) {
            break;
        }

        const int segmentStart = index;
        while (index < pathLength && [normalized characterAtIndex:index] != '/') {
            index++;
        }

        NSString *segment = [normalized substringWithRange:NSMakeRange(segmentStart, index - segmentStart)];

        const BOOL hasMoreSegments = index < pathLength ? YES : NO;
        const BOOL directoryOnly = hasMoreSegments || !finalSegmentIsFile;
        NSString *parentDirectory = resolvedPath.length == 0 ? @"." : resolvedPath;
        NSMutableString *resolvedSegment = [[NSMutableString alloc] init];

        // Most mixed-case stock paths already use the exact on-disk spelling.  A
        // direct stat avoids enumerating every parent directory for every loose-
        // file probe (including probes for assets that ultimately live in PK4s).
#ifndef WIN32
        NSMutableString *exactPath = [resolvedPath mutableCopy];
        [exactPath ud_appendPathComponent:segment];
        const BOOL exactEntryMatches = Sys_ExactFileEntryMatches([exactPath UTF8String], directoryOnly);
#else
        // Windows has no S_ISDIR and does not need this optimization on its
        // case-insensitive filesystem. Preserve the existing enumeration fallback
        // if case recovery is explicitly enabled there.
        const BOOL exactEntryMatches = NO;
#endif
        if (exactEntryMatches) {
            [resolvedSegment setString:segment];
        } else if (![self findCaseInsensitiveOSPathEntry:parentDirectory segment:segment directoryOnly:directoryOnly resolvedSegment:resolvedSegment]) {
            if (self.fs_debug) {
                NSLog(@"resolveCaseInsensitiveOSPath:resolvedPath:finalSegmentIsFile: could not resolve %@ segment '%@' under '%@' while resolving '%@'",
                    directoryOnly ? @"directory" : @"file",
                    segment,
                    parentDirectory,
                    path);
            }
            [resolvedPath setString:normalized];
            [resolvedPath ud_replaceSeparatorsWithString:[NSString stringWithFormat:@"%c", PATHSEPERATOR_CHAR]];
            return NO;
        }

        if (![resolvedSegment isEqualToString:segment]) {
            changed = YES;
        }
        [resolvedPath ud_appendPathComponent:resolvedSegment];
    }

    [resolvedPath ud_replaceSeparatorsWithString:[NSString stringWithFormat:@"%c", PATHSEPERATOR_CHAR]];
    return changed;
}

- (NSString *)buildOSPath:(NSString *)base game:(NSString *)game relativePath:(NSString *)relativePath {
    // Safeguard against nil inputs
    if (!base) base = @"";
    if (!game) game = @"";
    if (!relativePath) relativePath = @"";

    BOOL hasUpperDirectory = NO;
    NSMutableString *strBase = [base mutableCopy];
    [strBase ud_stripTrailingCharacter:'/'];
    [strBase ud_stripTrailingCharacter:'\\'];

    NSMutableString *newPath = [strBase mutableCopy];
    [newPath ud_appendPathComponent:game];
    [newPath ud_appendPathComponent:relativePath];
    [newPath ud_replaceSeparatorsWithString:[NSString stringWithFormat:@"%c", PATHSEPERATOR_CHAR]];

    if (self.fs_caseSensitiveOS /*|| com_developer.GetBool()*/) { // todo: add com_developer
        // extract the directory path and warn about non-portable casing
        NSMutableString *testPath = [game mutableCopy];
        [testPath ud_appendPathComponent:relativePath];
        [testPath ud_stripLastPathComponentCompat];

        if (UDStringHasUppercase(testPath)) {
            hasUpperDirectory = YES;
            BOOL warn = YES;

            // On case-insensitive OSes, avoid warning for top-level non-game folders
            // that are only being probed during discovery (e.g. CrashReports, Docs).
            if (!self.fs_caseSensitiveOS) {
                if (relativePath.length == 0) {
                    if ([game caseInsensitiveCompare:gameFolder] != NSOrderedSame &&
                        [game caseInsensitiveCompare:self.fs_game] != NSOrderedSame &&
                        [game caseInsensitiveCompare:self.fs_game_base] != NSOrderedSame) {
                        warn = NO;
                    }
                }
            }

            if (warn) {
                // NSLog(@"Non-portable: path contains uppercase characters: %@", testPath);
            }
        }
    }

    if (self.fs_caseSensitiveOS && hasUpperDirectory) {
        NSUInteger relativeLength = relativePath.length;
        BOOL finalSegmentIsFile = NO;
        
        if (relativeLength > 0) {
            unichar lastChar = [relativePath characterAtIndex:relativeLength - 1];
            finalSegmentIsFile = (lastChar != '/' && lastChar != '\\');
        }
        
        NSMutableString *directoryPath = [newPath mutableCopy];
        NSMutableString *fileName = [[NSMutableString alloc] init];

        if (finalSegmentIsFile) {
            [fileName setString:[directoryPath lastPathComponent]];
            [directoryPath ud_stripLastPathComponentCompat];
        }

        while (directoryPath.length > 1 && [directoryPath characterAtIndex:directoryPath.length - 1] == PATHSEPERATOR_CHAR) {
            [directoryPath deleteCharactersInRange:NSMakeRange(directoryPath.length - 1, 1)];
        }

        NSMutableString *resolvedDirectory = [[NSMutableString alloc] init];
        
        if (directoryPath.length > 0 && [self resolveCaseInsensitiveOSPath:directoryPath resolvedPath:resolvedDirectory finalSegmentIsFile:NO]) {
            if (finalSegmentIsFile) {
                [resolvedDirectory ud_appendPathComponent:fileName];
            }
            [newPath setString:resolvedDirectory];
            [newPath ud_replaceSeparatorsWithString:[NSString stringWithFormat:@"%c", PATHSEPERATOR_CHAR]];
            // NSLog(@"Resolved case-sensitive path to %@", newPath);
        }
    }

    return newPath;
}

- (NSString *)osPathToRelativePath:(NSString *)OSPath {
    if (OSPath.length == 0) {
        return @"";
    }
    
    // ------------------------------------------------------------------------
    // Inline Helper Block to find an exact directory match in the path
    // ------------------------------------------------------------------------
    NSRange (^findDirectory)(NSString *) = ^NSRange(NSString *targetDir) {
        if (!targetDir || targetDir.length == 0) {
            return NSMakeRange(NSNotFound, 0);
        }
        
        NSUInteger pathLen = OSPath.length;
        NSRange searchRange = NSMakeRange(0, pathLen);
        
        while (searchRange.location < pathLen) {
            // Find the directory string
            NSRange matchRange = [OSPath rangeOfString:targetDir options:0 range:searchRange];
            
            if (matchRange.location == NSNotFound) {
                break; // Not found at all
            }
            
            // Check preceding character boundary
            BOOL validStart = NO;
            if (matchRange.location == 0) {
                validStart = YES;
            } else {
                unichar c1 = [OSPath characterAtIndex:matchRange.location - 1];
                if (c1 == '/' || c1 == '\\') validStart = YES;
            }
            
            // Check succeeding character boundary
            BOOL validEnd = NO;
            NSUInteger endLocation = NSMaxRange(matchRange);
            if (endLocation == pathLen) {
                validEnd = YES;
            } else {
                unichar c2 = [OSPath characterAtIndex:endLocation];
                if (c2 == '/' || c2 == '\\') validEnd = YES;
            }
            
            // If it's bounded correctly, we found our directory!
            if (validStart && validEnd) {
                return matchRange;
            }
            
            // Keep searching forward
            searchRange.location = matchRange.location + 1;
            searchRange.length = pathLen - searchRange.location;
        }
        
        return NSMakeRange(NSNotFound, 0);
    };

    // ------------------------------------------------------------------------
    // Main Search Logic
    // ------------------------------------------------------------------------
    BOOL ignoreWarning = NO;
    NSRange matchRange = findDirectory(self.gamedir);

    // If not in gamedir, try fs_game
    if (matchRange.location == NSNotFound) {
        matchRange = findDirectory(self.fs_game);
    }

    // If not in fs_game, try fs_game_base
    if (matchRange.location == NSNotFound) {
        matchRange = findDirectory(self.fs_game_base);
    }

    // ------------------------------------------------------------------------
    // Extraction Logic
    // ------------------------------------------------------------------------
    if (matchRange.location != NSNotFound) {
        NSUInteger endOfBase = NSMaxRange(matchRange);
        
        // If there's a slash after the matched directory name, skip it
        if (endOfBase < OSPath.length) {
            unichar nextChar = [OSPath characterAtIndex:endOfBase];
            if (nextChar == '/' || nextChar == '\\') {
                NSString *relativePath = [OSPath substringFromIndex:endOfBase + 1];
                
                if (self.fs_debug) {
                    // NSLog(@"idFileSystem::OSPathToRelativePath: %@ becomes %@", OSPath, relativePath);
                }
                
                return relativePath;
            }
        }
        
        // A qpath containing only the game-directory segment is valid and maps
        // to the VFS root; do not report it as an OS-path conversion failure.
        return @"";
    }

    // Failure to match
    if (!ignoreWarning) {
        // NSLog(@"idFileSystem::OSPathToRelativePath failed on %@", OSPath);
    }
    
    return @"";
}

-(NSString *)relativePathToOSPath:(NSString *)relativePath basePath:(NSString *)basePath {
    NSString *path = [self cvarString:basePath];
    if (!path || !path.length) {
        path = self.fs_savepath;
    }
    return [self buildOSPath:path
                        game:self->gameFolder
                relativePath:relativePath];
}

-(void)removeFile:(NSString *)relativePath basePath:(NSString *)basePath {
    //idStr OSPath;

    if ([basePath caseInsensitiveCompare:@"fs_savepath"] != 0) {
        NSString *path = [self cvarString:basePath];

        if (path.length) {
            NSString *OSPath = [self buildOSPath:path game:gameFolder relativePath:relativePath];
            remove([OSPath UTF8String]);
        }
        [self clearDirCache];
        return;
    }

    if (self.fs_cdpath.length) {
        NSString *str = [self buildOSPath:self.fs_cdpath
                                     game:self->gameFolder
                             relativePath:relativePath];
        remove([str UTF8String]);
    }

    if (self.fs_savepath.length && [self.fs_savepath caseInsensitiveCompare:self.fs_cdpath] != 0) {
        NSString *str = [self buildOSPath:self.fs_savepath
                                     game:self->gameFolder
                             relativePath:relativePath];
        remove([str UTF8String]);
    }

    [self clearDirCache];
}

-(int)removeExplicitFile:(NSString *)OSPath {
    const int result = remove([OSPath UTF8String]);
    [self clearDirCache];
    return result;
}

-(BOOL)fileIsInPAK:(NSString *)relativePath error:(NSError **)error {
    searchpath_t    *search;
    pack_t            *pak;
    fileInPack_t    *pakFile;
    long            hash;
    NSMutableString *rpath;

    if ( !searchPaths ) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return NO;
    }

    if ( !relativePath ) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"fileIsInPAK called with a nil relative path.");
        return NO;
    }
    
    rpath = [relativePath mutableCopy];

    // qpaths are not supposed to have a leading slash
    if (rpath.length > 0) {
        unichar leadingCharacter = [rpath characterAtIndex:0];
        if (leadingCharacter == '/' || leadingCharacter == '\\') {
            [rpath deleteCharactersInRange:NSMakeRange(0, 1)];
        }
    }

    // make absolutely sure that it can't back up the path.
    // The searchpaths do guarantee that something will always
    // be prepended, so we don't need to worry about "c:" or "//limbo"
    if ([rpath rangeOfString:@".."].location != NSNotFound || [rpath rangeOfString:@"::"].location != NSNotFound ) {
        return NO;
    }

    //
    // search through the path, one element at a time
    //

    hash = [self hashFileName:rpath];
    BOOL found = NO;

    for (search = searchPaths; search && !found; search = search->next) {
        // is the element a pak file?
        if (search->pack && search->pack->hashTable[hash]) {

            // look through all the pak file elements
            pak = search->pack;
            pakFile = pak->hashTable[hash];
            do {
                // case and separator insensitive comparisons
                if (![self filenameCompare:pakFile->name to:rpath]) {
                    found = YES;
                    break;
                }
                pakFile = pakFile->next;
            } while( pakFile != NULL );
        }
    }
    return found;
}

-(int)readFile:(NSString *)relativePath buffer:(void **)buffer timestamp:(unsigned int*)timestamp error:(NSError **)error {
    idFile *    f;
    unsigned char *        buf;
    int            len;
    static bool warnedEmptyReadPath = NO;

    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return -1;
    }

    if (timestamp) {
        *timestamp = FILE_NOT_FOUND_TIMESTAMP;
    }

    if (buffer) {
        *buffer = NULL;
    }

    if (!relativePath || !relativePath.length) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"readFile called with an empty relative path.");
        if (!warnedEmptyReadPath) {
            NSLog(@"WARN: readFile called with empty name; treating as missing file");
            warnedEmptyReadPath = YES;
        }
        return -1;
    }
    
    buf = NULL;    // quiet compiler warning

    // look for it in the filesystem or pack files
    f = [self openFileReadFlags:relativePath
                          flags:FSFLAG_SEARCH_DIRS | FSFLAG_SEARCH_PAKS
                          found:NULL
                      copyFiles:(buffer != NULL)
                        gameDir:nil
                          error:error];
    if (f == NULL) {
        if (buffer) {
            *buffer = NULL;
        }
        return -1;
    }
    len = [f length];

    if (timestamp) {
        *timestamp = [f timestamp];
    }
    
    if (!buffer) {
        [self closeFile:f error:error];
        return len;
    }

    loadCount++;
    loadStack++;

    buf = (unsigned char *)calloc(len+1, 1);
    *buffer = buf;

    NSError *readError = nil;
    const int bytesRead = [f read:buf length:len error:&readError];
    if (bytesRead != len) {
        if (readError) {
            if (error) {
                *error = readError;
            }
        } else {
            UDFileSystemAssignError(error,
                                    UDFileSystemPortErrorCodeReadFailed,
                                    @"Short read while loading '%@' (%d of %d bytes).",
                                    relativePath,
                                    bytesRead,
                                    len);
        }
        [self closeFile:f error:error];
        free(buf);
        *buffer = NULL;
        loadStack--;
        loadCount--;
        return -1;
    }

    // guarantee that it will have a trailing 0 for string operations
    buf[len] = 0;
    [self closeFile:f error:error];

    return len;
}

-(BOOL)freeFile:(void *)buffer error:(NSError **)error {
    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return NO;
    }
    if (!buffer) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"freeFile called with a nil buffer.");
        return NO;
    }
    loadStack--;

    free(buffer);
    return YES;
}

-(int)writeFile:(NSString *)relativePath buffer:(const void *)buffer size:(int)size basePath:(NSString *)basePath error:(NSError **)error {
    idFile *f;

    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return -1;
    }

    if (!relativePath || !buffer) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"writeFile called with a nil path or buffer.");
        return -1;
    }

    f = [self openFileWrite:relativePath
                   basePath:(basePath.length ? basePath : @"")
                      error:error];
    if (!f) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeWriteFailed,
                                @"Failed to open '%@' for writing.",
                                relativePath);
        return -1;
    }

    size = [f write:buffer length:size error:error];

    [self closeFile:f error:error];

    return size;
}

-(idFile *)openFileRead:(NSString *)relativePath allowCopyFiles:(BOOL)allowCopyFiles error:(NSError **)error {
    if (!relativePath.length) {
        return nil;
    }

    return [self openFileRead:relativePath allowCopyFiles:allowCopyFiles gamedir:nil error:error];
}

-(idFile *)openFileReadFromPak:(NSString *)relativePath allowCopyFiles:(BOOL)allowCopyFiles error:(NSError **)error {
    if (!relativePath.length) {
        return nil;
    }

    return [self openFileReadFromPak:relativePath allowCopyFiles:allowCopyFiles gamedir:nil error:error];
}

-(void)setIsFileLoadingAllowed:(BOOL)mode {
    self->isFileLoadingAllowed = mode;
}

-(BOOL)isFileLoadingAllowed {
    return self->isFileLoadingAllowed;
}

-(idFile *)newFileMemory {
    // Must go through the designated initializer: plain -init leaves the
    // mode ivar at 0, so the file rejects every write (silently, when the
    // caller passes no error out-param).
    return [[idFile_Memory alloc] initWithFileSystem:self];
}

-(idFile *)newFilePermanent {
    return [[idFile_Permanent alloc] initWithFileSystem:self];
}

-(pack_t *)loadZipFile:(NSString *)zipfile {
    fileInPack_t *     buildBuffer;
    pack_t *           pack;
    unzFile            uf;
    int                err;
    unz_global_info    gi;
    char               filename_inzip[MAX_ZIPPED_FILE_NAME];
    unz_file_info      file_info;
    int                i;
    long               hash;
    //int              fs_numHeaderLongs;
    //int *            fs_headerLongs;
    FILE               *f;
    int                len;
    int                confHash;
    fileInPack_t       *pakFile;

    f = [self openOSFile:zipfile mode:"rb" caseSensitiveName:nil];
    if (!f) {
        NSLog(@"Could not open %@ '%@': %s", _workspace.pakFileExtension, zipfile, strerror(errno));
        return nil;
    }
    fseek(f, 0, SEEK_END);
    len = ftell(f);
    fclose(f);

    //fs_numHeaderLongs = 0;

    uf = unzOpen([zipfile UTF8String]);
    if (!uf) {
        NSLog(@"WARN: could not open %@ zip '%@'", _workspace.pakFileExtension, zipfile);
        return nil;
    }
    err = unzGetGlobalInfo(uf, &gi);

    if (err != UNZ_OK) {
        NSLog(@"WARN: could not read %@ central directory '%@'", _workspace.pakFileExtension, zipfile);
        unzClose( uf );
        return nil;
    }

    pack = [[pack_t alloc] initWithPakFilename:zipfile];
    pack->handle = uf;
    pack->numfiles = gi.number_entry;
    pack->referenced = NO;
    pack->binary = BINARY_UNKNOWN;
    pack->isNew = NO;

    pack->length = len;

    unzGoToFirstFile(uf);
    //fs_headerLongs = (int *)calloc(1, gi.number_entry * sizeof(int));
    for ( i = 0; i < (int)gi.number_entry; i++ ) {
        err = unzGetCurrentFileInfo(uf, &file_info, filename_inzip, sizeof(filename_inzip), NULL, 0, NULL, 0);
        if (err != UNZ_OK) {
            break;
        }
        /*
        if (file_info.uncompressed_size > 0) {
            fs_headerLongs[fs_numHeaderLongs++] = LittleLong( file_info.crc );
        }
        */
        hash = [self hashFileName:[NSString stringWithUTF8String:filename_inzip]];
        
        fileInPack_t *fip = [[fileInPack_t alloc] initWithName:[NSString stringWithUTF8String:filename_inzip]];
        // store the file position in the zip
        unzGetCurrentFileInfoPosition(uf, &fip->pos);
        // add the file to the hash
        fip->next = pack->hashTable[hash];
        pack->hashTable[hash] = fip;
        [pack->buildBuffer addObject:fip];
        // go to the next file in the zip
        unzGoToNextFile(uf);
    }

    pack->checksum = 0;
    /*
    pack->checksum = MD4_BlockChecksum( fs_headerLongs, 4 * fs_numHeaderLongs );
    pack->checksum = LittleLong( pack->checksum );

    Mem_Free( fs_headerLongs );
    */

    return pack;
}

-(int)addZipFile:(NSString *)path {
    NSMutableString *fullpath;
    pack_t            *pak;
    searchpath_t    *search, *last;
    NSString        *relativePath = path;

    fullpath = [self.fs_savepath mutableCopy];
    [fullpath ud_appendPathComponent:relativePath];

    pak = [self loadZipFile:fullpath];
    if (!pak) {
        NSLog(@"WARN: addZipFile: %@ failed", path);
        return 0;
    }
    // insert the pak at the end of the search list - temporary until we restart
    pak->isNew = YES;
    search = [[searchpath_t alloc] init];
    search->dir = nil;
    search->pack = pak;
    search->next = nil;
    last = searchPaths;
    while (last->next) {
        last = last->next;
    }
    last->next = search;
    NSLog(@"Appended %@ %@", _workspace.pakFileExtension, pak->pakFilename);
    return pak->checksum;
}

- (void)extension:(NSString *)extension toList:(NSMutableArray<NSString *> *)extensionList {
    if (!extension || extension.length == 0) {
        return;
    }
    
    NSArray<NSString *> *components = [extension componentsSeparatedByString:@"|"];
    
    [extensionList addObjectsFromArray:components];
}

static NSInteger sortPathsFunction(NSString *s1, NSString *s2, void *ctx) {
    return ud_comparePath(s1, s2);
}

static void sortPaths(NSArray<NSString *> *list) {
    [list sortedArrayUsingFunction:sortPathsFunction context:NULL];
}

static inline int Icmpn(NSString *a, NSString *b, NSUInteger n) {
    if (n == 0) return 0;
    
    NSUInteger lenA = a.length;
    NSUInteger lenB = b.length;
    NSUInteger len = MIN(n, MIN(lenA, lenB));
    
    for (NSUInteger i = 0; i < len; i++) {
        unichar ca = [a characterAtIndex:i];
        unichar cb = [b characterAtIndex:i];
        
        // Simple ASCII case fold (enough for Doom paths)
        if (ca >= 'A' && ca <= 'Z') ca += 32;
        if (cb >= 'A' && cb <= 'Z') cb += 32;
        
        if (ca != cb) {
            return (int)ca - (int)cb;
        }
    }
    
    // If we compared fewer than n characters, the shorter string "loses"
    if (len < n) {
        if (lenA < lenB) return -1;
        if (lenA > lenB) return  1;
    }
    
    return 0;
}

- (int)getFileList:(NSString *)relativePath
        extensions:(NSArray<NSString *> *)extensions
              list:(NSMutableArray<NSString *> *)list
         hashIndex:(NSMutableSet<NSString *> *)hashIndex
  fullRelativePath:(BOOL)fullRelativePath
           gamedir:(NSString *)gamedir
             error:(NSError **)error {
    int j;
    NSMutableString *work;

    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return 0;
    }

    if (extensions.count == 0 || !relativePath) {
        return 0;
    }
    BOOL findDirectoriesOnly = [extensions containsObject:@"/"];

    int pathLength = (int)relativePath.length;
    if (pathLength) {
        pathLength++; // for the trailing '/'
    }
    
    work = [[NSMutableString alloc] init];
    
    // search through the path, one element at a time, adding to list
    for (searchpath_t *search = searchPaths; search != nil; search = search->next) {
        if (search->dir) {
            NSString *dirGameDir = search->dir->gamedir;
            
            if (gamedir && gamedir.length > 0) {
                if (![dirGameDir isEqualToString:gamedir]) {
                    continue;
                }
            }

            NSString *netpath = [self buildOSPath:search->dir->path game:dirGameDir relativePath:relativePath];

            for (NSString *ext in extensions) {
                NSMutableArray<NSString *> *sysFiles = [NSMutableArray array];
                
                // scan for files in the filesystem
                [self listOSFiles:netpath extension:ext list:sysFiles];

                // if we are searching for directories, remove . and ..
                if ([ext isEqualToString:@"/"]) {
                    [sysFiles removeObject:@"."];
                    [sysFiles removeObject:@".."];
                }

                for (NSString *file in sysFiles) {
                    NSString *work;
                    if (fullRelativePath) {
                        work = [relativePath stringByAppendingPathComponent:file];
                    } else {
                        work = file;
                    }
                    
                    // unique the match
                    if (![hashIndex containsObject:work]) {
                        [hashIndex addObject:[work copy]];
                        [list addObject:[work copy]];
                    }
                }
            }
        } else if (search->pack) {
            // look through all the pak file elements
            pack_t *pak = search->pack;
            NSArray<fileInPack_t *> *buildBuffer = pak->buildBuffer;
            
            for (int i = 0; i < pak->numfiles; i++) {
                NSString *name = ((fileInPack_t *)[buildBuffer objectAtIndex:i])->name;
                int length = (int)name.length;
                
                // if the name is not long enough to at least contain the path
                if (length <= pathLength) {
                    continue;
                }

                // check for a path match without the trailing '/'
                if (pathLength && Icmpn(name, relativePath, pathLength - 1) != 0) {
                    continue;
                }

                // ensure we have a path, and not just a filename containing the path
                if (length == pathLength || [name characterAtIndex:pathLength - 1] != '/') {
                    continue;
                }
                
                if (findDirectoriesOnly) {
                    // Find the first slash AFTER pathLength
                    NSInteger slashIndex = -1;
                    for (j = pathLength; j < length; j++) {
                        if ([name characterAtIndex:j] == '/') {
                            slashIndex = j;
                            break;
                        }
                    }
                    
                    // If there's no slash after pathLength, it's a file, not a directory
                    if (slashIndex == -1) {
                        continue;
                    }

                    // Extract the virtual directory name (including or excluding fullRelativePath)
                    if (fullRelativePath) {
                        // e.g., "scripts/sub"
                        [work setString:[name substringToIndex:slashIndex]];
                    } else {
                        // e.g., "sub"
                        [work setString:[name substringWithRange:NSMakeRange(pathLength, slashIndex - pathLength)]];
                    }

                    if (![hashIndex containsObject:work]) {
                        [hashIndex addObject:[work copy]];
                        [list addObject:[work copy]];
                    }
                    continue;
                }

                // make sure the file is not in a subdirectory
                for (j = pathLength; j + 1 < length; j++) {
                    if ([name characterAtIndex:j] == '/') {
                        break;
                    }
                }
                if (j + 1 < length) {
                    continue;
                }

                // check for extension match
                for (j = 0; j < extensions.count; j++) {
                    NSString *ext = [extensions objectAtIndex:j];
                    NSRange targetRange = NSMakeRange(name.length - ext.length, ext.length);
                    if (name.length >= ext.length &&
                        [name compare:ext options:NSCaseInsensitiveSearch range:targetRange] == NSOrderedSame) {
                        break;
                    }
                }
                if (j >= extensions.count) {
                    continue;
                }

                // unique the match
                if (fullRelativePath) {
                    [work setString:relativePath];
                    [work appendString:@"/"];
                    [work appendString:[name substringFromIndex:pathLength]];
                    [work ud_stripTrailingCharacter:'/'];
                } else {
                    [work setString:[name substringFromIndex:pathLength]];
                    [work ud_stripTrailingCharacter:'/'];
                }
                
                if (![hashIndex containsObject:work]) {
                    [hashIndex addObject:[work copy]];
                    [list addObject:[work copy]];
                }
            }
        }
    }

    return (int)list.count;
}

-(idFileList *)listFiles:(NSString *)relativePath extension:(NSString*)extension sorted:(BOOL)sort fullRelativePath:(BOOL)fullRelativePath inGameDir:(NSString *)gamedir error:(NSError **)error {

    NSMutableSet<NSString *> *hashIndex = [[NSMutableSet alloc] initWithCapacity:4096];
    NSMutableArray<NSString *> *extensionList = [[NSMutableArray alloc] init];
    NSMutableArray<NSString *> *list = [[NSMutableArray alloc] init];
    idFileList *fileList = [[idFileList alloc] initWithBasePath:relativePath list:list];
    
    [self extension:extension toList:extensionList];
    
    int count = [self getFileList:relativePath
                       extensions:extensionList
                             list:list
                        hashIndex:hashIndex
                 fullRelativePath:fullRelativePath
                          gamedir:gamedir
                            error:error];

    if (sort) {
        sortPaths(list);
    }

    return fileList;
}

- (idFileList *)listFiles:(NSString *)relativePath extension:(NSString *)extension error:(NSError **)error {
    return [self listFiles:relativePath extension:extension sorted:NO fullRelativePath:NO inGameDir:nil error:error];
}

// fullRelativePath=NO, inGameDir=nil
- (idFileList *)listFiles:(NSString *)relativePath extension:(NSString *)extension sorted:(BOOL)sorted error:(NSError **)error {
    return [self listFiles:relativePath extension:extension sorted:sorted fullRelativePath:NO inGameDir:nil error:error];
}

// inGameDir=nil
- (idFileList *)listFiles:(NSString *)relativePath extension:(NSString *)extension sorted:(BOOL)sorted fullRelativePath:(BOOL)fullRelativePath error:(NSError **)error {
    return [self listFiles:relativePath extension:extension sorted:sorted fullRelativePath:fullRelativePath inGameDir:nil error:error];
}

-(int) getFileListTree:(NSString *)relativePath
         extensionList:(NSArray<NSString *> *)extensions
                  list:(NSMutableArray<NSString *> *)list
             hashIndex:(NSMutableSet<NSString *> *)hashIndex
               gamedir:(NSString *)gamedir
                 error:(NSError **)error {
    NSMutableArray<NSString *> *slash = [[NSMutableArray alloc] init];
    NSMutableArray<NSString *> *folders = [[NSMutableArray alloc] initWithCapacity:128];
    NSMutableSet<NSString *> *folderhashIndex = [[NSMutableSet alloc] initWithCapacity:1024];
    int i;

    // recurse through the subdirectories
    [slash addObject:@"/"];
    [self getFileList:relativePath extensions:slash list:folders hashIndex:folderhashIndex fullRelativePath:YES gamedir:gamedir error:error];

    for (i = 0; i < folders.count; i++) {
        NSString *folder = [folders objectAtIndex:i];

        if (folder.length && [folder characterAtIndex:0] == '.') {
            continue;
        }
        if ([folder caseInsensitiveCompare:relativePath] == NSOrderedSame){
            continue;
        }
        [self getFileListTree:folder extensionList:extensions list:list hashIndex:hashIndex gamedir:gamedir error:error];
    }

    // list files in the current directory
    [self getFileList:relativePath extensions:extensions list:list hashIndex:hashIndex fullRelativePath:YES gamedir:gamedir error:error];

    return (int)list.count;
}

-(idFileList *)listFilesTree:(NSString *)relativePath extension:(NSString *)extension sorted:(BOOL)sort inGameDir:(NSString *)gamedir error:(NSError **)error {
    NSMutableSet *hashIndex = [[NSMutableSet alloc] initWithCapacity:4096];
    NSMutableArray<NSString *> *extensionList = [[NSMutableArray alloc] init];
    NSMutableArray<NSString *> *list = [[NSMutableArray alloc] init];
    idFileList *fileList = [[idFileList alloc] initWithBasePath:relativePath list:list];
    
    [self extension:extension toList:extensionList];
    
    [self getFileListTree:relativePath
            extensionList:extensionList
                     list:list
                hashIndex:hashIndex
                  gamedir:gamedir
                    error:error];

    if (sort) {
        sortPaths(list);
    }

    return fileList;
}

-(void)freeFileList:(idFileList *)fileList {
    // TODO: how to delete it?
    //delete fileList;
}

#if 0
static const char *OPENQ4_MOD_MANIFEST_FILENAME = "mod.json";

/*
===============
idModInfoCompare
===============
*/
static int idModInfoCompare( const idModInfo *a, const idModInfo *b ) {
    const int displayNameCompare = a->displayName.Icmp( b->displayName );
    if ( displayNameCompare != 0 ) {
        return displayNameCompare;
    }

    return a->directory.Icmp( b->directory );
}

/*
===============
FS_FindModDirectory
===============
*/
static int FS_FindModDirectory( const idList<idModInfo> &mods, const char *directory ) {
    for ( int i = 0; i < mods.Num(); ++i ) {
        if ( !mods[i].directory.Icmp( directory ) ) {
            return i;
        }
    }

    return -1;
}

/*
===============
FS_SkipJsonWhitespace
===============
*/
static const char *FS_SkipJsonWhitespace( const char *cursor ) {
    while ( cursor != NULL && ( *cursor == ' ' || *cursor == '\t' || *cursor == '\r' || *cursor == '\n' ) ) {
        ++cursor;
    }

    return cursor;
}

/*
===============
FS_IsJsonHexDigit
===============
*/
static bool FS_IsJsonHexDigit( const char c ) {
    return ( c >= '0' && c <= '9' ) ||
           ( c >= 'a' && c <= 'f' ) ||
           ( c >= 'A' && c <= 'F' );
}

/*
===============
FS_JsonHexValue
===============
*/
static int FS_JsonHexValue( const char c ) {
    if ( c >= '0' && c <= '9' ) {
        return c - '0';
    }
    if ( c >= 'a' && c <= 'f' ) {
        return 10 + c - 'a';
    }
    if ( c >= 'A' && c <= 'F' ) {
        return 10 + c - 'A';
    }
    return -1;
}

/*
===============
FS_AppendJsonCodePoint
===============
*/
static bool FS_AppendJsonCodePoint( idStr &value, const unsigned int codePoint, idStr &errorOut ) {
    if ( codePoint == 0 ) {
        errorOut = "NUL characters are not supported in JSON strings";
        return NO;
    }

    if ( codePoint <= 0x7F ) {
        value += static_cast<char>( codePoint );
        return YES;
    }

    char utf8[ 4 ];
    int utf8Length = 0;
    if ( codePoint <= 0x7FF ) {
        utf8[ 0 ] = static_cast<char>( 0xC0 | ( codePoint >> 6 ) );
        utf8[ 1 ] = static_cast<char>( 0x80 | ( codePoint & 0x3F ) );
        utf8Length = 2;
    } else if ( codePoint <= 0xFFFF ) {
        utf8[ 0 ] = static_cast<char>( 0xE0 | ( codePoint >> 12 ) );
        utf8[ 1 ] = static_cast<char>( 0x80 | ( ( codePoint >> 6 ) & 0x3F ) );
        utf8[ 2 ] = static_cast<char>( 0x80 | ( codePoint & 0x3F ) );
        utf8Length = 3;
    } else if ( codePoint <= 0x10FFFF ) {
        utf8[ 0 ] = static_cast<char>( 0xF0 | ( codePoint >> 18 ) );
        utf8[ 1 ] = static_cast<char>( 0x80 | ( ( codePoint >> 12 ) & 0x3F ) );
        utf8[ 2 ] = static_cast<char>( 0x80 | ( ( codePoint >> 6 ) & 0x3F ) );
        utf8[ 3 ] = static_cast<char>( 0x80 | ( codePoint & 0x3F ) );
        utf8Length = 4;
    } else {
        errorOut = "JSON unicode escape is outside the valid Unicode range";
        return NO;
    }

    value.Append( utf8, utf8Length );
    return YES;
}

/*
===============
FS_ParseJsonHex4
===============
*/
static bool FS_ParseJsonHex4( const char *&cursor, unsigned int &codePoint, idStr &errorOut ) {
    codePoint = 0;
    for ( int i = 0; i < 4; ++i ) {
        if ( cursor == NULL || !FS_IsJsonHexDigit( *cursor ) ) {
            errorOut = "invalid JSON unicode escape";
            return NO;
        }
        codePoint = ( codePoint << 4 ) | FS_JsonHexValue( *cursor );
        ++cursor;
    }

    return YES;
}

/*
===============
FS_ParseJsonUnicodeEscape
===============
*/
static bool FS_ParseJsonUnicodeEscape( const char *&cursor, idStr &value, idStr &errorOut ) {
    unsigned int codePoint = 0;
    if ( !FS_ParseJsonHex4( cursor, codePoint, errorOut ) ) {
        return NO;
    }

    if ( codePoint >= 0xD800 && codePoint <= 0xDBFF ) {
        if ( cursor == NULL || cursor[ 0 ] != '\\' || cursor[ 1 ] != 'u' ) {
            errorOut = "high surrogate JSON unicode escape is missing a low surrogate";
            return NO;
        }
        cursor += 2;

        unsigned int lowSurrogate = 0;
        if ( !FS_ParseJsonHex4( cursor, lowSurrogate, errorOut ) ) {
            return NO;
        }
        if ( lowSurrogate < 0xDC00 || lowSurrogate > 0xDFFF ) {
            errorOut = "high surrogate JSON unicode escape is not followed by a low surrogate";
            return NO;
        }

        codePoint = 0x10000 + ( ( codePoint - 0xD800 ) << 10 ) + ( lowSurrogate - 0xDC00 );
    } else if ( codePoint >= 0xDC00 && codePoint <= 0xDFFF ) {
        errorOut = "low surrogate JSON unicode escape appears without a high surrogate";
        return NO;
    }

    return FS_AppendJsonCodePoint( value, codePoint, errorOut );
}

/*
===============
FS_ParseJsonString
===============
*/
static bool FS_ParseJsonString( const char *&cursor, idStr &value, idStr &errorOut ) {
    value.Clear();

    cursor = FS_SkipJsonWhitespace( cursor );
    if ( cursor == NULL || *cursor != '"' ) {
        errorOut = "expected JSON string";
        return NO;
    }

    ++cursor;
    while ( *cursor != '\0' ) {
        if ( *cursor == '"' ) {
            ++cursor;
            return YES;
        }

        if ( *cursor == '\\' ) {
            ++cursor;
            if ( *cursor == '\0' ) {
                errorOut = "unterminated escape sequence in JSON string";
                return NO;
            }

            switch ( *cursor ) {
                case '"':
                case '\\':
                case '/':
                    value += *cursor;
                    ++cursor;
                    break;
                case 'b':
                    value += '\b';
                    ++cursor;
                    break;
                case 'f':
                    value += '\f';
                    ++cursor;
                    break;
                case 'n':
                    value += '\n';
                    ++cursor;
                    break;
                case 'r':
                    value += '\r';
                    ++cursor;
                    break;
                case 't':
                    value += '\t';
                    ++cursor;
                    break;
                case 'u':
                    ++cursor;
                    if ( !FS_ParseJsonUnicodeEscape( cursor, value, errorOut ) ) {
                        return NO;
                    }
                    break;
                default:
                    errorOut = va( "unsupported JSON escape '\\%c'", *cursor );
                    return NO;
            }

            continue;
        }

        if ( static_cast<unsigned char>( *cursor ) < 0x20 ) {
            errorOut = "unescaped control character in JSON string";
            return NO;
        }

        value += *cursor;
        ++cursor;
    }

    errorOut = "unterminated JSON string";
    return NO;
}

static bool FS_SkipJsonValue( const char *&cursor, idStr &errorOut );

/*
===============
FS_SkipJsonLiteral
===============
*/
static bool FS_SkipJsonLiteral( const char *&cursor, const char *literal, idStr &errorOut ) {
    const char *scan = cursor;
    for ( const char *expected = literal; *expected != '\0'; ++expected, ++scan ) {
        if ( scan == NULL || *scan != *expected ) {
            errorOut = va( "expected JSON literal '%s'", literal );
            return NO;
        }
    }

    cursor = scan;
    return YES;
}

/*
===============
FS_SkipJsonNumber
===============
*/
static bool FS_SkipJsonNumber( const char *&cursor, idStr &errorOut ) {
    const char *scan = cursor;
    if ( *scan == '-' ) {
        ++scan;
    }

    if ( *scan == '0' ) {
        ++scan;
    } else if ( *scan >= '1' && *scan <= '9' ) {
        do {
            ++scan;
        } while ( *scan >= '0' && *scan <= '9' );
    } else {
        errorOut = "invalid JSON number";
        return NO;
    }

    if ( *scan == '.' ) {
        ++scan;
        if ( *scan < '0' || *scan > '9' ) {
            errorOut = "invalid JSON number fraction";
            return NO;
        }
        do {
            ++scan;
        } while ( *scan >= '0' && *scan <= '9' );
    }

    if ( *scan == 'e' || *scan == 'E' ) {
        ++scan;
        if ( *scan == '+' || *scan == '-' ) {
            ++scan;
        }
        if ( *scan < '0' || *scan > '9' ) {
            errorOut = "invalid JSON number exponent";
            return NO;
        }
        do {
            ++scan;
        } while ( *scan >= '0' && *scan <= '9' );
    }

    cursor = scan;
    return YES;
}

/*
===============
FS_SkipJsonArray
===============
*/
static bool FS_SkipJsonArray( const char *&cursor, idStr &errorOut ) {
    ++cursor;
    cursor = FS_SkipJsonWhitespace( cursor );
    if ( cursor == NULL ) {
        errorOut = "unterminated JSON array";
        return NO;
    }
    if ( *cursor == ']' ) {
        ++cursor;
        return YES;
    }

    while ( YES ) {
        if ( !FS_SkipJsonValue( cursor, errorOut ) ) {
            return NO;
        }

        cursor = FS_SkipJsonWhitespace( cursor );
        if ( cursor == NULL || *cursor == '\0' ) {
            errorOut = "unterminated JSON array";
            return NO;
        }
        if ( *cursor == ',' ) {
            ++cursor;
            continue;
        }
        if ( *cursor == ']' ) {
            ++cursor;
            return YES;
        }

        errorOut = "expected ',' or ']' after JSON array value";
        return NO;
    }
}

/*
===============
FS_SkipJsonObject
===============
*/
static bool FS_SkipJsonObject( const char *&cursor, idStr &errorOut ) {
    ++cursor;
    cursor = FS_SkipJsonWhitespace( cursor );
    if ( cursor == NULL ) {
        errorOut = "unterminated JSON object";
        return NO;
    }
    if ( *cursor == '}' ) {
        ++cursor;
        return YES;
    }

    while ( YES ) {
        idStr key;
        if ( !FS_ParseJsonString( cursor, key, errorOut ) ) {
            return NO;
        }

        cursor = FS_SkipJsonWhitespace( cursor );
        if ( cursor == NULL || *cursor != ':' ) {
            errorOut = "missing ':' after JSON object key";
            return NO;
        }
        ++cursor;

        if ( !FS_SkipJsonValue( cursor, errorOut ) ) {
            return NO;
        }

        cursor = FS_SkipJsonWhitespace( cursor );
        if ( cursor == NULL || *cursor == '\0' ) {
            errorOut = "unterminated JSON object";
            return NO;
        }
        if ( *cursor == ',' ) {
            ++cursor;
            continue;
        }
        if ( *cursor == '}' ) {
            ++cursor;
            return YES;
        }

        errorOut = "expected ',' or '}' after JSON object value";
        return NO;
    }
}

/*
===============
FS_SkipJsonValue
===============
*/
static bool FS_SkipJsonValue( const char *&cursor, idStr &errorOut ) {
    cursor = FS_SkipJsonWhitespace( cursor );
    if ( cursor == NULL || *cursor == '\0' ) {
        errorOut = "expected JSON value";
        return NO;
    }

    if ( *cursor == '"' ) {
        idStr ignored;
        return FS_ParseJsonString( cursor, ignored, errorOut );
    }
    if ( *cursor == '{' ) {
        return FS_SkipJsonObject( cursor, errorOut );
    }
    if ( *cursor == '[' ) {
        return FS_SkipJsonArray( cursor, errorOut );
    }
    if ( *cursor == 't' ) {
        return FS_SkipJsonLiteral( cursor, "true", errorOut );
    }
    if ( *cursor == 'f' ) {
        return FS_SkipJsonLiteral( cursor, "false", errorOut );
    }
    if ( *cursor == 'n' ) {
        return FS_SkipJsonLiteral( cursor, "null", errorOut );
    }
    if ( *cursor == '-' || ( *cursor >= '0' && *cursor <= '9' ) ) {
        return FS_SkipJsonNumber( cursor, errorOut );
    }

    errorOut = "expected JSON value";
    return NO;
}

/*
===============
FS_ModManifestKeyIsKnown
===============
*/
static bool FS_ModManifestKeyIsKnown( const idStr &key ) {
    return !key.Icmp( "name" ) ||
           !key.Icmp( "version" ) ||
           !key.Icmp( "releaseDate" ) ||
           !key.Icmp( "website" ) ||
           !key.Icmp( "author" ) ||
           !key.Icmp( "requiredopenQ4Version" );
}

/*
===============
FS_BuildModListLabel
===============
*/
static idStr FS_BuildModListLabel( const idModInfo &modInfo ) {
    idStr label = modInfo.displayName;
    label.Replace( "\t", " " );
    label.Replace( "\r", " " );
    label.Replace( "\n", " " );

    idStr version = modInfo.version;
    version.Replace( "\t", " " );
    version.Replace( "\r", " " );
    version.Replace( "\n", " " );

    return va( "%s\t%s", label.c_str(), version.c_str() );
}

/*
===============
FS_FinalizeModInfo
===============
*/
static void FS_FinalizeModInfo( idModInfo &modInfo ) {
    modInfo.listLabel = FS_BuildModListLabel( modInfo );
}

typedef struct openQ4BaseVersion_s {
    int major;
    int minor;
    int patch;
} openQ4BaseVersion_t;

/*
===============
FS_ParseopenQ4BaseVersion
===============
*/
static bool FS_ParseopenQ4BaseVersion( const char *version, openQ4BaseVersion_t &parsed ) {
    int values[3] = { 0, 0, 0 };

    if ( version == NULL || version[0] == '\0' ) {
        return NO;
    }

    const char *cursor = version;
    for ( int part = 0; part < 3; ++part ) {
        if ( *cursor < '0' || *cursor > '9' ) {
            return NO;
        }

        int value = 0;
        while ( *cursor >= '0' && *cursor <= '9' ) {
            value = ( value * 10 ) + ( *cursor - '0' );
            ++cursor;
        }

        values[part] = value;

        if ( part < 2 ) {
            if ( *cursor != '.' ) {
                return NO;
            }
            ++cursor;
        }
    }

    if ( *cursor != '\0' ) {
        return NO;
    }

    parsed.major = values[0];
    parsed.minor = values[1];
    parsed.patch = values[2];
    return YES;
}

/*
===============
FS_CompareopenQ4BaseVersions
===============
*/
static int FS_CompareopenQ4BaseVersions( const openQ4BaseVersion_t &left, const openQ4BaseVersion_t &right ) {
    if ( left.major != right.major ) {
        return left.major < right.major ? -1 : 1;
    }
    if ( left.minor != right.minor ) {
        return left.minor < right.minor ? -1 : 1;
    }
    if ( left.patch != right.patch ) {
        return left.patch < right.patch ? -1 : 1;
    }
    return 0;
}

/*
===============
FS_ParseModManifest
===============
*/
static bool FS_ParseModManifest( const char *jsonText, idModInfo &modInfo, idStr &errorOut ) {
    errorOut.Clear();
    modInfo.displayName.Clear();
    modInfo.version.Clear();
    modInfo.releaseDate.Clear();
    modInfo.website.Clear();
    modInfo.author.Clear();
    modInfo.requiredopenQ4Version.Clear();
    modInfo.listLabel.Clear();

    if ( jsonText == NULL ) {
        errorOut = "manifest content is null";
        return NO;
    }

    const char *cursor = FS_SkipJsonWhitespace( jsonText );
    if ( cursor == NULL || *cursor != '{' ) {
        errorOut = "manifest must begin with '{'";
        return NO;
    }

    ++cursor;
    while ( YES ) {
        idStr key;
        idStr value;

        cursor = FS_SkipJsonWhitespace( cursor );
        if ( cursor == NULL || *cursor == '\0' ) {
            errorOut = "manifest ended before closing '}'";
            return NO;
        }
        if ( *cursor == '}' ) {
            ++cursor;
            break;
        }

        if ( !FS_ParseJsonString( cursor, key, errorOut ) ) {
            return NO;
        }

        cursor = FS_SkipJsonWhitespace( cursor );
        if ( *cursor != ':' ) {
            errorOut = va( "missing ':' after '%s'", key.c_str() );
            return NO;
        }
        ++cursor;

        if ( FS_ModManifestKeyIsKnown( key ) ) {
            cursor = FS_SkipJsonWhitespace( cursor );
            if ( cursor == NULL || *cursor != '"' ) {
                errorOut = va( "field '%s' must be a JSON string", key.c_str() );
                return NO;
            }
            if ( !FS_ParseJsonString( cursor, value, errorOut ) ) {
                errorOut = va( "invalid value for '%s': %s", key.c_str(), errorOut.c_str() );
                return NO;
            }

            if ( !key.Icmp( "name" ) ) {
                modInfo.displayName = value;
            } else if ( !key.Icmp( "version" ) ) {
                modInfo.version = value;
            } else if ( !key.Icmp( "releaseDate" ) ) {
                modInfo.releaseDate = value;
            } else if ( !key.Icmp( "website" ) ) {
                modInfo.website = value;
            } else if ( !key.Icmp( "author" ) ) {
                modInfo.author = value;
            } else if ( !key.Icmp( "requiredopenQ4Version" ) ) {
                modInfo.requiredopenQ4Version = value;
            }
        } else if ( !FS_SkipJsonValue( cursor, errorOut ) ) {
            errorOut = va( "invalid value for '%s': %s", key.c_str(), errorOut.c_str() );
            return NO;
        }

        cursor = FS_SkipJsonWhitespace( cursor );
        if ( *cursor == ',' ) {
            ++cursor;
            cursor = FS_SkipJsonWhitespace( cursor );
            if ( cursor == NULL || *cursor == '\0' ) {
                errorOut = "manifest ended after trailing comma";
                return NO;
            }
            if ( *cursor == '}' ) {
                errorOut = "trailing comma before closing '}'";
                return NO;
            }
            continue;
        }
        if ( *cursor == '}' ) {
            ++cursor;
            break;
        }
        if ( *cursor == '\0' ) {
            errorOut = "manifest ended before closing '}'";
            return NO;
        }

        errorOut = "expected ',' or '}' after manifest value";
        return NO;
    }

    cursor = FS_SkipJsonWhitespace( cursor );
    if ( cursor == NULL || *cursor != '\0' ) {
        errorOut = "unexpected data after manifest object";
        return NO;
    }

    if ( modInfo.displayName.IsEmpty() ) {
        errorOut = "missing required field 'name'";
        return NO;
    }
    if ( modInfo.version.IsEmpty() ) {
        errorOut = "missing required field 'version'";
        return NO;
    }
    if ( modInfo.releaseDate.IsEmpty() ) {
        errorOut = "missing required field 'releaseDate'";
        return NO;
    }
    if ( modInfo.website.IsEmpty() ) {
        errorOut = "missing required field 'website'";
        return NO;
    }
    if ( modInfo.author.IsEmpty() ) {
        errorOut = "missing required field 'author'";
        return NO;
    }
    if ( modInfo.requiredopenQ4Version.IsEmpty() ) {
        errorOut = "missing required field 'requiredopenQ4Version'";
        return NO;
    }

    FS_FinalizeModInfo( modInfo );
    return YES;
}

/*
===============
idFileSystemLocal::ListMods
===============
*/
idModList *idFileSystemLocal::ListMods( void ) {
    idStrList    dirs;
    idModList    *list = new idModList;

    const char    *search[ 3 ];
    int            isearch;

    search[0] = fs_cdpath.GetString();
    search[1] = fs_basepath.GetString();
    search[2] = fs_savepath.GetString();

    for ( isearch = 0; isearch < 3; isearch++ ) {
        if ( !search[ isearch ] || !search[ isearch ][ 0 ] ) {
            continue;
        }

        dirs.Clear();

        // scan for directories
        ListOSFiles( search[ isearch ], "/", dirs );

        dirs.Remove( "." );
        dirs.Remove( ".." );
        dirs.Remove( "base" );
        dirs.Remove( "pb" );

        for ( int i = dirs.Num() - 1; i >= 0; --i ) {
            if ( dirs[ i ].HasUpper() ) {
                dirs.RemoveIndex( i );
            }
        }

        for ( int i = 0; i < dirs.Num(); i++ ) {
            if ( FS_FindModDirectory( list->mods, dirs[ i ] ) >= 0 ) {
                continue;
            }

            idModInfo modInfo;
            idStr reason;
            const modManifestStatus_t manifestStatus = ReadModManifestFromSearchPath( search[ isearch ], dirs[ i ], modInfo, &reason );
            if ( manifestStatus == MOD_MANIFEST_VALID ) {
                list->mods.Append( modInfo );
                continue;
            }

            if ( manifestStatus == MOD_MANIFEST_INVALID && reason.Length() ) {
                common->Warning( "Skipping mod '%s': %s", dirs[ i ].c_str(), reason.c_str() );
            }
        }
    }

    list->mods.Sort( idModInfoCompare );

    return list;
}

/*
===============
idFileSystemLocal::ReadModManifestFile
===============
*/
modManifestStatus_t idFileSystemLocal::ReadModManifestFile( const char *manifestPath, idModInfo &modInfo, idStr *reason ) {
    if ( reason != NULL ) {
        reason->Clear();
    }

    FILE *file = OpenOSFile( manifestPath, "rb" );
    if ( file == NULL ) {
        return MOD_MANIFEST_MISSING;
    }

    const int length = DirectFileLength( file );
    if ( length <= 0 ) {
        if ( reason != NULL ) {
            *reason = va( "manifest '%s' is empty", manifestPath );
        }
        fclose( file );
        return MOD_MANIFEST_INVALID;
    }

    idList<char> buffer;
    buffer.SetNum( length + 1 );
    const int bytesRead = static_cast<int>( fread( buffer.Ptr(), 1, length, file ) );
    buffer[ length ] = '\0';
    fclose( file );

    if ( bytesRead != length ) {
        if ( reason != NULL ) {
            *reason = va( "failed to read manifest '%s'", manifestPath );
        }
        return MOD_MANIFEST_INVALID;
    }

    idStr parseError;
    if ( !FS_ParseModManifest( buffer.Ptr(), modInfo, parseError ) ) {
        if ( reason != NULL ) {
            *reason = va( "%s: %s", manifestPath, parseError.c_str() );
        }
        return MOD_MANIFEST_INVALID;
    }

    openQ4BaseVersion_t requiredVersion;
    if ( !FS_ParseopenQ4BaseVersion( modInfo.requiredopenQ4Version.c_str(), requiredVersion ) ) {
        if ( reason != NULL ) {
            *reason = va(
                "%s has invalid required openQ4 version '%s' (expected major.minor.patch)",
                modInfo.displayName.c_str(),
                modInfo.requiredopenQ4Version.c_str() );
        }
        return MOD_MANIFEST_INVALID;
    }

    openQ4BaseVersion_t engineVersion;
    if ( !FS_ParseopenQ4BaseVersion( OPENQ4_VERSION_BASE, engineVersion ) ) {
        if ( reason != NULL ) {
            *reason = va( "this build has invalid openQ4 version '%s'", OPENQ4_VERSION_BASE );
        }
        return MOD_MANIFEST_INVALID;
    }

    if ( FS_CompareopenQ4BaseVersions( engineVersion, requiredVersion ) < 0 ) {
        if ( reason != NULL ) {
            *reason = va(
                "%s requires openQ4 %s or newer but this build is %s",
                modInfo.displayName.c_str(),
                modInfo.requiredopenQ4Version.c_str(),
                OPENQ4_VERSION_BASE );
        }
        return MOD_MANIFEST_INVALID;
    }

    return MOD_MANIFEST_VALID;
}

/*
===============
idFileSystemLocal::ReadModManifestFromSearchPath
===============
*/
modManifestStatus_t idFileSystemLocal::ReadModManifestFromSearchPath( const char *searchPath, const char *modDir, idModInfo &modInfo, idStr *reason ) {
    if ( !searchPath || !searchPath[ 0 ] || !modDir || !modDir[ 0 ] ) {
        if ( reason != NULL ) {
            reason->Clear();
        }
        return MOD_MANIFEST_MISSING;
    }

    const idStr manifestPath = BuildOSPath( searchPath, modDir, OPENQ4_MOD_MANIFEST_FILENAME );
    const modManifestStatus_t status = ReadModManifestFile( manifestPath.c_str(), modInfo, reason );
    if ( status != MOD_MANIFEST_VALID ) {
        return status;
    }

    modInfo.directory = modDir;
    return MOD_MANIFEST_VALID;
}
#endif
-(BOOL)getModInfo:(NSString *)modDir reason:(NSMutableString *)reason {
    if (reason != NULL) {
        [reason setString:@""];
    }

    if (modDir == nil || !modDir.length) {
        if (reason != nil) {
            [reason setString:@"mod directory is empty"];
        }
        return NO;
    }

    /*
    const char *search[ 3 ];
    search[ 0 ] = fs_cdpath.GetString();
    search[ 1 ] = fs_basepath.GetString();
    search[ 2 ] = fs_savepath.GetString();

    idStr failureReason;
    for ( int i = 0; i < 3; ++i ) {
        idStr localReason;
        const modManifestStatus_t status = ReadModManifestFromSearchPath( search[ i ], modDir, modInfo, &localReason );
        if ( status == MOD_MANIFEST_VALID ) {
            return YES;
        }
        if ( status == MOD_MANIFEST_INVALID && localReason.Length() ) {
            failureReason = localReason;
        }
    }

    if ( reason != NULL ) {
        if ( failureReason.Length() ) {
            *reason = failureReason;
        } else {
            *reason = va( "missing %s", OPENQ4_MOD_MANIFEST_FILENAME );
        }
    }

    return NO;*/
    return YES;
}

-(BOOL)validateConfiguredGameDir:(NSString *)gameDir reason:(NSMutableString *)reason {
    if (reason != nil) {
        [reason setString:@""];
    }

    if (gameDir == nil || gameDir.length == 0) {
        return YES;
    }

    if ([gameDir caseInsensitiveCompare:self.gamedir] == NSOrderedSame) {
        return YES;
    }

    //idModInfo modInfo;
    //return GetModInfo( gameDir, modInfo, reason );
    return [self getModInfo:gameDir reason:reason];
}

#if 0
/*
===============
idFileSystemLocal::FreeModList
===============
*/
void idFileSystemLocal::FreeModList( idModList *modList ) {
    delete modList;
}
#endif

-(int)listOSFiles:(NSString *)directory extension:(NSString *)extension list:(NSMutableArray<NSString *> *)list {
    int i, j, ret;
    NSString *cacheDirectory = directory;

    if (!extension) {
        extension = @"";
    }

    if (!self.fs_caseSensitiveOS) {
        return Sys_ListFiles(directory, extension, list);
    }

    NSMutableString *resolvedDirectory = [[NSMutableString alloc] init];

    // try in cache
    i = dir_cache_index - 1;
    while( i >= dir_cache_index - dir_cache_count ) {
        j = (i+MAX_CACHED_DIRS) % MAX_CACHED_DIRS;
        if ([dir_cache[j] matchesDirectory:directory withExtension:extension]) {
            if (self.fs_debug) {
                NSLog(@"listOSFiles: cache hit: %@\n", directory);
            }
            [list setArray:dir_cache[j].files];
            return list.count;
        }
        i--;
    }

    if (self.fs_debug) {
        NSLog(@"listOSFiles: cache miss: %@\n", directory);
    }

    ret = Sys_ListFiles(directory, extension, list);
    if (ret == -1 && [self resolveCaseInsensitiveOSPath:directory resolvedPath:resolvedDirectory finalSegmentIsFile:NO]) {
        cacheDirectory = resolvedDirectory;
        if (self.fs_debug) {
            NSLog(@"listOSFiles: changed %@ to %@", directory, cacheDirectory);
        }
        ret = Sys_ListFiles(cacheDirectory, extension, list);
    }

    if (ret == -1) {
        return -1;
    }

    // push a new entry
    dir_cache[dir_cache_index] = [[idDEntry alloc] initWithDirectory:cacheDirectory extension:extension list:list];
    dir_cache_index = (dir_cache_index + 1) % MAX_CACHED_DIRS;
    if (dir_cache_count < MAX_CACHED_DIRS) {
        dir_cache_count++;
    }

    return ret;
}

#if 0
/*
================
idFileSystemLocal::Dir_f
================
*/
void idFileSystemLocal::Dir_f( const idCmdArgs &args ) {
    idStr        relativePath;
    idStr        extension;
    idFileList *fileList;
    int            i;

    if ( args.Argc() < 2 || args.Argc() > 3 ) {
        common->Printf( "usage: dir <directory> [extension]\n" );
        return;
    }

    if ( args.Argc() == 2 ) {
        relativePath = args.Argv( 1 );
        extension = "";
    }
    else {
        relativePath = args.Argv( 1 );
        extension = args.Argv( 2 );
        if ( extension[0] != '.' ) {
            common->Warning( "extension should have a leading dot" );
        }
    }
    relativePath.BackSlashesToSlashes();
    relativePath.StripTrailing( '/' );

    common->Printf( "Listing of %s/*%s\n", relativePath.c_str(), extension.c_str() );
    common->Printf( "---------------\n" );

    fileList = fileSystemLocal.ListFiles( relativePath, extension );

    for ( i = 0; i < fileList->GetNumFiles(); i++ ) {
        common->Printf( "%s\n", fileList->GetFile( i ) );
    }
    common->Printf( "%d files\n", fileList->list.Num() );

    fileSystemLocal.FreeFileList( fileList );
}

/*
================
idFileSystemLocal::DirTree_f
================
*/
void idFileSystemLocal::DirTree_f( const idCmdArgs &args ) {
    idStr        relativePath;
    idStr        extension;
    idFileList *fileList;
    int            i;

    if ( args.Argc() < 2 || args.Argc() > 3 ) {
        common->Printf( "usage: dirtree <directory> [extension]\n" );
        return;
    }

    if ( args.Argc() == 2 ) {
        relativePath = args.Argv( 1 );
        extension = "";
    }
    else {
        relativePath = args.Argv( 1 );
        extension = args.Argv( 2 );
        if ( extension[0] != '.' ) {
            common->Warning( "extension should have a leading dot" );
        }
    }
    relativePath.BackSlashesToSlashes();
    relativePath.StripTrailing( '/' );

    common->Printf( "Listing of %s/*%s /s\n", relativePath.c_str(), extension.c_str() );
    common->Printf( "---------------\n" );

    fileList = fileSystemLocal.ListFilesTree( relativePath, extension );

    for ( i = 0; i < fileList->GetNumFiles(); i++ ) {
        common->Printf( "%s\n", fileList->GetFile( i ) );
    }
    common->Printf( "%d files\n", fileList->list.Num() );

    fileSystemLocal.FreeFileList( fileList );
}
#endif

-(void)path_f {
    searchpath_t *sp;

    NSLog(@"Current search path:");
    for (sp = self->searchPaths; sp; sp = sp->next) {
        if (sp->pack) {
            /*
            if (com_developer.GetBool()) {
                status = va( "%s (%i files - 0x%x %s", sp->pack->pakFilename.c_str(), sp->pack->numfiles, sp->pack->checksum, sp->pack->referenced ? "referenced" : "not referenced" );
                status += ")\n";
                common->Printf( "%s", status.c_str() );
            } else {*/
            NSLog(@"%@ (%d files)", sp->pack->pakFilename, sp->pack->numfiles);
            //}
        } else {
            NSLog(@"%@/%@", sp->dir->path, sp->dir->gamedir);
        }
    }
    /*
    NSLog(@"game DLL: 0x%x in pak: 0x%x\n", fileSystemLocal.gameDLLChecksum, fileSystemLocal.gamePakChecksum);
    for( i = 0; i < MAX_GAME_OS; i++ ) {
        if ( fileSystemLocal.gamePakForOS[ i ] ) {
            common->Printf( "OS %d - pak 0x%x\n", i, fileSystemLocal.gamePakForOS[ i ] );
        }
    }*/
}

#if 0
/*
============
idFileSystemLocal::GetOSMask
============
*/
int idFileSystemLocal::GetOSMask( void ) {
    int i, ret = 0;
    for( i = 0; i < MAX_GAME_OS; i++ ) {
        if ( fileSystemLocal.gamePakForOS[ i ] ) {
            ret |= ( 1 << i );
        }
    }
    if ( !ret ) {
        return -1;
    }
    return ret;
}

/*
============
idFileSystemLocal::TouchFile_f

The only purpose of this function is to allow game script files to copy
arbitrary files furing an "fs_copyfiles 1" run.
============
*/
void idFileSystemLocal::TouchFile_f( const idCmdArgs &args ) {
    idFile *f;

    if ( args.Argc() != 2 ) {
        common->Printf( "Usage: touchFile <file>\n" );
        return;
    }

    f = fileSystemLocal.OpenFileRead( args.Argv( 1 ) );
    if ( f ) {
        fileSystemLocal.CloseFile( f );
    }
}

/*
============
idFileSystemLocal::TouchFileList_f

Takes a text file and touches every file in it, use one file per line.
============
*/
void idFileSystemLocal::TouchFileList_f( const idCmdArgs &args ) {
    
    if ( args.Argc() != 2 ) {
        common->Printf( "Usage: touchFileList <filename>\n" );
        return;
    }

    const char *buffer = NULL;
    idParser src( LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT );
    if ( fileSystem->ReadFile( args.Argv( 1 ), ( void** )&buffer, NULL ) && buffer ) {
        src.LoadMemory( buffer, strlen( buffer ), args.Argv( 1 ) );
        if ( src.IsLoaded() ) {
            idToken token;
            while( src.ReadToken( &token ) ) {
                common->Printf( "%s\n", token.c_str() );
                session->UpdateScreen();
                idFile *f = fileSystemLocal.OpenFileRead( token );
                if ( f ) {
                    fileSystemLocal.CloseFile( f );
                }
            }
        }
    }

}
#endif

-(void)addGameDirectory:(NSString *)path dir:(NSString *)dir {
    int                         i;
    searchpath_t *              search;
    pack_t *                    pak;
    NSMutableString *           pakfile;
    NSMutableArray<NSString *> *pakfiles;

    // check if the search path already exists
    for (search = searchPaths; search; search = search->next) {
        // if this element is a pak file
        if (!search->dir) {
            continue;
        }
        if ([search->dir->path isEqualToString:path] && [search->dir->gamedir isEqualToString:dir]) {
            return;
        }
    }

    //
    // add the directory to the search path
    //
    search = [[searchpath_t alloc] init];
    search->dir = [[directory_t alloc] initWithPath:path gameDir:dir];
    search->pack = nil;
    search->next = searchPaths;
    searchPaths = search;

    // find all pak files in this directory
    pakfile = [[self buildOSPath:path
                            game:dir
                    relativePath:@""] mutableCopy];
    [pakfile ud_stripTrailingCharacter:'/'];
    [pakfile ud_stripTrailingCharacter:'\\'];
    
    pakfiles = [[NSMutableArray alloc] init];

    [self listOSFiles:pakfile extension:[@"." stringByAppendingString:_workspace.pakFileExtension] list:pakfiles];
    if (self.fs_debug) {
        NSLog(@"Found %d %@ file(s) in %@", (int)pakfiles.count, _workspace.pakFileExtension, pakfile);
    }

    // Sort them so later entries override earlier ones after they are inserted
    // into the search path. openQ4 reserves short pakN.pk4 names for its own
    // content, so those win over wider retail-style pakNNN.pk4 names.
    FS_SortPk4FilesForLoadOrder(pakfiles);

    for (i = 0; i < [pakfiles count]; i++ ) {
        
        NSString *pakFilename = [pakfiles objectAtIndex:i];
        
        [pakfile setString:[self buildOSPath:path game:dir relativePath:pakFilename]];
        pak = [self loadZipFile:pakfile];
        if (!pak) {
            continue;
        }
        // insert the pak after the directory it comes from
        search = [[searchpath_t alloc] init];
        search->dir = NULL;
        search->pack = pak;
        search->next = searchPaths->next;
        searchPaths->next = search;
        NSLog(@"Loaded %@ %@", _workspace.pakFileExtension, pakfile);
    }
}

-(void)setupGameDirectories:(NSString *)gameName {
    // setup savepath
    if (self.fs_savepath.length) {
        [self addGameDirectory:self.fs_savepath dir:gameName];
    }

    // setup basepath
    if (self.fs_basepath.length) {
        [self addGameDirectory:self.fs_basepath dir:gameName];
    }

    // setup cdpath last so it has highest search priority
    if (self.fs_cdpath.length) {
        [self addGameDirectory:self.fs_cdpath dir:gameName];
    }
}

#if 0
/*
================
idFileSystemLocal::NormalizeMapPath
================
*/
static bool FS_IsMapFilterWhitespace( const char ch ) {
    return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n';
}

static void FS_RemoveEmbeddedMapEntityFilter( idStr &mapName ) {
    mapName.BackSlashesToSlashes();
    mapName.Strip( ' ' );
    mapName.Strip( '\t' );
    mapName.StripTrailingWhitespace();
    mapName.StripQuotes();

    int split = -1;
    for ( int i = mapName.Length() - 1; i >= 0; --i ) {
        if ( FS_IsMapFilterWhitespace( mapName[ i ] ) ) {
            split = i;
            break;
        }
    }
    if ( split <= 0 ) {
        return;
    }

    idStr mapPart = mapName.Left( split );
    idStr filterPart = mapName.Right( mapName.Length() - split - 1 );
    mapPart.Strip( ' ' );
    mapPart.Strip( '\t' );
    mapPart.StripTrailingWhitespace();
    mapPart.StripQuotes();
    filterPart.Strip( ' ' );
    filterPart.Strip( '\t' );
    filterPart.StripTrailingWhitespace();
    filterPart.StripQuotes();

    if ( mapPart.Length() > 0 && filterPart.Length() > 0 ) {
        mapName = mapPart;
    }
}

bool idFileSystemLocal::NormalizeMapPath( const char *mapName, idStr &relativePath ) const {
    relativePath.Clear();

    if ( !mapName || !mapName[0] ) {
        return NO;
    }

    relativePath = mapName;
    FS_RemoveEmbeddedMapEntityFilter( relativePath );
    relativePath.StripFileExtension();
    if ( relativePath.Length() <= 0 ) {
        return NO;
    }

    if ( idStr::Icmpn( relativePath.c_str(), "maps/", 5 ) != 0 ) {
        relativePath = va( "maps/%s", relativePath.c_str() );
    }

    relativePath += ".map";
    relativePath.ToLower();
    return YES;
}
#endif

-(void)freePack:(pack_t *)pack {
    int i;

    if (pack == nil) {
        return;
    }

    if (pack->handle) {
        unzClose( pack->handle );
    }
    
    pack->buildBuffer = nil;
    for (i = 0; i < FILE_HASH_SIZE; i++) {
        pack->hashTable[i] = nil;
    }
    pack->handle = NULL;
}

#if 0
/*
================
idFileSystemLocal::IsGameDirPack
================
*/
bool idFileSystemLocal::IsGameDirPack( const pack_t *pak, const char *gameDir ) const {
    idStr path;
    idStr gameDirSegment;

    if ( !pak || !gameDir || !gameDir[ 0 ] ) {
        return NO;
    }

    path = pak->pakFilename;
    path.BackSlashesToSlashes();
    path.ToLower();

    gameDirSegment = "/";
    gameDirSegment += gameDir;
    gameDirSegment += "/";
    gameDirSegment.ToLower();

    if ( path.Find( gameDirSegment.c_str() ) >= 0 ) {
        return YES;
    }

    gameDirSegment.StripLeading( '/' );
    return !idStr::Icmpn( path.c_str(), gameDirSegment.c_str(), gameDirSegment.Length() );
}

/*
================
idFileSystemLocal::IsBaseGamePack
================
*/
bool idFileSystemLocal::IsBaseGamePack( const pack_t *pak ) const {
    return IsGameDirPack( pak, BASE_GAMEDIR );
}

/*
================
idFileSystemLocal::IsOpenQ4PurePack
================
*/
bool idFileSystemLocal::IsOpenQ4PurePack( const pack_t *pak ) const {
    idStr name;

    if ( !IsGameDirPack( pak, OPENQ4_GAMEDIR ) ) {
        return NO;
    }

    pak->pakFilename.ExtractFileName( name );
    return !name.Icmp( "pak0.pk4" ) || !name.Icmp( "pak1.pk4" );
}

/*
================
idFileSystemLocal::FindGamePackByName
================
*/
pack_t *idFileSystemLocal::FindGamePackByName( const char *name, const char *gameDir ) const {
    searchpath_t *search;
    idStr            pakName;

    for ( search = searchPaths; search; search = search->next ) {
        if ( !search->pack || !IsGameDirPack( search->pack, gameDir ) ) {
            continue;
        }
        search->pack->pakFilename.ExtractFileName( pakName );
        if ( !pakName.Icmp( name ) ) {
            return search->pack;
        }
    }
    return NULL;
}

/*
================
idFileSystemLocal::FindBaseGamePackByName
================
*/
pack_t *idFileSystemLocal::FindBaseGamePackByName( const char *name ) const {
    return FindGamePackByName( name, BASE_GAMEDIR );
}

/*
================
idFileSystemLocal::FindMisplacedOfficialPaks
================
*/
bool idFileSystemLocal::FindMisplacedOfficialPaks( idStr &errors ) const {
    const officialPk4Info_t    *info;
    pack_t                    *basePack;
    pack_t                    *openQ4Pack;

    errors.Clear();
    for ( int i = 0; officialPk4s[ i ].name != NULL; i++ ) {
        info = &officialPk4s[ i ];
        basePack = FindGamePackByName( info->name, BASE_GAMEDIR );
        openQ4Pack = FindGamePackByName( info->name, OPENQ4_GAMEDIR );
        if ( !openQ4Pack ) {
            continue;
        }

        if ( (unsigned int)openQ4Pack->checksum != info->checksum ) {
            errors += va( "%s was found in %s with checksum 0x%08x but belongs in %s (expected 0x%08x from %s)\n",
                info->name, OPENQ4_GAMEDIR, (unsigned int)openQ4Pack->checksum, BASE_GAMEDIR,
                info->checksum, openQ4Pack->pakFilename.c_str() );
            continue;
        }

        if ( basePack ) {
            errors += va( "%s was found in both %s and %s; remove the copy from %s (%s)\n",
                info->name, BASE_GAMEDIR, OPENQ4_GAMEDIR, OPENQ4_GAMEDIR, openQ4Pack->pakFilename.c_str() );
        } else {
            errors += va( "%s was found in %s but belongs in %s (%s)\n",
                info->name, OPENQ4_GAMEDIR, BASE_GAMEDIR, openQ4Pack->pakFilename.c_str() );
        }
    }

    return ( errors.Length() != 0 );
}

/*
================
idFileSystemLocal::ValidateOpenQ4Paks
================
*/
bool idFileSystemLocal::ValidateOpenQ4Paks( idStr &errors ) const {
    struct expectedOpenQ4Pak_t {
        const char *name;
        const char *md5;
    };
    static const expectedOpenQ4Pak_t expectedPaks[] = {
        { "pak0.pk4", OPENQ4_PAK0_MD5 },
        { "pak1.pk4", OPENQ4_PAK1_MD5 },
        { NULL, NULL }
    };

    errors.Clear();

    if ( idStr::Icmp( fs_game.GetString(), OPENQ4_GAMEDIR ) &&
         idStr::Icmp( fs_game_base.GetString(), OPENQ4_GAMEDIR ) ) {
        return YES;
    }

    for ( int i = 0; expectedPaks[ i ].name != NULL; i++ ) {
        const expectedOpenQ4Pak_t &expected = expectedPaks[ i ];
        pack_t *pack = FindGamePackByName( expected.name, OPENQ4_GAMEDIR );
        char actualMD5[33];

        if ( !pack ) {
            errors += va( "missing %s/%s (expected checksum %s)\n", OPENQ4_GAMEDIR, expected.name, expected.md5 );
            continue;
        }

        if ( !MD5_FileChecksum( pack->pakFilename.c_str(), actualMD5 ) ) {
            errors += va( "could not read %s for checksum validation\n", pack->pakFilename.c_str() );
            continue;
        }

        if ( idStr::Icmp( actualMD5, expected.md5 ) ) {
            errors += va( "checksum mismatch for %s/%s (expected %s, got %s from %s)\n",
                OPENQ4_GAMEDIR, expected.name, expected.md5, actualMD5, pack->pakFilename.c_str() );
        }
    }

    return ( errors.Length() == 0 );
}

/*
================
idFileSystemLocal::ValidateRequiredOfficialPaks
================
*/
bool idFileSystemLocal::ValidateRequiredOfficialPaks( idStr &errors ) const {
    const officialPk4Info_t    *info;
    pack_t                    *pack;

    errors.Clear();
    for ( int i = 0; officialPk4s[ i ].name != NULL; i++ ) {
        info = &officialPk4s[ i ];
        if ( !info->required ) {
            continue;
        }
        pack = FindBaseGamePackByName( info->name );
        if ( !pack ) {
            errors += va( "missing %s (expected 0x%08x)\n", info->name, info->checksum );
            continue;
        }
        if ( (unsigned int)pack->checksum != info->checksum ) {
            errors += va( "checksum mismatch for %s (expected 0x%08x, got 0x%08x from %s)\n",
                info->name, info->checksum, (unsigned int)pack->checksum, pack->pakFilename.c_str() );
        }
    }
    return ( errors.Length() == 0 );
}
#endif

-(BOOL)startup:(NSError **)error {
    //searchpath_t    **search;
    //int                i;
    //pack_t            *pak;
    //int                addon_index;

    NSLog(@"------ Initializing File System ------");
    

    //if ( restartChecksums.Num() ) {
    //    common->Printf( "restarting in pure mode with %d pak files\n", restartChecksums.Num() );
    //}

    NSMutableString *invalidReason = [[NSMutableString alloc] init];
    if (self.fs_game_base.length &&
         [self.fs_game_base caseInsensitiveCompare:self.gamedir] != NSOrderedSame &&
        ![self validateConfiguredGameDir:self.fs_game_base reason:invalidReason]) {
        NSLog(@"WARN: ignoring fs_game_base '%@': %@", self.fs_game_base, invalidReason);
        self.workspace.fs_game_base = @"";
    }

    if (self.fs_game.length &&
         [self.fs_game caseInsensitiveCompare:self.gamedir] != NSOrderedSame &&
        ![self validateConfiguredGameDir:self.fs_game reason:invalidReason]) {

        NSLog(@"WARN: ignoring fs_game '%@': %@", self.fs_game, invalidReason);
        self.workspace.fs_game = @"";
    }

    // File writes should use the selected game directory even while search paths
    // are still being populated. Pak-load diagnostics can open logFile as soon
    // as the first q4base search path exists.
    [gameFolder setString:@""];
    if (self.fs_game.length && [self.fs_game caseInsensitiveCompare:self.gamedir] != NSOrderedSame) {
        [gameFolder setString:self.fs_game];
    } else if (self.fs_game_base.length && [self.fs_game_base caseInsensitiveCompare:self.gamedir] != NSOrderedSame) {
        [gameFolder setString:self.fs_game_base];
    } else {
        [gameFolder setString:self.gamedir];
    }

    [self setupGameDirectories:self.gamedir];

    // fs_game_base override
    if (self.fs_game_base.length && [self.fs_game_base caseInsensitiveCompare:self.gamedir] != NSOrderedSame) {
        [self setupGameDirectories:self.fs_game_base];
    }

    // fs_game override
    if (self.fs_game.length &&
        [self.fs_game caseInsensitiveCompare:self.gamedir] != NSOrderedSame &&
        [self.fs_game caseInsensitiveCompare:self.fs_game_base] != NSOrderedSame) {
        [self setupGameDirectories:self.fs_game];
    }

    // add our commands
    /*
    cmdSystem->AddCommand( "dir", Dir_f, CMD_FL_SYSTEM, "lists a folder", idCmdSystem::ArgCompletion_FileName );
    cmdSystem->AddCommand( "dirtree", DirTree_f, CMD_FL_SYSTEM, "lists a folder with subfolders" );
    cmdSystem->AddCommand( "path", Path_f, CMD_FL_SYSTEM, "lists search paths" );
    cmdSystem->AddCommand( "touchFile", TouchFile_f, CMD_FL_SYSTEM, "touches a file" );
    cmdSystem->AddCommand( "touchFileList", TouchFileList_f, CMD_FL_SYSTEM, "touches a list of files" );
    */

    // print the current search paths
    [self path_f];

    NSLog(@"file system initialized.");
    NSLog(@"--------------------------------------");
    
    // see if we are going to allow add-ons
    //SetRestrictions();

    // spawn a thread to handle background file reads
    //StartBackgroundDownloadThread();

    //currentAssetLog = "assetlogs/default";
    //currentAssetLogUnfiltered = "assetlogs/default";

    /*
    // if we can't find default.cfg, assume that the paths are
    // busted and error out now, rather than getting an unreadable
    // graphics screen when the font fails to load
    // Dedicated servers can run with no outside files at all
    if ( ReadFile( "default.cfg", NULL, NULL ) <= 0 ) {
        common->FatalError(
            "openQ4 startup config 'default.cfg' could not be loaded.\n\n"
            "Rebuild or reinstall openQ4 so '%s/pak0.pk4' contains the runtime config files, and keep retail Quake 4 media PK4s in '%s'.",
            OPENQ4_GAMEDIR, BASE_GAMEDIR );
    }*/
    
    return YES;
}

#if 0
/*
===================
idFileSystemLocal::SetRestrictions

Looks for product keys and restricts media add on ability
if the full version is not found
===================
*/
void idFileSystemLocal::SetRestrictions( void ) {
#ifdef ID_DEMO_BUILD
    common->Printf( "\nRunning in restricted demo mode.\n\n" );
    // make sure that the pak file has the header checksum we expect
    searchpath_t    *search;
    for ( search = searchPaths; search; search = search->next ) {
        if ( search->pack ) {
            // a tiny attempt to keep the checksum from being scannable from the exe
            if ( ( search->pack->checksum ^ 0x84268436u ) != ( DEMO_PAK_CHECKSUM ^ 0x84268436u ) ) {
                return;
            }
        }
    }
    cvarSystem->SetCVarBool( "fs_restrict", YES );
#endif
}

/*
=====================
idFileSystemLocal::UpdatePureServerChecksums
=====================
*/
void idFileSystemLocal::UpdatePureServerChecksums( void ) {
    searchpath_t    *search;
    int                i;
    pureStatus_t    status;

    serverPaks.Clear();
    for ( search = searchPaths; search; search = search->next ) {
        // is the element a referenced pak file?
        if ( !search->pack ) {
            continue;
        }
        status = GetPackStatus( search->pack );
        if ( status == PURE_NEVER ) {
            continue;
        }
        if ( status == PURE_NEUTRAL && !search->pack->referenced ) {
            continue;
        }
        serverPaks.Append( search->pack );
        if ( serverPaks.Num() >= MAX_PURE_PAKS ) {
            common->FatalError( "MAX_PURE_PAKS ( %d ) exceeded\n", MAX_PURE_PAKS );
        }
    }
    if ( fs_debug.GetBool() ) {
        idStr checks;
        for ( i = 0; i < serverPaks.Num(); i++ ) {
            checks += va( "%x ", serverPaks[ i ]->checksum );
        }
        common->Printf( "set pure list - %d paks ( %s)\n", serverPaks.Num(), checks.c_str() );
    }
}

/*
=====================
idFileSystemLocal::UpdateGamePakChecksums
=====================
*/
bool idFileSystemLocal::UpdateGamePakChecksums( void ) {
    searchpath_t    *search;
    fileInPack_t    *pakFile;
    int                confHash;
    idFile            *confFile;
    char            *buf;
    idLexer            *lexConf;
    idToken            token;
    int                id;

    confHash = HashFileName( BINARY_CONFIG );

    memset( gamePakForOS, 0, sizeof( gamePakForOS ) );
    for ( search = searchPaths; search; search = search->next ) {
        if ( !search->pack ) {
            continue;
        }
        search->pack->binary = BINARY_NO;
        for ( pakFile = search->pack->hashTable[confHash]; pakFile; pakFile = pakFile->next ) {
            if ( !FilenameCompare( pakFile->name, BINARY_CONFIG ) ) {
                search->pack->binary = BINARY_YES;
                confFile = ReadFileFromZip( search->pack, pakFile, BINARY_CONFIG );
                buf = new char[ confFile->Length() + 1 ];
                confFile->Read( (void *)buf, confFile->Length() );
                buf[ confFile->Length() ] = '\0';
                lexConf = new idLexer( buf, confFile->Length(), confFile->GetFullPath() );
                while ( lexConf->ReadToken( &token ) ) {
                    if ( token.IsNumeric() ) {
                        id = atoi( token );
                        if ( id < MAX_GAME_OS && !gamePakForOS[ id ] ) {
                            if ( fs_debug.GetBool() ) {
                                common->Printf( "Adding game pak checksum for OS %d: %s 0x%x\n", id, confFile->GetFullPath(), search->pack->checksum );
                            }
                             gamePakForOS[ id ] = search->pack->checksum;
                        }
                    }
                }
                CloseFile( confFile );
                delete lexConf;
                delete[] buf;
            }
        }
    }

    // some sanity checks on the game code references
    // make sure that at least the local OS got a pure reference
    if ( !gamePakForOS[ BUILD_OS_ID ] ) {
        common->Warning( "No game code pak reference found for the local OS" );
        return NO;
    }

    if ( !cvarSystem->GetCVarBool( "net_serverAllowServerMod" ) &&
        gamePakChecksum != gamePakForOS[ BUILD_OS_ID ] ) {
        common->Warning( "The current game code doesn't match pak files (net_serverAllowServerMod is off)" );
        return NO;
    }

    return YES;
}

/*
=====================
idFileSystemLocal::GetPackForChecksum
=====================
*/
pack_t* idFileSystemLocal::GetPackForChecksum( int checksum, bool searchAddons ) {
    searchpath_t    *search;
    for ( search = searchPaths; search; search = search->next ) {
        if ( !search->pack ) {
            continue;
        }
        if ( search->pack->checksum == checksum ) {
            return search->pack;
        }
    }
    return NULL;
}

/*
===============
idFileSystemLocal::ValidateDownloadPakForChecksum
===============
*/
int idFileSystemLocal::ValidateDownloadPakForChecksum( int checksum, char path[ MAX_STRING_CHARS ], bool isBinary ) {
    int            i;
    idStrList    testList;
    idStr        name;
    idStr        relativePath;
    bool        pakBinary;
    pack_t        *pak = GetPackForChecksum( checksum );

    if ( !pak ) {
        return 0;
    }

    // validate this pak for a potential download
    // ignore pak*.pk4 for download. those are reserved to distribution and cannot be downloaded
    name = pak->pakFilename;
    name.StripPath();
    if ( strstr( name.c_str(), "pak" ) == name.c_str() ) {
        common->DPrintf( "%s is not a donwloadable pak\n", pak->pakFilename.c_str() );
        return 0;
    }
    // check the binary
    // a pure server sets the binary flag when starting the game
    assert( pak->binary != BINARY_UNKNOWN );
    pakBinary = ( pak->binary == BINARY_YES ) ? YES : NO;
    if ( isBinary != pakBinary ) {
        common->DPrintf( "%s binary flag mismatch\n", pak->pakFilename.c_str() );
        return 0;
    }

    // extract a path that includes the fs_game: != OSPathToRelativePath
    testList.Append( fs_cdpath.GetString() );
    testList.Append( fs_basepath.GetString() );
    testList.Append( fs_savepath.GetString() );
    for ( i = 0; i < testList.Num(); i ++ ) {
        if ( testList[ i ].Length() && !testList[ i ].Icmpn( pak->pakFilename, testList[ i ].Length() ) ) {
            relativePath = pak->pakFilename.c_str() + testList[ i ].Length() + 1;
            break;
        }
    }
    if ( i == testList.Num() ) {
        common->Warning( "idFileSystem::ValidateDownloadPak: failed to extract relative path for %s", pak->pakFilename.c_str() );
        return 0;
    }
    idStr::Copynz( path, relativePath, MAX_STRING_CHARS );
    return pak->length;
}

/*
=====================
idFileSystemLocal::ClearPureChecksums
=====================
*/
void idFileSystemLocal::ClearPureChecksums( void ) {
    common->DPrintf( "Cleared pure server lock\n" );
    serverPaks.Clear();
}

/*
=====================
idFileSystemLocal::SetPureServerChecksums
set the pure paks according to what the server asks
if that's not possible, identify why and build an answer
can be:
  loadedFileFromDir - some files were loaded from directories instead of paks (a restart in pure pak-only is required)
  missing/wrong checksums - some pak files would need to be installed/updated (downloaded for instance)
  some pak files currently referenced are not referenced by the server
  wrong order - if the pak order doesn't match, means some stuff could have been loaded from somewhere else
server referenced files are prepended to the list if possible ( that doesn't break pureness )
DLL:
  the checksum of the pak containing the DLL is maintained seperately, the server can send different replies by OS
=====================
*/
fsPureReply_t idFileSystemLocal::SetPureServerChecksums( const int pureChecksums[ MAX_PURE_PAKS ], int _gamePakChecksum, int missingChecksums[ MAX_PURE_PAKS ], int *missingGamePakChecksum ) {
    pack_t            *pack;
    int                i, j, imissing;
    bool            success = YES;
    bool            canPrepend = YES;
    char            dllName[MAX_OSPATH];
    int                dllHash;
    fileInPack_t *    pakFile;

    sys->DLL_GetFileName( "game", dllName, MAX_OSPATH );
    dllHash = HashFileName( dllName );

    imissing = 0;
    missingChecksums[ 0 ] = 0;
    assert( missingGamePakChecksum );
    *missingGamePakChecksum = 0;

    if ( pureChecksums[ 0 ] == 0 ) {
        ClearPureChecksums();
        return PURE_OK;
    }

    if ( !serverPaks.Num() ) {
        // there was no pure lockdown yet - lock to what we already have
        UpdatePureServerChecksums();
    }
    i = 0; j = 0;
    while ( pureChecksums[ i ] ) {
        if ( j < serverPaks.Num() && serverPaks[ j ]->checksum == pureChecksums[ i ] ) {
            canPrepend = NO; // once you start matching into the list there is no prepending anymore
            i++; j++; // the pak is matched, is in the right order, continue..
        } else {
            pack = GetPackForChecksum( pureChecksums[ i ], YES );

            if ( pack && pack->isNew ) {
                // that's a downloaded pack, we will need to restart
                if ( fs_debug.GetBool() ) {
                    common->Printf( "pak %s checksumed 0x%x is a newly downloaded file. Restart required.\n", pack->pakFilename.c_str(), pack->checksum );
                }
                success = NO;
            }
            if ( pack ) {
                if ( canPrepend ) {
                    // we still have a chance
                    if ( fs_debug.GetBool() ) {
                        common->Printf( "prepend pak %s checksumed 0x%x at index %d\n", pack->pakFilename.c_str(), pack->checksum, j );
                    }
                    // NOTE: there is a light possibility this adds at the end of the list if UpdatePureServerChecksums didn't set anything
                    serverPaks.Insert( pack, j );
                    i++; j++; // continue..
                } else {
                    success = NO;
                    if ( fs_debug.GetBool() ) {
                        // verbose the situation
                        if ( serverPaks.Find( pack ) ) {
                            common->Printf( "pak %s checksumed 0x%x is in the pure list at wrong index. Current index is %d, found at %d\n", pack->pakFilename.c_str(), pack->checksum, j, serverPaks.FindIndex( pack ) );
                        } else {
                            common->Printf( "pak %s checksumed 0x%x can't be added to pure list because of search order\n", pack->pakFilename.c_str(), pack->checksum );
                        }
                    }
                    i++; // advance server checksums only
                }
            } else {
                // didn't find a matching checksum
                success = NO;
                missingChecksums[ imissing++ ] = pureChecksums[ i ];
                missingChecksums[ imissing ] = 0;
                if ( fs_debug.GetBool() ) {
                    common->Printf( "checksum not found - 0x%x\n", pureChecksums[ i ] );
                }
                i++; // advance the server checksums only
            }
        }
    }
    while ( j < serverPaks.Num() ) {
        success = NO; // just in case some extra pak files are referenced at the end of our local list
        if ( fs_debug.GetBool() ) {
            common->Printf( "pak %s checksumed 0x%x is an extra reference at the end of local pure list\n", serverPaks[ j ]->pakFilename.c_str(), serverPaks[ j ]->checksum );
        }
        j++;
    }

    // DLL checksuming
    if ( !_gamePakChecksum ) {
        // server doesn't have knowledge of code we can use ( OS issue )
        return PURE_NODLL;
    }
    assert( gameDLLChecksum );
#if ID_FAKE_PURE
    gamePakChecksum = _gamePakChecksum;
#endif
    if ( _gamePakChecksum != gamePakChecksum ) {
        // current DLL is wrong, search for a pak with the approriate checksum
        // ( search all paks, the pure list is not relevant here )
        pack = GetPackForChecksum( _gamePakChecksum );
        if ( !pack ) {
            if ( fs_debug.GetBool() ) {
                common->Printf( "missing the game code pak ( 0x%x )\n", _gamePakChecksum );
            }
            // if there are other paks missing they have also been marked above
            *missingGamePakChecksum = _gamePakChecksum;
            return PURE_MISSING;
        }
        // if assets paks are missing, don't try any of the DLL restart / NODLL
        if ( imissing ) {
            return PURE_MISSING;
        }
        // we have a matching pak
        if ( fs_debug.GetBool() ) {
            common->Printf( "server's game code pak candidate is '%s' ( 0x%x )\n", pack->pakFilename.c_str(), pack->checksum );
        }
        // make sure there is a valid DLL for us
        if ( pack->hashTable[ dllHash ] ) {
            for ( pakFile = pack->hashTable[ dllHash ]; pakFile; pakFile = pakFile->next ) {
                if ( !FilenameCompare( pakFile->name, dllName ) ) {
                    gamePakChecksum = _gamePakChecksum;        // this will be used to extract the DLL in pure mode FindDLL
                    return PURE_RESTART;
                }
            }
        }
        common->Warning( "media is misconfigured. server claims pak '%s' ( 0x%x ) has media for us, but '%s' is not found\n", pack->pakFilename.c_str(), pack->checksum, dllName );
        return PURE_NODLL;
    }

    // we reply to missing after DLL check so it can be part of the list
    if ( imissing ) {
        return PURE_MISSING;
    }

    // one last check
    if ( loadedFileFromDir ) {
        success = NO;
        if ( fs_debug.GetBool() ) {
            common->Printf( "SetPureServerChecksums: there are files loaded from dir\n" );
        }
    }
    return ( success ? PURE_OK : PURE_RESTART );
}

/*
=====================
idFileSystemLocal::GetPureServerChecksums
=====================
*/
void idFileSystemLocal::GetPureServerChecksums( int checksums[ MAX_PURE_PAKS ], int OS, int *_gamePakChecksum ) {
    int i;

    for ( i = 0; i < serverPaks.Num(); i++ ) {
        checksums[ i ] = serverPaks[ i ]->checksum;
    }
    checksums[ i ] = 0;
    if ( _gamePakChecksum ) {
        if ( OS >= 0 ) {
            *_gamePakChecksum = gamePakForOS[ OS ];
        } else {
            *_gamePakChecksum = gamePakChecksum;
        }
    }
}

/*
=====================
idFileSystemLocal::SetRestartChecksums
=====================
*/
void idFileSystemLocal::SetRestartChecksums( const int pureChecksums[ MAX_PURE_PAKS ], int gamePakChecksum ) {
    int        i;
    pack_t    *pack;

    restartChecksums.Clear();
    i = 0;
    while ( pureChecksums[ i ] ) {
        pack = GetPackForChecksum( pureChecksums[ i ], YES );
        if ( !pack ) {
            common->FatalError( "SetRestartChecksums failed: no pak for checksum 0x%x\n", pureChecksums[i] );
        }

        restartChecksums.Append( pureChecksums[ i ] );
        i++;
    }
    restartGamePakChecksum = gamePakChecksum;
}
#endif

- (NSString *)gamedir               { return self.workspace.gamedir; }
- (BOOL)fs_debug                    { return self.workspace.fs_debug; }
- (BOOL)fs_restrict                 { return self.workspace.fs_restrict; }
- (int)fs_copyfiles                 { return self.workspace.fs_copyfiles; }
- (NSString *)fs_basepath           { return self.workspace.fs_basepath; }
- (NSString *)fs_homepath           { return self.workspace.fs_homepath; }
- (NSString *)fs_savepath           { return self.workspace.fs_savepath; }
- (NSString *)fs_cdpath             { return self.workspace.fs_cdpath; }
- (NSString *)fs_game               { return self.workspace.fs_game; }
- (NSString *)fs_game_base          { return self.workspace.fs_game_base; }
- (BOOL)fs_caseSensitiveOS          { return self.workspace.fs_caseSensitiveOS; }

-(instancetype)initWithWorkspace:(UDWorkspace *)workspace {
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _workspace = workspace;
    
    searchPaths = nil;
    readCount = 0;
    loadCount = 0;
    loadStack = 0;
    gameFolder = [[NSMutableString alloc] init];
    dir_cache_index = 0;
    dir_cache_count = 0;
    for (int i = 0; i < MAX_CACHED_DIRS; i++) {
        dir_cache[i] = nil;
    }
    loadedFileFromDir = NO;
    //restartGamePakChecksum = 0;
    isFileLoadingAllowed = NO;
    //currentAssetLog.Clear();
    //currentAssetLogUnfiltered.Clear();
    //assetLog.Clear();
    //backgroundDownloads = NULL;
    //memset( &defaultBackgroundDownload, 0, sizeof( defaultBackgroundDownload ) );
    //memset( &backgroundThread, 0, sizeof( backgroundThread ) );

    
    /*
    // allow command line parms to override our defaults
    // we have to specially handle this, because normal command
    // line variable sets don't happen until after the filesystem
    // has already been initialized
    common->StartupVariable( "fs_basepath", NO );
    common->StartupVariable( "fs_homepath", NO );
    common->StartupVariable( "fs_savepath", NO );
    common->StartupVariable( "fs_game", NO );
    common->StartupVariable( "fs_game_base", NO );
    common->StartupVariable( "fs_copyfiles", NO );
    common->StartupVariable( "fs_restrict", NO );
    */

    if (self.fs_basepath.length == 0) {
        self.workspace.fs_basepath = Sys_DefaultBasePath();
    }

    // fs_homepath is the user-writable root; fs_savepath follows it when unset.
    if (self.fs_homepath.length == 0) {
        if (self.fs_savepath.length) {
            self.workspace.fs_homepath = self.fs_savepath;
        } else {
            self.workspace.fs_homepath = Sys_DefaultSavePath();
        }
    }
    if (self.fs_savepath.length == 0) {
        self.workspace.fs_savepath = self.fs_homepath;
    }
    // allow cd path to be changed
    if (self.fs_cdpath.length == 0) {
        self.workspace.fs_cdpath = Sys_DefaultCDPath();
    }

    NSLog(
        @"Filesystem paths: fs_basepath='%@' fs_homepath='%@' fs_savepath='%@' fs_cdpath='%@' fs_game='%@' fs_game_base='%@'",
        self.fs_basepath,
        self.fs_homepath,
        self.fs_savepath,
        self.fs_cdpath,
        self.fs_game,
        self.fs_game_base);

    return self;
}

-(void)dealloc {
    if (self.isInitialized) {
        [self shutdown:YES];
    }
}

-(void)restart {
    // free anything we currently have loaded
    [self shutdown:YES];

    [self startup:nil];

    // see if we are going to allow add-ons
    //SetRestrictions();

    /*
    // if we can't find default.cfg, assume that the paths are
    // busted and error out now, rather than getting an unreadable
    // graphics screen when the font fails to load
    if ( ReadFile( "default.cfg", NULL, NULL ) <= 0 ) {
        common->FatalError(
            "openQ4 startup config 'default.cfg' could not be loaded after filesystem restart.\n\n"
            "Rebuild or reinstall openQ4 so '%s/pak0.pk4' contains the runtime config files, and keep retail Quake 4 media PK4s in '%s'.",
            OPENQ4_GAMEDIR, BASE_GAMEDIR );
    }*/
}

-(void)shutdown:(BOOL)reloading {
    searchpath_t *sp, *next;

    //StopBackgroundDownloadThread();

    [gameFolder setString:@""];

    //serverPaks.Clear();
    if ( !reloading ) {
        //restartChecksums.Clear();
        //addonChecksums.Clear();
    }
    loadedFileFromDir = NO;
    //gameDLLChecksum = 0;
    //gamePakChecksum = 0;

    [self clearDirCache];

    // free everything - loop through searchPaths and addonPaks
    for (sp = searchPaths; sp; sp = next) {
        next = sp->next;

        if (sp->pack) {
            [self freePack:sp->pack];
        }
        sp->dir = nil;
        sp->pack = nil;
        sp->next = nil;
    }

    // any FS_ calls will now be an error until reinitialized
    searchPaths = nil;

    /*
    cmdSystem->RemoveCommand( "path" );
    cmdSystem->RemoveCommand( "dir" );
    cmdSystem->RemoveCommand( "dirtree" );
    cmdSystem->RemoveCommand( "touchFile" );

    mapDict.Clear();
    */
}

-(BOOL)isInitialized {
    return (searchPaths != NULL);
}

-(BOOL)performingCopyFiles {
    return self.fs_copyfiles > 0;
}

/*
=================================================================================

Opening files

=================================================================================
*/

#if 0
/*
===========
idFileSystemLocal::FileAllowedFromDir
===========
*/
bool idFileSystemLocal::FileAllowedFromDir( const char *path ) {
    unsigned int l;

    if ( path == NULL ) {
        return NO;
    }

    l = strlen( path );
    if ( l == 0 ) {
        return NO;
    }

    if ( ( l >= 4 && !strcmp( path + l - 4, ".cfg" ) )        // for config files
        || ( l >= 4 && !strcmp( path + l - 4, ".dat" ) )        // for journal files
        || ( l >= 4 && !strcmp( path + l - 4, ".dll" ) )        // dynamic modules are handled a different way for pure
        || ( l >= 3 && !strcmp( path + l - 3, ".so" ) )
        || ( l >= 6 && !strcmp( path + l - 6, ".dylib" ) )
        || ( l >= 10 && !strcmp( path + l - 10, ".scriptcfg" ) )    // configuration script, such as map cycle
#if ID_PURE_ALLOWDDS
         || ( l >= 4 && !strcmp( path + l - 4, ".dds" ) )
#endif
         ) {
        // note: cd and xp keys, as well as config.spec are opened through an explicit OS path and don't hit this
        return YES;
    }
    // savegames
    if ( strstr( path, "savegames" ) == path &&
        ( ( l >= 4 && !strcmp( path + l - 4, ".tga" ) ) || ( l >= 4 && !strcmp( path + l -4, ".txt" ) ) || ( l >= 5 && !strcmp( path + l - 5, ".save" ) ) ) ) {
        return YES;
    }
    // screen shots
    if ( strstr( path, "screenshots" ) == path && l >= 4 && !strcmp( path + l - 4, ".tga" ) ) {
        return YES;
    }
    // objective tgas
    if ( strstr( path, "maps/game" ) == path &&
        l >= 4 && !strcmp( path + l - 4, ".tga" ) ) {
        return YES;
    }
    // splash screens extracted from addons
    if ( strstr( path, "guis/assets/splash/addon" ) == path &&
         l >= 4 && !strcmp( path + l -4, ".tga" ) ) {
        return YES;
    }

    return NO;
}

/*
===========
idFileSystemLocal::GetPackStatus
===========
*/
pureStatus_t idFileSystemLocal::GetPackStatus( pack_t *pak ) {
    int                i, l, hashindex;
    fileInPack_t    *file;
    bool            abrt;
    NSString        *name;
    const officialPk4Info_t *officialInfo;

    if ( pak->pureStatus != PURE_UNKNOWN ) {
        return pak->pureStatus;
    }

    // Keep openQ4's canonical runtime pack in the pure list no matter its content mix.
    name = [pak->pakFilename lastPathComponent];
    if ( IsOpenQ4PurePack( pak ) ) {
        pak->pureStatus = PURE_ALWAYS;
        return PURE_ALWAYS;
    }

    // Keep the stock Quake 4 base media in the pure list no matter their contents.
    officialInfo = FindOfficialPk4Info( [name UTF8String] );
    if ( officialInfo && officialInfo->pureBase ) {
        pak->pureStatus = PURE_ALWAYS;
        return PURE_ALWAYS;
    }

    // check content for PURE_NEVER
    i = 0;
    for ( hashindex = 0; hashindex < FILE_HASH_SIZE; hashindex++ ) {
        abrt = NO;
        file = pak->hashTable[ hashindex ];
        while ( file ) {
            l = (int)file->name.length;
            abrt = [UDExclusionManager excludeName:file->name length:l];
            /*
            abrt = YES;
                common->DPrintf( "pak '%s' candidate for pure: '%s'\n", [pak->pakFilename cString], [file->name cString] );
                if ( pureExclusions[j].func( pureExclusions[j], l, file->name ) ) {
                    abrt = NO;
                    break;
                }
            }*/
            if ( abrt ) {
                common->DPrintf( "pak '%s' candidate for pure: '%s'\n", pak->pakFilename.c_str(), file->name.c_str() );
                break;
            }
            file = file->next;
            i++;
        }
        if ( abrt ) {
            break;
        }
    }
    if ( i == pak->numfiles ) {
        pak->pureStatus = PURE_NEVER;
        return PURE_NEVER;
    }

    // check pak name for PURE_ALWAYS
    if ( !name.IcmpPrefixPath( "pak" ) ) {
        pak->pureStatus = PURE_ALWAYS;
        return PURE_ALWAYS;
    }

    pak->pureStatus = PURE_NEUTRAL;
    return PURE_NEUTRAL;
}
#endif

-(idFile_InZip *)readFileFromZip:(pack_t *)pak pakFile:(fileInPack_t *)pakFile relativePath:(NSString *)relativePath error:(NSError **)error {
    voidpf            fp;
    
    // open a new file on the pakfile
    unzFile *zfi = unzReOpen([pak->pakFilename UTF8String], pak->handle);
    if (zfi == NULL) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeReadFailed,
                                @"Failed to reopen archive '%@' while reading '%s'.",
                                pak->pakFilename,
                                relativePath);
        return nil;
    }
    idFile_InZip *file = [[idFile_InZip alloc] initWithUnzipInfo:zfi
                                                            name:relativePath
                                                     pakFilename:pak->pakFilename
                                                      fileSystem:self];
    // in case the file was new
    fp = unzGetFileStream(zfi);
    // set the file position in the zip file (also sets the current file info)
    unzSetCurrentFileInfoPosition(pak->handle, pakFile->pos);
    // copy the file info into the unzip structure
    unzCopyFileHandle(zfi, pak->handle);
    // we copy this back into the structure
    unzSetFileStream(zfi, fp);
    // open the file in the zip
    [file openCurrentFileAt:pakFile->pos];
    return file;
}

-(idFile *)openFileReadFlags:(NSString *)relativePath flags:(int)searchFlags found:(pack_t **)foundInPak copyFiles:(BOOL)allowCopyFiles gameDir:(NSString *)gamedir error:(NSError **)error {
    searchpath_t *    search;
    pack_t *        pak;
    fileInPack_t *    pakFile;
    directory_t *    dir;
    long            hash;
    FILE *            fp;
    
    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return nil;
    }

    if (!relativePath || !relativePath.length) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"openFileRead called with a nil relative path.");
        return nil;
    }

    if (foundInPak) {
        *foundInPak = NULL;
    }

    // qpaths are not supposed to have a leading slash
    if ([relativePath characterAtIndex:0] == '/' || [relativePath characterAtIndex:0] == '\\') {
        relativePath = [relativePath substringFromIndex:1];
    }

    // make absolutely sure that it can't back up the path.
    // The searchpaths do guarantee that something will always
    // be prepended, so we don't need to worry about "c:" or "//limbo"
    if ([relativePath containsString:@".."] || [relativePath containsString:@"::"]) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidPath,
                                @"Refusing to open unsafe relative path '%s'.",
                                relativePath);
        return nil;
    }
    
    // edge case
    if (relativePath.length == 0) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"openFileRead called with an empty relative path.");
        return nil;
    }

    //
    // search through the path, one element at a time
    //

    hash = [self hashFileName:relativePath];

    NSMutableString *netpath = [[NSMutableString alloc] init];

    for (search = searchPaths; search; search = search->next) {
        if (search->dir && (searchFlags & FSFLAG_SEARCH_DIRS)) {
            // check a file in the directory tree

            /*
            // if we are running restricted, the only files we
            // will allow to come from the directory are .cfg files
            if (fs_restrict) {
                if ( !FileAllowedFromDir( relativePath ) ) {
                    continue;
                }
            }*/

            dir = search->dir;

            if (gamedir && gamedir.length) {
                if (![dir->gamedir isEqualToString:gamedir]) {
                    continue;
                }
            }
            
            [netpath setString:[self buildOSPath:dir->path
                                            game:dir->gamedir
                                    relativePath:relativePath]];
            
            fp = [self openOSFileCorrectName:netpath mode:"rb"];
            if (!fp) {
                continue;
            }

            idFile_Permanent *file = [[idFile_Permanent alloc] initWithHandle:fp
                                                                         name:relativePath
                                                                     fullPath:netpath
                                                                         mode:(1 << FS_READ)
                                                                         sync:NO
                                                                     fileSize:directFileLength(fp)
                                                                   fileSystem:self];
            
            if (self.fs_debug) {
                NSLog(@"openFileReadFlags:flags:found:copyFiles: %@ (found in '%@/%@')\n", relativePath, dir->path, dir->gamedir);
            }

            /*
            if ( !loadedFileFromDir && !FileAllowedFromDir( relativePath ) ) {
                if ( restartChecksums.Num() ) {
                    common->FatalError( "'%s' loaded from directory: Failed to restart with pure mode restrictions for server connect", relativePath );
                }
                common->DPrintf( "filesystem: switching to pure mode will require a restart. '%s' loaded from directory.\n", relativePath );
                loadedFileFromDir = YES;
            }*/

            // if fs_copyfiles is set
            if (allowCopyFiles && self.fs_copyfiles) {

                NSMutableString *copypath = [[self buildOSPath:self.fs_savepath
                                                          game:dir->gamedir
                                                  relativePath:relativePath] mutableCopy];
                NSMutableString *name = [[netpath lastPathComponent] mutableCopy];
                [copypath ud_stripLastPathComponentCompat];
                [copypath ud_appendPathComponent:name];

                BOOL isFromCDPath = [dir->path isEqualToString:self.fs_cdpath];
                BOOL isFromSavePath = [dir->path isEqualToString:self.fs_savepath];
                BOOL isFromBasePath = [dir->path isEqualToString:self.fs_basepath];

                switch (self.fs_copyfiles) {
                    case 1:
                        // copy from cd path only
                        if (isFromCDPath) {
                            if (![self copyFileFrom:netpath to:copypath error:error]) {
                                return nil;
                            }
                        }
                        break;
                    case 2:
                        // from cd path + timestamps
                        if (isFromCDPath) {
                            if (![self copyFileFrom:netpath to:copypath error:error]) {
                                return nil;
                            }
                        } else if (isFromSavePath || isFromBasePath) {
                            NSMutableString *sourcepath = [[self buildOSPath:self.fs_cdpath
                                                                        game:dir->gamedir
                                                                relativePath:relativePath] mutableCopy];
                            
                            FILE *f1 = [self openOSFile:sourcepath mode:"r" caseSensitiveName:NULL];
                            if (f1) {
                                unsigned int t1 = Sys_FileTimeStamp(f1);
                                fclose(f1);
                                
                                FILE *f2 = [self openOSFile:copypath mode:"r" caseSensitiveName:NULL];
                                if (f2) {
                                    unsigned int t2 = Sys_FileTimeStamp(f2);
                                    fclose( f2 );
                                    if (t1 > t2) {
                                        if (![self copyFileFrom:sourcepath to:copypath error:error]) {
                                            return nil;
                                        }
                                    }
                                }
                            }
                        }
                        break;
                    case 3:
                        if (isFromCDPath || isFromBasePath) {
                            if (![self copyFileFrom:netpath to:copypath error:error]) {
                                return nil;
                            }
                        }
                        break;
                    case 4:
                        if ( isFromCDPath && !isFromBasePath ) {
                            if (![self copyFileFrom:netpath to:copypath error:error]) {
                                return nil;
                            }
                        }
                        break;
                }
            }

            //AddAssetLogEntry( relativePath );
            return file;
        } else if (search->pack && (searchFlags & FSFLAG_SEARCH_PAKS)) {

            if (!search->pack->hashTable[hash]) {
                continue;
            }

            /*
            // disregard if it doesn't match one of the allowed pure pak files
            if (serverPaks.Num() ) {
                GetPackStatus( search->pack );
                if ( search->pack->pureStatus != PURE_NEVER && !serverPaks.Find( search->pack ) ) {
                    continue; // not on the pure server pak list
                }
            }
            */

            // look through all the pak file elements
            pak = search->pack;

            /*
            if (searchFlags & FSFLAG_BINARY_ONLY) {
                // make sure this pak is tagged as a binary file
                if ( pak->binary == BINARY_UNKNOWN ) {
                    int                confHash;
                    fileInPack_t    *pakFile;
                    confHash = HashFileName( BINARY_CONFIG );
                    pak->binary = BINARY_NO;
                    for ( pakFile = search->pack->hashTable[confHash]; pakFile; pakFile = pakFile->next ) {
                        if ( !FilenameCompare( pakFile->name, BINARY_CONFIG ) ) {
                            pak->binary = BINARY_YES;
                            break;
                        }
                    }
                }
                if ( pak->binary == BINARY_NO ) {
                    continue; // not a binary pak, skip
                }
            }
            */

            for (pakFile = pak->hashTable[hash]; pakFile; pakFile = pakFile->next) {
                // case and separator insensitive comparisons
                if (![self filenameCompare:pakFile->name to:relativePath]) {
                    idFile_InZip *file = [self readFileFromZip:pak pakFile:pakFile relativePath:relativePath error:error];
                    if (!file) {
                        return nil;
                    }

                    if (foundInPak) {
                        *foundInPak = pak;
                    }

                    if (!pak->referenced && !(searchFlags & FSFLAG_PURE_NOREF)) {
                        // mark this pak referenced
                        if (self.fs_debug) {
                            NSLog(@"openFileRead: %@ -> adding %@ to referenced paks", relativePath, pak->pakFilename);
                        }
                        pak->referenced = YES;
                    }

                    if (self.fs_debug) {
                        NSLog(@"openFileRead: %@ (found in '%@')", relativePath, pak->pakFilename);
                    }
                    //AddAssetLogEntry( relativePath );
                    return file;
                }
            }
        }
    }
    
    if (self.fs_debug) {
        NSLog(@"Can't find %@", relativePath);
    }
    
    return nil;
}

-(idFile *)openFileRead:(NSString *)relativePath allowCopyFiles:(BOOL)allowCopyFiles gamedir:(NSString *)gamedir error:(NSError **)error {
        return [self openFileReadFlags:relativePath
                                 flags:FSFLAG_SEARCH_DIRS | FSFLAG_SEARCH_PAKS
                                 found:NULL
                             copyFiles:allowCopyFiles
                               gameDir:gamedir
                                 error:error];
}

-(idFile *)openFileReadFromPak:(NSString *)relativePath allowCopyFiles:(BOOL)allowCopyFiles gamedir:(NSString *)gamedir error:(NSError **)error {
        return [self openFileReadFlags:relativePath
                                 flags:FSFLAG_SEARCH_PAKS
                                 found:NULL
                             copyFiles:allowCopyFiles
                               gameDir:gamedir
                                 error:error];
}

- (idFile *)openFileWrite:(NSString *)relativePath basePath:(NSString *)basePath error:(NSError **)error {
    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return nil;
    }

    if (!relativePath || relativePath.length == 0) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"openFileWrite called with an empty relative path.");
        return nil;
    }

    NSString *path = [self cvarString:basePath];
    // Fall back to fs_savepath if basePath is nil or empty
    if (!path || path.length == 0) {
        path = self.fs_savepath;
    }

    // Call the buildOSPath method we translated earlier
    // (Assuming gameFolder is already ported to an NSString *)
    NSMutableString *OSpath = [[self buildOSPath:path
                                            game:gameFolder
                                    relativePath:relativePath] mutableCopy];

    if (self.fs_debug) {
        // NSLog(@"idFileSystem::OpenFileWrite: %@", OSpath);
    }

    // if the dir we are writing to is in our current list, it will be outdated
    // so just flush everything
    [self clearDirCache];

    if (![self createOSPath:OSpath error:error]) {
        return nil;
    }
    
    // Assuming openOSFile: is ported to take an NSString for the first argument.
    // If it still takes const char *, you would use [OSpath UTF8String] here.
    FILE *o = [self openOSFile:OSpath mode:"wb" caseSensitiveName:NULL];
    if (!o) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeWriteFailed,
                                @"Failed to open '%@' for writing.",
                                OSpath);
        return nil; // Changed NULL to nil for Obj-C object returns
    }
    
    // Pass the NSStrings directly without converting them back to cStrings
    idFile_Permanent *f = [[idFile_Permanent alloc] initWithHandle:o
                                                              name:relativePath
                                                          fullPath:OSpath
                                                              mode:(1 << FS_WRITE)
                                                              sync:NO
                                                          fileSize:0
                                                        fileSystem:self];

    return f;
}

-(idFile *)openExplicitFileRead:(NSString *)OSPath {
    idFile_Permanent *f;

    if (!searchPaths) {
        return nil;
    }

    if (self.fs_debug) {
        NSLog(@"openExplicitFileRead: %@", OSPath);
    }

    //common->DPrintf( "idFileSystem::OpenExplicitFileRead - reading from: %s\n", OSPath );

    FILE *o = [self openOSFile:OSPath mode:"rb" caseSensitiveName:nil];
    if (!o) {
        return nil;
    }
    
    f = [[idFile_Permanent alloc] initWithHandle:o
                                            name:OSPath
                                        fullPath:OSPath
                                            mode:(1 << FS_READ)
                                            sync:NO
                                        fileSize:directFileLength(o)
                                      fileSystem:self];

    return f;
}

-(idFile *)openExplicitFileWrite:(NSString *)OSPath {
    idFile_Permanent *f;

    if (!searchPaths) {
        return nil;
    }

    if (self.fs_debug) {
        NSLog(@"openExplicitFileWrite: %@", OSPath);
    }

    //common->DPrintf( "writing to: %s\n", OSPath );
    [self createOSPath:OSPath error:nil];
    
    FILE *o = [self openOSFile:OSPath mode:"wb" caseSensitiveName:NULL];
    if (!o) {
        return nil;
    }
    
    f = [[idFile_Permanent alloc] initWithHandle:o
                                            name:OSPath
                                        fullPath:OSPath
                                            mode:(1 << FS_WRITE)
                                            sync:NO
                                        fileSize:0
                                      fileSystem:self];

    return f;
}

-(idFile *)openFileAppend:(NSString *)relativePath sync:(BOOL)sync basePath:(NSString *)basePath error:(NSError **)error {
    NSString *path;
    NSMutableString *OSpath;
    idFile_Permanent *f;

    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return nil;
    }

    if (!relativePath || !relativePath.length) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"openFileAppend called with an empty relative path.");
        return nil;
    }

    path = [self cvarString:basePath];
    if (!path.length) {
        path = self.fs_savepath;
    }

    OSpath = [[self buildOSPath:path
                           game:gameFolder
                   relativePath:relativePath] mutableCopy];
    if (![self createOSPath:OSpath error:error]) {
        return nil;
    }

    if (self.fs_debug) {
        NSLog(@"openFileAppend: %@", OSpath);
    }

    FILE *o = [self openOSFile:OSpath mode:"ab" caseSensitiveName:NULL];
    if (!o) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeWriteFailed,
                                @"Failed to open '%@' for appending.",
                                OSpath);
        return NULL;
    }
    f = [[idFile_Permanent alloc]
            initWithHandle:o
                    name:relativePath
                fullPath:OSpath
                    mode:(1 << FS_WRITE) + (1 << FS_APPEND)
                    sync:sync
                fileSize:directFileLength(o)
              fileSystem:self];

    return f;
}

-(idFile *)openFileByMode:(NSString *)relativePath mode:(fsMode_t)mode error:(NSError **)error {
    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return nil;
    }
    if (!relativePath.length) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"openFileByMode called with an empty relative path.");
        return nil;
    }
    if ( mode == FS_READ ) {
        return [self openFileReadFlags:relativePath
                                  flags:FSFLAG_SEARCH_DIRS | FSFLAG_SEARCH_PAKS
                                  found:NULL
                              copyFiles:YES
                                gameDir:NULL
                                  error:error];
    }
    if ( mode == FS_WRITE ) {
        return [self openFileWrite:relativePath
                                  basePath:@"fs_savepath"
                                     error:error];
    }
    if ( mode == FS_APPEND ) {
        return [self openFileAppend:relativePath
                               sync:YES
                           basePath:nil
                              error:error];
    }
    UDFileSystemAssignError(error,
                            UDFileSystemPortErrorCodeInvalidArgument,
                            @"openFileByMode called with invalid mode %d.",
                            mode);
    return nil;
}

-(BOOL)closeFile:(idFile *)f error:(NSError **)error {
    if (!searchPaths) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeNotInitialized,
                                @"Filesystem call made without initialization.");
        return NO;
    }
    if (!f) {
        UDFileSystemAssignError(error,
                                UDFileSystemPortErrorCodeInvalidArgument,
                                @"closeFile called with a nil file.");
        return NO;
    }
    //delete f; // TODO: how to delete files? I think we need to keep references to them?
    return YES;
}

/*
=================================================================================

back ground loading

=================================================================================
*/

#if 0
/*
=================
idFileSystemLocal::CurlWriteFunction
=================
*/
size_t idFileSystemLocal::CurlWriteFunction( void *ptr, size_t size, size_t nmemb, void *stream ) {
    backgroundDownload_t *bgl = (backgroundDownload_t *)stream;
    if ( !bgl->f ) {
        return size * nmemb;
    }
    return fwrite(ptr, size, nmemb, static_cast<idFile_Permanent*>(bgl->f)->GetFilePtr());
}

/*
=================
idFileSystemLocal::CurlProgressFunction
=================
*/
int idFileSystemLocal::CurlProgressFunction( void *clientp, double dltotal, double dlnow, double ultotal, double ulnow ) {
    backgroundDownload_t *bgl = (backgroundDownload_t *)clientp;
    if ( bgl->url.status == DL_ABORTING || Sys_IsCurrentThreadStopRequested() ) {
        return 1;
    }
    bgl->url.dltotal = dltotal;
    bgl->url.dlnow = dlnow;
    return 0;
}

/*
===================
BackgroundDownload

Reads part of a file from a background thread.
===================
*/
dword BackgroundDownloadThread( void *parms ) {
    while( 1 ) {
        if ( Sys_IsCurrentThreadStopRequested() ) {
            return 0;
        }

        Sys_EnterCriticalSection();
        backgroundDownload_t    *bgl = fileSystemLocal.backgroundDownloads;
        if ( !bgl ) {
            Sys_LeaveCriticalSection();
            Sys_WaitForEvent();
            continue;
        }
        // remove this from the list
        fileSystemLocal.backgroundDownloads = bgl->next;
        Sys_LeaveCriticalSection();

        bgl->next = NULL;

        if ( bgl->opcode == DLTYPE_FILE ) {
            // use the low level read function, because fread may allocate memory
            fread(bgl->file.buffer, bgl->file.length, 1, static_cast<idFile_Permanent*>(bgl->f)->GetFilePtr());
            bgl->completed = YES;
        } else {
#if ID_ENABLE_CURL
            // DLTYPE_URL
            // use a local buffer for curl error since the size define is local
            char error_buf[ CURL_ERROR_SIZE ];
            bgl->url.dlerror[ 0 ] = '\0';
            CURL *session = curl_easy_init();
            CURLcode ret;
            if ( !session ) {
                bgl->url.dlstatus = CURLE_FAILED_INIT;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            ret = curl_easy_setopt( session, CURLOPT_ERRORBUFFER, error_buf );
            if ( ret ) {
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            ret = curl_easy_setopt( session, CURLOPT_URL, bgl->url.url.c_str() );
            if ( ret ) {
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            ret = curl_easy_setopt( session, CURLOPT_FAILONERROR, 1 );
            if ( ret ) {
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            ret = curl_easy_setopt( session, CURLOPT_WRITEFUNCTION, idFileSystemLocal::CurlWriteFunction );
            if ( ret ) {
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            ret = curl_easy_setopt( session, CURLOPT_WRITEDATA, bgl );
            if ( ret ) {
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            ret = curl_easy_setopt( session, CURLOPT_NOPROGRESS, 0 );
            if ( ret ) {
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            ret = curl_easy_setopt( session, CURLOPT_PROGRESSFUNCTION, idFileSystemLocal::CurlProgressFunction );
            if ( ret ) {
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            ret = curl_easy_setopt( session, CURLOPT_PROGRESSDATA, bgl );
            if ( ret ) {
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            bgl->url.dlnow = 0;
            bgl->url.dltotal = 0;
            bgl->url.status = DL_INPROGRESS;
            ret = curl_easy_perform( session );
            if ( ret ) {
                Sys_Printf( "curl_easy_perform failed: %s\n", error_buf );
                idStr::Copynz( bgl->url.dlerror, error_buf, MAX_STRING_CHARS );
                bgl->url.dlstatus = ret;
                bgl->url.status = DL_FAILED;
                bgl->completed = YES;
                continue;
            }
            bgl->url.status = DL_DONE;
            bgl->completed = YES;
#else
            bgl->url.status = DL_FAILED;
            bgl->completed = YES;
#endif
        }
    }
    return 0;
}

/*
=================
idFileSystemLocal::StartBackgroundReadThread
=================
*/
void idFileSystemLocal::StartBackgroundDownloadThread() {
    if ( !backgroundThread.threadHandle ) {
        Sys_CreateThread( (xthread_t)BackgroundDownloadThread, NULL, THREAD_NORMAL, backgroundThread, "backgroundDownload", g_threads, &g_thread_count );
        if ( !backgroundThread.threadHandle ) {
            common->Warning( "idFileSystemLocal::StartBackgroundDownloadThread: failed" );
        }
    } else {
        common->Printf( "background thread already running\n" );
    }
}

/*
=================
idFileSystemLocal::StopBackgroundDownloadThread
=================
*/
void idFileSystemLocal::StopBackgroundDownloadThread() {
    if ( backgroundThread.threadHandle ) {
        Sys_DestroyThread( backgroundThread );
    }

    Sys_EnterCriticalSection();
    backgroundDownload_t *bgl = backgroundDownloads;
    backgroundDownloads = NULL;
    Sys_LeaveCriticalSection();

    while ( bgl != NULL ) {
        backgroundDownload_t *next = bgl->next;
        bgl->next = NULL;
        if ( bgl->opcode == DLTYPE_URL ) {
            bgl->url.status = DL_FAILED;
            idStr::Copynz( bgl->url.dlerror, "filesystem shutting down", MAX_STRING_CHARS );
        }
        bgl->completed = YES;
        bgl = next;
    }
}

/*
=================
idFileSystemLocal::BackgroundDownload
=================
*/
void idFileSystemLocal::BackgroundDownload( backgroundDownload_t *bgl ) {
    if ( bgl->opcode == DLTYPE_FILE ) {
        if ( dynamic_cast<idFile_Permanent *>(bgl->f) ) {
            // add the bgl to the background download list
            Sys_EnterCriticalSection();
            bgl->next = backgroundDownloads;
            backgroundDownloads = bgl;
            Sys_TriggerEvent();
            Sys_LeaveCriticalSection();
        } else {
            // read zipped file directly
            bgl->f->Seek( bgl->file.position, FS_SEEK_SET );
            bgl->f->Read( bgl->file.buffer, bgl->file.length );
            bgl->completed = YES;
        }
    } else {
        Sys_EnterCriticalSection();
        bgl->next = backgroundDownloads;
        backgroundDownloads = bgl;
        Sys_TriggerEvent();
        Sys_LeaveCriticalSection();
    }
}

/*
=================
idFileSystemLocal::PerformingCopyFiles
=================
*/
bool idFileSystemLocal::PerformingCopyFiles( void ) const {
    return fs_copyfiles.GetInteger() > 0;
}

/*
=================
idFileSystemLocal::FindPakForFileChecksum
=================
*/
pack_t *idFileSystemLocal::FindPakForFileChecksum( const char *relativePath, int findChecksum, bool bReference ) {
    searchpath_t    *search;
    pack_t            *pak;
    fileInPack_t    *pakFile;
    int                hash;
    assert( !serverPaks.Num() );
    hash = HashFileName( relativePath );
    for ( search = searchPaths; search; search = search->next ) {
        if ( search->pack && search->pack->hashTable[ hash ] ) {
            pak = search->pack;
            for ( pakFile = pak->hashTable[ hash ]; pakFile; pakFile = pakFile->next ) {
                if ( !FilenameCompare( pakFile->name, relativePath ) ) {
                    idFile_InZip *file = ReadFileFromZip( pak, pakFile, relativePath );
                    if ( findChecksum == GetFileChecksum( file ) ) {
                        if ( fs_debug.GetBool() ) {
                            common->Printf( "found '%s' with checksum 0x%x in pak '%s'\n", relativePath, findChecksum, pak->pakFilename.c_str() );
                        }
                        if ( bReference ) {
                            pak->referenced = YES;
                            // FIXME: use dependencies for pak references
                        }
                        CloseFile( file );
                        return pak;
                    } else if ( fs_debug.GetBool() ) {
                        common->Printf( "'%s' in pak '%s' has != checksum %x\n", relativePath, pak->pakFilename.c_str(), GetFileChecksum( file ) );
                    }
                    CloseFile( file );
                }
            }
        }
    }
    if ( fs_debug.GetBool() ) {
        common->Printf( "no pak file found for '%s' checksumed %x\n", relativePath, findChecksum );
    }
    return NULL;
}

/*
=================
idFileSystemLocal::GetFileChecksum
=================
*/
int idFileSystemLocal::GetFileChecksum( idFile *file ) {
    int len, ret;
    byte *buf;

    file->Seek( 0, FS_SEEK_END );
    len = file->Tell();
    file->Seek( 0, FS_SEEK_SET );
    buf = (byte *)Mem_Alloc( len );
    if ( file->Read( buf, len ) != len ) {
        common->FatalError( "Short read in idFileSystemLocal::GetFileChecksum()\n" );
    }
    ret = MD4_BlockChecksum( buf, len );
    Mem_Free( buf );
    return ret;
}

static idFile *FS_OpenGameModuleFromExeDir( idFileSystemLocal *fileSystemLocal, const idStr &exeDir, const char *gameDir, const char *dllName, idStr &dllPath ) {
    if ( !gameDir || !gameDir[0] ) {
        return NULL;
    }

    dllPath = exeDir;
    dllPath.AppendPath( gameDir );
    dllPath.AppendPath( dllName );
    return fileSystemLocal->OpenExplicitFileRead( dllPath );
}

/*
=================
idFileSystemLocal::FindDLL
=================
*/
void idFileSystemLocal::FindDLL( const char *name, char _dllPath[ MAX_OSPATH ], bool updateChecksum ) {
    idFile            *dllFile = NULL;
    char            dllName[MAX_OSPATH];
    idStr            dllPath;

    sys->DLL_GetFileName( name, dllName, MAX_OSPATH );

    idStr exeDir = Sys_EXEPath();
    exeDir.StripFilename();

    // Only load openQ4 game modules staged next to the executable or in the
    // package root the application bundle was extracted into (macOS stages the
    // executable in openQ4.app/Contents/MacOS while game modules live at the
    // package root). Mods may provide their own module, but content-only mods
    // inherit baseoq4 modules. Do not load executable code from PK4s,
    // fs_savepath, pure-server code paks, or loose files outside the
    // executable/package root.
    idStr moduleSearchRoots[2];
    int numModuleSearchRoots = 0;
    moduleSearchRoots[numModuleSearchRoots++] = exeDir;
    char packageRoot[MAX_OSPATH];
    if ( Sys_GetPackageRootDirectory( packageRoot, sizeof( packageRoot ) ) && exeDir.Icmp( packageRoot ) != 0 ) {
        moduleSearchRoots[numModuleSearchRoots++] = packageRoot;
    }

    const char *moduleGameDir = fs_game.GetString();
    if ( !moduleGameDir[0] ) {
        moduleGameDir = OPENQ4_GAMEDIR;
    }
    for ( int i = 0; !dllFile && i < numModuleSearchRoots; i++ ) {
        dllFile = FS_OpenGameModuleFromExeDir( this, moduleSearchRoots[i], moduleGameDir, dllName, dllPath );
    }

    if ( !dllFile && idStr::Icmp( moduleGameDir, OPENQ4_GAMEDIR ) != 0 ) {
        for ( int i = 0; !dllFile && i < numModuleSearchRoots; i++ ) {
            dllFile = FS_OpenGameModuleFromExeDir( this, moduleSearchRoots[i], OPENQ4_GAMEDIR, dllName, dllPath );
        }
        if ( dllFile ) {
            common->DPrintf( "Game DLL '%s' not found in mod directory '%s'; falling back to '%s'.\n", dllName, moduleGameDir, OPENQ4_GAMEDIR );
        }
    }

    for ( int i = 0; !dllFile && i < numModuleSearchRoots; i++ ) {
        dllPath = moduleSearchRoots[i];
        dllPath.AppendPath( dllName );
        dllFile = OpenExplicitFileRead( dllPath );
    }

    if ( updateChecksum ) {
        if ( dllFile ) {
            gameDLLChecksum = GetFileChecksum( dllFile );
        } else {
            gameDLLChecksum = 0;
        }
        gamePakChecksum = 0;
    }
    if ( dllFile ) {
        dllPath = dllFile->GetFullPath( );
        CloseFile( dllFile );
        dllFile = NULL;
    } else {
        dllPath = "";
    }
    idStr::snPrintf( _dllPath, MAX_OSPATH, "%s", dllPath.c_str() );
}
#endif

-(void)clearDirCache {
    int i;

    dir_cache_index = 0;
    dir_cache_count = 0;
    for( i = 0; i < MAX_CACHED_DIRS; i++ ) {
        if (dir_cache[i]) {
            [dir_cache[i] clear];
        }
    }
}

-(idFile *)makeTemporaryFile {
    FILE *f = tmpfile();
    if (!f) {
        NSLog(@"makeTemporaryFile failed: %s", strerror(errno));
        return nil;
    }
    idFile_Permanent *file = [[idFile_Permanent alloc] initWithHandle:f
                                                                 name:@"<tempfile>"
                                                             fullPath:@""
                                                                 mode:(1 << FS_READ) + (1 << FS_WRITE)
                                                                 sync:NO
                                                             fileSize:0
                                                           fileSystem:self];
    return file;
}

-(findFile_t)findFile:(NSString *)path scheduleAddons:(BOOL)scheduleAddons error:(NSError **)error {
    pack_t *pak;
    idFile *f = [self openFileReadFlags:path
                                  flags:FSFLAG_SEARCH_DIRS | FSFLAG_SEARCH_PAKS
                                  found:&pak
                              copyFiles:NO
                                gameDir:self.fs_game
                                  error:error];
    if (!f) {
        return FIND_NO;
    }
    if (!pak) {
        // found in FS, not even in paks
        return FIND_YES;
    }

    return FIND_YES;
}

@end
