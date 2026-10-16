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
#import "idDeclManager.h"

typedef struct {
    float x, y;          // in the picture, its top row first
    float invW;          // 1 / the view's depth
    float s, t;          // texture coordinates, over the depth
    float r, g, b, a;    // vertex color 0–1, over the depth
} UDScreenVert;

@interface UDSoftwareRenderer () {
    float *pixels;           // RGBA, 0–1, the top row first
    float viewOrigin[3];
    float viewAxis[3][3];
    float projX, projY;      // the half picture over tan( half fov )
}
@property (nonatomic, strong, nullable) idDeclManager *declManager;
@property (nonatomic, strong, nullable) idFileSystem *fileSystem;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDMaterialParser *> *materials;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *images;
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

- (void)setViewOrigin:(const float [3])origin axis:(const float [3][3])axis fovX:(float)fovX {
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

#pragma mark - GL's part

/// A texel of @a image at ( @a s, @a t ), bilinear, as @a repeat has the
/// coordinates outside 0–1 (GL_REPEAT, or GL_CLAMP_TO_EDGE for the clamps).
static void UDSample( UDImage *image, int repeat, float s, float t, float out[4] ) {
    int w = image.width, h = image.height;
    const uint8_t *data = image.pixels.bytes;
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
                // TR_CLAMP_TO_ZERO: 0 0 0 255 beyond the edge; …_ALPHA: alpha 0
                if ( outside && repeat == 3 ) value = k == 3 ? 1.0f : 0.0f;
                if ( outside && repeat == 4 && k == 3 ) value = 0.0f;
                c[k] += value * weight;
            }
        }
    }
    memcpy( out, c, sizeof( c ) );
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
    for ( int y = minY; y <= maxY; y++ ) {
        for ( int x = minX; x <= maxX; x++ ) {
            float px = x + 0.5f, py = y + 0.5f;
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
            memcpy( dst, result, sizeof( result ) );
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
        float key = [self materialNamed:surf.material].sort;
        NSUInteger at = sorted.count;
        while ( at > 0 && [self materialNamed:sorted[at - 1].material].sort > key ) at--;
        [sorted insertObject:surf atIndex:at];
    }
    for ( UDParticleSurface *surf in sorted ) {
        [self drawSurface:surf time:time shaderParms:surf.shaderParms];
    }
}

- (void)drawSurface:(UDParticleSurface *)surf time:(float)time shaderParms:(const float *)shaderParms {
    UDMaterialParser *shader = [self materialNamed:surf.material];
    if ( surf.numVerts < 4 ) {
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

        // draw it: each quad as 0 2 3, 0 3 1
        const UDDrawVert *verts = surf.verts;
        for ( int i = 0; i + 3 < surf.numVerts; i += 4 ) {
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

@end
