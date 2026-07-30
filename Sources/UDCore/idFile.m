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

#include <sys/stat.h>
#include "unzip.h"

#import "idStr.h"
#import "idFile.h"
#import "idFileSystem.h"

NSString * const UDFileSystemErrorDomain = @"UDFileSystemErrorDomain";

#define    MAX_PRINT_MSG        4096

#if 0
/*
=================
FS_WriteFloatString
=================
*/
static void FS_AppendFloatString( char *buf, int bufSize, int &index, const char *fmt, ... ) {
    va_list argPtr;
    int written;

    if ( index < 0 || index >= bufSize ) {
        common->Error( "FS_WriteFloatString: output overflow" );
    }

    va_start( argPtr, fmt );
    written = idStr::vsnPrintf( buf + index, bufSize - index, fmt, argPtr );
    va_end( argPtr );

    if ( written < 0 ) {
        common->Error( "FS_WriteFloatString: output overflow" );
    }

    index += written;
}

int FS_WriteFloatString( char *buf, int bufSize, const char *fmt, va_list argPtr ) {
    int i;
    unsigned int u;
    double f;
    char *str;
    int index;
    idStr tmp, format;

    if ( buf == NULL || bufSize <= 0 ) {
        common->Error( "FS_WriteFloatString: invalid output buffer" );
    }
    if ( fmt == NULL ) {
        common->Error( "FS_WriteFloatString: invalid format string" );
    }

    index = 0;
    buf[0] = '\0';

    while( *fmt ) {
        switch( *fmt ) {
            case '%':
                format = "";
                format += *fmt++;
                while ( (*fmt >= '0' && *fmt <= '9') ||
                        *fmt == '.' || *fmt == '-' || *fmt == '+' || *fmt == '#') {
                    format += *fmt++;
                }
                format += *fmt;
                switch( *fmt ) {
                    case 'f':
                    case 'e':
                    case 'E':
                    case 'g':
                    case 'G':
                        f = va_arg( argPtr, double );
                        if ( format.Length() <= 2 ) {
                            char tmpBuffer[512];

                            // high precision floating point number without trailing zeros
                            idStr::snPrintf( tmpBuffer, sizeof( tmpBuffer ), "%1.10f", f );
                            tmp = tmpBuffer;
                            tmp.StripTrailing( '0' );
                            tmp.StripTrailing( '.' );
                            FS_AppendFloatString( buf, bufSize, index, "%s", tmp.c_str() );
                        }
                        else {
                            FS_AppendFloatString( buf, bufSize, index, format.c_str(), f );
                        }
                        break;
                    case 'd':
                    case 'i':
                        i = va_arg( argPtr, int );
                        FS_AppendFloatString( buf, bufSize, index, format.c_str(), i );
                        break;
                    case 'u':
                        u = va_arg( argPtr, unsigned int );
                        FS_AppendFloatString( buf, bufSize, index, format.c_str(), u );
                        break;
                    case 'o':
                        u = va_arg( argPtr, unsigned int );
                        FS_AppendFloatString( buf, bufSize, index, format.c_str(), u );
                        break;
                    case 'x':
                        u = va_arg( argPtr, unsigned int );
                        FS_AppendFloatString( buf, bufSize, index, format.c_str(), u );
                        break;
                    case 'X':
                        u = va_arg( argPtr, unsigned int );
                        FS_AppendFloatString( buf, bufSize, index, format.c_str(), u );
                        break;
                    case 'c':
                        i = va_arg( argPtr, int );
                        FS_AppendFloatString( buf, bufSize, index, format.c_str(), (char) i );
                        break;
                    case 's':
                        str = va_arg( argPtr, char * );
                        FS_AppendFloatString( buf, bufSize, index, format.c_str(), str ? str : "" );
                        break;
                    case '%':
                        FS_AppendFloatString( buf, bufSize, index, format.c_str() );
                        break;
                    default:
                        common->Error( "FS_WriteFloatString: invalid format %s", format.c_str() );
                        break;
                }
                fmt++;
                break;
            case '\\':
                fmt++;
                switch( *fmt ) {
                    case 't':
                        FS_AppendFloatString( buf, bufSize, index, "\t" );
                        break;
                    case 'v':
                        FS_AppendFloatString( buf, bufSize, index, "\v" );
                        break;
                    case 'n':
                        FS_AppendFloatString( buf, bufSize, index, "\n" );
                        break;
                    case '\\':
                        FS_AppendFloatString( buf, bufSize, index, "\\" );
                        break;
                    default:
                        common->Error( "FS_WriteFloatString: unknown escape character \'%c\'", *fmt );
                        break;
                }
                fmt++;
                break;
            default:
                FS_AppendFloatString( buf, bufSize, index, "%c", *fmt );
                fmt++;
                break;
        }
    }

    return index;
}
#endif

/*
=================================================================================

idFile

=================================================================================
*/

@implementation idFile

-(NSString *)name {
    return @"";
}

-(NSString *)fullPath {
    return @"";
}

-(int)read:(void *)buffer length:(int)len error:(NSError **)error {
    if (error)
        *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                     code:1001
                                 userInfo:@{NSLocalizedDescriptionKey: @"idFile -read:length:error: cannot read from idFile"}];
    return 0;
}

-(int)write:(const void *)buffer length:(int)len error:(NSError **)error {
    if (error)
        *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                     code:1001
                                 userInfo:@{NSLocalizedDescriptionKey: @"idFile -write:length:error: cannot write to idFile"}];

    return 0;
}

-(int)length {
    return 0;
}

-(unsigned int)timestamp {
    return 0;
}

-(int)tell {
    return 0;
}

-(void)forceFlush {
}

-(void)flush {
}

-(int)seek:(long)offset origin:(fsOrigin_t)origin {
    return -1;
}

-(void)rewind {
    [self seek:0 origin:FS_SEEK_SET];
}

-(int)printf:(NSString *)fmt, ... {
    char buf[MAX_PRINT_MSG];
    int length;
    va_list argptr;

    va_start(argptr, fmt);
    NSString *result = [[NSString alloc] initWithFormat:fmt arguments:argptr];
    va_end( argptr );

    // so notepad formats the lines correctly
    result = [result stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"];
    
    const char *utf8 = [result UTF8String];
    int len = (int)strlen(utf8);

    return [self write:utf8 length:len error:nil];
}

-(int)vprintf:(NSString *)fmt arg:(va_list)arg {
    NSString *result = [[NSString alloc] initWithFormat:fmt arguments:arg];
    const char *utf8 = [result UTF8String];
    int len = (int)strlen(utf8);

    return [self write:utf8 length:len error:nil];
}

/*
int idFile::WriteFloatString( const char *fmt, ... ) {
    char buf[MAX_PRINT_MSG];
    int len;
    va_list argPtr;

    va_start( argPtr, fmt );
    len = FS_WriteFloatString( buf, sizeof( buf ), fmt, argPtr );
    va_end( argPtr );

    return Write( buf, len );
}
*/

/*

-(int)readInt:(int *)value {
    int result = [self read:value length:sizeof(*value) error:nil];
    *value = LittleLong(*value);
    return result;
}

-(int)readUnsignedInt:(unsigned int*)value {
    int result = [self read:value length:sizeof(*value) error:nil];
    *value = LittleLong(*value);
    return result;
}

-(int)readShort:(short *)value {
    int result = [self read:value length:sizeof(*value) error:nil];
    *value = LittleShort(*value);
    return result;
}

-(int)readUnsignedShort:(unsigned short )value {
    int result = [self read:value length:sizeof(*value) error:nil];
    *value = LittleShort(*value);
    return result;
}

-(int)readChar:(char *)value {
    return [self read:value length:sizeof(*value) error:nil];
}

-(int)readUnsignedChar:(unsigned char *)value {
    return [self read:value length:sizeof(*value) error:nil];
}

-(int)readFloat:(float *)value {
    int result = [self read:value length:sizeof(*value) error:nil];
    value = LittleFloat(value);
    return result;
}

-(int)readBool:(BOOL *)value {
    unsigned char c;
    int result = [self readUnsignedChar:&c];
    value = c ? YES : NO;
    return result;
}

-(int)readString:(idStr *)string {
    int len;
    int result = 0;
    
    if ([self readInt:&len] != sizeof(len) || len < 0 ) {
        idStr_Clear(string);
        return 0;
    }

    const int fileLength = [self length];
    const int fileTell = [self tell];
    if (fileLength > 0 && fileTell >= 0 && len > fileLength - fileTell) {
        idStr_Clear(string);
        return 0;
    }

    if (len >  ) {
        idStr_Fill(string, ' ', len);
        result = [self read:&string->data[0] length:len error:nil];
        if (result != len) {
            idStr_Clear(string);
        }
    } else {
        idStr_Clear(string);
    }
    return result;
}

-(int)writeInt:(const int)value {
    int v = LittleLong(value);
    return [self write:&v length:sizeof(v) error:nil];
}

-(int)writeUnsignedInt:(const unsigned int)value {
    unsigned int v = LittleLong(value);
    return [self write:&v length:sizeof(v) error:nil];
}

-(int)writeShort:(const short)value {
    short v = LittleShort(value);
    return [self write:&v length:sizeof(v) error:nil];
}

-(int)writeUnsignedShort:(const unsigned short)value {
    unsigned short v = LittleShort(value);
    return [self write:&v length:sizeof(v) error:nil];
}

-(int)writeChar:(const char)value {
    return [self write:&value length:sizeof(value) error:nil];
}

-(int)writeUnsignedChar:(const unsigned char)value {
    return [self write:&value length:sizeof(value) error:nil];
}

-(int)writeFloat:(const float)value {
    float v = LittleFloat(value);
    return [self write:&v length:sizeof(v) error:nil];
}

-(int)writeBool:(const BOOL)value {
    unsigned char c = value;
    return [self writeUnsignedChar:c];
}

-(int)writeString:(const char *)value {
    int len;

    if (value == NULL) {
        value = "";
    }
    
    len = (int)strlen( value );
    [self writeInt:len];
    return [self write:value length:len error:nil];
}
*/

@end

/*
=================================================================================

idFile_Memory

=================================================================================
*/

@implementation idFile_Memory

-(instancetype)initWithFileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->name = @"*unknown*";
        self->maxSize = 0;
        self->fileSize = 0;
        self->allocated = 0;
        self->granularity = 16384;
        
        self->mode = ( 1 << FS_WRITE );
        self->filePtr = NULL;
        self->curPtr = NULL;
        
        self.fileSystem = fileSystem;
    }
    return self;
}

-(instancetype)initWithName:(NSString *)name fileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->name = name;
        self->maxSize = 0;
        self->fileSize = 0;
        self->allocated = 0;
        self->granularity = 16384;
        
        self->mode = ( 1 << FS_WRITE );
        self->filePtr = NULL;
        self->curPtr = NULL;
        
        self.fileSystem = fileSystem;
    }
    return self;
}

-(instancetype)initWithName:(NSString *)name buffer:(char *)data length:(int)length writing:(BOOL)writing fileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->name = name ? name : @"";
        if (data == NULL || length < 0) {
            data = NULL;
            length = 0;
        }

        self->granularity = 16384;

        if (writing) {
            self->maxSize = length;
            self->fileSize = 0;
            self->allocated = length;
            
            self->mode = (1 << FS_WRITE);
        } else {
            self->maxSize = 0;
            self->fileSize = length;
            self->allocated = 0;

            self->mode = (1 << FS_READ);
        }

        self->filePtr = data;
        self->curPtr = data;
        
        self.fileSystem = fileSystem;
    }
    return self;
}

-(void)dealloc {
    if ( self->filePtr && self->allocated > 0 && self->maxSize == 0 ) {
        free(self->filePtr);
    }
}

-(int)read:(void *)buffer length:(int)len error:(NSError **)error {

    if ( !( mode & ( 1 << FS_READ ) ) ) {
        if (error)
            *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"idFile_Memory -read:length:error: %@ not opened in read mode", self->name]}];

        return 0;
    }
    if (len <= 0 || buffer == NULL || self->curPtr == NULL || self->filePtr == NULL) {
        return 0;
    }

    if (self->curPtr + len > self->filePtr + self->fileSize) {
        len = self->filePtr + self->fileSize - self->curPtr;
    }
    if (len <= 0) {
        return 0;
    }
    memcpy(buffer, self->curPtr, len);
    self->curPtr += len;
    return len;
}

-(int)write:(const void *)buffer length:(int)len error:(NSError **)error {

    if (!(mode & (1 << FS_WRITE))) {
        if (error)
            *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"idFile_Memory -write:length:error: %@ not opened in write mode", self->name]}];

        return 0;
    }
    if (len <= 0 || buffer == NULL) {
        return 0;
    }

    const int curOffset = (self->filePtr != NULL && self->curPtr != NULL) ? (self->curPtr - self->filePtr) : 0;
    int alloc = curOffset + len + 1 - self->allocated; // need room for len+1
    if (alloc > 0) {
        if (self->maxSize != 0 ) {
            if (error)
                *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                             code:1003
                                         userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"idFile_Memory -write:length:error: exceeded maximum size %d", self->maxSize]}];

            return 0;
        }
        int extra = self->granularity * (1 + alloc / self->granularity);
        char *newPtr = (char *)malloc(self->allocated + extra);
        if (self->allocated) {
            memcpy(newPtr, self->filePtr, self->allocated);
        }
        self->allocated += extra;
        self->curPtr = newPtr + curOffset;
        if (self->filePtr) {
            free(self->filePtr);
        }
        self->filePtr = newPtr;
    }
    memcpy(self->curPtr, buffer, len);
    self->curPtr += len;
    self->fileSize += len;
    self->filePtr[fileSize] = 0; // len + 1
    return len;
}

-(int)length {
    return self->fileSize;
}

-(unsigned int)timestamp {
    return 0;
}

-(int)tell {
    if (self->curPtr == NULL || self->filePtr == NULL) {
        return 0;
    }
    return (int)(self->curPtr - self->filePtr);
}

-(void)forceFlush {
}

-(void)flush {
}

-(int)seek:(long)offset origin:(fsOrigin_t)origin {
    if (self->filePtr == NULL) {
        if (offset == 0) {
            self->curPtr = NULL;
            return 0;
        }
        return -1;
    }

    switch (origin) {
        case FS_SEEK_CUR: {
            self->curPtr += offset;
            break;
        }
        case FS_SEEK_END: {
            self->curPtr = self->filePtr + self->fileSize - offset;
            break;
        }
        case FS_SEEK_SET: {
            self->curPtr = self->filePtr + offset;
            break;
        }
        default: {
            //common->FatalError( "idFile_Memory::Seek: bad origin for %s\n", name.c_str() );
            return -1;
        }
    }
    if (self->curPtr < self->filePtr) {
        self->curPtr = self->filePtr;
        return -1;
    }
    if (self->curPtr > self->filePtr + self->fileSize ) {
        self->curPtr = self->filePtr + self->fileSize;
        return -1;
    }
    return 0;
}

-(void)makeReadOnly {
    self->mode = ( 1 << FS_READ );
    [self rewind];
}

-(void)clear:(BOOL)freeMemory {
    self->fileSize = 0;
    self->granularity = 16384;
    if (freeMemory) {
        self->allocated = 0;
        free(self->filePtr);
        self->filePtr = NULL;
        self->curPtr = NULL;
    } else {
        self->curPtr = self->filePtr;
    }
}

-(void)setData:(char *)data length:(int)length {
    if (data == NULL || length < 0) {
        data = "";
        length = 0;
    }
    self->maxSize = 0;
    self->fileSize = length;
    self->allocated = 0;
    self->granularity = 16384;

    self->mode = (1 << FS_READ);
    self->filePtr = data;
    self->curPtr = data;
}

-(char *)dataPtr {
    return self->filePtr;
}

@end

/*
=================================================================================

idFile_Permanent

=================================================================================
*/

@implementation idFile_Permanent

-(instancetype)initWithFileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->name = @"invalid";
        self->o = NULL;
        self->mode = 0;
        self->fileSize = 0;
        self->handleSync = NO;
        self.fileSystem = fileSystem;
    }
    return self;
}

-(instancetype) initWithHandle:(FILE *)fp
                          name:(NSString *)relativePath
                      fullPath:(NSString *)fullPath
                          mode:(int)mode
                          sync:(BOOL)sync
                      fileSize:(int)fileSize
                    fileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->o = fp;
        self->name = relativePath;
        self->fullPath = fullPath;
        self->mode = mode;
        self->fileSize = fileSize;
        self->handleSync = sync;
        self.fileSystem = fileSystem;
    }
    return self;
}

-(FILE *)filePtr {
    return self->o;
}

-(void)dealloc {
    if (self->o) {
        fclose(self->o);
    }
}

-(int)read:(void *)buffer length:(int)len error:(NSError **)error {
    int             block, remaining;
    int             read;
    unsigned char * buf;
    int             tries;
    static const int readChunkBytes = 64 * 1024;

    if (!(self->mode & (1 << FS_READ))) {
        if (error)
            *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"idFile_Permanent -read:length:error: %@ not opened in read mode", self->name]}];

        return 0;
    }

    if (!self->o) {
        return 0;
    }
    if (len <= 0 || buffer == NULL) {
        return 0;
    }

    buf = (unsigned char *)buffer;

    remaining = len;
    tries = 0;
    while (remaining) {
        block = remaining < readChunkBytes ? readChunkBytes : remaining;
        read = (int)fread(buf, 1, block, self->o);
        if (read == 0) {
            // we might have been trying to read from a CD, which
            // sometimes returns a 0 read on windows
            if (!tries) {
                tries = 1;
            } else {
                return len - remaining;
            }
        }

        if (read == -1) {
            if (error)
                *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                             code:1005
                                         userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"idFile_Permanent -read:length:error: -1 bytes from %@", self->name]}];
            return 0;
        }

        remaining -= read;
        buf += read;
        [self.fileSystem addToReadCount:read];
    }

    return len;
}

-(int)write:(const void *)buffer length:(int)len error:(NSError **)error {
    int             block, remaining;
    int             written;
    unsigned char * buf;
    int             tries;

    if (!(self->mode & ( 1 << FS_WRITE))) {
        if (error)
            *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"idFile_Permanent -write:length:error: %@ not opened in write mode", self->name]}];
        return 0;
    }

    if (!self->o) {
        return 0;
    }
    if (len <= 0 || buffer == NULL) {
        return 0;
    }

    buf = (unsigned char *)buffer;

    remaining = len;
    tries = 0;
    while (remaining) {
        block = remaining;
        written = fwrite(buf, 1, block, self->o);
        if (written == 0) {
            if (!tries) {
                tries = 1;
            } else {
                if (error)
                    *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                                 code:1005
                                             userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"idFile_Permanent -write:length:error: 0 bytes written to %@", self->name]}];

                return 0;
            }
        }

        if (written == -1) {
            if (error)
                *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                             code:1005
                                         userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"idFile_Permanent -write:length:error: -1 bytes written to %@", self->name]}];
            return 0;
        }

        remaining -= written;
        buf += written;
        self->fileSize += written;
    }
    if (self->handleSync) {
        fflush(self->o);
    }
    return len;
}

-(void)forceFlush {
    setvbuf(self->o, NULL, _IONBF, 0);
}

-(void)flush {
    fflush(self->o);
}

-(int)tell {
    return (int)ftell(self->o);
}

-(int)length {
    return self->fileSize;
}

-(unsigned int)timestamp {
    if (self->o == NULL) {
        return -1;
    }
    struct stat st;
    if (fstat(fileno(self->o), &st) == -1) {
        return -1;
    }
    return (unsigned int)st.st_mtime;
}

-(int)seek:(long)offset origin:(fsOrigin_t)origin {
    int _origin;

    switch (origin) {
        case FS_SEEK_CUR: {
            _origin = SEEK_CUR;
            break;
        }
        case FS_SEEK_END: {
            _origin = SEEK_END;
            break;
        }
        case FS_SEEK_SET: {
            _origin = SEEK_SET;
            break;
        }
        default: {
            _origin = SEEK_CUR;
            //common->FatalError( "idFile_Permanent::Seek: bad origin for %s\n", name.c_str() );
            return -1;
        }
    }

    return fseek(self->o, offset, _origin);
}

@end

/*
=================================================================================

idFile_InZip

=================================================================================
*/

@implementation idFile_InZip

-(instancetype)initWithUnzipInfo:(void *)z name:(NSString *)name pakFilename:(NSString *)pakFilename fileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->name = name;
        self->fullPath = [NSString stringWithFormat:@"%@/%@", pakFilename, name];
        self->z = z;
        self->zipFilePos = 0;
        self->fileSize = 0;
        self.fileSystem = fileSystem;
    }
    return self;
}

-(void)dealloc {
    unzCloseCurrentFile(self->z);
    unzClose(self->z);
}

-(void)openCurrentFileAt:(unsigned long)pos {
    unzOpenCurrentFile(self->z);
    self->zipFilePos = (int)pos;
    self->fileSize = (int)unzGetCurrentFileUncompressedSize(self->z);
}

-(int)read:(void *)buffer length:(int)len error:(NSError **)error {
    static const int readChunkBytes = 64 * 1024;
    if (len <= 0 || buffer == NULL) {
        return 0;
    }
    unsigned char *buf = (unsigned char *)buffer;
    int totalRead = 0;

    while (totalRead < len) {
        const int remaining = len - totalRead;
        const int block = remaining < readChunkBytes ? remaining : readChunkBytes;
        const int l = unzReadCurrentFile(self->z, buf + totalRead, block);

        if (l <= 0) {
            // Preserve error behavior for the first failed read.
            if (totalRead == 0) {
                return l;
            }
            break;
        }

        totalRead += l;
        [self.fileSystem addToReadCount:l];

        if (l < block) {
            break;
        }
    }

    return totalRead;
}

-(int)write:(const void *)buffer length:(int)len error:(NSError **)error {
    if (error)
        *error = [NSError errorWithDomain:UDFileSystemErrorDomain
                                     code:1010
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"idFile_InZip -write:length:error: cannot write to the zipped file %@", self->name]}];

    return 0;
}

-(void)forceFlush {
    //common->FatalError( "idFile_InZip::ForceFlush: cannot flush the zipped file %s", name.c_str() );
}

-(void)flush {
    //common->FatalError( "idFile_InZip::Flush: cannot flush the zipped file %s", name.c_str() );
}

-(int)tell {
    return unztell(self->z);
}

-(int)length {
    return self->fileSize;
}

-(unsigned int)timestamp {
    return 0;
}

#define ZIP_SEEK_BUF_SIZE    (1<<15)

-(int)seek:(long)offset origin:(fsOrigin_t)origin {
    int res, i;
    char *buf;

    switch( origin ) {
        case FS_SEEK_END: {
            offset = self->fileSize - offset;
            if (offset < 0) {
                return -1;
            }
        }
        case FS_SEEK_SET: {
            // set the file position in the zip file (also sets the current file info)
            unzSetCurrentFileInfoPosition(self->z, self->zipFilePos);
            unzOpenCurrentFile(self->z);
            if (offset < 0) {
                return -1;
            }
            if (offset <= 0) {
                return 0;
            }
        }
        case FS_SEEK_CUR: {
            if ( offset < 0 ) {
                return -1;
            }
            buf = (char *)alloca(ZIP_SEEK_BUF_SIZE);
            for (i = 0; i < (offset - ZIP_SEEK_BUF_SIZE); i += ZIP_SEEK_BUF_SIZE) {
                res = unzReadCurrentFile(self->z, buf, ZIP_SEEK_BUF_SIZE);
                if (res < ZIP_SEEK_BUF_SIZE) {
                    return -1;
                }
            }
            res = i + unzReadCurrentFile(self->z, buf, offset - i);
            return (res == offset) ? 0 : -1;
        }
        default: {
            //common->FatalError( "idFile_InZip::Seek: bad origin for %s\n", name.c_str() );
            break;
        }
    }
    return -1;
}

@end
