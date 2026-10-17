/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idFileAccess.h — what idLib reads files through: the engine's idLib holds
 * an idFileSystem it does not define (idLib::fileSystem, the framework's);
 * here, the parts of idFile and idFileSystem the lexer, the parser and the
 * language dictionary use, as protocols those framework classes adopt, so
 * idLib needs nothing of the framework's.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// idFile, as idLib reads one.
@protocol idFileReading <NSObject>
- (NSString *)fullPath;
- (int)read:(void *)buffer length:(int)len error:(NSError **)error;
- (int)length;
- (unsigned int)timestamp;
@end

/// idFileSystem, as idLib opens, reads and closes files with it.
@protocol idFileSystemReading <NSObject>
- (NSString *)osPathToRelativePath:(NSString *)osPath;
- (int)readFile:(NSString *)relativePath buffer:(void *_Nullable *_Nullable)buffer timestamp:(nullable unsigned int *)timestamp error:(NSError **)error;
- (BOOL)freeFile:(void *)buffer error:(NSError **)error;
- (nullable id<idFileReading>)openFileRead:(NSString *)relativePath allowCopyFiles:(BOOL)allowCopyFiles gamedir:(nullable NSString *)gamedir error:(NSError **)error;
- (nullable id<idFileReading>)openExplicitFileRead:(NSString *)osPath;
- (BOOL)closeFile:(id<idFileReading>)f error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
