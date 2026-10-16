#import "UDGuiGLView.h"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"   // GL, on macOS
#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "UDSoftwareRenderer.h"
#import "UDImageProgram.h"

#if !defined(__APPLE__) && !defined(UD_HAVE_GL)

// Built without GL's headers (a stack without libgl-dev): no GL view, and
// UDGuiView draws in software.
@implementation UDGuiGLView
+ (instancetype)viewWithFrame:(NSRect)frame {
    return nil;
}
- (NSBitmapImageRep *)readPicture {
    return nil;
}
@end

#else

#ifdef __APPLE__
#define GL_SILENCE_DEPRECATION
#import <OpenGL/gl3.h>
#define UD_GL_CORE 1
#else
#define GL_GLEXT_PROTOTYPES 1
#include <GL/gl.h>
#include <GL/glext.h>
#define UD_GL_CORE 0
#endif

/// A vertex as the shader takes it: the picture's x y, s t, r g b a.
enum { UDGLVertexFloats = 8 };

/// The vertex shader: the picture (y down) to clip space, as EmitFullScreen's
/// qglOrtho( 0, 640, 480, 0, 0, 1 ) has it. The triangles of a GUI's view
/// have no depth (invW 1), so their s t and colors are as they are.
static const char *const UDGLVertexSource =
    "uniform vec2 pictureSize;\n"
    "IN vec2 position;\n"
    "IN vec2 texcoord;\n"
    "IN vec4 color;\n"
    "OUT vec2 vTexcoord;\n"
    "OUT vec4 vColor;\n"
    "void main() {\n"
    "    gl_Position = vec4(position.x / pictureSize.x * 2.0 - 1.0, 1.0 - position.y / pictureSize.y * 2.0, 0.0, 1.0);\n"
    "    vTexcoord = texcoord;\n"
    "    vColor = color;\n"
    "}\n";

/// The fragment shader: GL_MODULATE, the vertex color and the second
/// texture unit's constant; TR_CLAMP_TO_ZERO (0 0 0 1 beyond the edge) and
/// TR_CLAMP_TO_ZERO_ALPHA (alpha 0 beyond it).
static const char *const UDGLFragmentSource =
    "uniform sampler2D image;\n"
    "uniform vec4 constantColor;\n"
    "uniform int clampMode;\n"
    "IN vec2 vTexcoord;\n"
    "IN vec4 vColor;\n"
    "FRAGMENT_OUT\n"
    "void main() {\n"
    "    vec4 texel = TEXTURE(image, vTexcoord);\n"
    "    if (clampMode != 0 && (vTexcoord.x < 0.0 || vTexcoord.x > 1.0 || vTexcoord.y < 0.0 || vTexcoord.y > 1.0)) {\n"
    "        if (clampMode == 3) texel = vec4(0.0, 0.0, 0.0, 1.0); else texel.a = 0.0;\n"
    "    }\n"
    "    FRAGMENT_COLOR = clamp(texel * vColor * constantColor, 0.0, 1.0);\n"
    "}\n";

#if UD_GL_CORE
static const char *const UDGLVertexPrelude = "#version 150\n#define IN in\n#define OUT out\n";
static const char *const UDGLFragmentPrelude = "#version 150\n#define IN in\n#define TEXTURE texture\n"
                                               "#define FRAGMENT_OUT out vec4 fragColor;\n#define FRAGMENT_COLOR fragColor\n";
#else
static const char *const UDGLVertexPrelude = "#version 120\n#define IN attribute\n#define OUT varying\n";
static const char *const UDGLFragmentPrelude = "#version 120\n#define IN varying\n#define TEXTURE texture2D\n"
                                               "#define FRAGMENT_OUT\n#define FRAGMENT_COLOR gl_FragColor\n";
#endif

/// glBlendFunc's source factor for drawStateBits' GLS_SRCBLEND_* (GL_State's).
static GLenum UDGLSourceFactor(int bits) {
    switch (bits & 0x0000000f) {
        case 0x1: return GL_ZERO;
        case 0x3: return GL_DST_COLOR;
        case 0x4: return GL_ONE_MINUS_DST_COLOR;
        case 0x5: return GL_SRC_ALPHA;
        case 0x6: return GL_ONE_MINUS_SRC_ALPHA;
        case 0x7: return GL_DST_ALPHA;
        case 0x8: return GL_ONE_MINUS_DST_ALPHA;
        case 0x9: return GL_SRC_ALPHA_SATURATE;
        default:  return GL_ONE;
    }
}

/// … and the destination factor for GLS_DSTBLEND_*.
static GLenum UDGLDestinationFactor(int bits) {
    switch (bits & 0x000000f0) {
        case 0x20: return GL_ONE;
        case 0x30: return GL_SRC_COLOR;
        case 0x40: return GL_ONE_MINUS_SRC_COLOR;
        case 0x50: return GL_SRC_ALPHA;
        case 0x60: return GL_ONE_MINUS_SRC_ALPHA;
        case 0x70: return GL_DST_ALPHA;
        case 0x80: return GL_ONE_MINUS_DST_ALPHA;
        default:   return GL_ZERO;
    }
}

static GLuint UDGLCompile(GLenum type, const char *prelude, const char *source, NSString **problem) {
    GLuint shader = glCreateShader(type);
    const char *sources[2] = { prelude, source };
    glShaderSource(shader, 2, sources, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024] = "";
        glGetShaderInfoLog(shader, sizeof(log), NULL, log);
        *problem = [NSString stringWithFormat:@"GLSL: %s", log];
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

@implementation UDGuiGLView {
    BOOL _prepared;
    GLuint _program;
    GLuint _vertexArray;
    GLuint _vertexBuffer;
    GLint _pictureSizeLocation, _constantColorLocation, _clampModeLocation, _imageLocation;
    /// UDImage → its texture (an NSNumber of the name).
    NSMapTable<UDImage *, NSNumber *> *_textures;
}

+ (instancetype)viewWithFrame:(NSRect)frame {
    NSOpenGLPixelFormatAttribute attributes[] = {
#if UD_GL_CORE
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
#endif
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        0
    };
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    if (format == nil) return nil;
    // its context is not asked for here: GNUstep's attaches itself to the
    // view's X window as it is made, and a view not in a window has none
    UDGuiGLView *view = [[self alloc] initWithFrame:frame pixelFormat:format];
    if (view == nil) return nil;
#ifdef __APPLE__
    view.wantsBestResolutionOpenGLSurface = YES;
#endif
    return view;
}

- (void)dealloc {
    NSOpenGLContext *context = _prepared ? self.openGLContext : nil;
    if (context != nil) {
        [context makeCurrentContext];
        for (NSNumber *texture in _textures.objectEnumerator) {
            GLuint name = texture.unsignedIntValue;
            glDeleteTextures(1, &name);
        }
        glDeleteBuffers(1, &_vertexBuffer);
#if UD_GL_CORE
        glDeleteVertexArrays(1, &_vertexArray);
#endif
        glDeleteProgram(_program);
    }
}

- (BOOL)isOpaque {
    return YES;
}

/// The superview, a UDGuiView, takes the events.
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

#pragma mark - Setting up

- (BOOL)_prepare {
    if (_prepared) return _program != 0;
    _prepared = YES;
    _glDescription = [NSString stringWithFormat:@"%s, %s, GLSL %s", glGetString(GL_VERSION), glGetString(GL_RENDERER),
                      glGetString(GL_SHADING_LANGUAGE_VERSION)];
    NSString *problem = nil;
    GLuint vertexShader = UDGLCompile(GL_VERTEX_SHADER, UDGLVertexPrelude, UDGLVertexSource, &problem);
    GLuint fragmentShader = vertexShader ? UDGLCompile(GL_FRAGMENT_SHADER, UDGLFragmentPrelude, UDGLFragmentSource, &problem) : 0;
    if (vertexShader == 0 || fragmentShader == 0) {
        NSLog(@"UDGuiGLView: %@", problem);
        return NO;
    }
    _program = glCreateProgram();
    glAttachShader(_program, vertexShader);
    glAttachShader(_program, fragmentShader);
    glBindAttribLocation(_program, 0, "position");
    glBindAttribLocation(_program, 1, "texcoord");
    glBindAttribLocation(_program, 2, "color");
#if UD_GL_CORE
    glBindFragDataLocation(_program, 0, "fragColor");
#endif
    glLinkProgram(_program);
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);
    GLint linked = 0;
    glGetProgramiv(_program, GL_LINK_STATUS, &linked);
    if (!linked) {
        char log[1024] = "";
        glGetProgramInfoLog(_program, sizeof(log), NULL, log);
        NSLog(@"UDGuiGLView: GLSL: %s", log);
        glDeleteProgram(_program);
        _program = 0;
        return NO;
    }
    _pictureSizeLocation = glGetUniformLocation(_program, "pictureSize");
    _constantColorLocation = glGetUniformLocation(_program, "constantColor");
    _clampModeLocation = glGetUniformLocation(_program, "clampMode");
    _imageLocation = glGetUniformLocation(_program, "image");

#if UD_GL_CORE
    glGenVertexArrays(1, &_vertexArray);
    glBindVertexArray(_vertexArray);
#endif
    glGenBuffers(1, &_vertexBuffer);
    _textures = [NSMapTable strongToStrongObjectsMapTable];
    return YES;
}

/// @a image's texture, uploaded the first time: RGBA, its top row first
/// (t 0, as the engine uploads its images), bilinear.
- (GLuint)_textureOf:(UDImage *)image {
    NSNumber *known = [_textures objectForKey:image];
    if (known != nil) return known.unsignedIntValue;
    GLuint name = 0;
    glGenTextures(1, &name);
    glBindTexture(GL_TEXTURE_2D, name);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, image.width, image.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, image.pixels.bytes);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    [_textures setObject:@(name) forKey:image];
    return name;
}

#pragma mark - Drawing

/// @a rect in the drawable's pixels (a Retina display's are two a point;
/// GNUstep's GL surface is a pixel a point).
- (NSRect)_backing:(NSRect)rect {
#ifdef __APPLE__
    return [self convertRectToBacking:rect];
#else
    return rect;
#endif
}

- (void)setTriangles:(UDTriangleList *)triangles {
    _triangles = triangles;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    if ([self _render]) {
        [self.openGLContext flushBuffer];
    }
}

/// The frame drawn into the back buffer; NO when there is no drawable (the
/// view in no window).
- (BOOL)_render {
    if (self.window == nil) return NO;
    NSOpenGLContext *context = self.openGLContext;
    // the drawable is the view's once its context has it (NSOpenGLView
    // hands it over when it first draws through -display)
    if (context.view != self && self.window != nil) {
        context.view = self;
    }
    [context makeCurrentContext];
    NSRect backing = [self _backing:self.bounds];
    glViewport(0, 0, (GLsizei)NSWidth(backing), (GLsizei)NSHeight(backing));
    glDisable(GL_BLEND);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);

    UDTriangleList *list = self.triangles;
    if (list != nil && list.count > 0 && [self _prepare]) {
        [self _drawList:list backing:backing];
    }
    return YES;
}

- (void)_drawList:(UDTriangleList *)list backing:(NSRect)backing {
    // the GUI's rect, in the backing's pixels from the bottom left (GL's)
    NSRect rect = self.guiRect;
    NSRect bottomUp = NSMakeRect(NSMinX(rect), NSHeight(self.bounds) - NSMaxY(rect), NSWidth(rect), NSHeight(rect));
    NSRect pixels = [self _backing:bottomUp];
    glViewport((GLint)lround(NSMinX(pixels)), (GLint)lround(NSMinY(pixels)),
               (GLsizei)lround(NSWidth(pixels)), (GLsizei)lround(NSHeight(pixels)));

    NSUInteger count = list.count;
    const UDTriangleCommand *triangles = list.triangles;
    NSMutableData *vertices = [NSMutableData dataWithLength:count * 3 * UDGLVertexFloats * sizeof(float)];
    float *out = vertices.mutableBytes;
    for (NSUInteger i = 0; i < count; i++) {
        for (int k = 0; k < 3; k++) {
            const UDScreenVert *v = &triangles[i].v[k];
            float invW = v->invW != 0 ? v->invW : 1;
            float values[UDGLVertexFloats] = { v->x, v->y, v->s / invW, v->t / invW,
                                               v->r / invW, v->g / invW, v->b / invW, v->a / invW };
            memcpy(out, values, sizeof(values));
            out += UDGLVertexFloats;
        }
    }

    glUseProgram(_program);
#if UD_GL_CORE
    glBindVertexArray(_vertexArray);
#endif
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)vertices.length, vertices.bytes, GL_STREAM_DRAW);
    GLsizei stride = UDGLVertexFloats * sizeof(float);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, (const void *)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, (const void *)(2 * sizeof(float)));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, stride, (const void *)(4 * sizeof(float)));
    glUniform2f(_pictureSizeLocation, (GLfloat)self.pictureSize.width, (GLfloat)self.pictureSize.height);
    glUniform1i(_imageLocation, 0);
    glActiveTexture(GL_TEXTURE0);

    // runs of triangles of one image and one stage's state, one draw each
    NSUInteger start = 0;
    while (start < count) {
        const UDTriangleCommand *first = &triangles[start];
        UDImage *image = [list imageOfTriangle:start];
        NSUInteger end = start + 1;
        while (end < count) {
            const UDTriangleCommand *next = &triangles[end];
            if ([list imageOfTriangle:end] != image || next->repeat != first->repeat || next->drawStateBits != first->drawStateBits
                || memcmp(next->constant, first->constant, sizeof(first->constant)) != 0) break;
            end++;
        }
        [self _setStateOf:first image:image];
        glDrawArrays(GL_TRIANGLES, (GLint)(start * 3), (GLsizei)((end - start) * 3));
        start = end;
    }
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glDisable(GL_BLEND);
}

- (NSBitmapImageRep *)readPicture {
    if (![self _render]) return nil;
    NSRect rect = self.guiRect;
    NSRect pixels = [self _backing:NSMakeRect(NSMinX(rect), NSHeight(self.bounds) - NSMaxY(rect), NSWidth(rect), NSHeight(rect))];
    GLint x = (GLint)lround(NSMinX(pixels)), y = (GLint)lround(NSMinY(pixels));
    GLsizei w = (GLsizei)lround(NSWidth(pixels)), h = (GLsizei)lround(NSHeight(pixels));
    if (w <= 0 || h <= 0) return nil;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
    glReadBuffer(GL_BACK);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    NSMutableData *rows = [NSMutableData dataWithLength:(NSUInteger)(w * h * 4)];
    glReadPixels(x, y, w, h, GL_RGBA, GL_UNSIGNED_BYTE, rows.mutableBytes);
    // GL's rows are bottom-up
    const uint8_t *from = rows.bytes;
    uint8_t *to = rep.bitmapData;
    for (GLsizei row = 0; row < h; row++) {
        memcpy(to + (size_t)row * (size_t)w * 4, from + (size_t)(h - 1 - row) * (size_t)w * 4, (size_t)w * 4);
    }
    // opaque, as the screen shows it: the framebuffer's alpha is the blends'
    for (size_t i = 0; i < (size_t)w * (size_t)h; i++) {
        to[i * 4 + 3] = 255;
    }
    [self.openGLContext flushBuffer];
    return rep;
}

/// GL_State's blend and mask for @a triangle's drawStateBits, its texture
/// bound and wrapped as its stage has it, its constant color.
- (void)_setStateOf:(const UDTriangleCommand *)triangle image:(UDImage *)image {
    int bits = triangle->drawStateBits;
    GLenum source = UDGLSourceFactor(bits), destination = UDGLDestinationFactor(bits);
    if (source == GL_ONE && destination == GL_ZERO) {
        glDisable(GL_BLEND);
    } else {
        glEnable(GL_BLEND);
        glBlendFunc(source, destination);
    }
    // GLS_REDMASK, _GREENMASK, _BLUEMASK, _ALPHAMASK
    glColorMask(!(bits & 0x00000200), !(bits & 0x00000400), !(bits & 0x00000800), !(bits & 0x00001000));

    glBindTexture(GL_TEXTURE_2D, [self _textureOf:image]);
    GLint wrap = triangle->repeat == 0 ? GL_REPEAT : GL_CLAMP_TO_EDGE;
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap);
    glUniform4fv(_constantColorLocation, 1, triangle->constant);
    glUniform1i(_clampModeLocation, triangle->repeat == 3 || triangle->repeat == 4 ? triangle->repeat : 0);
}

@end

#endif
