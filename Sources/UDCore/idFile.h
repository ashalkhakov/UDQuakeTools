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

#import <Foundation/Foundation.h>

/*
==============================================================

  File Streams.

==============================================================
*/

// mode parm for Seek
typedef enum {
    FS_SEEK_CUR,
    FS_SEEK_END,
    FS_SEEK_SET
} fsOrigin_t;


@interface idFile : NSObject

// Get the name of the file.
-(NSString *)name;

// Get the full file path.
-(NSString *)fullPath;

// Read data from the file to the buffer.
-(int)read:(void *)buffer length:(int)len error:(NSError **)error;

// Write data from the buffer to the file.
-(int)write:(const void *)buffer length:(int)len error:(NSError **)error;

// Returns the length of the file.
-(int)length;
// Return a time value for reload operations.

-(unsigned int)timestamp;

// Returns offset in file.
-(int)tell;
// Forces flush on files being writting to.
-(void)forceFlush;

// Causes any buffered data to be written to the file.
-(void)flush;
// Seek on a file.
-(int)seek:(long)offset origin:(fsOrigin_t)origin;
// Go back to the beginning of the file.
-(void)rewind;

// Like fprintf.
-(int)printf:(NSString *)fmt, ...;
// Like fprintf but with argument pointer
-(int)vprintf:(NSString *)fmt arg:(va_list)arg;
@end

@interface idFile_Memory : idFile {
    NSString *                name;            // name of the file
    int                       mode;            // open mode
    int                       maxSize;        // maximum size of file
    int                       fileSize;        // size of the file
    int                       allocated;        // allocated size
    int                       granularity;    // file granularity
    char *                    filePtr;        // buffer holding the file data
    char *                    curPtr;            // current read/write pointer
}

-(instancetype)init;    // file for writing without name
-(instancetype)initWithName:(NSString *)name;    // file for writing
-(instancetype)initWithName:(NSString *)name buffer:(char *)data length:(int)length writing:(BOOL)writing;    // file for writing or reading

// changes memory file to read only
-(void)makeReadOnly;
// clear the file
-(void)clear:(bool)freeMemory;
// set data for reading
-(void)setData:(char *)data length:(int)length;
// returns const pointer to the memory buffer
-(char *)dataPtr;
// set the file granularity
-(void)setGranularity:(int)g;

@end

@interface idFile_Permanent : idFile {
    NSString *                  name;            // relative path of the file - relative path
    NSString *                  fullPath;        // full file path - OS path
    int                         mode;            // open mode
    int                         fileSize;        // size of the file
    FILE *                      o;                // file handle
    BOOL                        handleSync;        // true if written data is immediately flushed
}

-(instancetype) initWithHandle:(FILE *)fp name:(NSString *)relativePath fullPath:(NSString *)fullPath mode:(int)mode sync:(BOOL)sync fileSize:(int)fileSize;

// get file pointer
-(FILE *)filePtr;
@end

@interface idFile_InZip : idFile {
    NSString *                 name;            // name of the file in the pak
    NSString *                 fullPath;        // full file path including pak file name
    int                        zipFilePos;        // zip file info position in pak
    int                        fileSize;        // size of the file
    void *                     z;                // unzip info
}

-(instancetype) initWithUnzipInfo:(void*)z name:(NSString *)name pakFilename:(NSString *)pakFilename;
-(void)openCurrentFileAt:(unsigned long)pos;

@end
