/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idDeviceContext.m — ui/DeviceContext.cpp, ported; the render system's
 * RegisterFont (renderer/tr_font.cpp, the .dat reader: no FreeType) and
 * SetColor/DrawStretchPic (RenderSystem.cpp) into the GUI model; and the
 * GUIs' idMaterial handle.
 */

#import "idFileSystem.h"
#import "idDeviceContext.h"
#import "idUserInterface.h"
#import "idGuiModel.h"
#import "idDict.h"
#import "UDSoftwareRenderer.h"
#import "UDMaterialParser.h"
#import "UDImageProgram.h"
#import "idStr.h"

idVec4 idDeviceContext_colorPurple;
idVec4 idDeviceContext_colorOrange;
idVec4 idDeviceContext_colorYellow;
idVec4 idDeviceContext_colorGreen;
idVec4 idDeviceContext_colorBlue;
idVec4 idDeviceContext_colorRed;
idVec4 idDeviceContext_colorBlack;
idVec4 idDeviceContext_colorWhite;
idVec4 idDeviceContext_colorNone;

#pragma mark - idMaterial

@interface idMaterial ()
@property (nonatomic, weak) idUserInterfaceManager *manager;
@end

@implementation idMaterial

- (instancetype)initWithName:(NSString *)name manager:(idUserInterfaceManager *)manager {
    self = [super init];
    if (self) {
        _name = [name copy];
        _manager = manager;
    }
    return self;
}


- (UDMaterialParser *)parser {
    return [self.manager.renderer materialNamed:self.name];
}

/// GetStage( 0 )->texture.image (the default image for one that doesn't load)
- (UDImage *)firstImage {
    UDMaterialStageInfo *stage = [self parser].stages.firstObject;
    UDImage *image = stage.imageName ? [self.manager.renderer imageNamed:stage.imageName] : nil;
    return image ?: [self.manager.renderer imageNamed:@"_default"];
}

- (int)getImageWidth { return [self firstImage].width; }
- (int)getImageHeight { return [self firstImage].height; }
- (BOOL)defaulted { return [self parser].defaulted; }
- (int)cinematicLength { return 0; }
- (void)updateCinematic:(int)time { }
- (void)resetCinematicTime:(int)time { }
- (void)setImageClassifications:(int)tag { }

- (void)setSort:(float)sort {
    [self.manager.renderer setSort:sort forMaterial:self.name];
}

- (float)getSort {
    return [self parser].sort;
}

@end

#pragma mark - RegisterFont (renderer/tr_font.cpp)

#define FILESIZE_fontInfo_t (20548)

static int readInt( const unsigned char *fdFile, int *fdOffset ) {
    int i = fdFile[*fdOffset]+(fdFile[*fdOffset+1]<<8)+(fdFile[*fdOffset+2]<<16)+(fdFile[*fdOffset+3]<<24);
    *fdOffset += 4;
    return i;
}

static float readFloat( const unsigned char *fdFile, int *fdOffset ) {
    float f;
    memcpy(&f, &fdFile[*fdOffset], sizeof(float));
    *fdOffset += sizeof(float);
    return f;   // LittleFloat: the hosts are little endian
}

/*
============
RegisterFont

Loads 3 point sizes, 12, 24, and 48
============
*/
static BOOL RegisterFont( idUserInterfaceManager *manager, NSString *fontName, fontInfoEx_t *font ) {
    void *faceData;
    int i, len, fontCount;
    NSString *name;

    int pointSize = 12;

    memset( font, 0, sizeof( *font ) );

    for ( fontCount = 0; fontCount < 3; fontCount++ ) {

        if ( fontCount == 0) {
            pointSize = 12;
        } else if ( fontCount == 1 ) {
            pointSize = 24;
        } else {
            pointSize = 48;
        }
        // we also need to adjust the scale based on point size relative to 48 points as the ui scaling is based on a 48 point font
        float glyphScale = 1.0f;        // change the scale to be relative to 1 based on 72 dpi ( so dpi of 144 means a scale of .5 )
        glyphScale *= 48.0f / pointSize;
        (void)glyphScale;

        name = [NSString stringWithFormat:@"%@/fontImage_%i.dat", fontName, pointSize];

        fontInfo_t *outFont;
        if ( fontCount == 0 ) {
            outFont = &font->fontInfoSmall;
        }
        else if ( fontCount == 1 ) {
            outFont = &font->fontInfoMedium;
        }
        else {
            outFont = &font->fontInfoLarge;
        }

        len = [manager.fileSystem readFile:name buffer:NULL timestamp:NULL error:NULL];
        if ( len != FILESIZE_fontInfo_t ) {
            [manager uiWarning:[NSString stringWithFormat:@"RegisterFont: couldn't find font: '%@'", name]];
            return NO;
        }

        [manager.fileSystem readFile:name buffer:&faceData timestamp:NULL error:NULL];
        int fdOffset = 0;
        const unsigned char *fdFile = faceData;

        for( i = 0; i < GLYPHS_PER_FONT; i++ ) {
            outFont->glyphs[i].height       = readInt( fdFile, &fdOffset );
            outFont->glyphs[i].top          = readInt( fdFile, &fdOffset );
            outFont->glyphs[i].bottom       = readInt( fdFile, &fdOffset );
            outFont->glyphs[i].pitch        = readInt( fdFile, &fdOffset );
            outFont->glyphs[i].xSkip        = readInt( fdFile, &fdOffset );
            outFont->glyphs[i].imageWidth   = readInt( fdFile, &fdOffset );
            outFont->glyphs[i].imageHeight  = readInt( fdFile, &fdOffset );
            outFont->glyphs[i].s            = readFloat( fdFile, &fdOffset );
            outFont->glyphs[i].t            = readFloat( fdFile, &fdOffset );
            outFont->glyphs[i].s2           = readFloat( fdFile, &fdOffset );
            outFont->glyphs[i].t2           = readFloat( fdFile, &fdOffset );
            /* font.glyphs[i].glyph         = */ readInt( fdFile, &fdOffset );
            //FIXME: the +6, -6 skips the embedded fonts/
            memcpy( outFont->glyphs[i].shaderName, &fdFile[fdOffset + 6], 32 - 6 );
            fdOffset += 32;
        }
        outFont->glyphScale = readFloat( fdFile, &fdOffset );

        int mw = 0;
        int mh = 0;
        for (i = GLYPH_START; i < GLYPH_END; i++) {
            name = [NSString stringWithFormat:@"%@/%@", fontName, [NSString ud_stringWithLatin1:outFont->glyphs[i].shaderName]];
            outFont->glyphs[i].glyph = [manager findMaterial:name];
            [outFont->glyphs[i].glyph setSort:SS_GUI];
            if (mh < outFont->glyphs[i].height) {
                mh = outFont->glyphs[i].height;
            }
            if (mw < outFont->glyphs[i].xSkip) {
                mw = outFont->glyphs[i].xSkip;
            }
        }
        if (fontCount == 0) {
            font->maxWidthSmall = mw;
            font->maxHeightSmall = mh;
        } else if (fontCount == 1) {
            font->maxWidthMedium = mw;
            font->maxHeightMedium = mh;
        } else {
            font->maxWidthLarge = mw;
            font->maxHeightLarge = mh;
        }
        [manager.fileSystem freeFile:faceData error:NULL];
    }

    return YES ;
}

#pragma mark - idStr's, over the engine's bytes

/// idStr::IsColor
static inline BOOL IsColor( const char *s ) {
    return ( s[0] == C_COLOR_ESCAPE && s[1] != '\0' && s[1] != ' ' );
}

static const idVec4 g_color_table[16] = {
    { 0.0f, 0.0f, 0.0f, 1.0f },
    { 1.0f, 0.0f, 0.0f, 1.0f }, // S_COLOR_RED
    { 0.0f, 1.0f, 0.0f, 1.0f }, // S_COLOR_GREEN
    { 1.0f, 1.0f, 0.0f, 1.0f }, // S_COLOR_YELLOW
    { 0.0f, 0.0f, 1.0f, 1.0f }, // S_COLOR_BLUE
    { 0.0f, 1.0f, 1.0f, 1.0f }, // S_COLOR_CYAN
    { 1.0f, 0.0f, 1.0f, 1.0f }, // S_COLOR_MAGENTA
    { 1.0f, 1.0f, 1.0f, 1.0f }, // S_COLOR_WHITE
    { 0.5f, 0.5f, 0.5f, 1.0f }, // S_COLOR_GRAY
    { 0.0f, 0.0f, 0.0f, 1.0f }, // S_COLOR_BLACK
    { 0.0f, 0.0f, 0.0f, 1.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f },
    { 0.0f, 0.0f, 0.0f, 1.0f },
};

/// idStr::ColorForIndex
static inline idVec4 ColorForIndex( int i ) {
    return g_color_table[ i & 15 ];
}

#pragma mark - idDeviceContext

@implementation idDeviceContext {
    __weak idUserInterfaceManager *manager;

    idMaterial      *cursorImages[CURSOR_COUNT];
    idMaterial      *scrollBarImages[SCROLLBAR_COUNT];
    idMaterial      *whiteImage;
    fontInfoEx_t    *activeFont;
    fontInfo_t      *useFont;
    float           xScale;
    float           yScale;

    //#modified-fva; BEGIN
    float           cst_xOffset;
    float           cst_yOffset;
    BOOL            cstAdjustCoords;
    //#modified-fva; END

    float           vidHeight;
    float           vidWidth;

    int             cursor;

    NSMutableArray<NSValue *> *clipRects;

    fontInfoEx_t    *fonts;         // idList<fontInfoEx_t>, its storage
    int             numFonts;
    NSString        *fontLang;
    NSMutableArray<NSString *> *fontNames;  // fontInfoEx_t's names

    BOOL            enableClipping;

    BOOL            overStrikeMode;

    idMat3          mat;
    idVec3          origin;
    BOOL            initialized;

    BOOL            mbcs;

    // DG: this is used for the "make sure menus are rendered as 4:3" hack
    idVec2          fixScaleForMenu;
    idVec2          fixOffsetForMenu;
}

- (instancetype)initWithManager:(idUserInterfaceManager *)aManager {
    self = [super init];
    if (self) {
        manager = aManager;
        clipRects = [NSMutableArray array];
        // the fonts' list doesn't move: activeFont points into it
        fonts = calloc( 256, sizeof( fontInfoEx_t ) );
        fontNames = [NSMutableArray array];
        [self clear];
    }
    return self;
}

- (void)dealloc {
    free( fonts );
}

- (int)findFont:(NSString *)name {
    int c = numFonts;
    for (int i = 0; i < c; i++) {
        if ([name ud_iequals:fontNames[i]]) {
            return i;
        }
    }

    // If the font was not found, try to register it
    // fileName.Replace( "fonts", va( "fonts/%s", fontLang.c_str() ) )
    NSString *fileName = [name stringByReplacingOccurrencesOfString:@"fonts" withString:[NSString stringWithFormat:@"fonts/%@", fontLang]];

    if ( numFonts == 256 ) {
        return -1;
    }
    int index = numFonts++;
    memset( &fonts[index], 0, sizeof( fontInfoEx_t ) ); // DG: initialize this
    [fontNames addObject:@""];
    if ( RegisterFont( manager, fileName, &fonts[index] ) ){
        fontNames[index] = [name copy];
        return index;
    } else {
        [manager uiWarning:[NSString stringWithFormat:@"Could not register font %@ [%@]", name, fileName]];
        return -1;
    }
}

- (void)setupFonts {
    fontLang = [manager.cvars getString:@"sys_lang"];

    // western european languages can use the english font
    if ( [fontLang isEqualToString:@"french"] || [fontLang isEqualToString:@"german"] || [fontLang isEqualToString:@"spanish"] || [fontLang isEqualToString:@"italian"] ) {
        fontLang = @"english";
    }

    // Default font has to be added first
    [self findFont:@"fonts"];
}

- (void)setFont:(int)num {
    if ( num >= 0 && num < numFonts ) {
        activeFont = &fonts[num];
    } else {
        activeFont = &fonts[0];
    }
}


- (void)deviceInit {
    xScale = 0.0;
    [self setSize:VIRTUAL_WIDTH height:VIRTUAL_HEIGHT];
    whiteImage = [manager findMaterial:@"guis/assets/white.tga"];
    [whiteImage setSort:SS_GUI];
    mbcs = NO;
    [self setupFonts];
    activeFont = &fonts[0];
    idDeviceContext_colorPurple = idVec4_Make(1, 0, 1, 1);
    idDeviceContext_colorOrange = idVec4_Make(1, 1, 0, 1);
    idDeviceContext_colorYellow = idVec4_Make(0, 1, 1, 1);
    idDeviceContext_colorGreen = idVec4_Make(0, 1, 0, 1);
    idDeviceContext_colorBlue = idVec4_Make(0, 0, 1, 1);
    idDeviceContext_colorRed = idVec4_Make(1, 0, 0, 1);
    idDeviceContext_colorWhite = idVec4_Make(1, 1, 1, 1);
    idDeviceContext_colorBlack = idVec4_Make(0, 0, 0, 1);
    idDeviceContext_colorNone = idVec4_Make(0, 0, 0, 0);
    cursorImages[CURSOR_ARROW] = [manager findMaterial:@"ui/assets/guicursor_arrow.tga"];
    cursorImages[CURSOR_HAND] = [manager findMaterial:@"ui/assets/guicursor_hand.tga"];
    scrollBarImages[SCROLLBAR_HBACK] = [manager findMaterial:@"ui/assets/scrollbarh.tga"];
    scrollBarImages[SCROLLBAR_VBACK] = [manager findMaterial:@"ui/assets/scrollbarv.tga"];
    scrollBarImages[SCROLLBAR_THUMB] = [manager findMaterial:@"ui/assets/scrollbar_thumb.tga"];
    scrollBarImages[SCROLLBAR_RIGHT] = [manager findMaterial:@"ui/assets/scrollbar_right.tga"];
    scrollBarImages[SCROLLBAR_LEFT] = [manager findMaterial:@"ui/assets/scrollbar_left.tga"];
    scrollBarImages[SCROLLBAR_UP] = [manager findMaterial:@"ui/assets/scrollbar_up.tga"];
    scrollBarImages[SCROLLBAR_DOWN] = [manager findMaterial:@"ui/assets/scrollbar_down.tga"];
    [cursorImages[CURSOR_ARROW] setSort:SS_GUI];
    [cursorImages[CURSOR_HAND] setSort:SS_GUI];
    [scrollBarImages[SCROLLBAR_HBACK] setSort:SS_GUI];
    [scrollBarImages[SCROLLBAR_VBACK] setSort:SS_GUI];
    [scrollBarImages[SCROLLBAR_THUMB] setSort:SS_GUI];
    [scrollBarImages[SCROLLBAR_RIGHT] setSort:SS_GUI];
    [scrollBarImages[SCROLLBAR_LEFT] setSort:SS_GUI];
    [scrollBarImages[SCROLLBAR_UP] setSort:SS_GUI];
    [scrollBarImages[SCROLLBAR_DOWN] setSort:SS_GUI];
    cursor = CURSOR_ARROW;
    enableClipping = YES;
    overStrikeMode = YES;
    idMat3_Identity( &mat );
    origin = vec3_origin;
    initialized = YES;

    // DG: this is used for the "make sure menus are rendered as 4:3" hack
    fixScaleForMenu = idVec2_Make(1, 1);
    fixOffsetForMenu = idVec2_Make(0, 0);
}

- (void)shutdown {
    [clipRects removeAllObjects];
    numFonts = 0;
    [fontNames removeAllObjects];
    [self clear];
}

- (void)clear {
    initialized = NO;
    useFont = NULL;
    activeFont = NULL;
    mbcs = NO;
}

- (BOOL)initialized { return initialized; }
- (void)enableLocalization { }

- (void)setTransformInfo:(idVec3)org mat:(idMat3)m {
    origin = org;
    mat = m;
}

//
//  added method
- (void)getTransformInfo:(idVec3 *)org mat:(idMat3 *)m {
    *m = mat;
    *org = origin;
}
//

- (void)popClipRect {
    if (clipRects.count) {
        [clipRects removeLastObject];
    }
}

- (void)pushClipRect:(idRectangle)r {
    [clipRects addObject:[NSValue valueWithBytes:&r objCType:@encode(idRectangle)]];
}

- (void)pushClipRect:(float)x y:(float)y w:(float)w h:(float)h {
    [self pushClipRect:idRectangle_Make(x, y, w, h)];
}

- (BOOL)clippedCoords:(float *)x y:(float *)y w:(float *)w h:(float *)h {
    return [self clippedCoords:x y:y w:w h:h s1:NULL t1:NULL s2:NULL t2:NULL];
}

- (BOOL)clippedCoords:(float *)x y:(float *)y w:(float *)w h:(float *)h s1:(float *)s1 t1:(float *)t1 s2:(float *)s2 t2:(float *)t2 {

    if ( enableClipping == NO || clipRects.count == 0 ) {
        return NO;
    }

    int c = (int)clipRects.count;
    while( --c > 0 ) {
        idRectangle clipRectValue;
        [clipRects[c] getValue:&clipRectValue];
        idRectangle *clipRect = &clipRectValue;

        float ox = *x;
        float oy = *y;
        float ow = *w;
        float oh = *h;

        if ( ow <= 0.0f || oh <= 0.0f ) {
            break;
        }

        if (*x < clipRect->x) {
            *w -= clipRect->x - *x;
            *x = clipRect->x;
        } else if (*x > clipRect->x + clipRect->w) {
            *x = *w = *y = *h = 0;
        }
        if (*y < clipRect->y) {
            *h -= clipRect->y - *y;
            *y = clipRect->y;
        } else if (*y > clipRect->y + clipRect->h) {
            *x = *w = *y = *h = 0;
        }
        if (*w > clipRect->w) {
            *w = clipRect->w - *x + clipRect->x;
        } else if (*x + *w > clipRect->x + clipRect->w) {
            *w = idRectangle_Right( clipRect ) - *x;
        }
        if (*h > clipRect->h) {
            *h = clipRect->h - *y + clipRect->y;
        } else if (*y + *h > clipRect->y + clipRect->h) {
            *h = idRectangle_Bottom( clipRect ) - *y;
        }

        if ( s1 && s2 && t1 && t2 && ow > 0.0f ) {
            float ns1, ns2, nt1, nt2;
            // upper left
            float u = ( *x - ox ) / ow;
            ns1 = *s1 * ( 1.0f - u ) + *s2 * ( u );

            // upper right
            u = ( *x + *w - ox ) / ow;
            ns2 = *s1 * ( 1.0f - u ) + *s2 * ( u );

            // lower left
            u = ( *y - oy ) / oh;
            nt1 = *t1 * ( 1.0f - u ) + *t2 * ( u );

            // lower right
            u = ( *y + *h - oy ) / oh;
            nt2 = *t1 * ( 1.0f - u ) + *t2 * ( u );

            // set values
            *s1 = ns1;
            *s2 = ns2;
            *t1 = nt1;
            *t2 = nt2;
        }
    }

    return (*w == 0 || *h == 0) ? YES : NO;
}

// DG: this is used for the "make sure menus are rendered as 4:3" hack
- (void)setMenuScaleFix:(BOOL)enable {
    if(enable) {
        float w = manager.screenWidth;
        float h = manager.screenHeight;
        float aspectRatio = w/h;
        static const float virtualAspectRatio = (float)VIRTUAL_WIDTH/(float)VIRTUAL_HEIGHT; // 4:3
        if(aspectRatio > 1.4f) {
            // widescreen (4:3 is 1.333 3:2 is 1.5, 16:10 is 1.6, 16:9 is 1.7778)
            // => we need to scale and offset X
            // All the coordinates here assume 640x480 (VIRTUAL_WIDTH x VIRTUAL_HEIGHT)
            // screensize, so to fit a 4:3 menu into 640x480 stretched to a widescreen,
            // we need do decrease the width to something smaller than 640 and center
            // the result with an offset
            float scaleX = virtualAspectRatio/aspectRatio;
            float offsetX = (1.0f-scaleX)*(VIRTUAL_WIDTH*0.5f); // (640 - scale*640)/2
            fixScaleForMenu = idVec2_Make(scaleX, 1);
            fixOffsetForMenu = idVec2_Make(offsetX, 0);
        } else if(aspectRatio < 1.24f) {
            // portrait-mode, "thinner" than 5:4 (which is 1.25)
            // => we need to scale and offset Y
            // it's analogue to the other case, but inverted and with height and Y
            float scaleY = aspectRatio/virtualAspectRatio;
            float offsetY = (1.0f - scaleY)*(VIRTUAL_HEIGHT*0.5f); // (480 - scale*480)/2
            fixScaleForMenu = idVec2_Make(1, scaleY);
            fixOffsetForMenu = idVec2_Make(0, offsetY);
        }
    } else {
        fixScaleForMenu = idVec2_Make(1, 1);
        fixOffsetForMenu = idVec2_Make(0, 0);
    }
}

- (BOOL)isMenuScaleFixActive {
    return fixOffsetForMenu.x != 0.0f || fixOffsetForMenu.y != 0.0f;
}

// DG: Note: not sure if AdjustCoords() works entirely as it should, but it seems
//     good enough for the idRenderWindow with the mars globe in the main menu
- (void)adjustCoords:(float *)x y:(float *)y w:(float *)w h:(float *)h {
    // TODO: not sure about cst_*Offset
    if (x) {
        *x *= xScale;
        *x += cst_xOffset; // DG: for CstDoom3 anchored windows

        *x *= fixScaleForMenu.x; // DG: for "render menus as 4:3" hack
        *x += fixOffsetForMenu.x;
    }
    if (y) {
        *y *= yScale;
        *y += cst_yOffset; // DG: for CstDoom3 anchored windows

        *y *= fixScaleForMenu.y; // DG: for "render menus as 4:3" hack
        *y += fixOffsetForMenu.y;
    }
    if (w) {
        *w *= xScale;

        *w *= fixScaleForMenu.x; // DG: for "render menus as 4:3" hack
    }
    if (h) {
        *h *= yScale;

        *h *= fixScaleForMenu.y; // DG: for "render menus as 4:3" hack
    }
}

static void SetQuadVerts( UDDrawVert verts[4], float x, float y, float w, float h, float s1, float t1, float s2, float t2 ) {
    // idDrawVert has no constructor; its color is whatever was there (here 0)
    memset( verts, 0, sizeof( UDDrawVert ) * 4 );
    verts[0].xyz[0] = x;
    verts[0].xyz[1] = y;
    verts[0].xyz[2] = 0;
    verts[0].st[0] = s1;
    verts[0].st[1] = t1;
    verts[1].xyz[0] = x + w;
    verts[1].xyz[1] = y;
    verts[1].xyz[2] = 0;
    verts[1].st[0] = s2;
    verts[1].st[1] = t1;
    verts[2].xyz[0] = x + w;
    verts[2].xyz[1] = y + h;
    verts[2].xyz[2] = 0;
    verts[2].st[0] = s2;
    verts[2].st[1] = t2;
    verts[3].xyz[0] = x;
    verts[3].xyz[1] = y + h;
    verts[3].xyz[2] = 0;
    verts[3].st[0] = s1;
    verts[3].st[1] = t2;
    for ( int i = 0; i < 4; i++ ) {
        verts[i].normal[0] = 0;
        verts[i].normal[1] = 0;
        verts[i].normal[2] = 1;
        verts[i].tangents[0][0] = 1;
        verts[i].tangents[0][1] = 0;
        verts[i].tangents[0][2] = 0;
        verts[i].tangents[1][0] = 0;
        verts[i].tangents[1][1] = 1;
        verts[i].tangents[1][2] = 0;
    }
}

static inline void TransformVert( UDDrawVert *v, idVec3 origin, const idMat3 *mat ) {
    // verts[i].xyz -= origin; verts[i].xyz *= mat; verts[i].xyz += origin;
    idVec3 p = idVec3_Make( v->xyz[0] - origin.x, v->xyz[1] - origin.y, v->xyz[2] - origin.z );
    p = idVec3_TimesMat3( p, mat );
    v->xyz[0] = p.x + origin.x;
    v->xyz[1] = p.y + origin.y;
    v->xyz[2] = p.z + origin.z;
}

// fva/DG: added adjustCoords argument for CstDoom3 anchored GUIs and our old
//         scale-menus-to-4:3-fix, it basically replaces calling AdjustCoords(&x, &y, &w, &h)
//         before calling this
- (void)drawStretchPic:(float)x y:(float)y w:(float)w h:(float)h s0:(float)s1 t0:(float)t1 s1:(float)s2 t1:(float)t2 mat:(idMaterial *)shader adjustCoords:(BOOL)adjustCoords {
    UDDrawVert verts[4];
    int indexes[6];
    indexes[0] = 3;
    indexes[1] = 0;
    indexes[2] = 2;
    indexes[3] = 2;
    indexes[4] = 0;
    indexes[5] = 1;
    SetQuadVerts( verts, x, y, w, h, s1, t1, s2, t2 );

    BOOL ident = !idMat3_IsIdentity( &mat );
    if ( ident ) {
        TransformVert( &verts[0], origin, &mat );
        TransformVert( &verts[1], origin, &mat );
        TransformVert( &verts[2], origin, &mat );
        TransformVert( &verts[3], origin, &mat );
    }

    //#modified-fva; BEGIN
    if (adjustCoords) {
        for( int i=0; i<4; ++i) {
            // Note: if cstAdjustCoords == NO; cst_*Offset is 0, so that doesn't require special handling
            float ax = verts[i].xyz[0] * xScale + cst_xOffset;
            float ay = verts[i].xyz[1] * yScale + cst_yOffset;
            verts[i].xyz[0] = ax * fixScaleForMenu.x + fixOffsetForMenu.x;
            verts[i].xyz[1] = ay * fixScaleForMenu.y + fixOffsetForMenu.y;
        }
    }
    //#modified-fva; END

    [manager.guiModel drawStretchPic:verts indexes:indexes vertCount:4 indexCount:6 material:shader clip:ident minX:0.0f minY:0.0f maxX:640.0f maxY:480.0f];

}

// renderSystem->SetColor( color )
- (void)setColor:(idVec4)color {
    [manager.guiModel setColor:color.x g:color.y b:color.z a:color.w];
}

- (void)drawMaterial:(float)x y:(float)y w:(float)w h:(float)h mat:(idMaterial *)material color:(idVec4)color {
    [self drawMaterial:x y:y w:w h:h mat:material color:color scalex:1.0 scaley:1.0];
}

- (void)drawMaterial:(float)x y:(float)y w:(float)w h:(float)h mat:(idMaterial *)material color:(idVec4)color scalex:(float)scalex scaley:(float)scaley {

    [self setColor:color];

    float   s0, s1, t0, t1;
//
//  handle negative scales as well
    if ( scalex < 0 )
    {
        w *= -1;
        scalex *= -1;
    }
    if ( scaley < 0 )
    {
        h *= -1;
        scaley *= -1;
    }
//
    if( w < 0 ) {   // flip about vertical
        w  = -w;
        s0 = 1 * scalex;
        s1 = 0;
    }
    else {
        s0 = 0;
        s1 = 1 * scalex;
    }

    if( h < 0 ) {   // flip about horizontal
        h  = -h;
        t0 = 1 * scaley;
        t1 = 0;
    }
    else {
        t0 = 0;
        t1 = 1 * scaley;
    }

    if ( [self clippedCoords:&x y:&y w:&w h:&h s1:&s0 t1:&t0 s2:&s1 t2:&t1] ) {
        return;
    }

    //#modified-fva; BEGIN
    [self drawStretchPic:x y:y w:w h:h s0:s0 t0:t0 s1:s1 t1:t1 mat:material adjustCoords:YES];
    //#modified-fva; END
}

- (void)drawMaterialRotated:(float)x y:(float)y w:(float)w h:(float)h mat:(idMaterial *)material color:(idVec4)color scalex:(float)scalex scaley:(float)scaley angle:(float)angle {

    [self setColor:color];

    float   s0, s1, t0, t1;
    //
    //  handle negative scales as well
    if ( scalex < 0 )
    {
        w *= -1;
        scalex *= -1;
    }
    if ( scaley < 0 )
    {
        h *= -1;
        scaley *= -1;
    }
    //
    if( w < 0 ) {   // flip about vertical
        w  = -w;
        s0 = 1 * scalex;
        s1 = 0;
    }
    else {
        s0 = 0;
        s1 = 1 * scalex;
    }

    if( h < 0 ) {   // flip about horizontal
        h  = -h;
        t0 = 1 * scaley;
        t1 = 0;
    }
    else {
        t0 = 0;
        t1 = 1 * scaley;
    }

    if ( angle == 0.0f && [self clippedCoords:&x y:&y w:&w h:&h s1:&s0 t1:&t0 s2:&s1 t2:&t1] ) {
        return;
    }

    //#modified-fva; BEGIN
    [self drawStretchPicRotated:x y:y w:w h:h s0:s0 t0:t0 s1:s1 t1:t1 mat:material angle:angle adjustCoords:YES];
    //#modified-fva; END
}

// fva/DG: added adjustCoords argument for CstDoom3 anchored GUIs and our old
//         scale-menus-to-4:3-fix, it basically replaces calling AdjustCoords(&x, &y, &w, &h)
//         before calling this
- (void)drawStretchPicRotated:(float)x y:(float)y w:(float)w h:(float)h s0:(float)s1 t0:(float)t1 s1:(float)s2 t1:(float)t2 mat:(idMaterial *)shader angle:(float)angle adjustCoords:(BOOL)adjustCoords {

    UDDrawVert verts[4];
    int indexes[6];
    indexes[0] = 3;
    indexes[1] = 0;
    indexes[2] = 2;
    indexes[3] = 2;
    indexes[4] = 0;
    indexes[5] = 1;
    SetQuadVerts( verts, x, y, w, h, s1, t1, s2, t2 );

    BOOL ident = !idMat3_IsIdentity( &mat );
    if ( ident ) {
        TransformVert( &verts[0], origin, &mat );
        TransformVert( &verts[1], origin, &mat );
        TransformVert( &verts[2], origin, &mat );
        TransformVert( &verts[3], origin, &mat );
    }

    //Generate a translation so we can translate to the center of the image rotate and draw
    idVec3 origTrans;
    origTrans.x = x+(w/2);
    origTrans.y = y+(h/2);
    origTrans.z = 0;


    //Rotate the verts about the z axis before drawing them
    float sinAng = sinf(angle);
    float cosAng = cosf(angle);
    for(int i = 0; i < 4; i++) {
        //Translate to origin
        float vx = verts[i].xyz[0] - origTrans.x;
        float vy = verts[i].xyz[1] - origTrans.y;
        float vz = verts[i].xyz[2] - origTrans.z;

        //Rotate: rotz * xyz, rotz an idMat4 with [0][0] cos, [0][1] sin,
        // [1][0] -sin, [1][1] cos
        float rx = cosAng * vx + sinAng * vy;
        float ry = -sinAng * vx + cosAng * vy;

        //Translate back
        verts[i].xyz[0] = rx + origTrans.x;
        verts[i].xyz[1] = ry + origTrans.y;
        verts[i].xyz[2] = vz + origTrans.z;
    }

    //#modified-fva; BEGIN
    if (adjustCoords) {
        for( int i=0; i<4; ++i) {
            // Note: if cstAdjustCoords == NO; cst_*Offset is 0, so that doesn't require special handling
            float ax = verts[i].xyz[0] * xScale + cst_xOffset;
            float ay = verts[i].xyz[1] * yScale + cst_yOffset;
            verts[i].xyz[0] = ax * fixScaleForMenu.x + fixOffsetForMenu.x;
            verts[i].xyz[1] = ay * fixScaleForMenu.y + fixOffsetForMenu.y;
        }
    }
    //#modified-fva; END

    [manager.guiModel drawStretchPic:verts indexes:indexes vertCount:4 indexCount:6 material:shader clip:(angle == 0.0) ? NO : YES minX:0.0f minY:0.0f maxX:640.0f maxY:480.0f];
}

- (void)drawFilledRect:(float)x y:(float)y width:(float)w height:(float)h color:(idVec4)color {

    if ( color.w == 0.0f ) {
        return;
    }

    [self setColor:color];

    if ([self clippedCoords:&x y:&y w:&w h:&h]) {
        return;
    }

    //#modified-fva; BEGIN
    [self drawStretchPic:x y:y w:w h:h s0:0 t0:0 s1:0 t1:0 mat:whiteImage adjustCoords:YES];
    //#modified-fva; END
}


- (void)drawRect:(float)x y:(float)y width:(float)w height:(float)h size:(float)size color:(idVec4)color {

    if ( color.w == 0.0f ) {
        return;
    }

    [self setColor:color];

    if ([self clippedCoords:&x y:&y w:&w h:&h]) {
        return;
    }

    //#modified-fva; BEGIN
    [self drawStretchPic:x y:y + size w:size h:h - 2.0f * size s0:0 t0:0 s1:0 t1:0 mat:whiteImage adjustCoords:YES];
    [self drawStretchPic:x + w - size y:y + size w:size h:h - 2.0f * size s0:0 t0:0 s1:0 t1:0 mat:whiteImage adjustCoords:YES];
    [self drawStretchPic:x y:y w:w h:size s0:0 t0:0 s1:0 t1:0 mat:whiteImage adjustCoords:YES];
    [self drawStretchPic:x y:y + h - size w:w h:size s0:0 t0:0 s1:0 t1:0 mat:whiteImage adjustCoords:YES];
    //#modified-fva; END
}

- (void)drawMaterialRect:(float)x y:(float)y w:(float)w h:(float)h size:(float)size mat:(idMaterial *)material color:(idVec4)color {

    if ( color.w == 0.0f ) {
        return;
    }

    [self setColor:color];
    [self drawMaterial:x y:y w:size h:h mat:material color:color];
    [self drawMaterial:x + w - size y:y w:size h:h mat:material color:color];
    [self drawMaterial:x y:y w:w h:size mat:material color:color];
    [self drawMaterial:x y:y + h - size w:w h:size mat:material color:color];
}


- (void)setCursor:(int)n {
    cursor = (n < CURSOR_ARROW || n >= CURSOR_COUNT) ? CURSOR_ARROW : n;
}

- (void)drawCursor:(float *)x y:(float *)y size:(float)size {
    if (*x < 0) {
        *x = 0;
    }

    if (*x >= vidWidth) {
        *x = vidWidth;
    }

    if (*y < 0) {
        *y = 0;
    }

    if (*y >= vidHeight) {
        *y = vidHeight;
    }

    [self setColor:idDeviceContext_colorWhite];

    // DG: originally, this just called AdjustCoords() and then DrawStretchPic().
    //     It had to be adjusted to scale menus and other fullscreen GUIs to 4:3 aspect ratio
    //     and for the CstDoom3 anchored GUIs, so all that is now done here

    // the following block used to be Adjust(Cursor)Coords()
    // (no point in keeping that function when it's only used here)
    *x *= xScale;
    *y *= yScale;
    size *= xScale;
    // TODO: not sure if scaling it by both is the right thing to do..
    //   but OTOH, probably one of them is always 1, at least when not using an anchor
    //   (and why would a cursor use an anchor)
    size *= yScale;

    // the *actual* sizes used (but not set to *x and *y) need to apply the menu fixes
    float sizeW = size * fixScaleForMenu.x;
    float sizeH = size * fixScaleForMenu.y;
    float fixedX = *x * fixScaleForMenu.x + fixOffsetForMenu.x;
    float fixedY = *y * fixScaleForMenu.y + fixOffsetForMenu.y;

    [self drawStretchPic:fixedX y:fixedY w:sizeW h:sizeH s0:0 t0:0 s1:1 t1:1 mat:cursorImages[cursor] adjustCoords:NO];
}
/*
 =======================================================================================================================
 =======================================================================================================================
 */

- (void)paintChar:(float)x y:(float)y width:(float)width height:(float)height scale:(float)scale s:(float)s t:(float)t s2:(float)s2 t2:(float)t2 shader:(idMaterial *)hShader {
    float   w, h;
    w = width * scale;
    h = height * scale;

    if ([self clippedCoords:&x y:&y w:&w h:&h s1:&s t1:&t s2:&s2 t2:&t2]) {
        return;
    }

    //#modified-fva; BEGIN
    [self drawStretchPic:x y:y w:w h:h s0:s t0:t s1:s2 t1:t2 mat:hShader adjustCoords:YES];
    //#modified-fva; END
}


- (void)setFontByScale:(float)scale {
    float gui_smallFontLimit = [manager.cvars getFloat:@"gui_smallFontLimit"];
    float gui_mediumFontLimit = [manager.cvars getFloat:@"gui_mediumFontLimit"];
    if (scale <= gui_smallFontLimit) {
        useFont = &activeFont->fontInfoSmall;
        activeFont->maxHeight = activeFont->maxHeightSmall;
        activeFont->maxWidth = activeFont->maxWidthSmall;
    } else if (scale <= gui_mediumFontLimit) {
        useFont = &activeFont->fontInfoMedium;
        activeFont->maxHeight = activeFont->maxHeightMedium;
        activeFont->maxWidth = activeFont->maxWidthMedium;
    } else {
        useFont = &activeFont->fontInfoLarge;
        activeFont->maxHeight = activeFont->maxHeightLarge;
        activeFont->maxWidth = activeFont->maxWidthLarge;
    }
}

- (int)drawText:(float)x y:(float)y scale:(float)scale color:(idVec4)color text:(const char *)text adjust:(float)adjust limit:(int)limit style:(int)style cursor:(int)cursorPos {
    int         len, count;
    idVec4      newColor;
    const glyphInfo_t *glyph;
    float       useScale;
    [self setFontByScale:scale];
    useScale = scale * useFont->glyphScale;
    count = 0;
    if ( text && color.w != 0.0f ) {
        const unsigned char *s = (const unsigned char*)text;
        [self setColor:color];
        newColor = color;
        len = (int)strlen(text);
        if (limit > 0 && len > limit) {
            len = limit;
        }

        while (s && *s && count < len) {
            if ( *s < GLYPH_START || *s > GLYPH_END ) {
                s++;
                continue;
            }
            glyph = &useFont->glyphs[*s];

            //
            // int yadj = Assets.textFont.glyphs[text[i]].bottom +
            // Assets.textFont.glyphs[text[i]].top; float yadj = scale *
            // (Assets.textFont.glyphs[text[i]].imageHeight -
            // Assets.textFont.glyphs[text[i]].height);
            //
            if ( IsColor((const char*)s) ) {
                if ( *(s+1) == C_COLOR_DEFAULT ) {
                    newColor = color;
                } else {
                    newColor = ColorForIndex( *(s+1) );
                    newColor.w = color.w;
                }
                if (cursorPos == count || cursorPos == count+1) {
                    float partialSkip = ((glyph->xSkip * useScale) + adjust) / 5.0f;
                    if ( cursorPos == count ) {
                        partialSkip *= 2.0f;
                    } else {
                        [self setColor:newColor];
                    }
                    [self drawEditCursor:x - partialSkip y:y scale:scale];
                }
                [self setColor:newColor];
                s += 2;
                count += 2;
                continue;
            } else {
                float yadj = useScale * glyph->top;
                [self paintChar:x y:y - yadj width:glyph->imageWidth height:glyph->imageHeight scale:useScale s:glyph->s t:glyph->t s2:glyph->s2 t2:glyph->t2 shader:glyph->glyph];

                if (cursorPos == count) {
                    [self drawEditCursor:x y:y scale:scale];
                }
                x += (glyph->xSkip * useScale) + adjust;
                s++;
                count++;
            }
        }
        if (cursorPos == len) {
            [self drawEditCursor:x y:y scale:scale];
        }
    }
    return count;
}

- (void)setSize:(float)width height:(float)height {
    vidWidth = VIRTUAL_WIDTH;
    vidHeight = VIRTUAL_HEIGHT;
    xScale = yScale = 1.0f; // DG: I think this was also changed by fva
    //#modified-fva; BEGIN
    cst_xOffset = cst_yOffset = 0.0f;
    cstAdjustCoords = NO;
    if ((width != vidWidth || height != vidHeight) && width > 0.0f && height > 0.0f) {
        cstAdjustCoords = YES;
    //#modified-fva; END
        xScale = vidWidth * ( 1.0f / width );
        yScale = vidHeight * ( 1.0f / height );
    }
}

//#modified-fva; BEGIN
// ===============
static BOOL CstGetVidScale( idUserInterfaceManager *manager, float *_xScale, float *_yScale ) {
    int glWidth = manager.screenWidth, glHeight = manager.screenHeight;
    if (glWidth <= 0 || glHeight <= 0) {
        return NO;
    }

    float glAspectRatio = (float)glWidth / (float)glHeight;

    const float vidWidth = VIRTUAL_WIDTH;
    const float vidHeight = VIRTUAL_HEIGHT;
    const float vidAspectRatio = (float)VIRTUAL_WIDTH / (float)VIRTUAL_HEIGHT;

    float modWidth = vidWidth;
    float modHeight = vidHeight;
    if (glAspectRatio >= vidAspectRatio) {
        modWidth = modHeight * glAspectRatio;
    } else {
        modHeight = modWidth / glAspectRatio;
    }

    *_xScale = vidWidth / modWidth;
    *_yScale = vidHeight / modHeight;
    return YES;
}


static void CstAdjustParmsForAnchor(int anchor, float *_xScale, float *_yScale, float *_xOffset, float *_yOffset) {
    const float vidWidth = VIRTUAL_WIDTH;
    const float vidHeight = VIRTUAL_HEIGHT;

    switch (anchor) {
    case CST_ANCHOR_TOP_LEFT: {
        *_xOffset = 0.0f;
        *_yOffset = 0.0f;
        break;
    }
    case CST_ANCHOR_TOP_CENTER: {
        *_xOffset = (vidWidth * 0.5f) * (1.0f - *_xScale);
        *_yOffset = 0.0f;
        break;
    }
    case CST_ANCHOR_TOP_RIGHT: {
        *_xOffset = vidWidth * (1.0f - *_xScale);
        *_yOffset = 0.0f;
        break;
    }
    case CST_ANCHOR_CENTER_LEFT: {
        *_xOffset = 0.0f;
        *_yOffset = (vidHeight * 0.5f) * (1.0f - *_yScale);
        break;
    }
    case CST_ANCHOR_CENTER_CENTER: {
        *_xOffset = (vidWidth * 0.5f) * (1.0f - *_xScale);
        *_yOffset = (vidHeight * 0.5f) * (1.0f - *_yScale);
        break;
    }
    case CST_ANCHOR_CENTER_RIGHT: {
        *_xOffset = vidWidth * (1.0f - *_xScale);
        *_yOffset = (vidHeight * 0.5f) * (1.0f - *_yScale);
        break;
    }
    case CST_ANCHOR_BOTTOM_LEFT: {
        *_xOffset = 0.0f;
        *_yOffset = vidHeight * (1.0f - *_yScale);
        break;
    }
    case CST_ANCHOR_BOTTOM_CENTER: {
        *_xOffset = (vidWidth * 0.5f) * (1.0f - *_xScale);
        *_yOffset = vidHeight * (1.0f - *_yScale);
        break;
    }
    case CST_ANCHOR_BOTTOM_RIGHT: {
        *_xOffset = vidWidth * (1.0f - *_xScale);
        *_yOffset = vidHeight * (1.0f - *_yScale);
        break;
    }
    case CST_ANCHOR_TOP: {
        *_xScale = 1.0f; // no horizontal scaling
        *_xOffset = 0.0f;
        *_yOffset = 0.0f;
        break;
    }
    case CST_ANCHOR_VCENTER: {
        *_xScale = 1.0f; // no horizontal scaling
        *_xOffset = 0.0f;
        *_yOffset = (vidHeight * 0.5f) * (1.0f - *_yScale);
        break;
    }
    case CST_ANCHOR_BOTTOM: {
        *_xScale = 1.0f; // no horizontal scaling
        *_xOffset = 0.0f;
        *_yOffset = vidHeight * (1.0f - *_yScale);
        break;
    }
    case CST_ANCHOR_LEFT: {
        *_yScale = 1.0f; // no vertical scaling
        *_xOffset = 0.0f;
        *_yOffset = 0.0f;
        break;
    }
    case CST_ANCHOR_HCENTER: {
        *_yScale = 1.0f; // no vertical scaling
        *_xOffset = (vidWidth * 0.5f) * (1.0f - *_xScale);
        *_yOffset = 0.0f;
        break;
    }
    case CST_ANCHOR_RIGHT: {
        *_yScale = 1.0f; // no vertical scaling
        *_xOffset = vidWidth * (1.0f - *_xScale);
        *_yOffset = 0.0f;
        break;
    }
    default: {
        *_xOffset = 0.0f;
        *_yOffset = 0.0f;
        break;
    }
    }
}


- (void)cstSetSize:(int)anchor anchorTo:(int)anchorTo factor:(float)factor {
    vidWidth = VIRTUAL_WIDTH;
    vidHeight = VIRTUAL_HEIGHT;
    xScale = 1.0f;
    yScale = 1.0f;
    cst_xOffset = 0.0f;
    cst_yOffset = 0.0f;
    cstAdjustCoords = NO;

    if (!CstGetVidScale(manager, &xScale, &yScale)) {
        return;
    }

    if (anchorTo == CST_ANCHOR_NONE) {
        CstAdjustParmsForAnchor(anchor, &xScale, &yScale, &cst_xOffset, &cst_yOffset);
    } else {
        float from_xScale = xScale;
        float from_yScale = yScale;
        float from_xOffset = 0.0f;
        float from_yOffset = 0.0f;
        CstAdjustParmsForAnchor(anchor, &from_xScale, &from_yScale, &from_xOffset, &from_yOffset);

        float to_xScale = xScale;
        float to_yScale = yScale;
        float to_xOffset = 0.0f;
        float to_yOffset = 0.0f;
        CstAdjustParmsForAnchor(anchorTo, &to_xScale, &to_yScale, &to_xOffset, &to_yOffset);

        factor = factor < 0.0f ? 0.0f : factor > 1.0f ? 1.0f : factor;

        xScale = from_xScale * (1.0f - factor) + to_xScale * factor;
        yScale = from_yScale * (1.0f - factor) + to_yScale * factor;

        cst_xOffset = from_xOffset * (1.0f - factor) + to_xOffset * factor;
        cst_yOffset = from_yOffset * (1.0f - factor) + to_yOffset * factor;
    }
    cstAdjustCoords = YES;
}
//#modified-fva; END

#define FtoiFast idMath_FtoiFast

- (int)charWidth:(unichar)c scale:(float)scale {
    glyphInfo_t *glyph;
    float       useScale;
    [self setFontByScale:scale];
    fontInfo_t  *font = useFont;
    useScale = scale * font->glyphScale;
    glyph = &font->glyphs[(const unsigned char)c];
    return FtoiFast( glyph->xSkip * useScale );
}

- (int)textWidth:(NSString *)string scale:(float)scale limit:(int)limit {
    int i, width;
    NSData *bytes __attribute__((objc_precise_lifetime)) = string ? [string ud_latin1Buffer] : nil;
    const char *text = bytes.bytes;

    [self setFontByScale:scale];
    const glyphInfo_t *glyphs = useFont->glyphs;

    if ( text == NULL ) {
        return 0;
    }

    width = 0;
    if ( limit > 0 ) {
        for ( i = 0; text[i] != '\0' && i < limit; i++ ) {
            if ( IsColor( text + i ) ) {
                i++;
            } else {
                width += glyphs[((const unsigned char *)text)[i]].xSkip;
            }
        }
    } else {
        for ( i = 0; text[i] != '\0'; i++ ) {
            if ( IsColor( text + i ) ) {
                i++;
            } else {
                width += glyphs[((const unsigned char *)text)[i]].xSkip;
            }
        }
    }
    return FtoiFast( scale * useFont->glyphScale * width );
}

- (int)textHeight:(NSString *)string scale:(float)scale limit:(int)limit {
    NSData *bytes __attribute__((objc_precise_lifetime)) = string ? [string ud_latin1Buffer] : nil;
    const char *text = bytes.bytes;
    int         len, count;
    float       max;
    glyphInfo_t *glyph;
    float       useScale;
    const char  *s = text;
    [self setFontByScale:scale];
    fontInfo_t  *font = useFont;

    useScale = scale * font->glyphScale;
    max = 0;
    if (text) {
        len = (int)strlen(text);
        if (limit > 0 && len > limit) {
            len = limit;
        }

        count = 0;
        while (s && *s && count < len) {
            if ( IsColor(s) ) {
                s += 2;
                continue;
            }
            else {
                glyph = &font->glyphs[*(const unsigned char*)s];
                if (max < glyph->height) {
                    max = glyph->height;
                }

                s++;
                count++;
            }
        }
    }

    return FtoiFast( max * useScale );
}

- (int)maxCharWidth:(float)scale {
    [self setFontByScale:scale];
    float useScale = scale * useFont->glyphScale;
    return FtoiFast( activeFont->maxWidth * useScale );
}

- (int)maxCharHeight:(float)scale {
    [self setFontByScale:scale];
    float useScale = scale * useFont->glyphScale;
    return FtoiFast( activeFont->maxHeight * useScale );
}

- (idMaterial *)getScrollBarImage:(int)index {
    if (index >= SCROLLBAR_HBACK && index < SCROLLBAR_COUNT) {
        return scrollBarImages[index];
    }
    return scrollBarImages[SCROLLBAR_HBACK];
}

- (void)drawEditCursor:(float)x y:(float)y scale:(float)scale {
    if ( (int)( manager.ticNumber >> 4 ) & 1 ) {
        return;
    }
    [self setFontByScale:scale];
    float useScale = scale * useFont->glyphScale;
    const glyphInfo_t *glyph2 = &useFont->glyphs[overStrikeMode ? (int)'_' : (int)'|'];
    float   yadj = useScale * glyph2->top;
    [self paintChar:x y:y - yadj width:glyph2->imageWidth height:glyph2->imageHeight scale:useScale s:glyph2->s t:glyph2->t s2:glyph2->s2 t2:glyph2->t2 shader:glyph2->glyph];
}

- (int)drawText:(NSString *)text textScale:(float)textScale textAlign:(int)textAlign color:(idVec4)color rectDraw:(idRectangle)rectDraw wrap:(BOOL)wrap {
    return [self drawText:text textScale:textScale textAlign:textAlign color:color rectDraw:rectDraw wrap:wrap cursor:-1 calcOnly:NO breaks:nil limit:0];
}

- (int)drawText:(NSString *)text textScale:(float)textScale textAlign:(int)textAlign color:(idVec4)color rectDraw:(idRectangle)rectDraw wrap:(BOOL)wrap cursor:(int)cursorPos {
    return [self drawText:text textScale:textScale textAlign:textAlign color:color rectDraw:rectDraw wrap:wrap cursor:cursorPos calcOnly:NO breaks:nil limit:0];
}

- (int)drawText:(NSString *)string textScale:(float)textScale textAlign:(int)textAlign color:(idVec4)color rectDraw:(idRectangle)rectDraw wrap:(BOOL)wrap cursor:(int)cursorPos calcOnly:(BOOL)calcOnly breaks:(NSMutableArray<NSNumber *> *)breaks limit:(int)limit {
    // the text's bytes: the glyphs are by byte
    NSData *bytes __attribute__((objc_precise_lifetime)) = string ? [string ud_latin1Buffer] : nil;
    const char *text = bytes.bytes;
    const char  *p, *textPtr, *newLinePtr;
    char        buff[1024];
    int         len, newLine, newLineWidth, count;
    float       y;
    float       textWidth;

    float       charSkip = [self maxCharWidth:textScale] + 1;
    float       lineSkip = [self maxCharHeight:textScale];

    float       cursorSkip = ( cursorPos >= 0 ? charSkip : 0 );

    BOOL        lineBreak, wordBreak;

    [self setFontByScale:textScale];

    textWidth = 0;
    newLinePtr = NULL;

    if (!calcOnly && !(text && *text)) {
        if (cursorPos == 0) {
            [self setColor:color];
            [self drawEditCursor:rectDraw.x y:lineSkip + rectDraw.y scale:textScale];
        }
        return FtoiFast( rectDraw.w / charSkip );
    }

    textPtr = text;

    y = lineSkip + rectDraw.y;
    len = 0;
    buff[0] = '\0';
    newLine = 0;
    newLineWidth = 0;
    p = textPtr;

    if ( breaks ) {
        [breaks addObject:@0];
    }
    count = 0;
    textWidth = 0;
    lineBreak = NO;
    wordBreak = NO;
    while (p) {

        if ( *p == '\n' || *p == '\r' || *p == '\0' ) {
            lineBreak = YES;
            if ((*p == '\n' && *(p + 1) == '\r') || (*p == '\r' && *(p + 1) == '\n')) {
                p++;
            }
        }

        int nextCharWidth = ( idStr_CharIsPrintable((unsigned char)*p) ? [self charWidth:(unsigned char)*p scale:textScale] : cursorSkip );
        // FIXME: this is a temp hack until the guis can be fixed not not overflow the bounding rectangles
        //        the side-effect is that list boxes and edit boxes will draw over their scroll bars
        //  The following line and the !linebreak in the if statement below should be removed
        nextCharWidth = 0;

        if ( !lineBreak && ( textWidth + nextCharWidth ) > rectDraw.w ) {
            // The next character will cause us to overflow, if we haven't yet found a suitable
            // break spot, set it to be this character
            if ( len > 0 && newLine == 0 ) {
                newLine = len;
                newLinePtr = p;
                newLineWidth = textWidth;
            }
            wordBreak = YES;
        } else if ( lineBreak || ( wrap && (*p == ' ' || *p == '\t') ) ) {
            // The next character is in view, so if we are a break character, store our position
            newLine = len;
            newLinePtr = p + 1;
            newLineWidth = textWidth;
        }

        if ( lineBreak || wordBreak ) {
            float x = rectDraw.x;

            if (textAlign == ALIGN_RIGHT) {
                x = rectDraw.x + rectDraw.w - newLineWidth;
            } else if (textAlign == ALIGN_CENTER) {
                x = rectDraw.x + (rectDraw.w - newLineWidth) / 2;
            }

            if ( wrap || newLine > 0 ) {
                buff[newLine] = '\0';

                // This is a special case to handle breaking in the middle of a word.
                // if we didn't do this, the cursor would appear on the end of this line
                // and the beginning of the next.
                if ( wordBreak && cursorPos >= newLine && newLine == len ) {
                    cursorPos++;
                }
            }

            if (!calcOnly) {
                count += [self drawText:x y:y scale:textScale color:color text:buff adjust:0 limit:0 style:0 cursor:cursorPos];
            }

            if ( cursorPos < newLine ) {
                cursorPos = -1;
            } else if ( cursorPos >= 0 ) {
                cursorPos -= ( newLine + 1 );
            }

            if ( !wrap ) {
                return newLine;
            }

            if ( ( limit && count > limit ) || *p == '\0' ) {
                break;
            }

            y += lineSkip + 5;

            if ( !calcOnly && y > idRectangle_Bottom( &rectDraw ) ) {
                break;
            }

            p = newLinePtr;

            if (breaks) {
                [breaks addObject:@( p - text )];
            }

            len = 0;
            newLine = 0;
            newLineWidth = 0;
            textWidth = 0;
            lineBreak = NO;
            wordBreak = NO;
            continue;
        }

        if ( len >= (int)sizeof( buff ) - 1 ) {
            // the engine's buff overflows here; a line this long is cut
            p++;
            continue;
        }
        buff[len++] = *p++;
        buff[len] = '\0';
        // update the width
        if ( *( buff + len - 1 ) != C_COLOR_ESCAPE && (len <= 1 || *( buff + len - 2 ) != C_COLOR_ESCAPE)) {
            textWidth += textScale * useFont->glyphScale * useFont->glyphs[ (const unsigned char)*( buff + len - 1 ) ].xSkip;
        }
    }

    return FtoiFast( rectDraw.w / charSkip );
}

- (void)enableClipping:(BOOL)b { enableClipping = b; }
- (void)setOverStrike:(BOOL)b { overStrikeMode = b; }
- (BOOL)getOverStrike { return overStrikeMode; }

@end
