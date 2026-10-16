/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDSoftwareRenderer.m — RB_STD_T_RenderShaderPasses' old-style stages and
 * RB_GetShaderTextureMatrix (draw_common.cpp, tr_render.cpp), ported, over
 * what the engine leaves to GL: the projection, a texture's sampling (its
 * repeat), GL_MODULATE with the vertex or constant color, and the blend
 * function the stage's drawStateBits name. This last part is not id's: it
 * is GL 1.x's fixed-function pipeline as its specification has it.
 *
 * Particles do not write depth (they are translucent, GLS_DEPTHMASK), so
 * there is no depth buffer: surfaces are drawn in the engine's order.
 * New-style stages (vertex and fragment programs) are not drawn; nor are
 * cube maps, cinematics or renders of the view.
 */

#import "UDSoftwareRenderer.h"
#import "UDImageProgram.h"
#import "UDMaterialParser.h"
#import "UDARBProgram.h"
#import "idFileSystem.h"
#import "idDeclManager.h"

typedef struct {
    float x, y;          // in the picture, its top row first
    float invW;          // 1 / the view's depth
    float s, t;          // texture coordinates, over the depth
    float r, g, b, a;    // vertex color 0–1, over the depth
} UDScreenVert;

@implementation UDPointLight {
    float lightOrigin[3];
    float lightRadius[3];
    float parms[12];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        lightRadius[0] = lightRadius[1] = lightRadius[2] = 300;
        // SHADERPARM_RED, _GREEN, _BLUE, _TIMESCALE
        parms[0] = parms[1] = parms[2] = parms[3] = 1;
    }
    return self;
}

- (float *)origin { return lightOrigin; }
- (float *)radius { return lightRadius; }
- (float *)shaderParms { return parms; }

@end

@interface UDSoftwareRenderer () {
    float *pixels;           // RGBA, 0–1, the top row first
    float viewOrigin[3];
    float viewAxis[3][3];
    float projX, projY;      // the half picture over tan( half fov )
    BOOL guiView;            // EmitFullScreen's: qglOrtho( 0, 640, 480, 0, 0, 1 )
}
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *sortOverrides;
@property (nonatomic, strong, nullable) idDeclManager *declManager;
@property (nonatomic, strong, nullable) idFileSystem *fileSystem;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDMaterialParser *> *materials;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *images;
@property (nonatomic, strong, nullable) UDARBProgram *interactionVertexProgram;
@property (nonatomic, strong, nullable) UDARBProgram *interactionFragmentProgram;
@property (nonatomic, copy, readwrite, nullable) NSString *interactionProblem;
@property (nonatomic) BOOL interactionLoaded;
@end

@implementation UDSoftwareRenderer

- (instancetype)initWithWidth:(int)width height:(int)height declManager:(idDeclManager *)declManager fileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        _width = MAX( width, 1 );
        _height = MAX( height, 1 );
        _declManager = declManager;
        _fileSystem = fileSystem;
        _materials = [NSMutableDictionary dictionary];
        _images = [NSMutableDictionary dictionary];
        _sortOverrides = [NSMutableDictionary dictionary];
        pixels = calloc( (size_t)( _width * _height * 4 ), sizeof( float ) );
        float origin[3] = { 0, 0, 0 };
        float axis[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
        [self setViewOrigin:origin axis:axis fovX:90];
    }
    return self;
}

- (void)dealloc {
    free( pixels );
}

- (void)resizeToWidth:(int)width height:(int)height {
    width = MAX( width, 1 );
    height = MAX( height, 1 );
    if ( width == _width && height == _height ) {
        return;
    }
    free( pixels );
    _width = width;
    _height = height;
    pixels = calloc( (size_t)( _width * _height * 4 ), sizeof( float ) );
    if ( !guiView ) {
        float halfX = self.width * 0.5f / projX;
        float fovX = atanf( halfX ) * 2.0f * 180.0f / (float)M_PI;
        [self setViewOrigin:viewOrigin axis:viewAxis fovX:fovX];
    }
}

- (void)setGuiView {
    guiView = YES;
}

- (void)setSort:(float)sort forMaterial:(NSString *)name {
    self.sortOverrides[name] = @( sort );
}

- (float)sortOfMaterial:(NSString *)name {
    NSNumber *sort = self.sortOverrides[name];
    return sort != nil ? sort.floatValue : [self materialNamed:name].sort;
}

- (void)setViewOrigin:(const float [3])origin axis:(const float [3][3])axis fovX:(float)fovX {
    guiView = NO;
    memcpy( viewOrigin, origin, sizeof( viewOrigin ) );
    memcpy( viewAxis, axis, sizeof( viewAxis ) );
    float halfX = tanf( fovX * 0.5f * (float)M_PI / 180.0f );
    projX = self.width * 0.5f / halfX;
    projY = projX;                                   // square pixels
}

- (void)clearToColor:(const float [4])color {
    for ( int i = 0; i < self.width * self.height; i++ ) {
        memcpy( pixels + i * 4, color, 4 * sizeof( float ) );
    }
}

- (UDImage *)image {
    NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)( self.width * self.height * 4 )];
    uint8_t *out = bytes.mutableBytes;
    for ( int i = 0; i < self.width * self.height * 4; i++ ) {
        float v = pixels[i];
        out[i] = (uint8_t)( v <= 0 ? 0 : v >= 1 ? 255 : (int)( v * 255.0f + 0.5f ) );
    }
    return [[UDImage alloc] initWithWidth:self.width height:self.height pixels:bytes];
}

#pragma mark - Materials and images

- (void)setMaterialText:(NSString *)text forName:(NSString *)name {
    self.materials[name] = [[UDMaterialParser alloc] initWithText:text name:name declManager:self.declManager];
}

- (UDMaterialParser *)materialNamed:(NSString *)name {
    UDMaterialParser *material = self.materials[name];
    if ( material == nil ) {
        // declManager->FindMaterial: the decl's text, idMaterial::Parse'd;
        // for a name no decl defines, idMaterial::SetDefaultText's.
        NSString *text = nil;
        idDeclBase *decl = [self.declManager findDeclWithoutParsing:DECL_MATERIAL name:name makeDefault:NO];
        if ( decl != nil ) {
            NSMutableData *buffer = [NSMutableData data];
            [decl text:buffer];
            if ( buffer.length > 0 ) [buffer setLength:buffer.length - 1];
            text = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
        }
        if ( text == nil ) {
            text = [UDSoftwareRenderer defaultTextForMaterial:name];
        }
        material = [[UDMaterialParser alloc] initWithText:text name:name declManager:self.declManager];
        self.materials[name] = material;
    }
    return material;
}

/*
==================
idMaterial::SetDefaultText
==================
*/
+ (NSString *)defaultTextForMaterial:(NSString *)name {
    // if there exists an image with the same name
    return [NSString stringWithFormat:
                        @"material %@ // IMPLICITLY GENERATED\n"
                        "{\n"
                        "{\n"
                        "blend blend\n"
                        "colored\n"
                        "map \"%@\"\n"
                        "clamp\n"
                        "}\n"
                        "}\n", name, name];
}

- (nullable UDImage *)imageNamed:(NSString *)name {
    id image = self.images[name];
    if ( image == nil ) {
        image = [UDImageProgram imageNamed:name fileSystem:self.fileSystem problem:NULL] ?: [NSNull null];
        self.images[name] = image;
    }
    return image == [NSNull null] ? nil : image;
}

- (void)setImage:(UDImage *)image forName:(NSString *)name {
    self.images[name] = image;
}

#pragma mark - GL's part

/// A texel of @a w × @a h RGBA @a data at ( @a s, @a t ), bilinear, as
/// @a repeat has the coordinates outside 0–1 (GL_REPEAT, or GL_CLAMP_TO_EDGE
/// for the clamps; TR_CLAMP_TO_ZERO's 0 0 0 255 and …_ALPHA's alpha 0
/// beyond the edge).
static void UDSampleRaw( const uint8_t *data, int w, int h, int repeat, float s, float t, float out[4] ) {
    float u = s * w - 0.5f, v = t * h - 0.5f;
    int x0 = (int)floorf( u ), y0 = (int)floorf( v );
    float fx = u - x0, fy = v - y0;
    float c[4] = { 0, 0, 0, 0 };
    for ( int j = 0; j < 2; j++ ) {
        for ( int i = 0; i < 2; i++ ) {
            int x = x0 + i, y = y0 + j;
            BOOL outside = NO;
            if ( repeat == 0 ) {
                x = ( ( x % w ) + w ) % w;
                y = ( ( y % h ) + h ) % h;
            } else {
                if ( x < 0 || x >= w || y < 0 || y >= h ) outside = YES;
                x = x < 0 ? 0 : x >= w ? w - 1 : x;
                y = y < 0 ? 0 : y >= h ? h - 1 : y;
            }
            float weight = ( i ? fx : 1 - fx ) * ( j ? fy : 1 - fy );
            const uint8_t *p = data + ( y * w + x ) * 4;
            for ( int k = 0; k < 4; k++ ) {
                float value = p[k] / 255.0f;
                if ( outside && repeat == 3 ) value = k == 3 ? 1.0f : 0.0f;
                if ( outside && repeat == 4 && k == 3 ) value = 0.0f;
                c[k] += value * weight;
            }
        }
    }
    memcpy( out, c, sizeof( c ) );
}

static void UDSample( UDImage *image, int repeat, float s, float t, float out[4] ) {
    UDSampleRaw( image.pixels.bytes, image.width, image.height, repeat, s, t, out );
}

/// glBlendFunc's factor for the bits of drawStateBits.
static float UDBlendFactor( int bits, BOOL source, int channel, const float src[4], const float dst[4] ) {
    if ( source ) {
        switch ( bits ) {
            case 0x0: return 1;                                            // GLS_SRCBLEND_ONE
            case 0x1: return 0;                                            // GLS_SRCBLEND_ZERO
            case 0x3: return dst[channel];                                 // GLS_SRCBLEND_DST_COLOR
            case 0x4: return 1 - dst[channel];                             // GLS_SRCBLEND_ONE_MINUS_DST_COLOR
            case 0x5: return src[3];                                       // GLS_SRCBLEND_SRC_ALPHA
            case 0x6: return 1 - src[3];                                   // GLS_SRCBLEND_ONE_MINUS_SRC_ALPHA
            case 0x7: return dst[3];                                       // GLS_SRCBLEND_DST_ALPHA
            case 0x8: return 1 - dst[3];                                   // GLS_SRCBLEND_ONE_MINUS_DST_ALPHA
            case 0x9: return channel == 3 ? 1 : MIN( src[3], 1 - dst[3] ); // GLS_SRCBLEND_ALPHA_SATURATE
        }
        return 1;
    }
    switch ( bits ) {
        case 0x00: return 0;                                               // GLS_DSTBLEND_ZERO
        case 0x20: return 1;                                               // GLS_DSTBLEND_ONE
        case 0x30: return src[channel];                                    // GLS_DSTBLEND_SRC_COLOR
        case 0x40: return 1 - src[channel];                                // GLS_DSTBLEND_ONE_MINUS_SRC_COLOR
        case 0x50: return src[3];                                          // GLS_DSTBLEND_SRC_ALPHA
        case 0x60: return 1 - src[3];                                      // GLS_DSTBLEND_ONE_MINUS_SRC_ALPHA
        case 0x70: return dst[3];                                          // GLS_DSTBLEND_DST_ALPHA
        case 0x80: return 1 - dst[3];                                      // GLS_DSTBLEND_ONE_MINUS_DST_ALPHA
    }
    return 0;
}

/// A vertex in the picture; NO behind the view.
- (BOOL)project:(const UDDrawVert *)vert texture:(const float [6])matrix vertexColor:(int)vertexColor into:(UDScreenVert *)out {
    if ( guiView ) {
        // the 640 x 480 virtual screen, stretched over the picture
        out->invW = 1.0f;
        out->x = vert->xyz[0] * self.width / 640.0f;
        out->y = vert->xyz[1] * self.height / 480.0f;
        out->s = matrix[0] * vert->st[0] + matrix[1] * vert->st[1] + matrix[2];
        out->t = matrix[3] * vert->st[0] + matrix[4] * vert->st[1] + matrix[5];
        for ( int k = 0; k < 4; k++ ) {
            float c = vert->color[k] / 255.0f;
            float v = vertexColor == 2 && k < 3 ? 1 - c : vertexColor == 0 ? 1 : c;
            if ( k == 0 ) out->r = v; else if ( k == 1 ) out->g = v; else if ( k == 2 ) out->b = v; else out->a = v;
        }
        return YES;
    }
    float d[3] = { vert->xyz[0] - viewOrigin[0], vert->xyz[1] - viewOrigin[1], vert->xyz[2] - viewOrigin[2] };
    float z = d[0] * viewAxis[0][0] + d[1] * viewAxis[0][1] + d[2] * viewAxis[0][2];
    if ( z < 1.0f ) return NO;                                    // the near plane
    float x = d[0] * viewAxis[1][0] + d[1] * viewAxis[1][1] + d[2] * viewAxis[1][2];
    float y = d[0] * viewAxis[2][0] + d[1] * viewAxis[2][1] + d[2] * viewAxis[2][2];
    out->invW = 1.0f / z;
    out->x = self.width * 0.5f - x * out->invW * projX;           // left is -x in the picture
    out->y = self.height * 0.5f - y * out->invW * projY;
    // the texture matrix: s' = m0 s + m1 t + m2, t' = m3 s + m4 t + m5
    float s = matrix[0] * vert->st[0] + matrix[1] * vert->st[1] + matrix[2];
    float t = matrix[3] * vert->st[0] + matrix[4] * vert->st[1] + matrix[5];
    out->s = s * out->invW;
    out->t = t * out->invW;
    float color[4];
    for ( int k = 0; k < 4; k++ ) {
        float c = vert->color[k] / 255.0f;
        color[k] = vertexColor == 2 && k < 3 ? 1 - c : vertexColor == 0 ? 1 : c;
    }
    out->r = color[0] * out->invW;
    out->g = color[1] * out->invW;
    out->b = color[2] * out->invW;
    out->a = color[3] * out->invW;
    return YES;
}

static float UDEdge( const UDScreenVert *a, const UDScreenVert *b, float x, float y ) {
    return ( b->x - a->x ) * ( y - a->y ) - ( b->y - a->y ) * ( x - a->x );
}

/// A triangle drawn: its texels modulated by its colors and @a constant
/// (GL_MODULATE, the second texture unit's constant color), blended by
/// @a drawStateBits.
- (void)drawTriangle:(const UDScreenVert *)v0 :(const UDScreenVert *)v1 :(const UDScreenVert *)v2
               image:(UDImage *)image repeat:(int)repeat constant:(const float [4])constant drawStateBits:(int)drawStateBits {
    float area = UDEdge( v0, v1, v2->x, v2->y );
    if ( fabsf( area ) < 1e-6f ) return;
    int minX = (int)floorf( MIN( v0->x, MIN( v1->x, v2->x ) ) ), maxX = (int)ceilf( MAX( v0->x, MAX( v1->x, v2->x ) ) );
    int minY = (int)floorf( MIN( v0->y, MIN( v1->y, v2->y ) ) ), maxY = (int)ceilf( MAX( v0->y, MAX( v1->y, v2->y ) ) );
    minX = MAX( minX, 0 ); minY = MAX( minY, 0 );
    maxX = MIN( maxX, self.width - 1 ); maxY = MIN( maxY, self.height - 1 );
    int srcBits = drawStateBits & UDGLSSrcBlendBits, dstBits = drawStateBits & UDGLSDstBlendBits;
    // GL_State's glColorMask: GLS_REDMASK, _GREENMASK, _BLUEMASK, _ALPHAMASK
    const bool writes[4] = { !( drawStateBits & 0x00000200 ), !( drawStateBits & 0x00000400 ),
                             !( drawStateBits & 0x00000800 ), !( drawStateBits & 0x00001000 ) };
    for ( int y = minY; y <= maxY; y++ ) {
        for ( int x = minX; x <= maxX; x++ ) {
            // the pixel's center, a hair off: a pixel on an edge two
            // triangles share is in exactly one of them
            float px = x + 0.5f + 1.0e-4f, py = y + 0.5f + 1.7e-4f;
            float w0 = UDEdge( v1, v2, px, py ) / area;
            float w1 = UDEdge( v2, v0, px, py ) / area;
            float w2 = UDEdge( v0, v1, px, py ) / area;
            if ( w0 < 0 || w1 < 0 || w2 < 0 ) continue;
            float invW = w0 * v0->invW + w1 * v1->invW + w2 * v2->invW;
            if ( invW <= 0 ) continue;
            float persp = 1.0f / invW;
            float s = ( w0 * v0->s + w1 * v1->s + w2 * v2->s ) * persp;
            float t = ( w0 * v0->t + w1 * v1->t + w2 * v2->t ) * persp;
            float color[4] = {
                ( w0 * v0->r + w1 * v1->r + w2 * v2->r ) * persp,
                ( w0 * v0->g + w1 * v1->g + w2 * v2->g ) * persp,
                ( w0 * v0->b + w1 * v1->b + w2 * v2->b ) * persp,
                ( w0 * v0->a + w1 * v1->a + w2 * v2->a ) * persp,
            };
            float texel[4];
            UDSample( image, repeat, s, t, texel );
            float src[4];
            for ( int k = 0; k < 4; k++ ) {
                src[k] = texel[k] * color[k] * constant[k];
                src[k] = src[k] < 0 ? 0 : src[k] > 1 ? 1 : src[k];
            }
            float *dst = pixels + ( y * self.width + x ) * 4;
            float result[4];
            for ( int k = 0; k < 4; k++ ) {
                float value = src[k] * UDBlendFactor( srcBits, YES, k, src, dst ) + dst[k] * UDBlendFactor( dstBits, NO, k, src, dst );
                result[k] = value < 0 ? 0 : value > 1 ? 1 : value;
            }
            for ( int k = 0; k < 4; k++ ) {
                if ( writes[k] ) {
                    dst[k] = result[k];
                }
            }
        }
    }
}

#pragma mark - RB_STD_T_RenderShaderPasses

/*
======================
RB_GetShaderTextureMatrix
======================
*/
static void UDGetShaderTextureMatrix( const float *shaderRegisters, UDMaterialStageInfo *texture, float matrix[6] ) {
    const int *m = texture.matrix;   // [2][3]
    matrix[0] = shaderRegisters[ m[0] ];
    matrix[1] = shaderRegisters[ m[1] ];
    matrix[2] = shaderRegisters[ m[2] ];

    // we attempt to keep scrolls from generating incredibly large texture values, but
    // center rotations and center scales can still generate offsets that need to be > 1
    if ( matrix[2] < -40 || matrix[2] > 40 ) {
        matrix[2] -= (int)matrix[2];
    }

    matrix[3] = shaderRegisters[ m[3] ];
    matrix[4] = shaderRegisters[ m[4] ];
    matrix[5] = shaderRegisters[ m[5] ];
    if ( matrix[5] < -40 || matrix[5] > 40 ) {
        matrix[5] -= (int)matrix[5];
    }
}

- (void)drawSurfaces:(NSArray<UDParticleSurface *> *)surfaces time:(float)time {
    // the engine's order: by the material's sort, stable (an insertion sort)
    NSMutableArray<UDParticleSurface *> *sorted = [NSMutableArray arrayWithCapacity:surfaces.count];
    for ( UDParticleSurface *surf in surfaces ) {
        float key = [self sortOfMaterial:surf.material];
        NSUInteger at = sorted.count;
        while ( at > 0 && [self sortOfMaterial:sorted[at - 1].material] > key ) at--;
        [sorted insertObject:surf atIndex:at];
    }
    for ( UDParticleSurface *surf in sorted ) {
        [self drawSurface:surf time:time shaderParms:surf.shaderParms];
    }
}

- (void)drawSurface:(UDParticleSurface *)surf time:(float)time shaderParms:(const float *)shaderParms {
    UDMaterialParser *shader = [self materialNamed:surf.material];
    if ( surf.indexes ? surf.numIndexes < 3 : surf.numVerts < 4 ) {
        return;
    }
    // the expressions for conditionals / color / texcoords
    NSData *registers = [shader registersAtTime:time shaderParms:shaderParms];
    const float *regs = registers.bytes;

    for ( UDMaterialStageInfo *pStage in shader.stages ) {
        // check the enable condition
        if ( regs[ pStage.conditionRegister ] == 0 ) {
            continue;
        }
        // skip the stages involved in lighting
        if ( pStage.lighting != UDStageLightingAmbient ) {
            continue;
        }
        // skip if the stage is ( GL_ZERO, GL_ONE ), which is used for some alpha masks
        if ( ( pStage.drawStateBits & (UDGLSSrcBlendBits|UDGLSDstBlendBits) ) == ( UDGLSSrcBlendZero | UDGLSDstBlendOne ) ) {
            continue;
        }
        // new-style stages: programs, not drawn here
        if ( pStage.newStage ) {
            continue;
        }

        // set the color
        float color[4];
        color[0] = regs[ pStage.colorRegisters[0] ];
        color[1] = regs[ pStage.colorRegisters[1] ];
        color[2] = regs[ pStage.colorRegisters[2] ];
        color[3] = regs[ pStage.colorRegisters[3] ];

        // skip the entire stage if an add would be black
        if ( ( pStage.drawStateBits & (UDGLSSrcBlendBits|UDGLSDstBlendBits) ) == ( UDGLSSrcBlendOne | UDGLSDstBlendOne )
            && color[0] <= 0 && color[1] <= 0 && color[2] <= 0 ) {
            continue;
        }

        // skip the entire stage if a blend would be completely transparent
        if ( ( pStage.drawStateBits & (UDGLSSrcBlendBits|UDGLSDstBlendBits) ) == ( UDGLSSrcBlendSrcAlpha | UDGLSDstBlendOneMinusSrcAlpha )
            && color[3] <= 0 ) {
            continue;
        }

        // the texture: its image (cube maps, cinematics and dynamic renders
        // are not drawn here)
        if ( pStage.imageName.length == 0 || pStage.cubeMap != UDCubeFiles2D ) {
            continue;
        }
        UDImage *image = [self imageNamed:pStage.imageName];
        if ( image == nil ) {
            image = [self imageNamed:@"_default"];
        }
        float matrix[6] = { 1, 0, 0, 0, 1, 0 };
        if ( pStage.hasMatrix ) {
            UDGetShaderTextureMatrix( regs, pStage, matrix );
        }

        // select the vertex color source: with vertex colors, the stage's
        // color is the second unit's constant; without, the color itself
        int vertexColor = pStage.vertexColor;

        // draw it: its triangles; or each quad as 0 2 3, 0 3 1
        const UDDrawVert *verts = surf.verts;
        const int *indexes = surf.indexes;
        for ( int i = 0; indexes && i + 2 < surf.numIndexes; i += 3 ) {
            UDScreenVert sv[3];
            BOOL visible = YES;
            for ( int k = 0; k < 3 && visible; k++ ) {
                visible = [self project:&verts[indexes[i + k]] texture:matrix vertexColor:vertexColor into:&sv[k]];
            }
            if ( !visible ) continue;
            [self drawTriangle:&sv[0] :&sv[1] :&sv[2] image:image repeat:pStage.repeat constant:color drawStateBits:pStage.drawStateBits];
        }
        for ( int i = 0; !indexes && i + 3 < surf.numVerts; i += 4 ) {
            UDScreenVert sv[4];
            BOOL visible = YES;
            for ( int k = 0; k < 4 && visible; k++ ) {
                visible = [self project:&verts[i + k] texture:matrix vertexColor:vertexColor into:&sv[k]];
            }
            if ( !visible ) continue;
            [self drawTriangle:&sv[0] :&sv[2] :&sv[3] image:image repeat:pStage.repeat constant:color drawStateBits:pStage.drawStateBits];
            [self drawTriangle:&sv[0] :&sv[3] :&sv[1] image:image repeat:pStage.repeat constant:color drawStateBits:pStage.drawStateBits];
        }
    }
}

#pragma mark - The interaction pass

/// A texture unit, its pixels: a 2D image or a cube map's six faces.
typedef struct {
    const uint8_t *data;
    int width, height;
    int repeat;
    BOOL cube;
    const uint8_t *faces[6];
    int faceSize;
} UDTextureUnit;

/// The GL cube map lookup: the major axis's face, its s and t.
static UDVec4 UDSampleCube( const UDTextureUnit *unit, UDVec4 coord ) {
    float rx = coord.v[0], ry = coord.v[1], rz = coord.v[2];
    float ax = fabsf( rx ), ay = fabsf( ry ), az = fabsf( rz );
    int face;
    float sc, tc, ma;
    if ( ax >= ay && ax >= az ) {
        face = rx >= 0 ? 0 : 1; ma = ax;
        sc = rx >= 0 ? -rz : rz; tc = -ry;
    } else if ( ay >= az ) {
        face = ry >= 0 ? 2 : 3; ma = ay;
        sc = rx; tc = ry >= 0 ? rz : -rz;
    } else {
        face = rz >= 0 ? 4 : 5; ma = az;
        sc = rz >= 0 ? rx : -rx; tc = -ry;
    }
    UDVec4 out = { { 0, 0, 0, 0 } };
    if ( ma == 0 ) return out;
    float s = ( sc / ma + 1 ) * 0.5f, t = ( tc / ma + 1 ) * 0.5f;
    UDSampleRaw( unit->faces[face], unit->faceSize, unit->faceSize, 1, s, t, out.v );
    return out;
}

static UDVec4 UDInteractionTexture( void *context, int unit, BOOL cube, UDVec4 coord ) {
    const UDTextureUnit *units = context;
    UDVec4 out = { { 0, 0, 0, 0 } };
    if ( unit < 0 || unit > 6 ) return out;
    const UDTextureUnit *u = &units[unit];
    if ( cube || u->cube ) {
        if ( !u->cube ) return out;
        return UDSampleCube( u, coord );
    }
    if ( u->data == NULL ) return out;
    UDSampleRaw( u->data, u->width, u->height, u->repeat, coord.v[0], coord.v[1], out.v );
    return out;
}

/// glprogs/interaction.vfp, as R_LoadARBProgram loads it for
/// VPROG_INTERACTION and FPROG_INTERACTION (dhewm3's gamma injection, at
/// r_gamma and r_brightness 1, changes nothing, and is left out).
- (BOOL)loadInteractionPrograms {
    if ( self.interactionLoaded ) return self.interactionVertexProgram != nil;
    self.interactionLoaded = YES;
    void *buffer = NULL;
    int length = [self.fileSystem readFile:@"glprogs/interaction.vfp" buffer:&buffer timestamp:NULL error:NULL];
    if ( length < 0 || buffer == NULL ) {
        self.interactionProblem = @"glprogs/interaction.vfp: File not found";
        return NO;
    }
    NSString *text = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)length encoding:NSISOLatin1StringEncoding] ?: @"";
    [self.fileSystem freeFile:buffer error:NULL];
    NSError *error = nil;
    self.interactionVertexProgram = [UDARBProgram programFromFileText:text vertex:YES error:&error];
    if ( self.interactionVertexProgram != nil ) {
        self.interactionFragmentProgram = [UDARBProgram programFromFileText:text vertex:NO error:&error];
    }
    if ( self.interactionFragmentProgram == nil ) {
        self.interactionVertexProgram = nil;
        self.interactionProblem = [NSString stringWithFormat:@"glprogs/interaction.vfp: %@", error.localizedDescription];
        return NO;
    }
    return YES;
}

/// An image, its upload's: a bump map's red in its alpha (idImage::GenerateImage,
/// image_useNormalCompression 2).
- (UDImage *)uploadedImageNamed:(NSString *)name depth:(int)depth {
    BOOL bump = depth == 3;          // TD_BUMP
    NSString *key = bump ? [name stringByAppendingString:@"\n(bump)"] : name;
    id image = self.images[key];
    if ( image == nil ) {
        UDImage *loaded = [self imageNamed:name] ?: [self imageNamed:@"_default"];
        if ( bump && loaded != nil ) {
            NSMutableData *swapped = [loaded.pixels mutableCopy];
            uint8_t *p = swapped.mutableBytes;
            for ( NSUInteger i = 0; i + 3 < swapped.length; i += 4 ) {
                p[i + 3] = p[i];
                p[i] = 0;
            }
            loaded = [[UDImage alloc] initWithWidth:loaded.width height:loaded.height pixels:swapped];
        }
        image = loaded ?: [NSNull null];
        self.images[key] = image;
    }
    return image == [NSNull null] ? nil : image;
}

static void UDSetUnit( UDTextureUnit *unit, UDImage *image, int repeat ) {
    memset( unit, 0, sizeof( *unit ) );
    unit->data = image.pixels.bytes;
    unit->width = image.width;
    unit->height = image.height;
    unit->repeat = repeat;
}

// drawInteraction_t
typedef struct {
    float               localLightOrigin[4];
    float               localViewOrigin[4];
    float               lightProjection[4][4];    // in local coordinates, possibly with a texture matrix baked in
    __unsafe_unretained UDImage *lightImage;
    int                 lightRepeat;
    __unsafe_unretained UDImage *lightFalloffImage;
    __unsafe_unretained UDImage *bumpImage;
    int                 bumpRepeat;
    __unsafe_unretained UDImage *diffuseImage;
    int                 diffuseRepeat;
    __unsafe_unretained UDImage *specularImage;
    int                 specularRepeat;
    float               diffuseColor[4];          // may have a light color baked into it, will be < tr.backEndRendererMaxLight
    float               specularColor[4];         // may have a light color baked into it, will be < tr.backEndRendererMaxLight
    int                 vertexColor;              // applies to both diffuse and specular
    BOOL                ambientLight;             // use tr.ambientNormalMap instead of normalization cube map
    float               bumpMatrix[2][4];
    float               diffuseMatrix[2][4];
    float               specularMatrix[2][4];
} drawInteraction_t;

/*
=================
myGlMultMatrix
=================
*/
static void myGlMultMatrix( const float a[16], const float b[16], float out[16] ) {
    for ( int i = 0; i < 4; i++ ) {
        for ( int j = 0; j < 4; j++ ) {
            out[ i * 4 + j ] = a[ i * 4 + 0 ] * b[ 0 * 4 + j ] + a[ i * 4 + 1 ] * b[ 1 * 4 + j ] +
                               a[ i * 4 + 2 ] * b[ 2 * 4 + j ] + a[ i * 4 + 3 ] * b[ 3 * 4 + j ];
        }
    }
}

/*
==================
RB_BakeTextureMatrixIntoTexgen
==================
*/
static void RB_BakeTextureMatrixIntoTexgen( float lightProject[3][4], const float *textureMatrix ) {
    float    genMatrix[16];
    float    final[16];

    genMatrix[0] = lightProject[0][0];
    genMatrix[4] = lightProject[0][1];
    genMatrix[8] = lightProject[0][2];
    genMatrix[12] = lightProject[0][3];

    genMatrix[1] = lightProject[1][0];
    genMatrix[5] = lightProject[1][1];
    genMatrix[9] = lightProject[1][2];
    genMatrix[13] = lightProject[1][3];

    genMatrix[2] = 0;
    genMatrix[6] = 0;
    genMatrix[10] = 0;
    genMatrix[14] = 0;

    genMatrix[3] = lightProject[2][0];
    genMatrix[7] = lightProject[2][1];
    genMatrix[11] = lightProject[2][2];
    genMatrix[15] = lightProject[2][3];

    myGlMultMatrix( genMatrix, textureMatrix, final );

    lightProject[0][0] = final[0];
    lightProject[0][1] = final[4];
    lightProject[0][2] = final[8];
    lightProject[0][3] = final[12];

    lightProject[1][0] = final[1];
    lightProject[1][1] = final[5];
    lightProject[1][2] = final[9];
    lightProject[1][3] = final[13];
}

/*
=================
R_SetDrawInteraction
=================
*/
- (void)setDrawInteraction:(UDMaterialStageInfo *)surfaceStage regs:(const float *)surfaceRegs
                     image:(__unsafe_unretained UDImage **)image repeat:(int *)repeat
                    matrix:(float [2][4])matrix color:(float *)color {
    *image = [self uploadedImageNamed:surfaceStage.imageName ?: @"_default" depth:surfaceStage.imageDepth];
    *repeat = surfaceStage.repeat;
    const int *m = surfaceStage.matrix;
    if ( surfaceStage.hasMatrix ) {
        matrix[0][0] = surfaceRegs[m[0]];
        matrix[0][1] = surfaceRegs[m[1]];
        matrix[0][2] = 0;
        matrix[0][3] = surfaceRegs[m[2]];

        matrix[1][0] = surfaceRegs[m[3]];
        matrix[1][1] = surfaceRegs[m[4]];
        matrix[1][2] = 0;
        matrix[1][3] = surfaceRegs[m[5]];

        // we attempt to keep scrolls from generating incredibly large texture values, but
        // center rotations and center scales can still generate offsets that need to be > 1
        if ( matrix[0][3] < -40 || matrix[0][3] > 40 ) {
            matrix[0][3] -= (int)matrix[0][3];
        }
        if ( matrix[1][3] < -40 || matrix[1][3] > 40 ) {
            matrix[1][3] -= (int)matrix[1][3];
        }
    } else {
        matrix[0][0] = 1;
        matrix[0][1] = 0;
        matrix[0][2] = 0;
        matrix[0][3] = 0;

        matrix[1][0] = 0;
        matrix[1][1] = 1;
        matrix[1][2] = 0;
        matrix[1][3] = 0;
    }

    if ( color ) {
        for ( int i = 0 ; i < 4 ; i++ ) {
            color[i] = surfaceRegs[surfaceStage.colorRegisters[i]];
            // clamp here, so card with greater range don't look different.
            // we could perform overbrighting like we do for lights, but
            // it doesn't currently look worth it.
            if ( color[i] < 0 ) {
                color[i] = 0;
            } else if ( color[i] > 1.0 ) {
                color[i] = 1.0;
            }
        }
    }
}

/*
=================
RB_SubmittInteraction
=================
*/
- (void)submittInteraction:(drawInteraction_t *)din surface:(UDParticleSurface *)surf {
    if ( !din->bumpImage ) {
        return;
    }

    UDImage *blackImage = [self imageNamed:@"_black"];
    if ( !din->diffuseImage ) {
        din->diffuseImage = blackImage;
    }
    if ( !din->specularImage || din->ambientLight ) {
        din->specularImage = blackImage;
    }

    // if we wouldn't draw anything, don't call the Draw function
    if (
        ( ( din->diffuseColor[0] > 0 ||
        din->diffuseColor[1] > 0 ||
        din->diffuseColor[2] > 0 ) && din->diffuseImage != blackImage )
        || ( ( din->specularColor[0] > 0 ||
        din->specularColor[1] > 0 ||
        din->specularColor[2] > 0 ) && din->specularImage != blackImage ) ) {
        [self drawInteraction:din surface:surf];
    }
}

/*
==================
RB_ARB2_DrawInteraction
==================
*/
- (void)drawInteraction:(const drawInteraction_t *)din surface:(UDParticleSurface *)surf {
    UDARBProgram *vp = self.interactionVertexProgram, *fp = self.interactionFragmentProgram;
    // load all the vertex program parameters
    UDVec4 *venv = vp.env, *fenv = fp.env;
    memcpy( venv[4].v, din->localLightOrigin, sizeof( float ) * 4 );       // PP_LIGHT_ORIGIN
    memcpy( venv[5].v, din->localViewOrigin, sizeof( float ) * 4 );        // PP_VIEW_ORIGIN
    memcpy( venv[6].v, din->lightProjection[0], sizeof( float ) * 4 );     // PP_LIGHT_PROJECT_S
    memcpy( venv[7].v, din->lightProjection[1], sizeof( float ) * 4 );     // PP_LIGHT_PROJECT_T
    memcpy( venv[8].v, din->lightProjection[2], sizeof( float ) * 4 );     // PP_LIGHT_PROJECT_Q
    memcpy( venv[9].v, din->lightProjection[3], sizeof( float ) * 4 );     // PP_LIGHT_FALLOFF_S
    memcpy( venv[10].v, din->bumpMatrix[0], sizeof( float ) * 4 );         // PP_BUMP_MATRIX_S
    memcpy( venv[11].v, din->bumpMatrix[1], sizeof( float ) * 4 );         // PP_BUMP_MATRIX_T
    memcpy( venv[12].v, din->diffuseMatrix[0], sizeof( float ) * 4 );      // PP_DIFFUSE_MATRIX_S
    memcpy( venv[13].v, din->diffuseMatrix[1], sizeof( float ) * 4 );      // PP_DIFFUSE_MATRIX_T
    memcpy( venv[14].v, din->specularMatrix[0], sizeof( float ) * 4 );     // PP_SPECULAR_MATRIX_S
    memcpy( venv[15].v, din->specularMatrix[1], sizeof( float ) * 4 );     // PP_SPECULAR_MATRIX_T

    static const UDVec4 zero = { { 0, 0, 0, 0 } };
    static const UDVec4 one = { { 1, 1, 1, 1 } };
    static const UDVec4 negOne = { { -1, -1, -1, -1 } };

    switch ( din->vertexColor ) {
    case 0:     // SVC_IGNORE
        venv[16] = zero;                // PP_COLOR_MODULATE
        venv[17] = one;                 // PP_COLOR_ADD
        break;
    case 1:     // SVC_MODULATE
        venv[16] = one;
        venv[17] = zero;
        break;
    case 2:     // SVC_INVERSE_MODULATE
        venv[16] = negOne;
        venv[17] = one;
        break;
    }

    // set the constant colors
    memcpy( fenv[0].v, din->diffuseColor, sizeof( float ) * 4 );
    memcpy( fenv[1].v, din->specularColor, sizeof( float ) * 4 );

    // set the textures (RB_ARB2_CreateDrawInteractions' 0 and 6, and these)
    UDTextureUnit units[7];
    NSArray<UDImage *> *cube = [UDImageProgram cubeImageNamed:din->ambientLight ? @"_ambient" : @"_normalCubeMap"];
    memset( &units[0], 0, sizeof( units[0] ) );
    units[0].cube = YES;
    units[0].faceSize = cube[0].width;
    for ( int f = 0; f < 6; f++ ) units[0].faces[f] = cube[(NSUInteger)f].pixels.bytes;
    // texture 1 will be the per-surface bump map
    UDSetUnit( &units[1], din->bumpImage, din->bumpRepeat );
    // texture 2 will be the light falloff texture (TR_CLAMP)
    UDSetUnit( &units[2], din->lightFalloffImage, 1 );
    // texture 3 will be the light projection texture
    UDSetUnit( &units[3], din->lightImage, din->lightRepeat );
    // texture 4 is the per-surface diffuse map
    UDSetUnit( &units[4], din->diffuseImage, din->diffuseRepeat );
    // texture 5 is the per-surface specular map
    UDSetUnit( &units[5], din->specularImage, din->specularRepeat );
    // texture 6 is the specular lookup table (TR_CLAMP)
    UDSetUnit( &units[6], [self imageNamed:@"_specularTable"], 1 );

    // draw it: GLS_SRCBLEND_ONE | GLS_DSTBLEND_ONE, each quad as 0 2 3, 0 3 1
    const UDDrawVert *verts = surf.verts;
    for ( int i = 0; i + 3 < surf.numVerts; i += 4 ) {
        UDARBState states[4];
        UDScreenVert screen[4];
        BOOL visible = YES;
        for ( int k = 0; k < 4 && visible; k++ ) {
            const UDDrawVert *vert = &verts[i + k];
            UDARBState *state = &states[k];
            memset( state, 0, sizeof( *state ) );
            state->position = (UDVec4){ { vert->xyz[0], vert->xyz[1], vert->xyz[2], 1 } };
            state->attrib[8] = (UDVec4){ { vert->st[0], vert->st[1], 0, 1 } };
            state->attrib[9] = (UDVec4){ { vert->tangents[0][0], vert->tangents[0][1], vert->tangents[0][2], 1 } };
            state->attrib[10] = (UDVec4){ { vert->tangents[1][0], vert->tangents[1][1], vert->tangents[1][2], 1 } };
            state->attrib[11] = (UDVec4){ { vert->normal[0], vert->normal[1], vert->normal[2], 1 } };
            state->color = (UDVec4){ { vert->color[0] / 255.0f, vert->color[1] / 255.0f, vert->color[2] / 255.0f, vert->color[3] / 255.0f } };
            [vp run:state texture:NULL context:NULL];
            float identity[6] = { 1, 0, 0, 0, 1, 0 };
            visible = [self project:vert texture:identity vertexColor:0 into:&screen[k]];
        }
        if ( !visible ) continue;
        [self drawInteractionTriangle:&screen[0] :&screen[2] :&screen[3] states:&states[0] :&states[2] :&states[3] fragment:fp units:units];
        [self drawInteractionTriangle:&screen[0] :&screen[3] :&screen[1] states:&states[0] :&states[3] :&states[1] fragment:fp units:units];
    }
}

/// A triangle of the interaction: the vertex program's outputs interpolated
/// (perspective-correct), the fragment program run at each pixel, its color
/// added (GL_ONE, GL_ONE).
- (void)drawInteractionTriangle:(const UDScreenVert *)v0 :(const UDScreenVert *)v1 :(const UDScreenVert *)v2
                         states:(const UDARBState *)s0 :(const UDARBState *)s1 :(const UDARBState *)s2
                       fragment:(UDARBProgram *)fp units:(UDTextureUnit *)units {
    float area = UDEdge( v0, v1, v2->x, v2->y );
    if ( fabsf( area ) < 1e-6f ) return;
    int minX = (int)floorf( MIN( v0->x, MIN( v1->x, v2->x ) ) ), maxX = (int)ceilf( MAX( v0->x, MAX( v1->x, v2->x ) ) );
    int minY = (int)floorf( MIN( v0->y, MIN( v1->y, v2->y ) ) ), maxY = (int)ceilf( MAX( v0->y, MAX( v1->y, v2->y ) ) );
    minX = MAX( minX, 0 ); minY = MAX( minY, 0 );
    maxX = MIN( maxX, self.width - 1 ); maxY = MIN( maxY, self.height - 1 );
    for ( int y = minY; y <= maxY; y++ ) {
        for ( int x = minX; x <= maxX; x++ ) {
            // the pixel's center, a hair off: a pixel on an edge two
            // triangles share is in exactly one of them
            float px = x + 0.5f + 1.0e-4f, py = y + 0.5f + 1.7e-4f;
            float w0 = UDEdge( v1, v2, px, py ) / area;
            float w1 = UDEdge( v2, v0, px, py ) / area;
            float w2 = UDEdge( v0, v1, px, py ) / area;
            if ( w0 < 0 || w1 < 0 || w2 < 0 ) continue;
            float i0 = w0 * v0->invW, i1 = w1 * v1->invW, i2 = w2 * v2->invW;
            float invW = i0 + i1 + i2;
            if ( invW <= 0 ) continue;
            float b0 = i0 / invW, b1 = i1 / invW, b2 = i2 / invW;
            UDARBState fragment;
            memset( &fragment, 0, sizeof( fragment ) );
            for ( int t = 0; t < 8; t++ ) {
                for ( int c = 0; c < 4; c++ ) {
                    fragment.texcoord[t].v[c] = b0 * s0->texcoord[t].v[c] + b1 * s1->texcoord[t].v[c] + b2 * s2->texcoord[t].v[c];
                }
            }
            for ( int c = 0; c < 4; c++ ) {
                fragment.color.v[c] = b0 * s0->resultColor.v[c] + b1 * s1->resultColor.v[c] + b2 * s2->resultColor.v[c];
                fragment.color.v[c] = fragment.color.v[c] < 0 ? 0 : fragment.color.v[c] > 1 ? 1 : fragment.color.v[c];
            }
            [fp run:&fragment texture:UDInteractionTexture context:units];
            float *dst = pixels + ( y * self.width + x ) * 4;
            for ( int c = 0; c < 4; c++ ) {
                float src = fragment.resultColor.v[c];
                src = src < 0 ? 0 : src > 1 ? 1 : src;
                float value = src + dst[c];
                dst[c] = value > 1 ? 1 : value;
            }
        }
    }
}

/*
=================
RB_CreateSingleDrawInteractions

This can be used by different draw_* backends to decompose a complex light / surface
interaction into primitive interactions
=================
*/
- (void)drawInteractionsOfSurfaces:(NSArray<UDParticleSurface *> *)surfaces light:(UDPointLight *)light time:(float)time {
    if ( ![self loadInteractionPrograms] ) {
        return;
    }

    // R_DeriveLightData, for a point light: its shader (lights/defaultPointLight
    // for none), its falloff image (the default one's for none), its projection
    UDMaterialParser *lightShader = [self materialNamed:light.material.length > 0 ? light.material : @"lights/defaultPointLight"];
    NSString *falloffName = lightShader.lightFalloffImageName ?: [self materialNamed:@"lights/defaultPointLight"].lightFalloffImageName;
    UDImage *falloffImage = falloffName != nil ? [self imageNamed:falloffName] : nil;
    if ( lightShader.fogLight || lightShader.blendLight || falloffImage == nil ) {
        return;                                 // other passes', or no falloff to light with
    }
    float lightProject[4][4];
    memset( lightProject, 0, sizeof( lightProject ) );
    lightProject[0][0] = 0.5f / light.radius[0];
    lightProject[1][1] = 0.5f / light.radius[1];
    lightProject[3][2] = 0.5f / light.radius[2];
    lightProject[0][3] = 0.5f;
    lightProject[1][3] = 0.5f;
    lightProject[2][3] = 1.0f;
    lightProject[3][3] = 0.5f;
    // R_LocalPlaneToGlobal by its model matrix (its axis the identity, its origin)
    for ( int i = 0; i < 4; i++ ) {
        lightProject[i][3] -= lightProject[i][0] * light.origin[0] + lightProject[i][1] * light.origin[1] + lightProject[i][2] * light.origin[2];
    }

    // RB_DetermineLightScale: backEndRendererMaxLight is 999 for ARB2, so
    // the light scale is r_lightScale's 2
    const float lightScale = 2.0f;

    NSData *lightRegisterData = [lightShader registersAtTime:time shaderParms:light.shaderParms];
    const float *lightRegs = lightRegisterData.bytes;

    for ( UDParticleSurface *surf in surfaces ) {
        UDMaterialParser *surfaceShader = [self materialNamed:surf.material];
        NSData *surfaceRegisterData = [surfaceShader registersAtTime:time shaderParms:surf.shaderParms];
        const float *surfaceRegs = surfaceRegisterData.bytes;

        drawInteraction_t inter;
        memset( &inter, 0, sizeof( inter ) );

        inter.lightFalloffImage = falloffImage;

        // the surfaces are in the world: local is global
        memcpy( inter.localLightOrigin, light.origin, sizeof( float ) * 3 );
        memcpy( inter.localViewOrigin, viewOrigin, sizeof( float ) * 3 );
        inter.localLightOrigin[3] = 0;
        inter.localViewOrigin[3] = 1;
        inter.ambientLight = lightShader.ambientLight;

        for ( UDMaterialStageInfo *lightStage in lightShader.stages ) {
            // ignore stages that fail the condition
            if ( !lightRegs[ lightStage.conditionRegister ] ) {
                continue;
            }

            inter.lightImage = [self uploadedImageNamed:lightStage.imageName ?: @"_default" depth:lightStage.imageDepth];
            inter.lightRepeat = lightStage.repeat;

            memcpy( inter.lightProjection, lightProject, sizeof( inter.lightProjection ) );
            // now multiply the texgen by the light texture matrix
            if ( lightStage.hasMatrix ) {
                const int *m = lightStage.matrix;
                float lightTextureMatrix[16];
                // RB_GetShaderTextureMatrix
                memset( lightTextureMatrix, 0, sizeof( lightTextureMatrix ) );
                lightTextureMatrix[0] = lightRegs[ m[0] ];
                lightTextureMatrix[4] = lightRegs[ m[1] ];
                lightTextureMatrix[12] = lightRegs[ m[2] ];
                if ( lightTextureMatrix[12] < -40 || lightTextureMatrix[12] > 40 ) {
                    lightTextureMatrix[12] -= (int)lightTextureMatrix[12];
                }
                lightTextureMatrix[1] = lightRegs[ m[3] ];
                lightTextureMatrix[5] = lightRegs[ m[4] ];
                lightTextureMatrix[13] = lightRegs[ m[5] ];
                if ( lightTextureMatrix[13] < -40 || lightTextureMatrix[13] > 40 ) {
                    lightTextureMatrix[13] -= (int)lightTextureMatrix[13];
                }
                lightTextureMatrix[10] = 1;
                lightTextureMatrix[15] = 1;
                RB_BakeTextureMatrixIntoTexgen( inter.lightProjection, lightTextureMatrix );
            }

            inter.bumpImage = nil;
            inter.specularImage = nil;
            inter.diffuseImage = nil;
            inter.diffuseColor[0] = inter.diffuseColor[1] = inter.diffuseColor[2] = inter.diffuseColor[3] = 0;
            inter.specularColor[0] = inter.specularColor[1] = inter.specularColor[2] = inter.specularColor[3] = 0;

            float lightColor[4];

            // backEnd.lightScale is calculated so that lightColor[] will never exceed
            // tr.backEndRendererMaxLight
            lightColor[0] = lightScale * lightRegs[ lightStage.colorRegisters[0] ];
            lightColor[1] = lightScale * lightRegs[ lightStage.colorRegisters[1] ];
            lightColor[2] = lightScale * lightRegs[ lightStage.colorRegisters[2] ];
            lightColor[3] = lightRegs[ lightStage.colorRegisters[3] ];

            // go through the individual stages
            for ( UDMaterialStageInfo *surfaceStage in surfaceShader.stages ) {
                switch( surfaceStage.lighting ) {
                    case UDStageLightingAmbient: {
                        // ignore ambient stages while drawing interactions
                        break;
                    }
                    case UDStageLightingBump: {
                        // ignore stage that fails the condition
                        if ( !surfaceRegs[ surfaceStage.conditionRegister ] ) {
                            break;
                        }
                        // draw any previous interaction
                        [self submittInteraction:&inter surface:surf];
                        inter.diffuseImage = nil;
                        inter.specularImage = nil;
                        [self setDrawInteraction:surfaceStage regs:surfaceRegs image:&inter.bumpImage repeat:&inter.bumpRepeat
                                          matrix:inter.bumpMatrix color:NULL];
                        break;
                    }
                    case UDStageLightingDiffuse: {
                        // ignore stage that fails the condition
                        if ( !surfaceRegs[ surfaceStage.conditionRegister ] ) {
                            break;
                        }
                        if ( inter.diffuseImage ) {
                            [self submittInteraction:&inter surface:surf];
                        }
                        [self setDrawInteraction:surfaceStage regs:surfaceRegs image:&inter.diffuseImage repeat:&inter.diffuseRepeat
                                          matrix:inter.diffuseMatrix color:inter.diffuseColor];
                        inter.diffuseColor[0] *= lightColor[0];
                        inter.diffuseColor[1] *= lightColor[1];
                        inter.diffuseColor[2] *= lightColor[2];
                        inter.diffuseColor[3] *= lightColor[3];
                        inter.vertexColor = surfaceStage.vertexColor;
                        break;
                    }
                    case UDStageLightingSpecular: {
                        // ignore stage that fails the condition
                        if ( !surfaceRegs[ surfaceStage.conditionRegister ] ) {
                            break;
                        }
                        if ( inter.specularImage ) {
                            [self submittInteraction:&inter surface:surf];
                        }
                        // (r_supportNoSpecular's default, -1, honors a light's noSpecular
                        // only where a map's worldspawn allows it: no map here)
                        [self setDrawInteraction:surfaceStage regs:surfaceRegs image:&inter.specularImage repeat:&inter.specularRepeat
                                          matrix:inter.specularMatrix color:inter.specularColor];
                        inter.specularColor[0] *= lightColor[0];
                        inter.specularColor[1] *= lightColor[1];
                        inter.specularColor[2] *= lightColor[2];
                        inter.specularColor[3] *= lightColor[3];
                        inter.vertexColor = surfaceStage.vertexColor;
                        break;
                    }
                }
            }

            // draw the final interaction
            [self submittInteraction:&inter surface:surf];
        }
    }
}

@end
