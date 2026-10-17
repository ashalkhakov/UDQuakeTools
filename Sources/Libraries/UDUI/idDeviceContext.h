/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idDeviceContext.h — what a GUI draws with (ui/DeviceContext.h,
 * DeviceContext.cpp), ported, and the parts of the render system it calls:
 * fonts (renderer/tr_font.cpp's RegisterFont, the .dat files) and the GUI
 * model it draws into (idGuiModel, renderer/GuiModel.cpp). The model's
 * surfaces are drawn by UDSoftwareRenderer as the engine's backend draws a
 * 2D view.
 */

#import <Foundation/Foundation.h>
#import "idGuiModel.h"
#import "idMath.h"

@class idUserInterfaceManager, idGuiModel, UDMaterialParser;

NS_ASSUME_NONNULL_BEGIN

#define VIRTUAL_WIDTH       640
#define VIRTUAL_HEIGHT      480
#define BLINK_DIVISOR       200

/// idMaterial, as a GUI has one: declManager->FindMaterial's, by name; the
/// same object for the same name.
@interface idMaterial : NSObject <idGuiMaterial>
@property (nonatomic, copy, readonly) NSString *name;
/// The material's parse (the renderer's).
- (UDMaterialParser *)parser;
/// GetImageWidth, GetImageHeight: its first stage's image's.
- (int)getImageWidth;
- (int)getImageHeight;
/// MF_DEFAULTED
- (BOOL)defaulted;
/// CinematicLength: 0, cinematics are not played.
- (int)cinematicLength;
- (void)updateCinematic:(int)time;
- (void)resetCinematicTime:(int)time;
/// SetSort: SS_GUI's the GUIs set.
- (void)setSort:(float)sort;
- (float)getSort;
- (void)setImageClassifications:(int)tag;
@end

#define SS_GUI      -2.0f

// font support
#define GLYPH_START         0
#define GLYPH_END           255
#define GLYPH_CHARSTART     32
#define GLYPH_CHAREND       127
#define GLYPHS_PER_FONT     ( GLYPH_END - GLYPH_START + 1 )

typedef struct {
    int                 height;         // number of scan lines
    int                 top;            // top of glyph in buffer
    int                 bottom;         // bottom of glyph in buffer
    int                 pitch;          // width for copying
    int                 xSkip;          // x adjustment
    int                 imageWidth;     // width of actual image
    int                 imageHeight;    // height of actual image
    float               s;              // x offset in image where glyph starts
    float               t;              // y offset in image where glyph starts
    float               s2;
    float               t2;
    __unsafe_unretained idMaterial *glyph;  // shader with the glyph
    char                shaderName[32];
} glyphInfo_t;

typedef struct {
    glyphInfo_t         glyphs [GLYPHS_PER_FONT];
    float               glyphScale;
} fontInfo_t;

typedef struct {
    fontInfo_t          fontInfoSmall;
    fontInfo_t          fontInfoMedium;
    fontInfo_t          fontInfoLarge;
    int                 maxHeight;
    int                 maxWidth;
    int                 maxHeightSmall;
    int                 maxWidthSmall;
    int                 maxHeightMedium;
    int                 maxWidthMedium;
    int                 maxHeightLarge;
    int                 maxWidthLarge;
} fontInfoEx_t;

enum {
    CURSOR_ARROW,
    CURSOR_HAND,
    CURSOR_COUNT
};

enum {
    ALIGN_LEFT,
    ALIGN_CENTER,
    ALIGN_RIGHT
};

enum {
    SCROLLBAR_HBACK,
    SCROLLBAR_VBACK,
    SCROLLBAR_THUMB,
    SCROLLBAR_RIGHT,
    SCROLLBAR_LEFT,
    SCROLLBAR_UP,
    SCROLLBAR_DOWN,
    SCROLLBAR_COUNT
};

//#modified-fva; BEGIN
enum {
    CST_ANCHOR_NONE = -1,
    CST_ANCHOR_TOP_LEFT,
    CST_ANCHOR_TOP_CENTER,
    CST_ANCHOR_TOP_RIGHT,
    CST_ANCHOR_CENTER_LEFT,
    CST_ANCHOR_CENTER_CENTER,
    CST_ANCHOR_CENTER_RIGHT,
    CST_ANCHOR_BOTTOM_LEFT,
    CST_ANCHOR_BOTTOM_CENTER,
    CST_ANCHOR_BOTTOM_RIGHT,
    CST_ANCHOR_TOP,
    CST_ANCHOR_VCENTER,
    CST_ANCHOR_BOTTOM,
    CST_ANCHOR_LEFT,
    CST_ANCHOR_HCENTER,
    CST_ANCHOR_RIGHT
};
//#modified-fva; END

extern idVec4 idDeviceContext_colorPurple;
extern idVec4 idDeviceContext_colorOrange;
extern idVec4 idDeviceContext_colorYellow;
extern idVec4 idDeviceContext_colorGreen;
extern idVec4 idDeviceContext_colorBlue;
extern idVec4 idDeviceContext_colorRed;
extern idVec4 idDeviceContext_colorWhite;
extern idVec4 idDeviceContext_colorBlack;
extern idVec4 idDeviceContext_colorNone;

@interface idDeviceContext : NSObject

/// The device context of @a manager (its render system, its fonts' files).
- (instancetype)initWithManager:(idUserInterfaceManager *)manager;

- (void)deviceInit;
- (void)shutdown;
- (BOOL)initialized;
- (void)enableLocalization;

- (void)getTransformInfo:(idVec3 *)origin mat:(idMat3 *)mat;
- (void)setTransformInfo:(idVec3)origin mat:(idMat3)mat;
- (void)drawMaterial:(float)x y:(float)y w:(float)w h:(float)h mat:(nullable idMaterial *)mat color:(idVec4)color scalex:(float)scalex scaley:(float)scaley;
- (void)drawMaterial:(float)x y:(float)y w:(float)w h:(float)h mat:(nullable idMaterial *)mat color:(idVec4)color;
- (void)drawRect:(float)x y:(float)y width:(float)width height:(float)height size:(float)size color:(idVec4)color;
- (void)drawFilledRect:(float)x y:(float)y width:(float)width height:(float)height color:(idVec4)color;
- (int)drawText:(NSString *)text textScale:(float)textScale textAlign:(int)textAlign color:(idVec4)color rectDraw:(idRectangle)rectDraw wrap:(BOOL)wrap cursor:(int)cursor calcOnly:(BOOL)calcOnly breaks:(nullable NSMutableArray<NSNumber *> *)breaks limit:(int)limit;
- (int)drawText:(NSString *)text textScale:(float)textScale textAlign:(int)textAlign color:(idVec4)color rectDraw:(idRectangle)rectDraw wrap:(BOOL)wrap cursor:(int)cursor;
- (int)drawText:(NSString *)text textScale:(float)textScale textAlign:(int)textAlign color:(idVec4)color rectDraw:(idRectangle)rectDraw wrap:(BOOL)wrap;
- (void)drawMaterialRect:(float)x y:(float)y w:(float)w h:(float)h size:(float)size mat:(nullable idMaterial *)mat color:(idVec4)color;
- (void)drawStretchPic:(float)x y:(float)y w:(float)w h:(float)h s0:(float)s0 t0:(float)t0 s1:(float)s1 t1:(float)t1 mat:(nullable idMaterial *)mat adjustCoords:(BOOL)adjustCoords;
- (void)drawMaterialRotated:(float)x y:(float)y w:(float)w h:(float)h mat:(nullable idMaterial *)mat color:(idVec4)color scalex:(float)scalex scaley:(float)scaley angle:(float)angle;
- (void)drawStretchPicRotated:(float)x y:(float)y w:(float)w h:(float)h s0:(float)s0 t0:(float)t0 s1:(float)s1 t1:(float)t1 mat:(nullable idMaterial *)mat angle:(float)angle adjustCoords:(BOOL)adjustCoords;

- (int)charWidth:(unichar)c scale:(float)scale;
- (int)textWidth:(NSString *)text scale:(float)scale limit:(int)limit;
- (int)textHeight:(NSString *)text scale:(float)scale limit:(int)limit;
- (int)maxCharHeight:(float)scale;
- (int)maxCharWidth:(float)scale;

- (int)findFont:(NSString *)name;
- (void)setupFonts;

- (void)setSize:(float)width height:(float)height;
//#modified-fva; BEGIN
- (void)cstSetSize:(int)anchor anchorTo:(int)anchorTo factor:(float)factor;
//#modified-fva; END

- (nullable idMaterial *)getScrollBarImage:(int)index;

- (void)drawCursor:(float *)x y:(float *)y size:(float)size;
- (void)setCursor:(int)n;
- (void)adjustCoords:(float *_Nullable)x y:(float *_Nullable)y w:(float *_Nullable)w h:(float *_Nullable)h;
- (BOOL)clippedCoords:(float *)x y:(float *)y w:(float *)w h:(float *)h;
- (BOOL)clippedCoords:(float *)x y:(float *)y w:(float *)w h:(float *)h s1:(float *_Nullable)s1 t1:(float *_Nullable)t1 s2:(float *_Nullable)s2 t2:(float *_Nullable)t2;

- (void)pushClipRect:(float)x y:(float)y w:(float)w h:(float)h;
- (void)pushClipRect:(idRectangle)r;
- (void)popClipRect;

- (void)enableClipping:(BOOL)b;
- (void)setFont:(int)num;

- (void)setOverStrike:(BOOL)b;
- (BOOL)getOverStrike;

- (void)drawEditCursor:(float)x y:(float)y scale:(float)scale;

// DG: this is used for the "make sure menus are rendered as 4:3" hack
- (void)setMenuScaleFix:(BOOL)enable;
- (BOOL)isMenuScaleFixActive;

@end

NS_ASSUME_NONNULL_END
