/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDImageProgram.h — images as the renderer loads them: image programs
 * (Image_program.cpp), the TGA, BMP and JPG loaders (Image_files.cpp), the
 * built-in images (Image_init.cpp) and the precompressed names
 * (Image_load.cpp), ported. No GL: an image is its 32-bit RGBA bytes.
 */

#import <Foundation/Foundation.h>

@class idFileSystem, idLexer;

NS_ASSUME_NONNULL_BEGIN

/// An image as R_LoadImageProgram leaves it: width × height RGBA bytes,
/// the top row first.
@interface UDImage : NSObject
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly) NSData *pixels;
- (instancetype)initWithWidth:(int)width height:(int)height pixels:(NSData *)pixels NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface UDImageProgram : NSObject

/// R_ParsePastImageProgram: the canonical text of the image program @a src
/// reads, advancing past it.
+ (NSString *)parsePastImageProgram:(idLexer *)src;

/// idImageManager::ImageFromFile's name for @a name: ".tga" taken out
/// everywhere, backslashes made slashes.
+ (NSString *)imageNameFromName:(NSString *)name;

/// The image ImageFromFile gives @a name: a built-in one ("_white",
/// "_flat"…), or R_LoadImageProgram's, the engine's power-of-two resample
/// done; nil, with @a problem the engine's ("Couldn't load image: …", or
/// a loader's error), when there is none to load. A precompressed .dds is
/// not decoded: the engine hands it to GL as it is.
+ (nullable UDImage *)imageNamed:(NSString *)name
                      fileSystem:(idFileSystem *)fileSystem
                         problem:(NSString * _Nullable * _Nullable)problem;

/// Whether the engine finds an image for @a name: a built-in one, the
/// files its program names (R_LoadImageProgram for timestamps), or its
/// precompressed .dds (ImageProgramStringToCompressedFileName).
+ (BOOL)imageExistsNamed:(NSString *)name fileSystem:(idFileSystem *)fileSystem;

/// The names idImageManager::Init generates images for, lowercase.
+ (NSSet<NSString *> *)builtInImageNames;

@end

NS_ASSUME_NONNULL_END
