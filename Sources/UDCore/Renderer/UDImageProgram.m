/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDImageProgram.m — Image_program.cpp, Image_files.cpp's loaders, and the
 * parts of Image_process.cpp, Image_init.cpp and Image_load.cpp they use,
 * ported. The cvars they read keep their defaults.
 */

#import "UDImageProgram.h"
#import "UDEndian.h"
#import "idFileSystem.h"
#import "idLexer.h"
#import "idToken.h"
#import "UDDeclCodec.h"
#import <objc/runtime.h>

#define STBI_NO_THREAD_LOCALS
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_ONLY_JPEG // at least for now, only use it for JPEG
#define STBI_NO_STDIO  // images are passed as buffers
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wcomma"
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#pragma clang diagnostic ignored "-Wconversion"
#import "stb_image.h"
#pragma clang diagnostic pop

typedef unsigned char byte;

#define DEFAULT_SIZE    16
#define MAX_DIMENSION   4096
#define MAX_IMAGE_NAME  256

// image_roundDown's and image_useNormalCompression's defaults.
static const BOOL UDImageRoundDown = YES;
static const int UDImageUseNormalCompression = 2;

@implementation UDImage

- (instancetype)init {
    return [self initWithWidth:0 height:0 pixels:[NSData data]];
}

- (instancetype)initWithWidth:(int)width height:(int)height pixels:(NSData *)pixels {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _pixels = [pixels copy];
    }
    return self;
}

@end

#pragma mark - idMath and idVec3

// idMath::RSqrt
static float UDRSqrt( float x ) {
    int i;
    float y, r;

    y = x * 0.5f;
    memcpy( &i, &x, sizeof( i ) );
    i = 0x5f3759df - ( i >> 1 );
    memcpy( &r, &i, sizeof( r ) );
    r = r * ( 1.5f - r * r * y );
    return r;
}

// idVec3::NormalizeFast
static float UDVec3NormalizeFast( float v[3] ) {
    float sqrLength, invLength;

    sqrLength = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
    invLength = UDRSqrt( sqrLength );
    v[0] *= invLength;
    v[1] *= invLength;
    v[2] *= invLength;
    return invLength * sqrLength;
}

// idVec3::LengthFast
static float UDVec3LengthFast( const float v[3] ) {
    float sqrLength;

    sqrLength = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
    return sqrLength * UDRSqrt( sqrLength );
}

// idVec3::Normalize (idMath::InvSqrt's table is its approximation of this)
static float UDVec3Normalize( float v[3] ) {
    float sqrLength, invLength;

    sqrLength = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
    invLength = 1.0f / sqrtf( sqrLength );
    v[0] *= invLength;
    v[1] *= invLength;
    v[2] *= invLength;
    return invLength * sqrLength;
}

#pragma mark - Image_process.cpp

/*
================
R_ResampleTexture

Used to resample images in a more general than quartering fashion.

This will only have filter coverage if the resampled size
is greater than half the original size.

If a larger shrinking is needed, use the mipmap function
after resampling to the next lower power of two.
================
*/
static byte *R_ResampleTexture( const byte *in, int inwidth, int inheight,
                               int outwidth, int outheight ) {
    int        i, j;
    const byte    *inrow, *inrow2;
    unsigned int    frac, fracstep;
    unsigned int    p1[MAX_DIMENSION], p2[MAX_DIMENSION];
    const byte        *pix1, *pix2, *pix3, *pix4;
    byte        *out, *out_p;

    if ( outwidth > MAX_DIMENSION ) {
        outwidth = MAX_DIMENSION;
    }
    if ( outheight > MAX_DIMENSION ) {
        outheight = MAX_DIMENSION;
    }

    out = (byte *)malloc( outwidth * outheight * 4 );
    out_p = out;

    fracstep = inwidth*0x10000/outwidth;

    frac = fracstep>>2;
    for ( i=0 ; i<outwidth ; i++ ) {
        p1[i] = 4*(frac>>16);
        frac += fracstep;
    }
    frac = 3*(fracstep>>2);
    for ( i=0 ; i<outwidth ; i++ ) {
        p2[i] = 4*(frac>>16);
        frac += fracstep;
    }

    for (i=0 ; i<outheight ; i++, out_p += outwidth*4 ) {
        inrow = in + 4 * inwidth * (int)( ( i + 0.25f ) * inheight / outheight );
        inrow2 = in + 4 * inwidth * (int)( ( i + 0.75f ) * inheight / outheight );
        frac = fracstep >> 1;
        for (j=0 ; j<outwidth ; j++) {
            pix1 = inrow + p1[j];
            pix2 = inrow + p2[j];
            pix3 = inrow2 + p1[j];
            pix4 = inrow2 + p2[j];
            out_p[j*4+0] = (pix1[0] + pix2[0] + pix3[0] + pix4[0])>>2;
            out_p[j*4+1] = (pix1[1] + pix2[1] + pix3[1] + pix4[1])>>2;
            out_p[j*4+2] = (pix1[2] + pix2[2] + pix3[2] + pix4[2])>>2;
            out_p[j*4+3] = (pix1[3] + pix2[3] + pix3[3] + pix4[3])>>2;
        }
    }

    return out;
}

/*
================
R_Dropsample

Used to resample images in a more general than quartering fashion.
Normal maps and such should not be bilerped.
================
*/
static byte *R_Dropsample( const byte *in, int inwidth, int inheight,
                          int outwidth, int outheight ) {
    int        i, j, k;
    const byte    *inrow;
    const byte    *pix1;
    byte        *out, *out_p;

    out = (byte *)malloc( outwidth * outheight * 4 );
    out_p = out;

    for (i=0 ; i<outheight ; i++, out_p += outwidth*4 ) {
        inrow = in + 4*inwidth*(int)((i+0.25)*inheight/outheight);
        for (j=0 ; j<outwidth ; j++) {
            k = j * inwidth / outwidth;
            pix1 = inrow + k * 4;
            out_p[j*4+0] = pix1[0];
            out_p[j*4+1] = pix1[1];
            out_p[j*4+2] = pix1[2];
            out_p[j*4+3] = pix1[3];
        }
    }

    return out;
}

/*
==================
R_VerticalFlip

Flip the image in place
==================
*/
static void R_VerticalFlip( byte *data, int width, int height ) {
    int        i, j;
    int        temp;

    for ( i = 0 ; i < width ; i++ ) {
        for ( j = 0 ; j < height / 2 ; j++ ) {
            temp = *( (int *)data + j * width + i );
            *( (int *)data + j * width + i ) = *( (int *)data + ( height - 1 - j ) * width + i );
            *( (int *)data + ( height - 1 - j ) * width + i ) = temp;
        }
    }
}

#pragma mark - Image_files.cpp

// A loader's common->Error: the load stops, and says why.
#define UD_IMAGE_ERROR(...) do { \
    if ( problem != NULL ) *problem = [NSString stringWithFormat:__VA_ARGS__]; \
    free( *pic ); *pic = NULL; \
    [fileSystem freeFile:buffer error:NULL]; \
    return; \
} while ( 0 )

static short UDReadShort( const byte *p ) {
    return LittleShort( (short)( p[0] | ( p[1] << 8 ) ) );
}

static int UDReadInt( const byte *p ) {
    return LittleLong( (int)( (unsigned)p[0] | ( (unsigned)p[1] << 8 ) | ( (unsigned)p[2] << 16 ) | ( (unsigned)p[3] << 24 ) ) );
}

typedef struct
{
    char id[2];
    unsigned int fileSize;
    unsigned int reserved0;
    unsigned int bitmapDataOffset;
    unsigned int bitmapHeaderSize;
    unsigned int width;
    unsigned int height;
    unsigned short planes;
    unsigned short bitsPerPixel;
    unsigned int compression;
    unsigned int bitmapDataSize;
    unsigned int hRes;
    unsigned int vRes;
    unsigned int colors;
    unsigned int importantColors;
    unsigned char palette[256][4];
} BMPHeader_t;

/*
==============
LoadBMP
==============
*/
static void LoadBMP( idFileSystem *fileSystem, NSString *name, byte **pic, int *width, int *height, unsigned int *timestamp, NSString **problem )
{
    int        columns, rows, numPixels;
    byte    *pixbuf;
    int        row, column;
    byte    *buf_p;
    byte    *buffer = NULL;
    int        length;
    BMPHeader_t bmpHeader;
    byte        *bmpRGBA;

    if ( !pic ) {
        [fileSystem readFile:name buffer:NULL timestamp:timestamp error:NULL];
        return;    // just getting timestamp
    }

    *pic = NULL;

    //
    // load the file
    //
    length = [fileSystem readFile:name buffer:(void **)&buffer timestamp:timestamp error:NULL];
    if ( !buffer ) {
        return;
    }

    buf_p = buffer;

    bmpHeader.id[0] = *buf_p++;
    bmpHeader.id[1] = *buf_p++;
    bmpHeader.fileSize = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.reserved0 = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.bitmapDataOffset = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.bitmapHeaderSize = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.width = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.height = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.planes = UDReadShort( buf_p );
    buf_p += 2;
    bmpHeader.bitsPerPixel = UDReadShort( buf_p );
    buf_p += 2;
    bmpHeader.compression = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.bitmapDataSize = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.hRes = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.vRes = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.colors = UDReadInt( buf_p );
    buf_p += 4;
    bmpHeader.importantColors = UDReadInt( buf_p );
    buf_p += 4;

    memcpy( bmpHeader.palette, buf_p, sizeof( bmpHeader.palette ) );

    if ( bmpHeader.bitsPerPixel == 8 )
        buf_p += 1024;

    if ( bmpHeader.id[0] != 'B' && bmpHeader.id[1] != 'M' )
    {
        UD_IMAGE_ERROR( @"LoadBMP: only Windows-style BMP files supported (%@)", name );
    }
    if ( bmpHeader.fileSize != (unsigned int)length )
    {
        UD_IMAGE_ERROR( @"LoadBMP: header size does not match file size (%u vs. %d) (%@)", bmpHeader.fileSize, length, name );
    }
    if ( bmpHeader.compression != 0 )
    {
        UD_IMAGE_ERROR( @"LoadBMP: only uncompressed BMP files supported (%@)", name );
    }
    if ( bmpHeader.bitsPerPixel < 8 )
    {
        UD_IMAGE_ERROR( @"LoadBMP: monochrome and 4-bit BMP files not supported (%@)", name );
    }

    columns = bmpHeader.width;
    rows = bmpHeader.height;
    if ( rows < 0 )
        rows = -rows;
    numPixels = columns * rows;

    if ( width )
        *width = columns;
    if ( height )
        *height = rows;

    bmpRGBA = (byte *)malloc( numPixels * 4 );
    *pic = bmpRGBA;


    for ( row = rows-1; row >= 0; row-- )
    {
        pixbuf = bmpRGBA + row*columns*4;

        for ( column = 0; column < columns; column++ )
        {
            unsigned char red, green, blue, alpha;
            int palIndex;
            unsigned short shortPixel;

            switch ( bmpHeader.bitsPerPixel )
            {
            case 8:
                palIndex = *buf_p++;
                *pixbuf++ = bmpHeader.palette[palIndex][2];
                *pixbuf++ = bmpHeader.palette[palIndex][1];
                *pixbuf++ = bmpHeader.palette[palIndex][0];
                *pixbuf++ = 0xff;
                break;
            case 16:
                shortPixel = * ( unsigned short * ) pixbuf;
                pixbuf += 2;
                *pixbuf++ = ( shortPixel & ( 31 << 10 ) ) >> 7;
                *pixbuf++ = ( shortPixel & ( 31 << 5 ) ) >> 2;
                *pixbuf++ = ( shortPixel & ( 31 ) ) << 3;
                *pixbuf++ = 0xff;
                break;

            case 24:
                blue = *buf_p++;
                green = *buf_p++;
                red = *buf_p++;
                *pixbuf++ = red;
                *pixbuf++ = green;
                *pixbuf++ = blue;
                *pixbuf++ = 255;
                break;
            case 32:
                blue = *buf_p++;
                green = *buf_p++;
                red = *buf_p++;
                alpha = *buf_p++;
                *pixbuf++ = red;
                *pixbuf++ = green;
                *pixbuf++ = blue;
                *pixbuf++ = alpha;
                break;
            default:
                UD_IMAGE_ERROR( @"LoadBMP: illegal pixel_size '%d' in file '%@'", bmpHeader.bitsPerPixel, name );
                break;
            }
        }
    }

    [fileSystem freeFile:buffer error:NULL];

}

typedef struct _TargaHeader {
    unsigned char    id_length, colormap_type, image_type;
    unsigned short    colormap_index, colormap_length;
    unsigned char    colormap_size;
    unsigned short    x_origin, y_origin, width, height;
    unsigned char    pixel_size, attributes;
} TargaHeader;

/*
=============
LoadTGA
=============
*/
static void LoadTGA( idFileSystem *fileSystem, NSString *name, byte **pic, int *width, int *height, unsigned int *timestamp, NSString **problem ) {
    int        columns, rows, numPixels, fileSize, numBytes;
    byte    *pixbuf;
    int        row, column;
    byte    *buf_p;
    byte    *buffer = NULL;
    TargaHeader    targa_header;
    byte        *targa_rgba;

    if ( !pic ) {
        [fileSystem readFile:name buffer:NULL timestamp:timestamp error:NULL];
        return;    // just getting timestamp
    }

    *pic = NULL;

    //
    // load the file
    //
    fileSize = [fileSystem readFile:name buffer:(void **)&buffer timestamp:timestamp error:NULL];
    if ( !buffer ) {
        return;
    }

    buf_p = buffer;

    targa_header.id_length = *buf_p++;
    targa_header.colormap_type = *buf_p++;
    targa_header.image_type = *buf_p++;

    targa_header.colormap_index = UDReadShort( buf_p );
    buf_p += 2;
    targa_header.colormap_length = UDReadShort( buf_p );
    buf_p += 2;
    targa_header.colormap_size = *buf_p++;
    targa_header.x_origin = UDReadShort( buf_p );
    buf_p += 2;
    targa_header.y_origin = UDReadShort( buf_p );
    buf_p += 2;
    targa_header.width = UDReadShort( buf_p );
    buf_p += 2;
    targa_header.height = UDReadShort( buf_p );
    buf_p += 2;
    targa_header.pixel_size = *buf_p++;
    targa_header.attributes = *buf_p++;

    if ( targa_header.image_type != 2 && targa_header.image_type != 10 && targa_header.image_type != 3 ) {
        UD_IMAGE_ERROR( @"LoadTGA( %@ ): Only type 2 (RGB), 3 (gray), and 10 (RGB) TGA images supported", name );
    }

    if ( targa_header.colormap_type != 0 ) {
        UD_IMAGE_ERROR( @"LoadTGA( %@ ): colormaps not supported", name );
    }

    if ( ( targa_header.pixel_size != 32 && targa_header.pixel_size != 24 ) && targa_header.image_type != 3 ) {
        UD_IMAGE_ERROR( @"LoadTGA( %@ ): Only 32 or 24 bit images supported (no colormaps)", name );
    }

    if ( targa_header.image_type == 2 || targa_header.image_type == 3 ) {
        numBytes = targa_header.width * targa_header.height * ( targa_header.pixel_size >> 3 );
        if ( numBytes > fileSize - 18 - targa_header.id_length ) {
            UD_IMAGE_ERROR( @"LoadTGA( %@ ): incomplete file", name );
        }
    }

    columns = targa_header.width;
    rows = targa_header.height;
    numPixels = columns * rows;

    if ( width ) {
        *width = columns;
    }
    if ( height ) {
        *height = rows;
    }

    targa_rgba = (byte *)malloc(numPixels*4);
    *pic = targa_rgba;

    if ( targa_header.id_length != 0 ) {
        buf_p += targa_header.id_length;  // skip TARGA image comment
    }

    if ( targa_header.image_type == 2 || targa_header.image_type == 3 )
    {
        // Uncompressed RGB or gray scale image
        for( row = rows - 1; row >= 0; row-- )
        {
            pixbuf = targa_rgba + row*columns*4;
            for( column = 0; column < columns; column++)
            {
                unsigned char red,green,blue,alphabyte;
                switch( targa_header.pixel_size )
                {

                case 8:
                    blue = *buf_p++;
                    green = blue;
                    red = blue;
                    *pixbuf++ = red;
                    *pixbuf++ = green;
                    *pixbuf++ = blue;
                    *pixbuf++ = 255;
                    break;

                case 24:
                    blue = *buf_p++;
                    green = *buf_p++;
                    red = *buf_p++;
                    *pixbuf++ = red;
                    *pixbuf++ = green;
                    *pixbuf++ = blue;
                    *pixbuf++ = 255;
                    break;
                case 32:
                    blue = *buf_p++;
                    green = *buf_p++;
                    red = *buf_p++;
                    alphabyte = *buf_p++;
                    *pixbuf++ = red;
                    *pixbuf++ = green;
                    *pixbuf++ = blue;
                    *pixbuf++ = alphabyte;
                    break;
                default:
                    UD_IMAGE_ERROR( @"LoadTGA( %@ ): illegal pixel_size '%d'", name, targa_header.pixel_size );
                    break;
                }
            }
        }
    }
    else if ( targa_header.image_type == 10 ) {   // Runlength encoded RGB images
        unsigned char red,green,blue,alphabyte,packetHeader,packetSize,j;

        red = 0;
        green = 0;
        blue = 0;
        alphabyte = 0xff;

        for( row = rows - 1; row >= 0; row-- ) {
            pixbuf = targa_rgba + row*columns*4;
            for( column = 0; column < columns; ) {
                packetHeader= *buf_p++;
                packetSize = 1 + (packetHeader & 0x7f);
                if ( packetHeader & 0x80 ) {        // run-length packet
                    switch( targa_header.pixel_size ) {
                        case 24:
                                blue = *buf_p++;
                                green = *buf_p++;
                                red = *buf_p++;
                                alphabyte = 255;
                                break;
                        case 32:
                                blue = *buf_p++;
                                green = *buf_p++;
                                red = *buf_p++;
                                alphabyte = *buf_p++;
                                break;
                        default:
                            UD_IMAGE_ERROR( @"LoadTGA( %@ ): illegal pixel_size '%d'", name, targa_header.pixel_size );
                            break;
                    }

                    for( j = 0; j < packetSize; j++ ) {
                        *pixbuf++=red;
                        *pixbuf++=green;
                        *pixbuf++=blue;
                        *pixbuf++=alphabyte;
                        column++;
                        if ( column == columns ) { // run spans across rows
                            column = 0;
                            if ( row > 0) {
                                row--;
                            }
                            else {
                                goto breakOut;
                            }
                            pixbuf = targa_rgba + row*columns*4;
                        }
                    }
                }
                else {                            // non run-length packet
                    for( j = 0; j < packetSize; j++ ) {
                        switch( targa_header.pixel_size ) {
                            case 24:
                                    blue = *buf_p++;
                                    green = *buf_p++;
                                    red = *buf_p++;
                                    *pixbuf++ = red;
                                    *pixbuf++ = green;
                                    *pixbuf++ = blue;
                                    *pixbuf++ = 255;
                                    break;
                            case 32:
                                    blue = *buf_p++;
                                    green = *buf_p++;
                                    red = *buf_p++;
                                    alphabyte = *buf_p++;
                                    *pixbuf++ = red;
                                    *pixbuf++ = green;
                                    *pixbuf++ = blue;
                                    *pixbuf++ = alphabyte;
                                    break;
                            default:
                                UD_IMAGE_ERROR( @"LoadTGA( %@ ): illegal pixel_size '%d'", name, targa_header.pixel_size );
                                break;
                        }
                        column++;
                        if ( column == columns ) { // pixel packet run spans across rows
                            column = 0;
                            if ( row > 0 ) {
                                row--;
                            }
                            else {
                                goto breakOut;
                            }
                            pixbuf = targa_rgba + row*columns*4;
                        }
                    }
                }
            }
            breakOut: ;
        }
    }

    if ( (targa_header.attributes & (1<<5)) ) {            // image flp bit
        R_VerticalFlip( *pic, *width, *height );
    }

    [fileSystem freeFile:buffer error:NULL];
}

/*
=============
LoadJPG
=============
*/
static void LoadJPG( idFileSystem *fileSystem, NSString *filename, unsigned char **pic, int *width, int *height, unsigned int *timestamp, NSString **problem ) {

    if ( pic ) {
        *pic = NULL;        // until proven otherwise
    }

    byte *fbuffer = NULL;
    int len = [fileSystem readFile:filename buffer:( pic ? (void **)&fbuffer : NULL ) timestamp:timestamp error:NULL];
    if ( len < 0 ) {
        return;
    }
    if ( !pic ) {
        return;    // just getting timestamp
    }

    int w=0, h=0, comp=0;
    byte* decodedImageData = stbi_load_from_memory( fbuffer, len, &w, &h, &comp, 4 );

    [fileSystem freeFile:fbuffer error:NULL];

    if ( decodedImageData == NULL ) {
        if ( problem != NULL ) {
            *problem = [NSString stringWithFormat:@"stb_image was unable to load JPG %@ : %s", filename, stbi_failure_reason()];
        }
        return;
    }

    int size = w*h*4;
    *pic = (byte *)malloc( size );
    memcpy( *pic, decodedImageData, size );
    *width = w;
    *height = h;
    // now that decodedImageData has been copied into *pic, it's not needed anymore
    stbi_image_free( decodedImageData );
}

/*
=================
R_LoadImage

Loads any of the supported image types into a cannonical
32 bit format.

Automatically attempts to load .jpg files if .tga files fail to load.

*pic will be NULL if the load failed.

If pic is NULL, the image won't actually be loaded, it will just find the
timestamp.

(LoadPCX32 is not ported: no Doom 3 material names a .pcx.)
=================
*/
static void R_LoadImage( idFileSystem *fileSystem, NSString *cname, byte **pic, int *width, int *height, unsigned int *timestamp, BOOL makePowerOf2, NSString **problem ) {
    NSString *name = cname;

    if ( pic ) {
        *pic = NULL;
    }
    if ( timestamp ) {
        *timestamp = FILE_NOT_FOUND_TIMESTAMP;
    }
    if ( width ) {
        *width = 0;
    }
    if ( height ) {
        *height = 0;
    }

    // idStr::DefaultFileExtension: an extension only when the last path
    // component has none.
    if ( name.lastPathComponent.pathExtension.length == 0 && ![name.lastPathComponent containsString:@"."] ) {
        name = [name stringByAppendingString:@".tga"];
    }

    if (name.length<5) {
        return;
    }

    name = name.lowercaseString;
    NSString *ext = name.pathExtension;

    if ( [ext isEqualToString:@"tga"] ) {
        LoadTGA( fileSystem, name, pic, width, height, timestamp, problem );            // try tga first
        if ( ( pic && *pic == 0 ) || ( timestamp && *timestamp == FILE_NOT_FOUND_TIMESTAMP ) ) {
            name = [name.stringByDeletingPathExtension stringByAppendingString:@".jpg"];
            LoadJPG( fileSystem, name, pic, width, height, timestamp, problem );
        }
    } else if ( [ext isEqualToString:@"bmp"] ) {
        LoadBMP( fileSystem, name, pic, width, height, timestamp, problem );
    } else if ( [ext isEqualToString:@"jpg"] ) {
        LoadJPG( fileSystem, name, pic, width, height, timestamp, problem );
    }

    if ( ( width && *width < 1 ) || ( height && *height < 1 ) ) {
        if ( pic && *pic ) {
            free( *pic );
            *pic = 0;
        }
    }

    //
    // convert to exact power of 2 sizes
    //
    if ( pic && *pic && makePowerOf2 ) {
        int        w, h;
        int        scaled_width, scaled_height;
        byte    *resampledBuffer;

        w = *width;
        h = *height;

        for (scaled_width = 1 ; scaled_width < w ; scaled_width<<=1)
            ;
        for (scaled_height = 1 ; scaled_height < h ; scaled_height<<=1)
            ;

        if ( scaled_width != w || scaled_height != h ) {
            if ( UDImageRoundDown && scaled_width > w ) {
                scaled_width >>= 1;
            }
            if ( UDImageRoundDown && scaled_height > h ) {
                scaled_height >>= 1;
            }

            resampledBuffer = R_ResampleTexture( *pic, w, h, scaled_width, scaled_height );
            free( *pic );
            *pic = resampledBuffer;
            *width = MIN( scaled_width, MAX_DIMENSION );
            *height = MIN( scaled_height, MAX_DIMENSION );
        }
    }
}

#pragma mark - Image_program.cpp

/*
=================
R_HeightmapToNormalMap

it is not possible to convert a heightmap into a normal map
properly without knowing the texture coordinate stretching.
We can assume constant and equal ST vectors for walls, but not for characters.
=================
*/
static void R_HeightmapToNormalMap( byte *data, int width, int height, float scale ) {
    int        i, j;
    byte    *depth;

    scale = scale / 256;

    // copy and convert to grey scale
    j = width * height;
    depth = (byte *)malloc( j );
    for ( i = 0 ; i < j ; i++ ) {
        depth[i] = ( data[i*4] + data[i*4+1] + data[i*4+2] ) / 3;
    }

    for ( i = 0 ; i < height ; i++ ) {
        for ( j = 0 ; j < width ; j++ ) {
            int        d1, d2, d3, d4;
            int        a1, a3, a4;
            float    dir[3], dir2[3];

            // FIXME: look at five points?

            // look at three points to estimate the gradient
            a1 = d1 = depth[ ( i * width + j ) ];
            d2 = depth[ ( i * width + ( ( j + 1 ) & ( width - 1 ) ) ) ];
            a3 = d3 = depth[ ( ( ( i + 1 ) & ( height - 1 ) ) * width + j ) ];
            a4 = d4 = depth[ ( ( ( i + 1 ) & ( height - 1 ) ) * width + ( ( j + 1 ) & ( width - 1 ) ) ) ];

            d2 -= d1;
            d3 -= d1;

            dir[0] = -d2 * scale;
            dir[1] = -d3 * scale;
            dir[2] = 1;
            UDVec3NormalizeFast( dir );

            a1 -= a3;
            a4 -= a3;

            dir2[0] = -a4 * scale;
            dir2[1] = a1 * scale;
            dir2[2] = 1;
            UDVec3NormalizeFast( dir2 );

            dir[0] += dir2[0];
            dir[1] += dir2[1];
            dir[2] += dir2[2];
            UDVec3NormalizeFast( dir );

            a1 = ( i * width + j ) * 4;
            data[ a1 + 0 ] = (byte)(dir[0] * 127 + 128);
            data[ a1 + 1 ] = (byte)(dir[1] * 127 + 128);
            data[ a1 + 2 ] = (byte)(dir[2] * 127 + 128);
            data[ a1 + 3 ] = 255;
        }
    }


    free( depth );
}

/*
=================
R_ImageScale
=================
*/
static void R_ImageScale( byte *data, int width, int height, float scale[4] ) {
    int        i, j;
    int        c;

    c = width * height * 4;

    for ( i = 0 ; i < c ; i++ ) {
        j = (byte)(data[i] * scale[i&3]);
        if ( j < 0 ) {
            j = 0;
        } else if ( j > 255 ) {
            j = 255;
        }
        data[i] = j;
    }
}

/*
=================
R_InvertAlpha
=================
*/
static void R_InvertAlpha( byte *data, int width, int height ) {
    int        i;
    int        c;

    c = width * height* 4;

    for ( i = 0 ; i < c ; i+=4 ) {
        data[i+3] = 255 - data[i+3];
    }
}

/*
=================
R_InvertColor
=================
*/
static void R_InvertColor( byte *data, int width, int height ) {
    int        i;
    int        c;

    c = width * height* 4;

    for ( i = 0 ; i < c ; i+=4 ) {
        data[i+0] = 255 - data[i+0];
        data[i+1] = 255 - data[i+1];
        data[i+2] = 255 - data[i+2];
    }
}


/*
===================
R_AddNormalMaps

===================
*/
static void R_AddNormalMaps( byte *data1, int width1, int height1, byte *data2, int width2, int height2 ) {
    int        i, j;
    byte    *newMap;

    // resample pic2 to the same size as pic1
    if ( width2 != width1 || height2 != height1 ) {
        newMap = R_Dropsample( data2, width2, height2, width1, height1 );
        data2 = newMap;
    } else {
        newMap = NULL;
    }

    // add the normal change from the second and renormalize
    for ( i = 0 ; i < height1 ; i++ ) {
        for ( j = 0 ; j < width1 ; j++ ) {
            byte    *d1, *d2;
            float   n[3];
            float   len;

            d1 = data1 + ( i * width1 + j ) * 4;
            d2 = data2 + ( i * width1 + j ) * 4;

            n[0] = ( d1[0] - 128 ) / 127.0;
            n[1] = ( d1[1] - 128 ) / 127.0;
            n[2] = ( d1[2] - 128 ) / 127.0;

            // There are some normal maps that blend to 0,0,0 at the edges
            // this screws up compression, so we try to correct that here by instead fading it to 0,0,1
            len = UDVec3LengthFast( n );
            if ( len < 1.0f ) {
                n[2] = sqrtf(1.0 - (n[0]*n[0]) - (n[1]*n[1]));
            }

            n[0] += ( d2[0] - 128 ) / 127.0;
            n[1] += ( d2[1] - 128 ) / 127.0;
            UDVec3Normalize( n );

            d1[0] = (byte)(n[0] * 127 + 128);
            d1[1] = (byte)(n[1] * 127 + 128);
            d1[2] = (byte)(n[2] * 127 + 128);
            d1[3] = 255;
        }
    }

    if ( newMap ) {
        free( newMap );
    }
}

/*
================
R_SmoothNormalMap
================
*/
static void R_SmoothNormalMap( byte *data, int width, int height ) {
    byte    *orig;
    int        i, j, k, l;
    float    normal[3];
    byte    *out;
    static float    factors[3][3] = {
        { 1, 1, 1 },
        { 1, 1, 1 },
        { 1, 1, 1 }
    };

    orig = (byte *)malloc( width * height * 4 );
    memcpy( orig, data, width * height * 4 );

    for ( i = 0 ; i < width ; i++ ) {
        for ( j = 0 ; j < height ; j++ ) {
            normal[0] = normal[1] = normal[2] = 0;
            for ( k = -1 ; k < 2 ; k++ ) {
                for ( l = -1 ; l < 2 ; l++ ) {
                    byte    *in;

                    in = orig + ( ((j+l)&(height-1))*width + ((i+k)&(width-1)) ) * 4;

                    // ignore 000 and -1 -1 -1
                    if ( in[0] == 0 && in[1] == 0 && in[2] == 0 ) {
                        continue;
                    }
                    if ( in[0] == 128 && in[1] == 128 && in[2] == 128 ) {
                        continue;
                    }

                    normal[0] += factors[k+1][l+1] * ( in[0] - 128 );
                    normal[1] += factors[k+1][l+1] * ( in[1] - 128 );
                    normal[2] += factors[k+1][l+1] * ( in[2] - 128 );
                }
            }
            UDVec3Normalize( normal );
            out = data + ( j * width + i ) * 4;
            out[0] = (byte)(128 + 127 * normal[0]);
            out[1] = (byte)(128 + 127 * normal[1]);
            out[2] = (byte)(128 + 127 * normal[2]);
        }
    }

    free( orig );
}


/*
===================
R_ImageAdd

===================
*/
static void R_ImageAdd( byte *data1, int width1, int height1, byte *data2, int width2, int height2 ) {
    int        i, j;
    int        c;
    byte    *newMap;

    // resample pic2 to the same size as pic1
    if ( width2 != width1 || height2 != height1 ) {
        newMap = R_Dropsample( data2, width2, height2, width1, height1 );
        data2 = newMap;
    } else {
        newMap = NULL;
    }


    c = width1 * height1 * 4;

    for ( i = 0 ; i < c ; i++ ) {
        j = data1[i] + data2[i];
        if ( j > 255 ) {
            j = 255;
        }
        data1[i] = j;
    }

    if ( newMap ) {
        free( newMap );
    }
}

// The program parse's state: the canonical token form of the image
// program (the engine's static parseBuffer), the file system, and what a
// loader said.
typedef struct {
    __unsafe_unretained idFileSystem *fileSystem;
    __unsafe_unretained NSMutableString *parseBuffer;
    __autoreleasing NSString **problem;
} UDImageProgramState;

/*
===================
AppendToken
===================
*/
static void AppendToken( UDImageProgramState *state, idToken *token ) {
    // add a leading space if not at the beginning
    if ( state->parseBuffer.length > 0 ) {
        [state->parseBuffer appendString:@" "];
    }
    [state->parseBuffer appendString:UDTokenString( token )];
}

/*
===================
MatchAndAppendToken
===================
*/
static void MatchAndAppendToken( UDImageProgramState *state, idLexer *src, NSString *match ) {
    if ( ![src expectTokenString:match error:NULL] ) {
        return;
    }
    // a matched token won't need a leading space
    [state->parseBuffer appendString:match];
}

/*
===================
R_ParseImageProgram_r

If pic is NULL, the timestamps will be filled in, but no image will be generated
If both pic and timestamps are NULL, it will just advance past it, which can be
used to parse an image program from a text stream.
===================
*/
static BOOL R_ParseImageProgram_r( UDImageProgramState *state, idLexer *src, byte **pic, int *width, int *height,
                                  unsigned int *timestamps ) {
    idToken        token;
    float        scale;
    unsigned int        timestamp;

    idToken_Init( &token );
    [src readToken:&token error:NULL];
    AppendToken( state, &token );

    if ( !strcasecmp( token.text, "heightmap" ) ) {
        MatchAndAppendToken( state, src, @"(" );

        if ( !R_ParseImageProgram_r( state, src, pic, width, height, timestamps ) ) {
            return NO;
        }

        MatchAndAppendToken( state, src, @"," );

        [src readToken:&token error:NULL];
        AppendToken( state, &token );
        scale = idToken_FloatValue( &token );

        // process it
        if ( pic ) {
            R_HeightmapToNormalMap( *pic, *width, *height, scale );
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    if ( !strcasecmp( token.text, "addnormals" ) ) {
        byte    *pic2 = NULL;
        int        width2, height2;

        MatchAndAppendToken( state, src, @"(" );

        if ( !R_ParseImageProgram_r( state, src, pic, width, height, timestamps ) ) {
            return NO;
        }

        MatchAndAppendToken( state, src, @"," );

        if ( !R_ParseImageProgram_r( state, src, pic ? &pic2 : NULL, &width2, &height2, timestamps ) ) {
            if ( pic ) {
                free( *pic );
                *pic = NULL;
            }
            return NO;
        }

        // process it
        if ( pic ) {
            R_AddNormalMaps( *pic, *width, *height, pic2, width2, height2 );
            free( pic2 );
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    if ( !strcasecmp( token.text, "smoothnormals" ) ) {
        MatchAndAppendToken( state, src, @"(" );

        if ( !R_ParseImageProgram_r( state, src, pic, width, height, timestamps ) ) {
            return NO;
        }

        if ( pic ) {
            R_SmoothNormalMap( *pic, *width, *height );
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    if ( !strcasecmp( token.text, "add" ) ) {
        byte    *pic2 = NULL;
        int        width2, height2;

        MatchAndAppendToken( state, src, @"(" );

        if ( !R_ParseImageProgram_r( state, src, pic, width, height, timestamps ) ) {
            return NO;
        }

        MatchAndAppendToken( state, src, @"," );

        if ( !R_ParseImageProgram_r( state, src, pic ? &pic2 : NULL, &width2, &height2, timestamps ) ) {
            if ( pic ) {
                free( *pic );
                *pic = NULL;
            }
            return NO;
        }

        // process it
        if ( pic ) {
            R_ImageAdd( *pic, *width, *height, pic2, width2, height2 );
            free( pic2 );
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    if ( !strcasecmp( token.text, "scale" ) ) {
        float    scale[4];
        int        i;

        MatchAndAppendToken( state, src, @"(" );

        R_ParseImageProgram_r( state, src, pic, width, height, timestamps );

        for ( i = 0 ; i < 4 ; i++ ) {
            MatchAndAppendToken( state, src, @"," );
            [src readToken:&token error:NULL];
            AppendToken( state, &token );
            scale[i] = idToken_FloatValue( &token );
        }

        // process it
        if ( pic && *pic ) {
            R_ImageScale( *pic, *width, *height, scale );
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    if ( !strcasecmp( token.text, "invertAlpha" ) ) {
        MatchAndAppendToken( state, src, @"(" );

        R_ParseImageProgram_r( state, src, pic, width, height, timestamps );

        // process it
        if ( pic && *pic ) {
            R_InvertAlpha( *pic, *width, *height );
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    if ( !strcasecmp( token.text, "invertColor" ) ) {
        MatchAndAppendToken( state, src, @"(" );

        R_ParseImageProgram_r( state, src, pic, width, height, timestamps );

        // process it
        if ( pic && *pic ) {
            R_InvertColor( *pic, *width, *height );
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    if ( !strcasecmp( token.text, "makeIntensity" ) ) {
        int        i;

        MatchAndAppendToken( state, src, @"(" );

        R_ParseImageProgram_r( state, src, pic, width, height, timestamps );

        // copy red to green, blue, and alpha
        if ( pic && *pic ) {
            int        c;
            c = *width * *height * 4;
            for ( i = 0 ; i < c ; i+=4 ) {
                (*pic)[i+1] =
                (*pic)[i+2] =
                (*pic)[i+3] = (*pic)[i];
            }
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    if ( !strcasecmp( token.text, "makeAlpha" ) ) {
        int        i;

        MatchAndAppendToken( state, src, @"(" );

        R_ParseImageProgram_r( state, src, pic, width, height, timestamps );

        // average RGB into alpha, then set RGB to white
        if ( pic && *pic ) {
            int        c;
            c = *width * *height * 4;
            for ( i = 0 ; i < c ; i+=4 ) {
                (*pic)[i+3] = ( (*pic)[i+0] + (*pic)[i+1] + (*pic)[i+2] ) / 3;
                (*pic)[i+0] =
                (*pic)[i+1] =
                (*pic)[i+2] = 255;
            }
        }

        MatchAndAppendToken( state, src, @")" );
        return YES;
    }

    // if we are just parsing instead of loading or checking,
    // don't do the R_LoadImage
    if ( !timestamps && !pic ) {
        return YES;
    }

    // load it as an image
    R_LoadImage( state->fileSystem, UDTokenString( &token ), pic, width, height, &timestamp, YES, state->problem );

    if ( timestamp == FILE_NOT_FOUND_TIMESTAMP ) {
        return NO;
    }

    // add this to the timestamp
    if ( timestamps ) {
        if ( timestamp > *timestamps ) {
            *timestamps = timestamp;
        }
    }

    return YES;
}

/// A lexer over an image program's text, as R_LoadImageProgram makes one.
static idLexer *UDImageProgramLexer(NSString *name, idFileSystem *fileSystem) {
    NSData *text = [name dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    idLexer *src = [[idLexer alloc] initWithFileSystem:fileSystem];
    NSMutableData *buffer = [text mutableCopy];
    [buffer appendBytes:"" length:1];
    [src setFlags:LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_NOSTRINGESCAPECHARS | LEXFL_ALLOWPATHNAMES |
                  LEXFL_NOERRORS | LEXFL_NOWARNINGS];
    if (![src loadMemory:buffer.bytes length:(int)text.length name:name startLine:1 error:NULL]) {
        return nil;
    }
    // loadMemory borrows the bytes (see UDDeclCodecLexerWithFlags).
    objc_setAssociatedObject(src, (__bridge const void *)src, buffer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return src;
}

/*
===================
R_LoadImageProgram
===================
*/
static void R_LoadImageProgram( idFileSystem *fileSystem, NSString *name, byte **pic, int *width, int *height, unsigned int *timestamps, NSString **problem ) {
    idLexer *src = UDImageProgramLexer( name, fileSystem );
    NSMutableString *parseBuffer = [NSMutableString string];
    UDImageProgramState state = { fileSystem, parseBuffer, problem };

    if ( timestamps ) {
        *timestamps = 0;
    }

    if ( src != nil ) {
        R_ParseImageProgram_r( &state, src, pic, width, height, timestamps );
    }

    [src freeSource];
}

#pragma mark - Image_load.cpp

/*
================
ImageProgramStringToCompressedFileName
================
*/
static NSString *ImageProgramStringToCompressedFileName( NSString *imageProg ) {
    const char    *s;
    char    fileName[MAX_IMAGE_NAME * 2];
    char    *f;

    strcpy( fileName, "dds/" );
    f = fileName + strlen( fileName );

    int depth = 0;

    // convert all illegal characters to underscores
    // this could conceivably produce a duplicated mapping, but we aren't going to worry about it
    for ( s = imageProg.UTF8String ; *s && f < fileName + sizeof( fileName ) - 5 ; s++ ) {
        if ( *s == '/' || *s == '\\' || *s == '(') {
            if ( depth < 4 ) {
                *f = '/';
                depth ++;
            } else {
                *f = ' ';
            }
            f++;
        } else if ( *s == '<' || *s == '>' || *s == ':' || *s == '|' || *s == '"' || *s == '.' ) {
            *f = '_';
            f++;
        } else if ( *s == ' ' && *(f-1) == '/' ) {    // ignore a space right after a slash
        } else if ( *s == ')' || *s == ',' ) {        // always ignore these
        } else {
            *f = *s;
            f++;
        }
    }
    *f++ = 0;
    strcat( fileName, ".dds" );
    return @(fileName);
}

#pragma mark - Image_init.cpp

static UDImage *UDImageWithBytes(const byte *data, int width, int height) {
    return [[UDImage alloc] initWithWidth:width height:height pixels:[NSData dataWithBytes:data length:(NSUInteger)(width * height * 4)]];
}

/*
==================
idImage::MakeDefault

the default image will be grey with a white box outline
to allow you to see the mapping coordinates on a surface
(com_developer's; without it, as its default is, all zero)
==================
*/
static UDImage *R_DefaultImage( void ) {
    byte    data[DEFAULT_SIZE][DEFAULT_SIZE][4];
    memset( data, 0, sizeof( data ) );
    return UDImageWithBytes( (byte *)data, DEFAULT_SIZE, DEFAULT_SIZE );
}

static UDImage *R_WhiteImage( void ) {
    byte    data[DEFAULT_SIZE][DEFAULT_SIZE][4];

    // solid white texture
    memset( data, 255, sizeof( data ) );
    return UDImageWithBytes( (byte *)data, DEFAULT_SIZE, DEFAULT_SIZE );
}

static UDImage *R_BlackImage( void ) {
    byte    data[DEFAULT_SIZE][DEFAULT_SIZE][4];

    // solid black texture
    memset( data, 0, sizeof( data ) );
    return UDImageWithBytes( (byte *)data, DEFAULT_SIZE, DEFAULT_SIZE );
}

static UDImage *R_FlatNormalImage( void ) {
    byte    data[DEFAULT_SIZE][DEFAULT_SIZE][4];
    int        i;

    int red = ( UDImageUseNormalCompression == 1 ) ? 0 : 3;
    int alpha = ( red == 0 ) ? 3 : 0;
    // flat normal map for default bunp mapping
    for ( i = 0 ; i < 4 ; i++ ) {
        data[0][i][red] = 128;
        data[0][i][1] = 128;
        data[0][i][2] = 255;
        data[0][i][alpha] = 255;
    }
    return UDImageWithBytes( (byte *)data, 2, 2 );
}

/*
================
R_SpecularTableImage

Creates a ramp that matches our fudged specular calculation
================
*/
static UDImage *R_SpecularTableImage( void ) {
    int        x;
    byte    data[256][4];

    for (x=0 ; x<256 ; x++) {
        float f = x/255.f;
        // this is the behavior of the hacked up fragment programs that
        // can't really do a power function
        f = (f-0.75)*4;
        if ( f < 0 ) {
            f = 0;
        }
        f = f * f;
        int        b = (int)(f * 255);

        data[x][0] =
        data[x][1] =
        data[x][2] =
        data[x][3] = b;
    }

    return UDImageWithBytes( (byte *)data, 256, 1 );
}

#define    NORMAL_MAP_SIZE        32

/*
================
getCubeVector
================
*/
static void getCubeVector(int i, int cubesize, int x, int y, float *vector) {
  float s, t, sc, tc, mag;

  s = ((float)x + 0.5) / (float)cubesize;
  t = ((float)y + 0.5) / (float)cubesize;
  sc = s*2.0 - 1.0;
  tc = t*2.0 - 1.0;

  switch (i) {
  case 0:
    vector[0] = 1.0;
    vector[1] = -tc;
    vector[2] = -sc;
    break;
  case 1:
    vector[0] = -1.0;
    vector[1] = -tc;
    vector[2] = sc;
    break;
  case 2:
    vector[0] = sc;
    vector[1] = 1.0;
    vector[2] = tc;
    break;
  case 3:
    vector[0] = sc;
    vector[1] = -1.0;
    vector[2] = -tc;
    break;
  case 4:
    vector[0] = sc;
    vector[1] = -tc;
    vector[2] = 1.0;
    break;
  case 5:
    vector[0] = -sc;
    vector[1] = -tc;
    vector[2] = -1.0;
    break;
  default:
    return;
  }

  mag = 1.0f / sqrtf(vector[0]*vector[0] + vector[1]*vector[1] + vector[2]*vector[2]);     // idMath::InvSqrt
  vector[0] *= mag;
  vector[1] *= mag;
  vector[2] *= mag;
}

/*
=================
makeNormalizeVectorCubeMap

Creates a cube map to normalize the vector towards the light
=================
*/
static NSArray<UDImage *> *makeNormalizeVectorCubeMap( void ) {
    float vector[3] = { 0, 0, 0 };
    int i, x, y;
    int        size = NORMAL_MAP_SIZE;
    NSMutableArray<UDImage *> *faces = [NSMutableArray arrayWithCapacity:6];
    byte *pixels = malloc( size*size*4 );

    for (i = 0; i < 6; i++) {
        for (y = 0; y < size; y++) {
          for (x = 0; x < size; x++) {
            getCubeVector(i, size, x, y, vector);
            pixels[4*(y*size+x) + 0] = (byte)(128 + 127*vector[0]);
            pixels[4*(y*size+x) + 1] = (byte)(128 + 127*vector[1]);
            pixels[4*(y*size+x) + 2] = (byte)(128 + 127*vector[2]);
            pixels[4*(y*size+x) + 3] = 255;
          }
        }
        [faces addObject:UDImageWithBytes( pixels, size, size )];
    }

    free( pixels );
    return faces;
}

/*
================
R_AmbientNormalImage
================
*/
static NSArray<UDImage *> *R_AmbientNormalImage( void ) {
    byte    data[DEFAULT_SIZE][DEFAULT_SIZE][4];
    int        i;
    // tr.ambientLightVector, as idRenderSystemLocal::Init sets it
    const float ambientLightVector[3] = { 0.5f, 0.5f - 0.385f, 0.8925f };

    int red = ( UDImageUseNormalCompression == 1 ) ? 0 : 3;
    int alpha = ( red == 0 ) ? 3 : 0;
    // flat normal map for default bunp mapping
    for ( i = 0 ; i < 4 ; i++ ) {
        data[0][i][red] = (byte)(255 * ambientLightVector[0]);
        data[0][i][1] = (byte)(255 * ambientLightVector[1]);
        data[0][i][2] = (byte)(255 * ambientLightVector[2]);
        data[0][i][alpha] = 255;
    }
    // this must be a cube map for fragment programs to simply substitute for the normalization cube map
    UDImage *face = UDImageWithBytes( (byte *)data, 2, 2 );
    return @[face, face, face, face, face, face];
}

@implementation UDImageProgram

+ (NSArray<UDImage *> *)cubeImageNamed:(NSString *)name {
    NSString *lower = name.lowercaseString;
    if ( [lower isEqualToString:@"_normalcubemap"] ) return makeNormalizeVectorCubeMap();
    if ( [lower isEqualToString:@"_ambient"] ) return R_AmbientNormalImage();
    return nil;
}

+ (NSSet<NSString *> *)builtInImageNames {
    static NSSet<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[
            @"_default", @"_white", @"_black", @"_borderclamp", @"_flat", @"_ambient", @"_speculartable",
            @"_specular2dtable", @"_ramp", @"_alpharamp", @"_alphanotch", @"_fog", @"_fogenter",
            @"_normalcubemap", @"_nofalloff", @"_quadratic", @"_cinematic", @"_scratch", @"_scratch2",
            @"_accum", @"_scratchcubemap", @"_currentrender", @"_currentdepth"]];
    });
    return names;
}

+ (NSString *)parsePastImageProgram:(idLexer *)src {
    NSMutableString *parseBuffer = [NSMutableString string];
    UDImageProgramState state = { nil, parseBuffer, NULL };
    R_ParseImageProgram_r( &state, src, NULL, NULL, NULL, NULL );
    return [parseBuffer copy];
}

+ (NSString *)imageNameFromName:(NSString *)name {
    // strip any .tga file extensions from anywhere in the _name, including image program parameters
    return [[name stringByReplacingOccurrencesOfString:@".tga" withString:@""]
            stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
}

+ (UDImage *)imageNamed:(NSString *)rawName fileSystem:(idFileSystem *)fileSystem problem:(NSString **)problem {
    if ( rawName.length == 0 || [rawName caseInsensitiveCompare:@"default"] == NSOrderedSame ) {
        return R_DefaultImage();
    }
    NSString *name = [self imageNameFromName:rawName];
    NSString *lower = name.lowercaseString;
    if ( [lower isEqualToString:@"_default"] ) return R_DefaultImage();
    if ( [lower isEqualToString:@"_white"] ) return R_WhiteImage();
    if ( [lower isEqualToString:@"_black"] ) return R_BlackImage();
    if ( [lower isEqualToString:@"_flat"] ) return R_FlatNormalImage();
    if ( [lower isEqualToString:@"_speculartable"] ) return R_SpecularTableImage();
    if ( [[self builtInImageNames] containsObject:lower] ) {
        if ( problem != NULL ) *problem = [NSString stringWithFormat:@"%@ is generated by the renderer as it draws", name];
        return nil;
    }

    byte *pic = NULL;
    int width = 0, height = 0;
    unsigned int timestamp = 0;
    NSString *loaderProblem = nil;
    R_LoadImageProgram( fileSystem, name, &pic, &width, &height, &timestamp, &loaderProblem );
    if ( pic == NULL ) {
        if ( problem != NULL ) {
            *problem = loaderProblem ?: [NSString stringWithFormat:@"Couldn't load image: %@", name];
            if ( loaderProblem == nil && [fileSystem readFile:ImageProgramStringToCompressedFileName( name ) buffer:NULL timestamp:NULL error:NULL] >= 0 ) {
                *problem = [NSString stringWithFormat:@"%@ is only precompressed (%@), which goes to GL as it is",
                            name, ImageProgramStringToCompressedFileName( name )];
            }
        }
        return nil;
    }
    UDImage *image = UDImageWithBytes( pic, width, height );
    free( pic );
    return image;
}

+ (UDImage *)loadImage:(NSString *)name fileSystem:(idFileSystem *)fileSystem {
    byte *pic = NULL;
    int width = 0, height = 0;
    R_LoadImage( fileSystem, name, &pic, &width, &height, NULL, NO, NULL );
    if ( pic == NULL ) {
        return nil;
    }
    NSData *pixels = [NSData dataWithBytes:pic length:(NSUInteger)width * height * 4];
    free( pic );
    return [[UDImage alloc] initWithWidth:width height:height pixels:pixels];
}

+ (BOOL)imageExistsNamed:(NSString *)rawName fileSystem:(idFileSystem *)fileSystem {
    if ( rawName.length == 0 || [rawName caseInsensitiveCompare:@"default"] == NSOrderedSame ) {
        return YES;
    }
    NSString *name = [self imageNameFromName:rawName];
    if ( [[self builtInImageNames] containsObject:name.lowercaseString] ) {
        return YES;
    }
    // idImage::CheckPrecompressedImage's file, then the program's own.
    if ( [fileSystem readFile:ImageProgramStringToCompressedFileName( name ) buffer:NULL timestamp:NULL error:NULL] >= 0 ) {
        return YES;
    }
    unsigned int timestamp = 0;
    idLexer *src = UDImageProgramLexer( name, fileSystem );
    if ( src == nil ) {
        return NO;
    }
    NSMutableString *parseBuffer = [NSMutableString string];      // the state's, unretained: held here
    UDImageProgramState state = { fileSystem, parseBuffer, NULL };
    BOOL found = R_ParseImageProgram_r( &state, src, NULL, NULL, NULL, &timestamp );
    [src freeSource];
    return found;
}

@end
