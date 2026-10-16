/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDMaterialParser.m — Material.cpp, ported literally: CommonInit,
 * CheckSurfaceParm, the expression parser, ParseBlend, ParseVertexParm,
 * ParseFragmentMap, ParseStage, ParseDeform, AddImplicitStages,
 * SortInteractionStages, ParseMaterial, Parse, EvaluateRegisters and
 * CheckForConstantRegisters; DeclTable.cpp's TableLookup for its tables.
 *
 * What the renderer does with a name is not done: an image is the name
 * ImageFromFile would be asked for (the image is UDImageProgram's), a
 * program, cinematic, sound map, GUI or mega texture its name. The cvars
 * read keep their defaults (image_ignoreHighQuality 0); glConfig is a
 * renderer's that has fragment programs.
 *
 * As the parse goes, the keywords it reads from the text are noted where
 * they are (UDMaterialTextNode): the editor's model is the text the engine
 * read, cut where the engine cut it.
 */

#import "UDMaterialParser.h"
#import "UDDeclCodec.h"
#import "UDDeclTable.h"
#import "UDDeclTextChecker.h"
#import "UDImageProgram.h"
#import "idDeclManager.h"
#import "idLexer.h"
#import "idToken.h"
#import <objc/runtime.h>

#ifndef BIT
#define BIT( num )                  ( 1 << ( num ) )
#endif

#define MAX_SHADER_STAGES           256
#define MAX_TEXGEN_REGISTERS        4
#define MAX_ENTITY_SHADER_PARMS     12
#define MAX_EXPRESSION_REGISTERS    4096
#define MAX_EXPRESSION_OPS          4096
#define MAX_FRAGMENT_IMAGES         8
#define MAX_VERTEX_PARMS            4
#define MAX_IMAGE_NAME              256

// image_ignoreHighQuality's default
static const int image_ignoreHighQuality = 0;

#pragma mark - Material.h

typedef enum {
    TF_LINEAR,
    TF_NEAREST,
    TF_DEFAULT                // use the user-specified r_textureFilter
} textureFilter_t;

typedef enum {
    TR_REPEAT,
    TR_CLAMP,
    TR_CLAMP_TO_BORDER,
    TR_CLAMP_TO_ZERO,
    TR_CLAMP_TO_ZERO_ALPHA
} textureRepeat_t;

typedef enum {
    TD_SPECULAR,            // may be compressed, and always zeros the alpha channel
    TD_DIFFUSE,                // may be compressed
    TD_DEFAULT,                // will use compressed formats when possible
    TD_BUMP,                // may be compressed with 8 bit lookup
    TD_HIGH_QUALITY            // either 32 bit or a component format, no loss at all
} textureDepth_t;

typedef enum {
    CF_2D,            // not a cube map
    CF_NATIVE,        // _px, _nx, _py, etc, directly sent to GL
    CF_CAMERA        // _forward, _back, etc, rotated and flipped as needed before sending to GL
} cubeFiles_t;

typedef struct {
    int        stayTime;        // msec for no change
    int        fadeTime;        // msec to fade vertex colors over
    float    start[4];        // vertex color at spawn (possibly out of 0.0 - 1.0 range, will clamp after calc)
    float    end[4];            // vertex color at fade-out (possibly out of 0.0 - 1.0 range, will clamp after calc)
} decalInfo_t;

typedef enum {
    DFRM_NONE,
    DFRM_SPRITE,
    DFRM_TUBE,
    DFRM_FLARE,
    DFRM_EXPAND,
    DFRM_MOVE,
    DFRM_EYEBALL,
    DFRM_PARTICLE,
    DFRM_PARTICLE2,
    DFRM_TURB
} deform_t;

typedef enum {
    DI_STATIC,
    DI_SCRATCH,        // video, screen wipe, etc
    DI_CUBE_RENDER,
    DI_MIRROR_RENDER,
    DI_XRAY_RENDER,
    DI_REMOTE_RENDER
} dynamicidImage_t;

typedef enum {
    OP_TYPE_ADD,
    OP_TYPE_SUBTRACT,
    OP_TYPE_MULTIPLY,
    OP_TYPE_DIVIDE,
    OP_TYPE_MOD,
    OP_TYPE_TABLE,
    OP_TYPE_GT,
    OP_TYPE_GE,
    OP_TYPE_LT,
    OP_TYPE_LE,
    OP_TYPE_EQ,
    OP_TYPE_NE,
    OP_TYPE_AND,
    OP_TYPE_OR,
    OP_TYPE_SOUND
} expOpType_t;

typedef enum {
    EXP_REG_TIME,

    EXP_REG_PARM0,
    EXP_REG_PARM1,
    EXP_REG_PARM2,
    EXP_REG_PARM3,
    EXP_REG_PARM4,
    EXP_REG_PARM5,
    EXP_REG_PARM6,
    EXP_REG_PARM7,
    EXP_REG_PARM8,
    EXP_REG_PARM9,
    EXP_REG_PARM10,
    EXP_REG_PARM11,

    EXP_REG_GLOBAL0,
    EXP_REG_GLOBAL1,
    EXP_REG_GLOBAL2,
    EXP_REG_GLOBAL3,
    EXP_REG_GLOBAL4,
    EXP_REG_GLOBAL5,
    EXP_REG_GLOBAL6,
    EXP_REG_GLOBAL7,

    EXP_REG_NUM_PREDEFINED
} expRegister_t;

typedef struct {
    expOpType_t        opType;
    int                a, b, c;
} expOp_t;

typedef struct {
    int                registers[4];
} colorStage_t;

typedef enum {
    TG_EXPLICIT,
    TG_DIFFUSE_CUBE,
    TG_REFLECT_CUBE,
    TG_SKYBOX_CUBE,
    TG_WOBBLESKY_CUBE,
    TG_SCREEN,            // screen aligned, for mirrorRenders and screen space temporaries
    TG_SCREEN2,
    TG_GLASSWARP
} texgen_t;

// An image: the name and options ImageFromFile is called with.
typedef struct {
    char                name[MAX_IMAGE_NAME];
    textureFilter_t     filter;
    BOOL                allowPicmip;
    textureRepeat_t     repeat;
    textureDepth_t      depth;
    cubeFiles_t         cubeMap;
} imageRef_t;

typedef struct {
    BOOL                cinematic;        // idCinematic::Alloc's, its file's name
    char                cinematicName[MAX_IMAGE_NAME];
    BOOL                hasImage;
    imageRef_t          image;
    texgen_t            texgen;
    BOOL                hasMatrix;
    int                 matrix[2][3];    // we only allow a subset of the full projection matrix

    // dynamic image variables
    dynamicidImage_t    dynamic;
    int                 width, height;
    int                 dynamicFrameCount;
} textureStage_t;

// the order BUMP / DIFFUSE / SPECULAR is necessary for interactions to draw correctly on low end cards
typedef enum {
    SL_AMBIENT,                        // execute after lighting
    SL_BUMP,
    SL_DIFFUSE,
    SL_SPECULAR
} stageLighting_t;

// cross-blended terrain textures need to modulate the color by
// the vertex color to smoothly blend between two textures
typedef enum {
    SVC_IGNORE,
    SVC_MODULATE,
    SVC_INVERSE_MODULATE
} stageVertexColor_t;

typedef struct {
    char                vertexProgram[MAX_IMAGE_NAME];     // R_FindARBProgram's name
    int                 numVertexParms;
    int                 vertexParms[MAX_VERTEX_PARMS][4];    // evaluated register indexes

    char                fragmentProgram[MAX_IMAGE_NAME];
    int                 numFragmentProgramImages;
    imageRef_t          fragmentProgramImages[MAX_FRAGMENT_IMAGES];

    char                megaTexture[MAX_IMAGE_NAME];        // handles all the binding and parameter setting
} newShaderStage_t;

typedef struct {
    int                    conditionRegister;    // if registers[conditionRegister] == 0, skip stage
    stageLighting_t        lighting;            // determines which passes interact with lights
    int                    drawStateBits;
    colorStage_t        color;
    BOOL                hasAlphaTest;
    int                    alphaTestRegister;
    textureStage_t        texture;
    stageVertexColor_t    vertexColor;
    BOOL                ignoreAlphaTest;    // this stage should act as translucent, even
                                            // if the surface is alpha tested
    float                privatePolygonOffset;    // a per-stage polygon offset

    BOOL                hasNewStage;
    newShaderStage_t    newStage;            // vertex / fragment program based stage

    int                 textIndex;          // (its place in the text, for the editor)
} shaderStage_t;

typedef enum {
    MC_BAD,
    MC_OPAQUE,            // completely fills the triangle, will have black drawn on fillDepthBuffer
    MC_PERFORATED,        // may have alpha tested holes
    MC_TRANSLUCENT        // blended with background
} materialCoverage_t;

typedef enum {
    SS_SUBVIEW = -3,    // mirrors, viewscreens, etc
    SS_GUI = -2,        // guis
    SS_BAD = -1,
    SS_OPAQUE,            // opaque

    SS_PORTAL_SKY,

    SS_DECAL,            // scorch marks, etc.

    SS_FAR,
    SS_MEDIUM,            // normal translucent
    SS_CLOSE,

    SS_ALMOST_NEAREST,    // gun smoke puffs

    SS_NEAREST,            // screen blood blobs

    SS_POST_PROCESS = 100    // after a screen copy to texture
} materialSort_t;

typedef enum {
    CT_FRONT_SIDED,
    CT_BACK_SIDED,
    CT_TWO_SIDED
} cullType_t;

// material flags
typedef enum {
    MF_DEFAULTED                = BIT(0),
    MF_POLYGONOFFSET            = BIT(1),
    MF_NOSHADOWS                = BIT(2),
    MF_FORCESHADOWS                = BIT(3),
    MF_NOSELFSHADOW                = BIT(4),
    MF_NOPORTALFOG                = BIT(5),    // this fog volume won't ever consider a portal fogged out
    MF_EDITOR_VISIBLE            = BIT(6)    // in use (visible) per editor
} materialFlags_t;

// contents flags, NOTE: make sure to keep the defines in doom_defs.script up to date with these!
typedef enum {
    CONTENTS_SOLID                = BIT(0),    // an eye is never valid in a solid
    CONTENTS_OPAQUE                = BIT(1),    // blocks visibility (for ai)
    CONTENTS_WATER                = BIT(2),    // used for water
    CONTENTS_PLAYERCLIP            = BIT(3),    // solid to players
    CONTENTS_MONSTERCLIP        = BIT(4),    // solid to monsters
    CONTENTS_MOVEABLECLIP        = BIT(5),    // solid to moveable entities
    CONTENTS_IKCLIP                = BIT(6),    // solid to IK
    CONTENTS_BLOOD                = BIT(7),    // used to detect blood decals
    CONTENTS_BODY                = BIT(8),    // used for actors
    CONTENTS_PROJECTILE            = BIT(9),    // used for projectiles
    CONTENTS_CORPSE                = BIT(10),    // used for dead bodies
    CONTENTS_RENDERMODEL        = BIT(11),    // used for render models for collision detection
    CONTENTS_TRIGGER            = BIT(12),    // used for triggers
    CONTENTS_AAS_SOLID            = BIT(13),    // solid for AAS
    CONTENTS_AAS_OBSTACLE        = BIT(14),    // used to compile an obstacle into AAS that can be enabled/disabled
    CONTENTS_FLASHLIGHT_TRIGGER    = BIT(15),    // used for triggers that are activated by the flashlight

    // contents used by utils
    CONTENTS_AREAPORTAL            = BIT(20),    // portal separating renderer areas
    CONTENTS_NOCSG                = BIT(21),    // don't cut this brush with CSG operations in the editor

    CONTENTS_REMOVE_UTIL        = ~(CONTENTS_AREAPORTAL|CONTENTS_NOCSG)
} contentsFlags_t;

// surface types
#define NUM_SURFACE_BITS        4
#define MAX_SURFACE_TYPES        ( 1 << NUM_SURFACE_BITS )

typedef enum {
    SURFTYPE_NONE,                    // default type
    SURFTYPE_METAL,
    SURFTYPE_STONE,
    SURFTYPE_FLESH,
    SURFTYPE_WOOD,
    SURFTYPE_CARDBOARD,
    SURFTYPE_LIQUID,
    SURFTYPE_GLASS,
    SURFTYPE_PLASTIC,
    SURFTYPE_RICOCHET,
    SURFTYPE_10,
    SURFTYPE_11,
    SURFTYPE_12,
    SURFTYPE_13,
    SURFTYPE_14,
    SURFTYPE_15
} surfTypes_t;

// surface flags
typedef enum {
    SURF_TYPE_BIT0                = BIT(0),    // encodes the material type (metal, flesh, concrete, etc.)
    SURF_TYPE_BIT1                = BIT(1),    // "
    SURF_TYPE_BIT2                = BIT(2),    // "
    SURF_TYPE_BIT3                = BIT(3),    // "
    SURF_TYPE_MASK                = ( 1 << NUM_SURFACE_BITS ) - 1,

    SURF_NODAMAGE                = BIT(4),    // never give falling damage
    SURF_SLICK                    = BIT(5),    // effects game physics
    SURF_COLLISION                = BIT(6),    // collision surface
    SURF_LADDER                    = BIT(7),    // player can climb up this surface
    SURF_NOIMPACT                = BIT(8),    // don't make missile explosions
    SURF_NOSTEPS                = BIT(9),    // no footstep sounds
    SURF_DISCRETE                = BIT(10),    // not clipped or merged by utilities
    SURF_NOFRAGMENT                = BIT(11),    // dmap won't cut surface at each bsp boundary
    SURF_NULLNORMAL                = BIT(12)    // renderbump will draw this surface as 0x80 0x80 0x80, which
                                            // won't collect light from any angle
} surfaceFlags_t;

#pragma mark - tr_local.h

const int GLS_SRCBLEND_ZERO                        = 0x00000001;
const int GLS_SRCBLEND_ONE                        = 0x0;
const int GLS_SRCBLEND_DST_COLOR                = 0x00000003;
const int GLS_SRCBLEND_ONE_MINUS_DST_COLOR        = 0x00000004;
const int GLS_SRCBLEND_SRC_ALPHA                = 0x00000005;
const int GLS_SRCBLEND_ONE_MINUS_SRC_ALPHA        = 0x00000006;
const int GLS_SRCBLEND_DST_ALPHA                = 0x00000007;
const int GLS_SRCBLEND_ONE_MINUS_DST_ALPHA        = 0x00000008;
const int GLS_SRCBLEND_ALPHA_SATURATE            = 0x00000009;
const int GLS_SRCBLEND_BITS                        = 0x0000000f;

const int GLS_DSTBLEND_ZERO                        = 0x0;
const int GLS_DSTBLEND_ONE                        = 0x00000020;
const int GLS_DSTBLEND_SRC_COLOR                = 0x00000030;
const int GLS_DSTBLEND_ONE_MINUS_SRC_COLOR        = 0x00000040;
const int GLS_DSTBLEND_SRC_ALPHA                = 0x00000050;
const int GLS_DSTBLEND_ONE_MINUS_SRC_ALPHA        = 0x00000060;
const int GLS_DSTBLEND_DST_ALPHA                = 0x00000070;
const int GLS_DSTBLEND_ONE_MINUS_DST_ALPHA        = 0x00000080;
const int GLS_DSTBLEND_BITS                        = 0x000000f0;

const int GLS_DEPTHMASK                            = 0x00000100;
const int GLS_REDMASK                            = 0x00000200;
const int GLS_GREENMASK                            = 0x00000400;
const int GLS_BLUEMASK                            = 0x00000800;
const int GLS_ALPHAMASK                            = 0x00001000;
const int GLS_COLORMASK                            = (GLS_REDMASK|GLS_GREENMASK|GLS_BLUEMASK);

const int GLS_DEPTHFUNC_ALWAYS                    = 0x00010000;
const int GLS_DEPTHFUNC_EQUAL                    = 0x00020000;
const int GLS_DEPTHFUNC_LESS                    = 0x0;

const int UDGLSSrcBlendBits = GLS_SRCBLEND_BITS, UDGLSDstBlendBits = GLS_DSTBLEND_BITS;
const int UDGLSSrcBlendZero = GLS_SRCBLEND_ZERO, UDGLSSrcBlendOne = GLS_SRCBLEND_ONE,
          UDGLSSrcBlendDstColor = GLS_SRCBLEND_DST_COLOR, UDGLSSrcBlendOneMinusDstColor = GLS_SRCBLEND_ONE_MINUS_DST_COLOR,
          UDGLSSrcBlendSrcAlpha = GLS_SRCBLEND_SRC_ALPHA, UDGLSSrcBlendOneMinusSrcAlpha = GLS_SRCBLEND_ONE_MINUS_SRC_ALPHA,
          UDGLSSrcBlendDstAlpha = GLS_SRCBLEND_DST_ALPHA, UDGLSSrcBlendOneMinusDstAlpha = GLS_SRCBLEND_ONE_MINUS_DST_ALPHA,
          UDGLSSrcBlendAlphaSaturate = GLS_SRCBLEND_ALPHA_SATURATE;
const int UDGLSDstBlendZero = GLS_DSTBLEND_ZERO, UDGLSDstBlendOne = GLS_DSTBLEND_ONE,
          UDGLSDstBlendSrcColor = GLS_DSTBLEND_SRC_COLOR, UDGLSDstBlendOneMinusSrcColor = GLS_DSTBLEND_ONE_MINUS_SRC_COLOR,
          UDGLSDstBlendSrcAlpha = GLS_DSTBLEND_SRC_ALPHA, UDGLSDstBlendOneMinusSrcAlpha = GLS_DSTBLEND_ONE_MINUS_SRC_ALPHA,
          UDGLSDstBlendDstAlpha = GLS_DSTBLEND_DST_ALPHA, UDGLSDstBlendOneMinusDstAlpha = GLS_DSTBLEND_ONE_MINUS_DST_ALPHA;

#pragma mark - Material.cpp

// keep all of these on the stack, when they are static it makes material parsing non-reentrant
typedef struct mtrParsingData_s {
    BOOL            registerIsTemporary[MAX_EXPRESSION_REGISTERS];
    float            shaderRegisters[MAX_EXPRESSION_REGISTERS];
    expOp_t            shaderOps[MAX_EXPRESSION_OPS];
    shaderStage_t    parseStages[MAX_SHADER_STAGES];

    BOOL            registersAreConstant;
    BOOL            forceOverlays;
} mtrParsingData_t;

// info parms
typedef struct {
    const char    *name;
    int        clearSolid, surfaceFlags, contents;
} infoParm_t;

static const infoParm_t    infoParms[] = {
    // game relevant attributes
    {"solid",        0,    0,    CONTENTS_SOLID },        // may need to override a clearSolid
    {"water",        1,    0,    CONTENTS_WATER },        // used for water
    {"playerclip",    0,    0,    CONTENTS_PLAYERCLIP },    // solid to players
    {"monsterclip",    0,    0,    CONTENTS_MONSTERCLIP },    // solid to monsters
    {"moveableclip",0,    0,    CONTENTS_MOVEABLECLIP },// solid to moveable entities
    {"ikclip",        0,    0,    CONTENTS_IKCLIP },        // solid to IK
    {"blood",        0,    0,    CONTENTS_BLOOD },        // used to detect blood decals
    {"trigger",        0,    0,    CONTENTS_TRIGGER },        // used for triggers
    {"aassolid",    0,    0,    CONTENTS_AAS_SOLID },    // solid for AAS
    {"aasobstacle",    0,    0,    CONTENTS_AAS_OBSTACLE },// used to compile an obstacle into AAS that can be enabled/disabled
    {"flashlight_trigger",    0,    0,    CONTENTS_FLASHLIGHT_TRIGGER }, // used for triggers that are activated by the flashlight
    {"nonsolid",    1,    0,    0 },                    // clears the solid flag
    {"nullNormal",    0,    SURF_NULLNORMAL,0 },        // renderbump will draw as 0x80 0x80 0x80

    // utility relevant attributes
    {"areaportal",    1,    0,    CONTENTS_AREAPORTAL },    // divides areas
    {"qer_nocarve",    1,    0,    CONTENTS_NOCSG},        // don't cut brushes in editor

    {"discrete",    1,    SURF_DISCRETE,    0 },        // surfaces should not be automatically merged together or
                                                    // clipped to the world,
                                                    // because they represent discrete objects like gui shaders
                                                    // mirrors, or autosprites
    {"noFragment",    0,    SURF_NOFRAGMENT,    0 },

    {"slick",        0,    SURF_SLICK,        0 },
    {"collision",    0,    SURF_COLLISION,    0 },
    {"noimpact",    0,    SURF_NOIMPACT,    0 },        // don't make impact explosions or marks
    {"nodamage",    0,    SURF_NODAMAGE,    0 },        // no falling damage when hitting
    {"ladder",        0,    SURF_LADDER,    0 },        // climbable
    {"nosteps",        0,    SURF_NOSTEPS,    0 },        // no footsteps

    // material types for particle, sound, footstep feedback
    {"metal",        0,  SURFTYPE_METAL,        0 },    // metal
    {"stone",        0,  SURFTYPE_STONE,        0 },    // stone
    {"flesh",        0,  SURFTYPE_FLESH,        0 },    // flesh
    {"wood",        0,  SURFTYPE_WOOD,        0 },    // wood
    {"cardboard",    0,    SURFTYPE_CARDBOARD,    0 },    // cardboard
    {"liquid",        0,    SURFTYPE_LIQUID,    0 },    // liquid
    {"glass",        0,    SURFTYPE_GLASS,        0 },    // glass
    {"plastic",        0,    SURFTYPE_PLASTIC,    0 },    // plastic
    {"ricochet",    0,    SURFTYPE_RICOCHET,    0 },    // behaves like metal but causes a ricochet sound

    // unassigned surface types
    {"surftype10",    0,    SURFTYPE_10,    0 },
    {"surftype11",    0,    SURFTYPE_11,    0 },
    {"surftype12",    0,    SURFTYPE_12,    0 },
    {"surftype13",    0,    SURFTYPE_13,    0 },
    {"surftype14",    0,    SURFTYPE_14,    0 },
    {"surftype15",    0,    SURFTYPE_15,    0 },
};

static const int numInfoParms = sizeof(infoParms) / sizeof (infoParms[0]);

static BOOL UDTokenIs( const idToken *token, const char *text ) {
    return !strcmp( token->text, text );
}

static BOOL UDTokenIcmp( const idToken *token, const char *text ) {
    return !strcasecmp( token->text, text );
}

#pragma mark - The text the parse reads

@interface UDMaterialTextNode ()
@property (nonatomic) UDMaterialTextKind kind;
@property (nonatomic, copy) NSString *leading;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *keyword;
@property (nonatomic, copy, nullable) NSString *value;
@property (nonatomic, copy, nullable) NSArray<UDMaterialTextNode *> *children;
@property (nonatomic, copy, nullable) NSString *closing;
@property (nonatomic) BOOL closed;
// Where it is in the text's bytes, while the parse goes.
@property (nonatomic) NSInteger leadingStart;
@property (nonatomic) NSInteger start;
@property (nonatomic) NSInteger keywordEnd;
@property (nonatomic) NSInteger closingStart;
@property (nonatomic) NSInteger closingEnd;
@property (nonatomic, strong, nullable) NSMutableArray<UDMaterialTextNode *> *mutableChildren;
@end

@implementation UDMaterialTextNode

- (NSString *)description {
    return [NSString stringWithFormat:@"<%ld %@ %@>", (long)self.kind, self.keyword ?: @"", self.kind == UDMaterialTextStage ? self.children : self.text];
}

@end

@interface UDMaterialStageInfo () {
@public
    shaderStage_t stage;
}
@property (nonatomic, copy, nullable) NSString *imageName;
@end

@implementation UDMaterialStageInfo

- (int)conditionRegister { return stage.conditionRegister; }
- (UDStageLighting)lighting { return (UDStageLighting)stage.lighting; }
- (int)drawStateBits { return stage.drawStateBits; }
- (const int *)colorRegisters { return stage.color.registers; }
- (BOOL)hasAlphaTest { return stage.hasAlphaTest; }
- (int)alphaTestRegister { return stage.alphaTestRegister; }
- (UDCubeFiles)cubeMap { return (UDCubeFiles)stage.texture.image.cubeMap; }
- (UDTexgen)texgen { return (UDTexgen)stage.texture.texgen; }
- (BOOL)hasMatrix { return stage.texture.hasMatrix; }
- (const int *)matrix { return &stage.texture.matrix[0][0]; }
- (BOOL)dynamic { return stage.texture.dynamic != DI_STATIC; }
- (BOOL)cinematic { return stage.texture.cinematic; }
- (BOOL)newStage { return stage.hasNewStage; }
- (NSInteger)textIndex { return stage.textIndex; }

@end

#pragma mark - idMaterial

@interface UDMaterialParser () {
    mtrParsingData_t    *pd;            // only valid during parse

    NSString            *desc;            // description
    NSString            *renderBump;        // renderbump command options, without the "renderbump" at the start
    NSString            *editorImageName;
    imageRef_t          lightFalloffImage;
    BOOL                hasLightFalloffImage;

    int                    entityGui;            // draw a gui with the idUserInterface from the renderEntity_t
                                            // non zero will draw gui, gui2, or gui3 from renderEnitty_t
    NSString            *gui;            // non-custom guis are shared by all users of a material

    BOOL                noFog;                // surface does not create fog interactions

    int                    spectrum;            // for invisible writing, used for both lights and surfaces

    float                polygonOffset;

    int                    contentFlags;        // content flags
    int                    surfaceFlags;        // surface flags
    int                    materialFlags;    // material flags

    decalInfo_t            decalInfo;

    float                sort;                // lower numbered shaders draw before higher numbered
    deform_t            deform;
    int                    deformRegisters[4];        // numeric parameter for deforms
    NSString            *deformDecl;        // for surface emitted particle deforms and tables

    int                    texGenRegisters[MAX_TEXGEN_REGISTERS];    // for wobbleSky

    materialCoverage_t    coverage;
    cullType_t            cullType;            // CT_FRONT_SIDED, CT_BACK_SIDED, or CT_TWO_SIDED
    BOOL                shouldCreateBackSides;

    BOOL                fogLight;
    BOOL                blendLight;
    BOOL                ambientLight;
    BOOL                unsmoothedTangents;
    BOOL                hasSubview;            // mirror, remote render, etc
    BOOL                allowOverlays;

    int                    numOps;
    expOp_t *            ops;                // evaluate to make expressionRegisters

    int                    numRegisters;                                                                            //
    float *                expressionRegisters;

    float *                constantRegisters;    // NULL if ops ever reference globalParms or entityParms

    int                    numStages;
    int                    numAmbientStages;

    shaderStage_t *        stages;

    float                editorAlpha;

    BOOL                suppressInSubview;
    BOOL                portalSky;

    // The tables OP_TYPE_TABLE's a indexes, by name (declManager's index).
    NSMutableArray<NSString *> *tables;

    // The text, and where the parse is in it.
    NSData              *textData;
    int                 textStages;     // ParseStage from the text, shortcuts counted
}
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong, nullable) idDeclManager *declManager;
@property (nonatomic, strong) idLexer *mainSrc;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *diagnostics;
@property (nonatomic, strong) NSMutableArray<UDMaterialTextNode *> *bodyNodes;
@property (nonatomic, strong) NSMutableArray<NSMutableArray<UDMaterialTextNode *> *> *containers;
@property (nonatomic, strong) NSMutableArray<UDMaterialTextNode *> *openStages;
@property (nonatomic, strong, nullable) UDMaterialTextNode *lastNode;
@property (nonatomic) NSInteger bodyClosingStart;
@property (nonatomic) NSInteger bodyClosingEnd;
@property (nonatomic) BOOL bodyClosed;
@property (nonatomic, copy, readwrite) NSArray<UDMaterialTextNode *> *body;
@property (nonatomic, copy, readwrite) NSString *closing;
@end

@implementation UDMaterialParser

- (instancetype)initWithText:(NSString *)text name:(NSString *)name declManager:(idDeclManager *)declManager {
    self = [super init];
    if (self) {
        _name = [name copy];
        _declManager = declManager;
        _diagnostics = [NSMutableArray array];
        tables = [NSMutableArray array];
        [self parse:text];
    }
    return self;
}

- (void)dealloc {
    free( stages );
    free( ops );
    free( expressionRegisters );
    free( constantRegisters );
}

- (NSArray<UDDeclTextProblem *> *)problems {
    NSMutableArray<UDDeclTextProblem *> *problems = [NSMutableArray array];
    for (NSDictionary *diagnostic in self.diagnostics) {
        [problems addObject:[[UDDeclTextProblem alloc] initWithLine:[diagnostic[@"line"] integerValue]
                                                            message:diagnostic[@"message"]
                                                            isError:[diagnostic[@"error"] boolValue]]];
    }
    return problems;
}

- (BOOL)defaulted { return [self testMaterialFlag:MF_DEFAULTED]; }
- (NSString *)desc { return desc; }
- (NSString *)editorImageName { return editorImageName ?: @""; }
- (int)coverage { return coverage; }
- (float)sort { return sort; }
- (int)contentFlags { return contentFlags; }
- (int)surfaceFlags { return surfaceFlags; }
- (int)materialFlags { return materialFlags; }

- (NSArray<UDMaterialStageInfo *> *)stages {
    NSMutableArray<UDMaterialStageInfo *> *infos = [NSMutableArray array];
    for (int i = 0; i < numStages; i++) {
        UDMaterialStageInfo *info = [[UDMaterialStageInfo alloc] init];
        info->stage = stages[i];
        info.imageName = stages[i].texture.hasImage ? @(stages[i].texture.image.name) : nil;
        [infos addObject:info];
    }
    return infos;
}

#pragma mark - The engine's helpers

- (void)setMaterialFlag:(int)flag { materialFlags |= flag; }
- (void)clearMaterialFlag:(int)flag { materialFlags &= ~flag; }
- (BOOL)testMaterialFlag:(int)flag { return ( materialFlags & flag ) != 0; }

/// common->Warning: at the line the material's parse is on.
- (void)commonWarning:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {
    va_list ap;
    va_start(ap, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    [self.mainSrc warning:@"%@", message];
}

/// declManager->FindType( DECL_TABLE, name, false ): its index in the
/// tables this material names, or -1 when there is none.
- (int)findTable:(NSString *)name {
    if ( [self.declManager findDeclWithoutParsing:DECL_TABLE name:name makeDefault:NO] == nil ) {
        return -1;
    }
    NSUInteger index = [tables indexOfObject:name.lowercaseString];
    if ( index == NSNotFound ) {
        [tables addObject:name.lowercaseString];
        index = tables.count - 1;
    }
    return (int)index;
}

/// An idLexer over generated text, as ParseMaterial and AddImplicitStages
/// make one: LoadMemory, then their flags.
- (idLexer *)lexerOverBuffer:(NSString *)buffer name:(NSString *)name {
    NSData *data = [buffer dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *bytes = [data mutableCopy];
    [bytes appendBytes:"" length:1];
    idLexer *newSrc = [[idLexer alloc] initWithFileSystem:nil];
    if ( ![newSrc loadMemory:bytes.bytes length:(int)data.length name:name startLine:1 error:NULL] ) {
        return nil;
    }
    objc_setAssociatedObject(newSrc, (__bridge const void *)newSrc, bytes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [newSrc setFlags:LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_NOSTRINGESCAPECHARS | LEXFL_ALLOWPATHNAMES];
    return newSrc;
}

static void UDCopyName( char *dest, NSString *source ) {
    strncpy( dest, source.UTF8String ?: "", MAX_IMAGE_NAME - 1 );
    dest[MAX_IMAGE_NAME - 1] = 0;
}

/// ImageFromFile( name, tf, allowPicmip, trp, td, cubeMap ): the image
/// asked for.
static imageRef_t UDImageFromFile( const char *name, textureFilter_t tf, BOOL allowPicmip, textureRepeat_t trp,
                                   textureDepth_t td, cubeFiles_t cubeMap ) {
    imageRef_t ref;
    memset( &ref, 0, sizeof( ref ) );
    strncpy( ref.name, name, MAX_IMAGE_NAME - 1 );
    ref.filter = tf;
    ref.allowPicmip = allowPicmip;
    ref.repeat = trp;
    ref.depth = td;
    ref.cubeMap = cubeMap;
    return ref;
}

#pragma mark - Noting the text

- (NSString *)sliceFrom:(NSInteger)start to:(NSInteger)end {
    if ( start < 0 || end < start || (NSUInteger)end > textData.length ) {
        return @"";
    }
    NSData *bytes = [textData subdataWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))];
    return [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] ?:
           [[NSString alloc] initWithData:bytes encoding:NSISOLatin1StringEncoding] ?: @"";
}

- (NSInteger)offsetOf:(const char *)pointer inLexer:(idLexer *)src {
    return pointer != NULL ? (NSInteger)( pointer - [src buffer] ) : -1;
}

/// A keyword read from the text, at the parse's level (the body's, or a
/// stage's): noted where it is.
- (UDMaterialTextNode *)noteToken:(idToken *)token inLexer:(idLexer *)src kind:(UDMaterialTextKind)kind {
    if ( src != self.mainSrc || self.containers.count == 0 ) {
        return nil;
    }
    UDMaterialTextNode *node = [[UDMaterialTextNode alloc] init];
    node.kind = kind;
    node.leadingStart = [self offsetOf:token->whiteSpaceStart_p inLexer:src];
    node.start = [self offsetOf:token->whiteSpaceEnd_p inLexer:src];
    node.keywordEnd = node.start + (NSInteger)strlen( token->text );
    node.keyword = UDTokenString( token );
    [self.containers.lastObject addObject:node];
    self.lastNode = node;
    if ( kind == UDMaterialTextStage ) {
        node.mutableChildren = [NSMutableArray array];
        node.closingStart = -1;
        [self.containers addObject:node.mutableChildren];
        [self.openStages addObject:node];
    }
    return node;
}

/// A close brace: the stage's, or the body's.
- (void)noteClose:(idToken *)token inLexer:(idLexer *)src {
    if ( src != self.mainSrc || self.containers.count == 0 ) {
        return;
    }
    NSInteger closingStart = [self offsetOf:token->whiteSpaceStart_p inLexer:src];
    NSInteger closingEnd = [self offsetOf:token->whiteSpaceEnd_p inLexer:src];
    if ( self.openStages.count > 0 && self.containers.count > 1 ) {
        UDMaterialTextNode *stage = self.openStages.lastObject;
        stage.closingStart = closingStart;
        stage.closingEnd = closingEnd;
        stage.closed = YES;
        [self.openStages removeLastObject];
        [self.containers removeLastObject];
    } else {
        self.bodyClosingStart = closingStart;
        self.bodyClosingEnd = closingEnd;
        self.bodyClosed = YES;
        [self.containers removeLastObject];
    }
}

/// The text of each node: from its keyword to where what follows it
/// begins.
- (void)finishNodes:(NSArray<UDMaterialTextNode *> *)nodes until:(NSInteger)end {
    for (NSUInteger i = 0; i < nodes.count; i++) {
        UDMaterialTextNode *node = nodes[i];
        NSInteger next = i + 1 < nodes.count ? nodes[i + 1].leadingStart : end;
        node.leading = [self sliceFrom:node.leadingStart to:node.start];
        if ( node.kind == UDMaterialTextStage ) {
            NSInteger childrenEnd = node.closed ? node.closingStart : next;
            [self finishNodes:node.mutableChildren until:childrenEnd];
            node.children = node.mutableChildren;
            node.closing = node.closed ? [self sliceFrom:node.closingStart to:node.closingEnd] : @"";
            node.text = @"{";
        } else {
            node.text = [self sliceFrom:node.start to:next];
            if ( node.value == nil && node.kind == UDMaterialTextKeyword ) {
                node.value = [[self sliceFrom:node.keywordEnd to:next]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
        node.mutableChildren = nil;
    }
}

/// Where the parse gave up: the keyword it was on, and the rest of the
/// text to the material's close brace, as it is.
- (void)noteUnparsedRest {
    UDMaterialTextNode *last = self.lastNode;
    if ( last == nil || self.bodyClosed ) {
        return;
    }
    // Take the keyword it was on out of the level it was at.
    NSMutableArray<NSMutableArray<UDMaterialTextNode *> *> *levels = [NSMutableArray arrayWithObject:self.bodyNodes];
    for (NSUInteger i = 0; i < levels.count; i++) {
        for (UDMaterialTextNode *node in levels[i]) {
            if ( node.mutableChildren != nil ) [levels addObject:node.mutableChildren];
        }
    }
    NSMutableArray<UDMaterialTextNode *> *level = nil;
    for (NSMutableArray<UDMaterialTextNode *> *candidate in levels) {
        if ( [candidate containsObject:last] ) level = candidate;
    }
    // The decl's text ends with its close brace.
    const char *bytes = textData.bytes;
    NSInteger end = (NSInteger)textData.length;
    while ( end > 0 && bytes[end - 1] != '}' ) end--;
    NSInteger bodyEnd = end > 0 ? end - 1 : (NSInteger)textData.length;

    UDMaterialTextNode *rest = [[UDMaterialTextNode alloc] init];
    rest.kind = UDMaterialTextUnparsed;
    rest.leadingStart = last.leadingStart;
    rest.start = last.start;
    rest.keyword = last.keyword;
    rest.value = nil;
    [level removeObject:last];
    [level addObject:rest];
    self.lastNode = rest;
    // The levels it was in are left unclosed; the body's brace is the text's last.
    self.bodyClosingStart = bodyEnd;
    self.bodyClosingEnd = bodyEnd;
    self.restEnd = bodyEnd;
}

- (void)setRestEnd:(NSInteger)restEnd {
    objc_setAssociatedObject(self, @selector(restEnd), @(restEnd), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSInteger)restEnd {
    NSNumber *value = objc_getAssociatedObject(self, @selector(restEnd));
    return value != nil ? value.integerValue : -1;
}

#pragma mark - Material.cpp

/*
=============
idMaterial::CommonInit
=============
*/
- (void)commonInit {
    desc = @"<none>";
    renderBump = @"";
    contentFlags = CONTENTS_SOLID;
    surfaceFlags = SURFTYPE_NONE;
    materialFlags = 0;
    sort = SS_BAD;
    coverage = MC_BAD;
    cullType = CT_FRONT_SIDED;
    deform = DFRM_NONE;
    numOps = 0;
    ops = NULL;
    numRegisters = 0;
    expressionRegisters = NULL;
    constantRegisters = NULL;
    numStages = 0;
    numAmbientStages = 0;
    stages = NULL;
    editorImageName = @"";
    hasLightFalloffImage = NO;
    shouldCreateBackSides = NO;
    entityGui = 0;
    fogLight = NO;
    blendLight = NO;
    ambientLight = NO;
    noFog = NO;
    hasSubview = NO;
    allowOverlays = YES;
    unsmoothedTangents = NO;
    gui = nil;
    memset( deformRegisters, 0, sizeof( deformRegisters ) );
    editorAlpha = 1.0;
    spectrum = 0;
    polygonOffset = 0;
    suppressInSubview = NO;
    portalSky = NO;

    decalInfo.stayTime = 10000;
    decalInfo.fadeTime = 4000;
    decalInfo.start[0] = 1;
    decalInfo.start[1] = 1;
    decalInfo.start[2] = 1;
    decalInfo.start[3] = 1;
    decalInfo.end[0] = 0;
    decalInfo.end[1] = 0;
    decalInfo.end[2] = 0;
    decalInfo.end[3] = 0;
}

/*
===============
idMaterial::CheckSurfaceParm

See if the current token matches one of the surface parm bit flags
===============
*/
- (BOOL)checkSurfaceParm:(idToken *)token {

    for ( int i = 0 ; i < numInfoParms ; i++ ) {
        if ( UDTokenIcmp( token, infoParms[i].name ) ) {
            if ( infoParms[i].surfaceFlags & SURF_TYPE_MASK ) {
                // ensure we only have one surface type set
                surfaceFlags &= ~SURF_TYPE_MASK;
            }
            surfaceFlags |= infoParms[i].surfaceFlags;
            contentFlags |= infoParms[i].contents;
            if ( infoParms[i].clearSolid ) {
                contentFlags &= ~CONTENTS_SOLID;
            }
            return YES;
        }
    }
    return NO;
}

/*
===============
idMaterial::MatchToken

Sets defaultShader and returns false if the next token doesn't match
===============
*/
- (BOOL)matchToken:(idLexer *)src match:(NSString *)match {
    if ( ![src expectTokenString:match error:NULL] ) {
        [self setMaterialFlag:MF_DEFAULTED];
        return NO;
    }
    return YES;
}

/*
=================
idMaterial::ParseSort
=================
*/
- (void)parseSort:(idLexer *)src {
    idToken token;
    idToken_Init( &token );

    if ( ![src readTokenOnLine:&token error:NULL] ) {
        [src warning:@"missing sort parameter"];
        [self setMaterialFlag:MF_DEFAULTED];
        return;
    }

    if ( UDTokenIcmp( &token, "subview" ) ) {
        sort = SS_SUBVIEW;
    } else if ( UDTokenIcmp( &token, "opaque" ) ) {
        sort = SS_OPAQUE;
    }else if ( UDTokenIcmp( &token, "decal" ) ) {
        sort = SS_DECAL;
    } else if ( UDTokenIcmp( &token, "far" ) ) {
        sort = SS_FAR;
    } else if ( UDTokenIcmp( &token, "medium" ) ) {
        sort = SS_MEDIUM;
    } else if ( UDTokenIcmp( &token, "close" ) ) {
        sort = SS_CLOSE;
    } else if ( UDTokenIcmp( &token, "almostNearest" ) ) {
        sort = SS_ALMOST_NEAREST;
    } else if ( UDTokenIcmp( &token, "nearest" ) ) {
        sort = SS_NEAREST;
    } else if ( UDTokenIcmp( &token, "postProcess" ) ) {
        sort = SS_POST_PROCESS;
    } else if ( UDTokenIcmp( &token, "portalSky" ) ) {
        sort = SS_PORTAL_SKY;
    } else {
        sort = atof( token.text );
    }
}

/*
=================
idMaterial::ParseDecalInfo
=================
*/
- (void)parseDecalInfo:(idLexer *)src {
    float value;
    [src parseFloat:&value error:NULL];
    decalInfo.stayTime = value * 1000;
    [src parseFloat:&value error:NULL];
    decalInfo.fadeTime = value * 1000;
    float    start[4], end[4];
    [src parse1DMatrix:4 matrix:start error:NULL];
    [src parse1DMatrix:4 matrix:end error:NULL];
    for ( int i = 0 ; i < 4 ; i++ ) {
        decalInfo.start[i] = start[i];
        decalInfo.end[i] = end[i];
    }
}

/*
=============
idMaterial::GetExpressionConstant
=============
*/
- (int)getExpressionConstant:(float)f {
    int        i;

    for ( i = EXP_REG_NUM_PREDEFINED ; i < numRegisters ; i++ ) {
        if ( !pd->registerIsTemporary[i] && pd->shaderRegisters[i] == f ) {
            return i;
        }
    }
    if ( numRegisters == MAX_EXPRESSION_REGISTERS ) {
        [self commonWarning:@"GetExpressionConstant: material '%@' hit MAX_EXPRESSION_REGISTERS", self.name];
        [self setMaterialFlag:MF_DEFAULTED];
        return 0;
    }
    pd->registerIsTemporary[i] = NO;
    pd->shaderRegisters[i] = f;
    numRegisters++;

    return i;
}

/*
=============
idMaterial::GetExpressionTemporary
=============
*/
- (int)getExpressionTemporary {
    if ( numRegisters == MAX_EXPRESSION_REGISTERS ) {
        [self commonWarning:@"GetExpressionTemporary: material '%@' hit MAX_EXPRESSION_REGISTERS", self.name];
        [self setMaterialFlag:MF_DEFAULTED];
        return 0;
    }
    pd->registerIsTemporary[numRegisters] = YES;
    numRegisters++;
    return numRegisters - 1;
}

/*
=============
idMaterial::GetExpressionOp
=============
*/
- (expOp_t *)getExpressionOp {
    if ( numOps == MAX_EXPRESSION_OPS ) {
        [self commonWarning:@"GetExpressionOp: material '%@' hit MAX_EXPRESSION_OPS", self.name];
        [self setMaterialFlag:MF_DEFAULTED];
        return &pd->shaderOps[0];
    }

    return &pd->shaderOps[numOps++];
}

/*
=================
idMaterial::EmitOp
=================
*/
- (int)emitOp:(int)a b:(int)b opType:(expOpType_t)opType {
    expOp_t    *op;

    // optimize away identity operations
    if ( opType == OP_TYPE_ADD ) {
        if ( !pd->registerIsTemporary[a] && pd->shaderRegisters[a] == 0 ) {
            return b;
        }
        if ( !pd->registerIsTemporary[b] && pd->shaderRegisters[b] == 0 ) {
            return a;
        }
        if ( !pd->registerIsTemporary[a] && !pd->registerIsTemporary[b] ) {
            return [self getExpressionConstant:pd->shaderRegisters[a] + pd->shaderRegisters[b]];
        }
    }
    if ( opType == OP_TYPE_MULTIPLY ) {
        if ( !pd->registerIsTemporary[a] && pd->shaderRegisters[a] == 1 ) {
            return b;
        }
        if ( !pd->registerIsTemporary[a] && pd->shaderRegisters[a] == 0 ) {
            return a;
        }
        if ( !pd->registerIsTemporary[b] && pd->shaderRegisters[b] == 1 ) {
            return a;
        }
        if ( !pd->registerIsTemporary[b] && pd->shaderRegisters[b] == 0 ) {
            return b;
        }
        if ( !pd->registerIsTemporary[a] && !pd->registerIsTemporary[b] ) {
            return [self getExpressionConstant:pd->shaderRegisters[a] * pd->shaderRegisters[b]];
        }
    }

    op = [self getExpressionOp];
    op->opType = opType;
    op->a = a;
    op->b = b;
    op->c = [self getExpressionTemporary];

    return op->c;
}

/*
=================
idMaterial::ParseEmitOp
=================
*/
- (int)parseEmitOp:(idLexer *)src a:(int)a opType:(expOpType_t)opType priority:(int)priority {
    int        b;

    b = [self parseExpressionPriority:src priority:priority];
    return [self emitOp:a b:b opType:opType];
}

/*
=================
idMaterial::ParseTerm

Returns a register index
=================
*/
- (int)parseTerm:(idLexer *)src {
    idToken token;
    int        a, b;
    idToken_Init( &token );

    [src readToken:&token error:NULL];

    if ( UDTokenIs( &token, "(" ) ) {
        a = [self parseExpression:src];
        [self matchToken:src match:@")"];
        return a;
    }

    if ( UDTokenIcmp( &token, "time" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_TIME;
    }
    if ( UDTokenIcmp( &token, "parm0" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM0;
    }
    if ( UDTokenIcmp( &token, "parm1" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM1;
    }
    if ( UDTokenIcmp( &token, "parm2" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM2;
    }
    if ( UDTokenIcmp( &token, "parm3" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM3;
    }
    if ( UDTokenIcmp( &token, "parm4" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM4;
    }
    if ( UDTokenIcmp( &token, "parm5" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM5;
    }
    if ( UDTokenIcmp( &token, "parm6" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM6;
    }
    if ( UDTokenIcmp( &token, "parm7" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM7;
    }
    if ( UDTokenIcmp( &token, "parm8" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM8;
    }
    if ( UDTokenIcmp( &token, "parm9" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM9;
    }
    if ( UDTokenIcmp( &token, "parm10" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM10;
    }
    if ( UDTokenIcmp( &token, "parm11" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_PARM11;
    }
    if ( UDTokenIcmp( &token, "global0" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_GLOBAL0;
    }
    if ( UDTokenIcmp( &token, "global1" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_GLOBAL1;
    }
    if ( UDTokenIcmp( &token, "global2" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_GLOBAL2;
    }
    if ( UDTokenIcmp( &token, "global3" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_GLOBAL3;
    }
    if ( UDTokenIcmp( &token, "global4" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_GLOBAL4;
    }
    if ( UDTokenIcmp( &token, "global5" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_GLOBAL5;
    }
    if ( UDTokenIcmp( &token, "global6" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_GLOBAL6;
    }
    if ( UDTokenIcmp( &token, "global7" ) ) {
        pd->registersAreConstant = NO;
        return EXP_REG_GLOBAL7;
    }
    if ( UDTokenIcmp( &token, "fragmentPrograms" ) ) {
        // glConfig.ARBFragmentProgramAvailable
        return [self getExpressionConstant:(float)1];
    }

    if ( UDTokenIcmp( &token, "sound" ) ) {
        pd->registersAreConstant = NO;
        return [self emitOp:0 b:0 opType:OP_TYPE_SOUND];
    }

    // parse negative numbers
    if ( UDTokenIs( &token, "-" ) ) {
        [src readToken:&token error:NULL];
        if ( token.type == TT_NUMBER || UDTokenIs( &token, "." ) ) {
            return [self getExpressionConstant:-(float)idToken_FloatValue( &token )];
        }
        [src warning:@"Bad negative number '%s'", token.text];
        [self setMaterialFlag:MF_DEFAULTED];
        return 0;
    }

    if ( token.type == TT_NUMBER || UDTokenIs( &token, "." ) || UDTokenIs( &token, "-" ) ) {
        return [self getExpressionConstant:(float)idToken_FloatValue( &token )];
    }

    // see if it is a table name
    int table = [self findTable:UDTokenString( &token )];
    if ( table < 0 ) {
        [src warning:@"Bad term '%s'", token.text];
        [self setMaterialFlag:MF_DEFAULTED];
        return 0;
    }

    // parse a table expression
    [self matchToken:src match:@"["];

    b = [self parseExpression:src];

    [self matchToken:src match:@"]"];

    return [self emitOp:table b:b opType:OP_TYPE_TABLE];
}

/*
=================
idMaterial::ParseExpressionPriority

Returns a register index
=================
*/
#define    TOP_PRIORITY 4
- (int)parseExpressionPriority:(idLexer *)src priority:(int)priority {
    idToken token;
    int        a;
    idToken_Init( &token );

    if ( priority == 0 ) {
        return [self parseTerm:src];
    }

    a = [self parseExpressionPriority:src priority:priority - 1];

    if ( [self testMaterialFlag:MF_DEFAULTED] ) {    // we have a parse error
        return 0;
    }

    if ( ![src readToken:&token error:NULL] ) {
        // we won't get EOF in a real file, but we can
        // when parsing from generated strings
        return a;
    }

    if ( priority == 1 && UDTokenIs( &token, "*" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_MULTIPLY priority:priority];
    }
    if ( priority == 1 && UDTokenIs( &token, "/" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_DIVIDE priority:priority];
    }
    if ( priority == 1 && UDTokenIs( &token, "%" ) ) {    // implied truncate both to integer
        return [self parseEmitOp:src a:a opType:OP_TYPE_MOD priority:priority];
    }
    if ( priority == 2 && UDTokenIs( &token, "+" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_ADD priority:priority];
    }
    if ( priority == 2 && UDTokenIs( &token, "-" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_SUBTRACT priority:priority];
    }
    if ( priority == 3 && UDTokenIs( &token, ">" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_GT priority:priority];
    }
    if ( priority == 3 && UDTokenIs( &token, ">=" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_GE priority:priority];
    }
    if ( priority == 3 && UDTokenIs( &token, "<" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_LT priority:priority];
    }
    if ( priority == 3 && UDTokenIs( &token, "<=" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_LE priority:priority];
    }
    if ( priority == 3 && UDTokenIs( &token, "==" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_EQ priority:priority];
    }
    if ( priority == 3 && UDTokenIs( &token, "!=" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_NE priority:priority];
    }
    if ( priority == 4 && UDTokenIs( &token, "&&" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_AND priority:priority];
    }
    if ( priority == 4 && UDTokenIs( &token, "||" ) ) {
        return [self parseEmitOp:src a:a opType:OP_TYPE_OR priority:priority];
    }

    // assume that anything else terminates the expression
    // not too robust error checking...

    [src unreadToken:&token error:NULL];

    return a;
}

/*
=================
idMaterial::ParseExpression

Returns a register index
=================
*/
- (int)parseExpression:(idLexer *)src {
    return [self parseExpressionPriority:src priority:TOP_PRIORITY];
}


/*
===============
idMaterial::ClearStage
===============
*/
- (void)clearStage:(shaderStage_t *)ss {
    ss->drawStateBits = 0;
    ss->conditionRegister = [self getExpressionConstant:1];
    ss->color.registers[0] =
    ss->color.registers[1] =
    ss->color.registers[2] =
    ss->color.registers[3] = [self getExpressionConstant:1];
}

/*
===============
idMaterial::NameToSrcBlendMode
===============
*/
- (int)nameToSrcBlendMode:(const idToken *)name {
    if ( UDTokenIcmp( name, "GL_ONE" ) ) {
        return GLS_SRCBLEND_ONE;
    } else if ( UDTokenIcmp( name, "GL_ZERO" ) ) {
        return GLS_SRCBLEND_ZERO;
    } else if ( UDTokenIcmp( name, "GL_DST_COLOR" ) ) {
        return GLS_SRCBLEND_DST_COLOR;
    } else if ( UDTokenIcmp( name, "GL_ONE_MINUS_DST_COLOR" ) ) {
        return GLS_SRCBLEND_ONE_MINUS_DST_COLOR;
    } else if ( UDTokenIcmp( name, "GL_SRC_ALPHA" ) ) {
        return GLS_SRCBLEND_SRC_ALPHA;
    } else if ( UDTokenIcmp( name, "GL_ONE_MINUS_SRC_ALPHA" ) ) {
        return GLS_SRCBLEND_ONE_MINUS_SRC_ALPHA;
    } else if ( UDTokenIcmp( name, "GL_DST_ALPHA" ) ) {
        return GLS_SRCBLEND_DST_ALPHA;
    } else if ( UDTokenIcmp( name, "GL_ONE_MINUS_DST_ALPHA" ) ) {
        return GLS_SRCBLEND_ONE_MINUS_DST_ALPHA;
    } else if ( UDTokenIcmp( name, "GL_SRC_ALPHA_SATURATE" ) ) {
        return GLS_SRCBLEND_ALPHA_SATURATE;
    }

    [self commonWarning:@"unknown blend mode '%s' in material '%@'", name->text, self.name];
    [self setMaterialFlag:MF_DEFAULTED];

    return GLS_SRCBLEND_ONE;
}

/*
===============
idMaterial::NameToDstBlendMode
===============
*/
- (int)nameToDstBlendMode:(const idToken *)name {
    if ( UDTokenIcmp( name, "GL_ONE" ) ) {
        return GLS_DSTBLEND_ONE;
    } else if ( UDTokenIcmp( name, "GL_ZERO" ) ) {
        return GLS_DSTBLEND_ZERO;
    } else if ( UDTokenIcmp( name, "GL_SRC_ALPHA" ) ) {
        return GLS_DSTBLEND_SRC_ALPHA;
    } else if ( UDTokenIcmp( name, "GL_ONE_MINUS_SRC_ALPHA" ) ) {
        return GLS_DSTBLEND_ONE_MINUS_SRC_ALPHA;
    } else if ( UDTokenIcmp( name, "GL_DST_ALPHA" ) ) {
        return GLS_DSTBLEND_DST_ALPHA;
    } else if ( UDTokenIcmp( name, "GL_ONE_MINUS_DST_ALPHA" ) ) {
        return GLS_DSTBLEND_ONE_MINUS_DST_ALPHA;
    } else if ( UDTokenIcmp( name, "GL_SRC_COLOR" ) ) {
        return GLS_DSTBLEND_SRC_COLOR;
    } else if ( UDTokenIcmp( name, "GL_ONE_MINUS_SRC_COLOR" ) ) {
        return GLS_DSTBLEND_ONE_MINUS_SRC_COLOR;
    }

    [self commonWarning:@"unknown blend mode '%s' in material '%@'", name->text, self.name];
    [self setMaterialFlag:MF_DEFAULTED];

    return GLS_DSTBLEND_ONE;
}

/*
================
idMaterial::ParseBlend
================
*/
- (void)parseBlend:(idLexer *)src stage:(shaderStage_t *)stage {
    idToken token;
    int        srcBlend, dstBlend;
    idToken_Init( &token );

    if ( ![src readToken:&token error:NULL] ) {
        return;
    }

    // blending combinations
    if ( UDTokenIcmp( &token, "blend" ) ) {
        stage->drawStateBits = GLS_SRCBLEND_SRC_ALPHA | GLS_DSTBLEND_ONE_MINUS_SRC_ALPHA;
        return;
    }
    if ( UDTokenIcmp( &token, "add" ) ) {
        stage->drawStateBits = GLS_SRCBLEND_ONE | GLS_DSTBLEND_ONE;
        return;
    }
    if ( UDTokenIcmp( &token, "filter" ) || UDTokenIcmp( &token, "modulate" ) ) {
        stage->drawStateBits = GLS_SRCBLEND_DST_COLOR | GLS_DSTBLEND_ZERO;
        return;
    }
    if (  UDTokenIcmp( &token, "none" ) ) {
        // none is used when defining an alpha mask that doesn't draw
        stage->drawStateBits = GLS_SRCBLEND_ZERO | GLS_DSTBLEND_ONE;
        return;
    }
    if ( UDTokenIcmp( &token, "bumpmap" ) ) {
        stage->lighting = SL_BUMP;
        return;
    }
    if ( UDTokenIcmp( &token, "diffusemap" ) ) {
        stage->lighting = SL_DIFFUSE;
        return;
    }
    if ( UDTokenIcmp( &token, "specularmap" ) ) {
        stage->lighting = SL_SPECULAR;
        return;
    }

    srcBlend = [self nameToSrcBlendMode:&token];

    [self matchToken:src match:@","];
    if ( ![src readToken:&token error:NULL] ) {
        return;
    }
    dstBlend = [self nameToDstBlendMode:&token];

    stage->drawStateBits = srcBlend | dstBlend;
}

/*
================
idMaterial::ParseVertexParm

If there is a single value, it will be repeated across all elements
If there are two values, 3 = 0.0, 4 = 1.0
if there are three values, 4 = 1.0
================
*/
- (void)parseVertexParm:(idLexer *)src newStage:(newShaderStage_t *)newStage {
    idToken                token;
    idToken_Init( &token );

    [src readTokenOnLine:&token error:NULL];
    int    parm = idToken_IntValue( &token );
    if ( token.type != TT_NUMBER || parm < 0 || parm >= MAX_VERTEX_PARMS ) {
        [self commonWarning:@"bad vertexParm number\n"];
        [self setMaterialFlag:MF_DEFAULTED];
        return;
    }
    if ( parm >= newStage->numVertexParms ) {
        newStage->numVertexParms = parm+1;
    }

    newStage->vertexParms[parm][0] = [self parseExpression:src];

    idToken_Init( &token );
    [src readTokenOnLine:&token error:NULL];
    if ( !token.text[0] || !UDTokenIcmp( &token, "," ) ) {
        newStage->vertexParms[parm][1] =
        newStage->vertexParms[parm][2] =
        newStage->vertexParms[parm][3] = newStage->vertexParms[parm][0];
        return;
    }

    newStage->vertexParms[parm][1] = [self parseExpression:src];

    idToken_Init( &token );
    [src readTokenOnLine:&token error:NULL];
    if ( !token.text[0] || !UDTokenIcmp( &token, "," ) ) {
        newStage->vertexParms[parm][2] = [self getExpressionConstant:0];
        newStage->vertexParms[parm][3] = [self getExpressionConstant:1];
        return;
    }

    newStage->vertexParms[parm][2] = [self parseExpression:src];

    idToken_Init( &token );
    [src readTokenOnLine:&token error:NULL];
    if ( !token.text[0] || !UDTokenIcmp( &token, "," ) ) {
        newStage->vertexParms[parm][3] = [self getExpressionConstant:1];
        return;
    }

    newStage->vertexParms[parm][3] = [self parseExpression:src];
}


/*
================
idMaterial::ParseFragmentMap
================
*/
- (void)parseFragmentMap:(idLexer *)src newStage:(newShaderStage_t *)newStage {
    NSString            *str;
    textureFilter_t        tf;
    textureRepeat_t        trp;
    textureDepth_t        td;
    cubeFiles_t            cubeMap;
    BOOL                allowPicmip;
    idToken                token;
    idToken_Init( &token );

    tf = TF_DEFAULT;
    trp = TR_REPEAT;
    td = TD_DEFAULT;
    allowPicmip = YES;
    cubeMap = CF_2D;

    [src readTokenOnLine:&token error:NULL];
    int    unit = idToken_IntValue( &token );
    if ( token.type != TT_NUMBER || unit < 0 || unit >= MAX_FRAGMENT_IMAGES ) {
        [self commonWarning:@"bad fragmentMap number\n"];
        [self setMaterialFlag:MF_DEFAULTED];
        return;
    }

    // unit 1 is the normal map.. make sure it gets flagged as the proper depth
    if ( unit == 1 ) {
        td = TD_BUMP;
    }

    if ( unit >= newStage->numFragmentProgramImages ) {
        newStage->numFragmentProgramImages = unit+1;
    }

    while( 1 ) {
        [src readTokenOnLine:&token error:NULL];

        if ( UDTokenIcmp( &token, "cubeMap" ) ) {
            cubeMap = CF_NATIVE;
            continue;
        }
        if ( UDTokenIcmp( &token, "cameraCubeMap" ) ) {
            cubeMap = CF_CAMERA;
            continue;
        }
        if ( UDTokenIcmp( &token, "nearest" ) ) {
            tf = TF_NEAREST;
            continue;
        }
        if ( UDTokenIcmp( &token, "linear" ) ) {
            tf = TF_LINEAR;
            continue;
        }
        if ( UDTokenIcmp( &token, "clamp" ) ) {
            trp = TR_CLAMP;
            continue;
        }
        if ( UDTokenIcmp( &token, "noclamp" ) ) {
            trp = TR_REPEAT;
            continue;
        }
        if ( UDTokenIcmp( &token, "zeroclamp" ) ) {
            trp = TR_CLAMP_TO_ZERO;
            continue;
        }
        if ( UDTokenIcmp( &token, "alphazeroclamp" ) ) {
            trp = TR_CLAMP_TO_ZERO_ALPHA;
            continue;
        }
        if ( UDTokenIcmp( &token, "forceHighQuality" ) ) {
            td = TD_HIGH_QUALITY;
            continue;
        }

        if ( UDTokenIcmp( &token, "uncompressed" ) || UDTokenIcmp( &token, "highquality" ) ) {
            if ( !image_ignoreHighQuality ) {
                td = TD_HIGH_QUALITY;
            }
            continue;
        }
        if ( UDTokenIcmp( &token, "nopicmip" ) ) {
            allowPicmip = NO;
            continue;
        }

        // assume anything else is the image name
        [src unreadToken:&token error:NULL];
        break;
    }
    str = [UDImageProgram parsePastImageProgram:src];

    newStage->fragmentProgramImages[unit] =
        UDImageFromFile( str.UTF8String ?: "", tf, allowPicmip, trp, td, cubeMap );
}

/*
===============
idMaterial::MultiplyTextureMatrix
===============
*/
- (void)multiplyTextureMatrix:(textureStage_t *)ts registers:(int[2][3])registers {
    int        old[2][3];

    if ( !ts->hasMatrix ) {
        ts->hasMatrix = YES;
        memcpy( ts->matrix, registers, sizeof( ts->matrix ) );
        return;
    }

    memcpy( old, ts->matrix, sizeof( old ) );

    // multiply the two maticies
    ts->matrix[0][0] = [self emitOp:
                            [self emitOp:old[0][0] b:registers[0][0] opType:OP_TYPE_MULTIPLY]
                                  b:[self emitOp:old[0][1] b:registers[1][0] opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_ADD];
    ts->matrix[0][1] = [self emitOp:
                            [self emitOp:old[0][0] b:registers[0][1] opType:OP_TYPE_MULTIPLY]
                                  b:[self emitOp:old[0][1] b:registers[1][1] opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_ADD];
    ts->matrix[0][2] = [self emitOp:
                            [self emitOp:
                                [self emitOp:old[0][0] b:registers[0][2] opType:OP_TYPE_MULTIPLY]
                                       b:[self emitOp:old[0][1] b:registers[1][2] opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_ADD]
                                  b:old[0][2] opType:OP_TYPE_ADD];

    ts->matrix[1][0] = [self emitOp:
                            [self emitOp:old[1][0] b:registers[0][0] opType:OP_TYPE_MULTIPLY]
                                  b:[self emitOp:old[1][1] b:registers[1][0] opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_ADD];
    ts->matrix[1][1] = [self emitOp:
                            [self emitOp:old[1][0] b:registers[0][1] opType:OP_TYPE_MULTIPLY]
                                  b:[self emitOp:old[1][1] b:registers[1][1] opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_ADD];
    ts->matrix[1][2] = [self emitOp:
                            [self emitOp:
                                [self emitOp:old[1][0] b:registers[0][2] opType:OP_TYPE_MULTIPLY]
                                       b:[self emitOp:old[1][1] b:registers[1][2] opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_ADD]
                                  b:old[1][2] opType:OP_TYPE_ADD];

}

/*
=================
idMaterial::ParseStage

An open brace has been parsed


{
    if <expression>
    map <imageprogram>
    "nearest" "linear" "clamp" "zeroclamp" "uncompressed" "highquality" "nopicmip"
    scroll, scale, rotate
}

=================
*/
- (void)parseStage:(idLexer *)src trpDefault:(const textureRepeat_t)trpDefault {
    idToken                token;
    NSString            *str;
    shaderStage_t        *ss;
    textureStage_t        *ts;
    textureFilter_t        tf;
    textureRepeat_t        trp;
    textureDepth_t        td;
    cubeFiles_t            cubeMap;
    BOOL                allowPicmip;
    char                imageName[MAX_IMAGE_NAME];
    int                    a, b;
    int                    matrix[2][3];
    newShaderStage_t    newStage;
    idToken_Init( &token );

    if ( numStages >= MAX_SHADER_STAGES ) {
        [self setMaterialFlag:MF_DEFAULTED];
        [self commonWarning:@"material '%@' exceeded %i stages", self.name, MAX_SHADER_STAGES];
        // (the engine goes on to write past its stages; here, the last one)
    }

    tf = TF_DEFAULT;
    trp = trpDefault;
    td = TD_DEFAULT;
    allowPicmip = YES;
    cubeMap = CF_2D;

    imageName[0] = 0;

    memset( &newStage, 0, sizeof( newStage ) );

    ss = &pd->parseStages[MIN( numStages, MAX_SHADER_STAGES - 1 )];
    ts = &ss->texture;

    [self clearStage:ss];
    ss->textIndex = src == self.mainSrc ? textStages++ : -1;

    while ( 1 ) {
        if ( [self testMaterialFlag:MF_DEFAULTED] ) {    // we have a parse error
            return;
        }
        if ( ![src expectAnyToken:&token error:NULL] ) {
            [self setMaterialFlag:MF_DEFAULTED];
            return;
        }

        // the close brace for the entire material ends the draw block
        if ( UDTokenIs( &token, "}" ) ) {
            [self noteClose:&token inLexer:src];
            break;
        }

        UDMaterialTextNode *node = [self noteToken:&token inLexer:src kind:UDMaterialTextKeyword];

        //BSM Nerve: Added for stage naming in the material editor
        if( UDTokenIcmp( &token, "name") ) {
            const char *rest = [src scriptPointer];
            [src skipRestOfLine:NULL];
            // MaterialDoc::ParseStage's: the rest of the line, its quotes off
            NSMutableString *name = [[[NSString alloc] initWithBytes:rest length:(NSUInteger)( [src scriptPointer] - rest )
                                                            encoding:NSUTF8StringEncoding] mutableCopy] ?: [NSMutableString string];
            NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            while ( [trimmed hasSuffix:@"\""] ) trimmed = [trimmed substringToIndex:trimmed.length - 1];
            while ( [trimmed hasPrefix:@"\""] ) trimmed = [trimmed substringFromIndex:1];
            node.value = trimmed;
            continue;
        }

        // image options
        if ( UDTokenIcmp( &token, "blend" ) ) {
            [self parseBlend:src stage:ss];
            continue;
        }

        if (  UDTokenIcmp( &token, "map" ) ) {
            str = [UDImageProgram parsePastImageProgram:src];
            UDCopyName( imageName, str );
            continue;
        }

        if (  UDTokenIcmp( &token, "remoteRenderMap" ) ) {
            ts->dynamic = DI_REMOTE_RENDER;
            [src parseInt:&ts->width error:NULL];
            [src parseInt:&ts->height error:NULL];
            continue;
        }

        if (  UDTokenIcmp( &token, "mirrorRenderMap" ) ) {
            ts->dynamic = DI_MIRROR_RENDER;
            [src parseInt:&ts->width error:NULL];
            [src parseInt:&ts->height error:NULL];
            ts->texgen = TG_SCREEN;
            continue;
        }

        if (  UDTokenIcmp( &token, "xrayRenderMap" ) ) {
            ts->dynamic = DI_XRAY_RENDER;
            [src parseInt:&ts->width error:NULL];
            [src parseInt:&ts->height error:NULL];
            ts->texgen = TG_SCREEN;
            continue;
        }
        if (  UDTokenIcmp( &token, "screen" ) ) {
            ts->texgen = TG_SCREEN;
            continue;
        }
        if (  UDTokenIcmp( &token, "screen2" ) ) {
            ts->texgen = TG_SCREEN2;
            continue;
        }
        if (  UDTokenIcmp( &token, "glassWarp" ) ) {
            ts->texgen = TG_GLASSWARP;
            continue;
        }

        if ( UDTokenIcmp( &token, "videomap" ) ) {
            // note that videomaps will always be in clamp mode, so texture
            // coordinates had better be in the 0 to 1 range
            if ( ![src readToken:&token error:NULL] ) {
                [self commonWarning:@"missing parameter for 'videoMap' keyword in material '%@'", self.name];
                continue;
            }
            if ( UDTokenIcmp( &token, "loop" ) ) {
                if ( ![src readToken:&token error:NULL] ) {
                    [self commonWarning:@"missing parameter for 'videoMap' keyword in material '%@'", self.name];
                    continue;
                }
            }
            // idCinematic::Alloc(); InitFromFile( token, loop )
            ts->cinematic = YES;
            UDCopyName( ts->cinematicName, UDTokenString( &token ) );
            continue;
        }

        if ( UDTokenIcmp( &token, "soundmap" ) ) {
            if ( ![src readToken:&token error:NULL] ) {
                [self commonWarning:@"missing parameter for 'soundmap' keyword in material '%@'", self.name];
                continue;
            }
            // new idSndWindow(); InitFromFile( token, true )
            ts->cinematic = YES;
            UDCopyName( ts->cinematicName, UDTokenString( &token ) );
            continue;
        }

        if ( UDTokenIcmp( &token, "cubeMap" ) ) {
            str = [UDImageProgram parsePastImageProgram:src];
            UDCopyName( imageName, str );
            cubeMap = CF_NATIVE;
            continue;
        }

        if ( UDTokenIcmp( &token, "cameraCubeMap" ) ) {
            str = [UDImageProgram parsePastImageProgram:src];
            UDCopyName( imageName, str );
            cubeMap = CF_CAMERA;
            continue;
        }

        if ( UDTokenIcmp( &token, "ignoreAlphaTest" ) ) {
            ss->ignoreAlphaTest = YES;
            continue;
        }
        if ( UDTokenIcmp( &token, "nearest" ) ) {
            tf = TF_NEAREST;
            continue;
        }
        if ( UDTokenIcmp( &token, "linear" ) ) {
            tf = TF_LINEAR;
            continue;
        }
        if ( UDTokenIcmp( &token, "clamp" ) ) {
            trp = TR_CLAMP;
            continue;
        }
        if ( UDTokenIcmp( &token, "noclamp" ) ) {
            trp = TR_REPEAT;
            continue;
        }
        if ( UDTokenIcmp( &token, "zeroclamp" ) ) {
            trp = TR_CLAMP_TO_ZERO;
            continue;
        }
        if ( UDTokenIcmp( &token, "alphazeroclamp" ) ) {
            trp = TR_CLAMP_TO_ZERO_ALPHA;
            continue;
        }
        if ( UDTokenIcmp( &token, "uncompressed" ) || UDTokenIcmp( &token, "highquality" ) ) {
            if ( !image_ignoreHighQuality ) {
                td = TD_HIGH_QUALITY;
            }
            continue;
        }
        if ( UDTokenIcmp( &token, "forceHighQuality" ) ) {
            td = TD_HIGH_QUALITY;
            continue;
        }
        if ( UDTokenIcmp( &token, "nopicmip" ) ) {
            allowPicmip = NO;
            continue;
        }
        if ( UDTokenIcmp( &token, "vertexColor" ) ) {
            ss->vertexColor = SVC_MODULATE;
            continue;
        }
        if ( UDTokenIcmp( &token, "inverseVertexColor" ) ) {
            ss->vertexColor = SVC_INVERSE_MODULATE;
            continue;
        }

        // privatePolygonOffset
        else if ( UDTokenIcmp( &token, "privatePolygonOffset" ) ) {
            if ( ![src readTokenOnLine:&token error:NULL] ) {
                ss->privatePolygonOffset = 1;
                continue;
            }
            // explict larger (or negative) offset
            [src unreadToken:&token error:NULL];
            [src parseFloat:&ss->privatePolygonOffset error:NULL];
            continue;
        }

        // texture coordinate generation
        if ( UDTokenIcmp( &token, "texGen" ) ) {
            [src expectAnyToken:&token error:NULL];
            if ( UDTokenIcmp( &token, "normal" ) ) {
                ts->texgen = TG_DIFFUSE_CUBE;
            } else if ( UDTokenIcmp( &token, "reflect" ) ) {
                ts->texgen = TG_REFLECT_CUBE;
            } else if ( UDTokenIcmp( &token, "skybox" ) ) {
                ts->texgen = TG_SKYBOX_CUBE;
            } else if ( UDTokenIcmp( &token, "wobbleSky" ) ) {
                ts->texgen = TG_WOBBLESKY_CUBE;
                texGenRegisters[0] = [self parseExpression:src];
                texGenRegisters[1] = [self parseExpression:src];
                texGenRegisters[2] = [self parseExpression:src];
            } else {
                [self commonWarning:@"bad texGen '%s' in material %@", token.text, self.name];
                [self setMaterialFlag:MF_DEFAULTED];
            }
            continue;
        }
        if ( UDTokenIcmp( &token, "scroll" ) || UDTokenIcmp( &token, "translate" ) ) {
            a = [self parseExpression:src];
            [self matchToken:src match:@","];
            b = [self parseExpression:src];
            matrix[0][0] = [self getExpressionConstant:1];
            matrix[0][1] = [self getExpressionConstant:0];
            matrix[0][2] = a;
            matrix[1][0] = [self getExpressionConstant:0];
            matrix[1][1] = [self getExpressionConstant:1];
            matrix[1][2] = b;

            [self multiplyTextureMatrix:ts registers:matrix];
            continue;
        }
        if ( UDTokenIcmp( &token, "scale" ) ) {
            a = [self parseExpression:src];
            [self matchToken:src match:@","];
            b = [self parseExpression:src];
            // this just scales without a centering
            matrix[0][0] = a;
            matrix[0][1] = [self getExpressionConstant:0];
            matrix[0][2] = [self getExpressionConstant:0];
            matrix[1][0] = [self getExpressionConstant:0];
            matrix[1][1] = b;
            matrix[1][2] = [self getExpressionConstant:0];

            [self multiplyTextureMatrix:ts registers:matrix];
            continue;
        }
        if ( UDTokenIcmp( &token, "centerScale" ) ) {
            a = [self parseExpression:src];
            [self matchToken:src match:@","];
            b = [self parseExpression:src];
            // this subtracts 0.5, then scales, then adds 0.5
            matrix[0][0] = a;
            matrix[0][1] = [self getExpressionConstant:0];
            matrix[0][2] = [self emitOp:[self getExpressionConstant:0.5]
                                      b:[self emitOp:[self getExpressionConstant:0.5] b:a opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_SUBTRACT];
            matrix[1][0] = [self getExpressionConstant:0];
            matrix[1][1] = b;
            matrix[1][2] = [self emitOp:[self getExpressionConstant:0.5]
                                      b:[self emitOp:[self getExpressionConstant:0.5] b:b opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_SUBTRACT];

            [self multiplyTextureMatrix:ts registers:matrix];
            continue;
        }
        if ( UDTokenIcmp( &token, "shear" ) ) {
            a = [self parseExpression:src];
            [self matchToken:src match:@","];
            b = [self parseExpression:src];
            // this subtracts 0.5, then shears, then adds 0.5
            matrix[0][0] = [self getExpressionConstant:1];
            matrix[0][1] = a;
            matrix[0][2] = [self emitOp:[self getExpressionConstant:-0.5] b:a opType:OP_TYPE_MULTIPLY];
            matrix[1][0] = b;
            matrix[1][1] = [self getExpressionConstant:1];
            matrix[1][2] = [self emitOp:[self getExpressionConstant:-0.5] b:b opType:OP_TYPE_MULTIPLY];

            [self multiplyTextureMatrix:ts registers:matrix];
            continue;
        }
        if ( UDTokenIcmp( &token, "rotate" ) ) {
            int        table;
            int        sinReg, cosReg;

            // in cycles
            a = [self parseExpression:src];

            table = [self findTable:@"sinTable"];
            if ( table < 0 ) {
                [self commonWarning:@"no sinTable for rotate defined"];
                [self setMaterialFlag:MF_DEFAULTED];
                return;
            }
            sinReg = [self emitOp:table b:a opType:OP_TYPE_TABLE];

            table = [self findTable:@"cosTable"];
            if ( table < 0 ) {
                [self commonWarning:@"no cosTable for rotate defined"];
                [self setMaterialFlag:MF_DEFAULTED];
                return;
            }
            cosReg = [self emitOp:table b:a opType:OP_TYPE_TABLE];

            // this subtracts 0.5, then rotates, then adds 0.5
            matrix[0][0] = cosReg;
            matrix[0][1] = [self emitOp:[self getExpressionConstant:0] b:sinReg opType:OP_TYPE_SUBTRACT];
            matrix[0][2] = [self emitOp:[self emitOp:[self emitOp:[self getExpressionConstant:-0.5] b:cosReg opType:OP_TYPE_MULTIPLY]
                                                   b:[self emitOp:[self getExpressionConstant:0.5] b:sinReg opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_ADD]
                                      b:[self getExpressionConstant:0.5] opType:OP_TYPE_ADD];

            matrix[1][0] = sinReg;
            matrix[1][1] = cosReg;
            matrix[1][2] = [self emitOp:[self emitOp:[self emitOp:[self getExpressionConstant:-0.5] b:sinReg opType:OP_TYPE_MULTIPLY]
                                                   b:[self emitOp:[self getExpressionConstant:-0.5] b:cosReg opType:OP_TYPE_MULTIPLY] opType:OP_TYPE_ADD]
                                      b:[self getExpressionConstant:0.5] opType:OP_TYPE_ADD];

            [self multiplyTextureMatrix:ts registers:matrix];
            continue;
        }

        // color mask options
        if ( UDTokenIcmp( &token, "maskRed" ) ) {
            ss->drawStateBits |= GLS_REDMASK;
            continue;
        }
        if ( UDTokenIcmp( &token, "maskGreen" ) ) {
            ss->drawStateBits |= GLS_GREENMASK;
            continue;
        }
        if ( UDTokenIcmp( &token, "maskBlue" ) ) {
            ss->drawStateBits |= GLS_BLUEMASK;
            continue;
        }
        if ( UDTokenIcmp( &token, "maskAlpha" ) ) {
            ss->drawStateBits |= GLS_ALPHAMASK;
            continue;
        }
        if ( UDTokenIcmp( &token, "maskColor" ) ) {
            ss->drawStateBits |= GLS_COLORMASK;
            continue;
        }
        if ( UDTokenIcmp( &token, "maskDepth" ) ) {
            ss->drawStateBits |= GLS_DEPTHMASK;
            continue;
        }
        if ( UDTokenIcmp( &token, "ignoreDepth" ) ) { // Added in #3877.
            ss->drawStateBits |= GLS_DEPTHFUNC_ALWAYS;
            continue;
        }
        if ( UDTokenIcmp( &token, "alphaTest" ) ) {
            ss->hasAlphaTest = YES;
            ss->alphaTestRegister = [self parseExpression:src];
            coverage = MC_PERFORATED;
            continue;
        }

        // shorthand for 2D modulated
        if ( UDTokenIcmp( &token, "colored" ) ) {
            ss->color.registers[0] = EXP_REG_PARM0;
            ss->color.registers[1] = EXP_REG_PARM1;
            ss->color.registers[2] = EXP_REG_PARM2;
            ss->color.registers[3] = EXP_REG_PARM3;
            pd->registersAreConstant = NO;
            continue;
        }

        if ( UDTokenIcmp( &token, "color" ) ) {
            ss->color.registers[0] = [self parseExpression:src];
            [self matchToken:src match:@","];
            ss->color.registers[1] = [self parseExpression:src];
            [self matchToken:src match:@","];
            ss->color.registers[2] = [self parseExpression:src];
            [self matchToken:src match:@","];
            ss->color.registers[3] = [self parseExpression:src];
            continue;
        }
        if ( UDTokenIcmp( &token, "red" ) ) {
            ss->color.registers[0] = [self parseExpression:src];
            continue;
        }
        if ( UDTokenIcmp( &token, "green" ) ) {
            ss->color.registers[1] = [self parseExpression:src];
            continue;
        }
        if ( UDTokenIcmp( &token, "blue" ) ) {
            ss->color.registers[2] = [self parseExpression:src];
            continue;
        }
        if ( UDTokenIcmp( &token, "alpha" ) ) {
            ss->color.registers[3] = [self parseExpression:src];
            continue;
        }
        if ( UDTokenIcmp( &token, "rgb" ) ) {
            ss->color.registers[0] = ss->color.registers[1] =
                ss->color.registers[2] = [self parseExpression:src];
            continue;
        }
        if ( UDTokenIcmp( &token, "rgba" ) ) {
            ss->color.registers[0] = ss->color.registers[1] =
                ss->color.registers[2] = ss->color.registers[3] = [self parseExpression:src];
            continue;
        }

        if ( UDTokenIcmp( &token, "if" ) ) {
            ss->conditionRegister = [self parseExpression:src];
            continue;
        }
        if ( UDTokenIcmp( &token, "program" ) ) {
            if ( [src readTokenOnLine:&token error:NULL] ) {
                // R_FindARBProgram( GL_VERTEX_PROGRAM_ARB, … ), and the fragment one
                UDCopyName( newStage.vertexProgram, UDTokenString( &token ) );
                UDCopyName( newStage.fragmentProgram, UDTokenString( &token ) );
            }
            continue;
        }
        if ( UDTokenIcmp( &token, "fragmentProgram" ) ) {
            if ( [src readTokenOnLine:&token error:NULL] ) {
                UDCopyName( newStage.fragmentProgram, UDTokenString( &token ) );
            }
            continue;
        }
        if ( UDTokenIcmp( &token, "vertexProgram" ) ) {
            if ( [src readTokenOnLine:&token error:NULL] ) {
                UDCopyName( newStage.vertexProgram, UDTokenString( &token ) );
            }
            continue;
        }
        if ( UDTokenIcmp( &token, "megaTexture" ) ) {
            if ( [src readTokenOnLine:&token error:NULL] ) {
                // new idMegaTexture; InitFromMegaFile( token ): its file
                UDCopyName( newStage.megaTexture, UDTokenString( &token ) );
                UDCopyName( newStage.vertexProgram, @"megaTexture.vfp" );
                UDCopyName( newStage.fragmentProgram, @"megaTexture.vfp" );
                continue;
            }
        }


        if ( UDTokenIcmp( &token, "vertexParm" ) ) {
            [self parseVertexParm:src newStage:&newStage];
            continue;
        }

        if (  UDTokenIcmp( &token, "fragmentMap" ) ) {
            [self parseFragmentMap:src newStage:&newStage];
            continue;
        }


        [self commonWarning:@"unknown token '%s' in material '%@'", token.text, self.name];
        [self setMaterialFlag:MF_DEFAULTED];
        return;
    }


    // if we are using newStage, allocate a copy of it
    if ( newStage.fragmentProgram[0] || newStage.vertexProgram[0] ) {
        ss->hasNewStage = YES;
        ss->newStage = newStage;
    }

    // successfully parsed a stage
    numStages++;

    // select a compressed depth based on what the stage is
    if ( td == TD_DEFAULT ) {
        switch( ss->lighting ) {
        case SL_BUMP:
            td = TD_BUMP;
            break;
        case SL_DIFFUSE:
            td = TD_DIFFUSE;
            break;
        case SL_SPECULAR:
            td = TD_SPECULAR;
            break;
        default:
            break;
        }
    }

    // now load the image with all the parms we parsed
    if ( imageName[0] ) {
        ts->hasImage = YES;
        ts->image = UDImageFromFile( imageName, tf, allowPicmip, trp, td, cubeMap );
    } else if ( !ts->cinematic && !ts->dynamic && !ss->hasNewStage ) {
        [self commonWarning:@"material '%@' had stage with no image", self.name];
        ts->hasImage = YES;
        ts->image = UDImageFromFile( "_default", TF_DEFAULT, YES, TR_REPEAT, TD_DEFAULT, CF_2D );   // globalImages->defaultImage
    }
}

/*
===============
idMaterial::ParseDeform
===============
*/
- (void)parseDeform:(idLexer *)src {
    idToken token;
    idToken_Init( &token );

    if ( ![src expectAnyToken:&token error:NULL] ) {
        return;
    }

    if ( UDTokenIcmp( &token, "sprite" ) ) {
        deform = DFRM_SPRITE;
        cullType = CT_TWO_SIDED;
        [self setMaterialFlag:MF_NOSHADOWS];
        return;
    }
    if ( UDTokenIcmp( &token, "tube" ) ) {
        deform = DFRM_TUBE;
        cullType = CT_TWO_SIDED;
        [self setMaterialFlag:MF_NOSHADOWS];
        return;
    }
    if ( UDTokenIcmp( &token, "flare" ) ) {
        deform = DFRM_FLARE;
        cullType = CT_TWO_SIDED;
        deformRegisters[0] = [self parseExpression:src];
        [self setMaterialFlag:MF_NOSHADOWS];
        return;
    }
    if ( UDTokenIcmp( &token, "expand" ) ) {
        deform = DFRM_EXPAND;
        deformRegisters[0] = [self parseExpression:src];
        return;
    }
    if ( UDTokenIcmp( &token, "move" ) ) {
        deform = DFRM_MOVE;
        deformRegisters[0] = [self parseExpression:src];
        return;
    }
    if ( UDTokenIcmp( &token, "turbulent" ) ) {
        deform = DFRM_TURB;

        if ( ![src expectAnyToken:&token error:NULL] ) {
            [src warning:@"deform particle missing particle name"];
            [self setMaterialFlag:MF_DEFAULTED];
            return;
        }
        // declManager->FindType( DECL_TABLE, token, true ): one no file
        // defines is made a default one, and nothing is said
        deformDecl = UDTokenString( &token );

        deformRegisters[0] = [self parseExpression:src];
        deformRegisters[1] = [self parseExpression:src];
        deformRegisters[2] = [self parseExpression:src];
        return;
    }
    if ( UDTokenIcmp( &token, "eyeBall" ) ) {
        deform = DFRM_EYEBALL;
        return;
    }
    if ( UDTokenIcmp( &token, "particle" ) ) {
        deform = DFRM_PARTICLE;
        if ( ![src expectAnyToken:&token error:NULL] ) {
            [src warning:@"deform particle missing particle name"];
            [self setMaterialFlag:MF_DEFAULTED];
            return;
        }
        // declManager->FindType( DECL_PARTICLE, token, true ): as turbulent's table
        deformDecl = UDTokenString( &token );
        return;
    }
    if ( UDTokenIcmp( &token, "particle2" ) ) {
        deform = DFRM_PARTICLE2;
        if ( ![src expectAnyToken:&token error:NULL] ) {
            [src warning:@"deform particle missing particle name"];
            [self setMaterialFlag:MF_DEFAULTED];
            return;
        }
        deformDecl = UDTokenString( &token );
        return;
    }
    [src warning:@"Bad deform type '%s'", token.text];
    [self setMaterialFlag:MF_DEFAULTED];
}


/*
==============
idMaterial::AddImplicitStages

If a material has diffuse or specular stages without any
bump stage, add an implicit _flat bumpmap stage.

If a material has a bump stage but no diffuse or specular
stage, add a _white diffuse stage.

It is valid to have either a diffuse or specular without the other.

It is valid to have a reflection map and a bump map for bumpy reflection
==============
*/
- (void)addImplicitStages:(const textureRepeat_t)trpDefault {
    BOOL hasDiffuse = NO;
    BOOL hasSpecular = NO;
    BOOL hasBump = NO;
    BOOL hasReflection = NO;

    for ( int i = 0 ; i < numStages ; i++ ) {
        if ( pd->parseStages[i].lighting == SL_BUMP ) {
            hasBump = YES;
        }
        if ( pd->parseStages[i].lighting == SL_DIFFUSE ) {
            hasDiffuse = YES;
        }
        if ( pd->parseStages[i].lighting == SL_SPECULAR ) {
            hasSpecular = YES;
        }
        if ( pd->parseStages[i].texture.texgen == TG_REFLECT_CUBE ) {
            hasReflection = YES;
        }
    }

    // if it doesn't have an interaction at all, don't add anything
    if ( !hasBump && !hasDiffuse && !hasSpecular ) {
        return;
    }

    if ( numStages == MAX_SHADER_STAGES ) {
        return;
    }

    if ( !hasBump ) {
        idLexer *newSrc = [self lexerOverBuffer:@"blend bumpmap\nmap _flat\n}\n" name:@"bumpmap"];
        [self parseStage:newSrc trpDefault:trpDefault];
        [newSrc freeSource];
    }

    if ( !hasDiffuse && !hasSpecular && !hasReflection ) {
        idLexer *newSrc = [self lexerOverBuffer:@"blend diffusemap\nmap _white\n}\n" name:@"diffusemap"];
        [self parseStage:newSrc trpDefault:trpDefault];
        [newSrc freeSource];
    }

}

/*
===============
idMaterial::SortInteractionStages

The renderer expects bump, then diffuse, then specular
There can be multiple bump maps, followed by additional
diffuse and specular stages, which allows cross-faded bump mapping.

Ambient stages can be interspersed anywhere, but they are
ignored during interactions, and all the interaction
stages are ignored during ambient drawing.
===============
*/
- (void)sortInteractionStages {
    int        j;

    for ( int i = 0 ; i < numStages ; i = j ) {
        // find the next bump map
        for ( j = i + 1 ; j < numStages ; j++ ) {
            if ( pd->parseStages[j].lighting == SL_BUMP ) {
                // if the very first stage wasn't a bumpmap,
                // this bumpmap is part of the first group
                if ( pd->parseStages[i].lighting != SL_BUMP ) {
                    continue;
                }
                break;
            }
        }

        // bubble sort everything bump / diffuse / specular
        for ( int l = 1 ; l < j-i ; l++ ) {
            for ( int k = i ; k < j-l ; k++ ) {
                if ( pd->parseStages[k].lighting > pd->parseStages[k+1].lighting ) {
                    shaderStage_t    temp;

                    temp = pd->parseStages[k];
                    pd->parseStages[k] = pd->parseStages[k+1];
                    pd->parseStages[k+1] = temp;
                }
            }
        }
    }
}

/*
=================
idMaterial::ParseMaterial

The current text pointer is at the explicit text definition of the
Parse it into the global material variable. Later functions will optimize it.

If there is any error during parsing, defaultShader will be set.
=================
*/
- (void)parseMaterial:(idLexer *)src {
    idToken        token;
    NSString    *str;
    int            i;
    idToken_Init( &token );

    numOps = 0;
    numRegisters = EXP_REG_NUM_PREDEFINED;    // leave space for the parms to be copied in
    for ( i = 0 ; i < numRegisters ; i++ ) {
        pd->registerIsTemporary[i] = YES;        // they aren't constants that can be folded
    }

    numStages = 0;

    textureRepeat_t    trpDefault = TR_REPEAT;        // allow a global setting for repeat

    while ( 1 ) {
        if ( [self testMaterialFlag:MF_DEFAULTED] ) {    // we have a parse error
            return;
        }
        if ( ![src expectAnyToken:&token error:NULL] ) {
            [self setMaterialFlag:MF_DEFAULTED];
            return;
        }

        // end of material definition
        if ( UDTokenIs( &token, "}" ) ) {
            [self noteClose:&token inLexer:src];
            break;
        }

        UDMaterialTextNode *node = [self noteToken:&token inLexer:src
                                              kind:UDTokenIs( &token, "{" ) ? UDMaterialTextStage : UDMaterialTextKeyword];

        if ( UDTokenIcmp( &token, "qer_editorimage") ) {
            [src readTokenOnLine:&token error:NULL];
            editorImageName = UDTokenString( &token );
            node.value = editorImageName;
            [src skipRestOfLine:NULL];
            continue;
        }
        // description
        else if ( UDTokenIcmp( &token, "description") ) {
            [src readTokenOnLine:&token error:NULL];
            desc = UDTokenString( &token );
            node.value = desc;
            continue;
        }
        // check for the surface / content bit flags
        else if ( [self checkSurfaceParm:&token] ) {
            continue;
        }


        // polygonOffset
        else if ( UDTokenIcmp( &token, "polygonOffset" ) ) {
            [self setMaterialFlag:MF_POLYGONOFFSET];
            if ( ![src readTokenOnLine:&token error:NULL] ) {
                polygonOffset = 1;
                continue;
            }
            // explict larger (or negative) offset
            polygonOffset = idToken_FloatValue( &token );
            continue;
        }
        // noshadow
        else if ( UDTokenIcmp( &token, "noShadows" ) ) {
            [self setMaterialFlag:MF_NOSHADOWS];
            continue;
        }
        else if ( UDTokenIcmp( &token, "suppressInSubview" ) ) {
            suppressInSubview = YES;
            continue;
        }
        else if ( UDTokenIcmp( &token, "portalSky" ) ) {
            portalSky = YES;
            continue;
        }
        // noSelfShadow
        else if ( UDTokenIcmp( &token, "noSelfShadow" ) ) {
            [self setMaterialFlag:MF_NOSELFSHADOW];
            continue;
        }
        // noPortalFog
        else if ( UDTokenIcmp( &token, "noPortalFog" ) ) {
            [self setMaterialFlag:MF_NOPORTALFOG];
            continue;
        }
        // forceShadows allows nodraw surfaces to cast shadows
        else if ( UDTokenIcmp( &token, "forceShadows" ) ) {
            [self setMaterialFlag:MF_FORCESHADOWS];
            continue;
        }
        // overlay / decal suppression
        else if ( UDTokenIcmp( &token, "noOverlays" ) ) {
            allowOverlays = NO;
            continue;
        }
        // moster blood overlay forcing for alpha tested or translucent surfaces
        else if ( UDTokenIcmp( &token, "forceOverlays" ) ) {
            pd->forceOverlays = YES;
            continue;
        }
        // translucent
        else if ( UDTokenIcmp( &token, "translucent" ) ) {
            coverage = MC_TRANSLUCENT;
            continue;
        }
        // global zero clamp
        else if ( UDTokenIcmp( &token, "zeroclamp" ) ) {
            trpDefault = TR_CLAMP_TO_ZERO;
            continue;
        }
        // global clamp
        else if ( UDTokenIcmp( &token, "clamp" ) ) {
            trpDefault = TR_CLAMP;
            continue;
        }
        // global clamp
        else if ( UDTokenIcmp( &token, "alphazeroclamp" ) ) {
            trpDefault = TR_CLAMP_TO_ZERO;
            continue;
        }
        // forceOpaque is used for skies-behind-windows
        else if ( UDTokenIcmp( &token, "forceOpaque" ) ) {
            coverage = MC_OPAQUE;
            continue;
        }
        // twoSided
        else if ( UDTokenIcmp( &token, "twoSided" ) ) {
            cullType = CT_TWO_SIDED;
            // twoSided implies no-shadows, because the shadow
            // volume would be coplanar with the surface, giving depth fighting
            // we could make this no-self-shadows, but it may be more important
            // to receive shadows from no-self-shadow monsters
            [self setMaterialFlag:MF_NOSHADOWS];
        }
        // backSided
        else if ( UDTokenIcmp( &token, "backSided" ) ) {
            cullType = CT_BACK_SIDED;
            // the shadow code doesn't handle this, so just disable shadows.
            // We could fix this in the future if there was a need.
            [self setMaterialFlag:MF_NOSHADOWS];
        }
        // foglight
        else if ( UDTokenIcmp( &token, "fogLight" ) ) {
            fogLight = YES;
            continue;
        }
        // blendlight
        else if ( UDTokenIcmp( &token, "blendLight" ) ) {
            blendLight = YES;
            continue;
        }
        // ambientLight
        else if ( UDTokenIcmp( &token, "ambientLight" ) ) {
            ambientLight = YES;
            continue;
        }
        // mirror
        else if ( UDTokenIcmp( &token, "mirror" ) ) {
            sort = SS_SUBVIEW;
            coverage = MC_OPAQUE;
            continue;
        }
        // noFog
        else if ( UDTokenIcmp( &token, "noFog" ) ) {
            noFog = YES;
            continue;
        }
        // unsmoothedTangents
        else if ( UDTokenIcmp( &token, "unsmoothedTangents" ) ) {
            unsmoothedTangents = YES;
            continue;
        }
        // lightFallofImage <imageprogram>
        // specifies the image to use for the third axis of projected
        // light volumes
        else if ( UDTokenIcmp( &token, "lightFalloffImage" ) ) {
            str = [UDImageProgram parsePastImageProgram:src];
            NSString    *copy;

            copy = str;    // so other things don't step on it
            hasLightFalloffImage = YES;
            lightFalloffImage = UDImageFromFile( copy.UTF8String ?: "", TF_DEFAULT, NO, TR_CLAMP /* TR_CLAMP_TO_ZERO */, TD_DEFAULT, CF_2D );
            continue;
        }
        // guisurf <guifile> | guisurf entity
        // an entity guisurf must have an idUserInterface
        // specified in the renderEntity
        else if ( UDTokenIcmp( &token, "guisurf" ) ) {
            [src readTokenOnLine:&token error:NULL];
            if ( UDTokenIcmp( &token, "entity" ) ) {
                entityGui = 1;
            } else if ( UDTokenIcmp( &token, "entity2" ) ) {
                entityGui = 2;
            } else if ( UDTokenIcmp( &token, "entity3" ) ) {
                entityGui = 3;
            } else {
                // uiManager->FindGui( token, true )
                gui = UDTokenString( &token );
            }
            continue;
        }
        // sort
        else if ( UDTokenIcmp( &token, "sort" ) ) {
            [self parseSort:src];
            continue;
        }
        // spectrum <integer>
        else if ( UDTokenIcmp( &token, "spectrum" ) ) {
            [src readTokenOnLine:&token error:NULL];
            spectrum = atoi( token.text );
            continue;
        }
        // deform < sprite | tube | flare >
        else if ( UDTokenIcmp( &token, "deform" ) ) {
            [self parseDeform:src];
            continue;
        }
        // decalInfo <staySeconds> <fadeSeconds> ( <start rgb> ) ( <end rgb> )
        else if ( UDTokenIcmp( &token, "decalInfo" ) ) {
            [self parseDecalInfo:src];
            continue;
        }
        // renderbump <args...>
        else if ( UDTokenIcmp( &token, "renderbump") ) {
            NSMutableString *rest = [NSMutableString string];
            [src parseRestOfLine:rest error:NULL];
            renderBump = rest;
            continue;
        }
        // diffusemap for stage shortcut
        else if ( UDTokenIcmp( &token, "diffusemap" ) ) {
            str = [UDImageProgram parsePastImageProgram:src];
            NSString *buffer = [NSString stringWithFormat:@"blend diffusemap\nmap %@\n}\n", str];
            idLexer *newSrc = [self lexerOverBuffer:buffer name:@"diffusemap"];
            textStages++;
            [self parseStage:newSrc trpDefault:trpDefault];
            pd->parseStages[MIN( numStages, MAX_SHADER_STAGES ) - 1].textIndex = textStages - 1;
            [newSrc freeSource];
            continue;
        }
        // specularmap for stage shortcut
        else if ( UDTokenIcmp( &token, "specularmap" ) ) {
            str = [UDImageProgram parsePastImageProgram:src];
            NSString *buffer = [NSString stringWithFormat:@"blend specularmap\nmap %@\n}\n", str];
            idLexer *newSrc = [self lexerOverBuffer:buffer name:@"specularmap"];
            textStages++;
            [self parseStage:newSrc trpDefault:trpDefault];
            pd->parseStages[MIN( numStages, MAX_SHADER_STAGES ) - 1].textIndex = textStages - 1;
            [newSrc freeSource];
            continue;
        }
        // normalmap for stage shortcut
        else if ( UDTokenIcmp( &token, "bumpmap" ) ) {
            str = [UDImageProgram parsePastImageProgram:src];
            NSString *buffer = [NSString stringWithFormat:@"blend bumpmap\nmap %@\n}\n", str];
            idLexer *newSrc = [self lexerOverBuffer:buffer name:@"bumpmap"];
            textStages++;
            [self parseStage:newSrc trpDefault:trpDefault];
            pd->parseStages[MIN( numStages, MAX_SHADER_STAGES ) - 1].textIndex = textStages - 1;
            [newSrc freeSource];
            continue;
        }
        // DECAL_MACRO for backwards compatibility with the preprocessor macros
        else if ( UDTokenIcmp( &token, "DECAL_MACRO" ) ) {
            // polygonOffset
            [self setMaterialFlag:MF_POLYGONOFFSET];
            polygonOffset = 1;

            // discrete
            surfaceFlags |= SURF_DISCRETE;
            contentFlags &= ~CONTENTS_SOLID;

            // sort decal
            sort = SS_DECAL;

            // noShadows
            [self setMaterialFlag:MF_NOSHADOWS];
            continue;
        }
        else if ( UDTokenIs( &token, "{" ) ) {
            // create the new stage
            [self parseStage:src trpDefault:trpDefault];
            continue;
        }
        else {
            [self commonWarning:@"unknown general material parameter '%s' in '%@'", token.text, self.name];
            [self setMaterialFlag:MF_DEFAULTED];
            return;
        }
    }

    // add _flat or _white stages if needed
    [self addImplicitStages:TR_REPEAT];

    // order the diffuse / bump / specular stages properly
    [self sortInteractionStages];

    // if we need to do anything with normals (lighting or environment mapping)
    // and two sided lighting was asked for, flag
    // shouldCreateBackSides() and change culling back to single sided,
    // so we get proper tangent vectors on both sides

    // we can't just call ReceivesLighting(), because the stages are still
    // in temporary form
    if ( cullType == CT_TWO_SIDED ) {
        for ( i = 0 ; i < numStages ; i++ ) {
            if ( pd->parseStages[i].lighting != SL_AMBIENT || pd->parseStages[i].texture.texgen != TG_EXPLICIT ) {
                if ( cullType == CT_TWO_SIDED ) {
                    cullType = CT_FRONT_SIDED;
                    shouldCreateBackSides = YES;
                }
                break;
            }
        }
    }

    // currently a surface can only have one unique texgen for all the stages on old hardware
    texgen_t firstGen = TG_EXPLICIT;
    for ( i = 0; i < numStages; i++ ) {
        if ( pd->parseStages[i].texture.texgen != TG_EXPLICIT ) {
            if ( firstGen == TG_EXPLICIT ) {
                firstGen = pd->parseStages[i].texture.texgen;
            } else if ( firstGen != pd->parseStages[i].texture.texgen ) {
                [self commonWarning:@"material '%@' has multiple stages with a texgen", self.name];
                break;
            }
        }
    }
}

/*
=========================
idMaterial::Parse

Parses the current material definition and finds all necessary images.
=========================
*/
- (BOOL)parse:(NSString *)text {
    idLexer    *src;
    mtrParsingData_t *parsingData;

    textData = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    // LoadMemory( text, …, GetFileName(), GetLineNum() ); SetFlags( DECL_LEXER_FLAGS );
    // SkipUntilString( "{" ): the codec lexer's.
    src = UDDeclCodecLexerWithFlags( textData, self.name, self.name, 1, DECL_LEXER_FLAGS, nil, NULL );
    if ( src == nil ) {
        [self commonInit];
        [self setMaterialFlag:MF_DEFAULTED];
        self.body = @[];
        self.closing = @"";
        return NO;
    }
    src.diagnostics = self.diagnostics;
    self.mainSrc = src;
    self.bodyNodes = [NSMutableArray array];
    self.containers = [NSMutableArray arrayWithObject:self.bodyNodes];
    self.openStages = [NSMutableArray array];

    // reset to the unparsed state
    [self commonInit];

    parsingData = (mtrParsingData_t *)calloc( 1, sizeof( *parsingData ) );

    pd = parsingData;    // this is only valid during parse

    // parse it
    [self parseMaterial:src];

    // what the parse did not get through
    if ( [self testMaterialFlag:MF_DEFAULTED] ) {
        [self noteUnparsedRest];
    }

    //
    // count non-lit stages
    numAmbientStages = 0;
    int i;
    for ( i = 0 ; i < numStages ; i++ ) {
        if ( pd->parseStages[i].lighting == SL_AMBIENT ) {
            numAmbientStages++;
        }
    }

    // see if there is a subview stage
    if ( sort == SS_SUBVIEW ) {
        hasSubview = YES;
    } else {
        hasSubview = NO;
        for ( i = 0 ; i < numStages ; i++ ) {
            if ( pd->parseStages[i].texture.dynamic ) {
                hasSubview = YES;
            }
        }
    }

    // automatically determine coverage if not explicitly set
    if ( coverage == MC_BAD ) {
        // automatically set MC_TRANSLUCENT if we don't have any interaction stages and
        // the first stage is blended and not an alpha test mask or a subview
        if ( !numStages ) {
            // non-visible
            coverage = MC_TRANSLUCENT;
        } else if ( numStages != numAmbientStages ) {
            // we have an interaction draw
            coverage = MC_OPAQUE;
        } else if (
            ( pd->parseStages[0].drawStateBits & GLS_DSTBLEND_BITS ) != GLS_DSTBLEND_ZERO ||
            ( pd->parseStages[0].drawStateBits & GLS_SRCBLEND_BITS ) == GLS_SRCBLEND_DST_COLOR ||
            ( pd->parseStages[0].drawStateBits & GLS_SRCBLEND_BITS ) == GLS_SRCBLEND_ONE_MINUS_DST_COLOR ||
            ( pd->parseStages[0].drawStateBits & GLS_SRCBLEND_BITS ) == GLS_SRCBLEND_DST_ALPHA ||
            ( pd->parseStages[0].drawStateBits & GLS_SRCBLEND_BITS ) == GLS_SRCBLEND_ONE_MINUS_DST_ALPHA
            ) {
            // blended with the destination
                coverage = MC_TRANSLUCENT;
        } else {
            coverage = MC_OPAQUE;
        }
    }

    // translucent automatically implies noshadows
    if ( coverage == MC_TRANSLUCENT ) {
        [self setMaterialFlag:MF_NOSHADOWS];
    } else {
        // mark the contents as opaque
        contentFlags |= CONTENTS_OPAQUE;
    }

    // if we are translucent, draw with an alpha in the editor
    if ( coverage == MC_TRANSLUCENT ) {
        editorAlpha = 0.5;
    } else {
        editorAlpha = 1.0;
    }

    // the sorts can make reasonable defaults
    if ( sort == SS_BAD ) {
        if ( [self testMaterialFlag:MF_POLYGONOFFSET] ) {
            sort = SS_DECAL;
        } else if ( coverage == MC_TRANSLUCENT ) {
            sort = SS_MEDIUM;
        } else {
            sort = SS_OPAQUE;
        }
    }

    // anything that references _currentRender will automatically get sort = SS_POST_PROCESS
    // and coverage = MC_TRANSLUCENT

    for ( i = 0 ; i < numStages ; i++ ) {
        shaderStage_t    *pStage = &pd->parseStages[i];
        if ( pStage->texture.hasImage && !strcasecmp( pStage->texture.image.name, "_currentRender" ) ) {
            if ( sort != SS_PORTAL_SKY ) {
                sort = SS_POST_PROCESS;
                coverage = MC_TRANSLUCENT;
            }
            break;
        }
        if ( pStage->hasNewStage ) {
            for ( int j = 0 ; j < pStage->newStage.numFragmentProgramImages ; j++ ) {
                if ( !strcasecmp( pStage->newStage.fragmentProgramImages[j].name, "_currentRender" ) ) {
                    if ( sort != SS_PORTAL_SKY ) {
                        sort = SS_POST_PROCESS;
                        coverage = MC_TRANSLUCENT;
                    }
                    i = numStages;
                    break;
                }
            }
        }
    }

    // set the drawStateBits depth flags
    for ( i = 0 ; i < numStages ; i++ ) {
        shaderStage_t    *pStage = &pd->parseStages[i];
        if ( sort == SS_POST_PROCESS ) {
            // post-process effects fill the depth buffer as they draw, so only the
            // topmost post-process effect is rendered
            pStage->drawStateBits |= GLS_DEPTHFUNC_LESS;
        } else if ( coverage == MC_TRANSLUCENT || pStage->ignoreAlphaTest ) {
            // translucent surfaces can extend past the exactly marked depth buffer
            pStage->drawStateBits |= GLS_DEPTHFUNC_LESS | GLS_DEPTHMASK;
        } else {
            // opaque and perforated surfaces must exactly match the depth buffer,
            // which gets alpha test correct
            pStage->drawStateBits |= GLS_DEPTHFUNC_EQUAL | GLS_DEPTHMASK;
        }
    }

    // determine if this surface will accept overlays / decals

    if ( pd->forceOverlays ) {
        // explicitly flaged in material definition
        allowOverlays = YES;
    } else {
        if ( !( numStages > 0 || entityGui != 0 || gui != nil ) ) {    // !IsDrawn()
            allowOverlays = NO;
        }
        if ( coverage != MC_OPAQUE ) {
            allowOverlays = NO;
        }
        if ( surfaceFlags & SURF_NOIMPACT ) {
            allowOverlays = NO;
        }
    }

    if (numStages) {
        stages = (shaderStage_t *)malloc( numStages * sizeof( stages[0] ) );
        memcpy( stages, pd->parseStages, numStages * sizeof( stages[0] ) );
    }

    if ( numOps ) {
        ops = (expOp_t *)malloc( numOps * sizeof( ops[0] ) );
        memcpy( ops, pd->shaderOps, numOps * sizeof( ops[0] ) );
    }

    if ( numRegisters ) {
        expressionRegisters = (float *)malloc( numRegisters * sizeof( expressionRegisters[0] ) );
        memcpy( expressionRegisters, pd->shaderRegisters, numRegisters * sizeof( expressionRegisters[0] ) );
    }

    // see if the registers are completely constant, and don't need to be evaluated
    // per-surface
    [self checkForConstantRegisters];

    pd = NULL;    // the pointer will be invalid after exiting this function
    free( parsingData );

    // the text it went through
    NSInteger restEnd = self.restEnd;
    NSInteger bodyEnd = self.bodyClosed || restEnd >= 0 ? self.bodyClosingStart : (NSInteger)textData.length;
    [self finishNodes:self.bodyNodes until:bodyEnd];
    self.body = self.bodyNodes;
    self.closing = self.bodyClosed ? [self sliceFrom:self.bodyClosingStart to:self.bodyClosingEnd] : @"";

    // finish things up
    if ( [self testMaterialFlag:MF_DEFAULTED] ) {
        // MakeDefault(): the decl manager's default text, parsed
        return NO;
    }
    return YES;
}

/*
===================
idDeclTable::TableLookup
===================
*/
- (float)tableLookup:(int)tableIndex index:(float)index {
    if ( tableIndex < 0 || (NSUInteger)tableIndex >= tables.count ) {
        return 1.0f;
    }
    UDDeclTable *decl = nil;
    NSDictionary *parsed = nil;
    idDeclBase *base = [self.declManager findDeclWithoutParsing:DECL_TABLE name:tables[tableIndex] makeDefault:NO];
    if ( base != nil ) {
        NSMutableData *buffer = [NSMutableData data];
        [base text:buffer];
        if ( buffer.length > 0 ) [buffer setLength:buffer.length - 1];
        parsed = [UDDeclTable ud_parseValuesFromText:buffer name:tables[tableIndex] fileName:nil lineNum:1 fileSystem:nil error:NULL];
    }
    (void)decl;
    NSArray *read = [parsed[@"values"] valueForKey:@"number"] ?: @[];
    BOOL clamp = [parsed[@"clamp"] boolValue];
    BOOL snap = [parsed[@"snap"] boolValue];
    // copy the 0 element to the end, so lerping doesn't
    // need to worry about the wrap case (idDeclTable::Parse)
    NSMutableArray<NSNumber *> *values = [read mutableCopy];
    if ( values.count > 0 ) [values addObject:values[0]];

    int iIndex;
    float iFrac;

    int domain = (int)values.count - 1;

    if ( domain <= 1 ) {
        return 1.0f;
    }

    if ( clamp ) {
        index *= (domain-1);
        if ( index >= domain - 1 ) {
            return values[domain - 1].floatValue;
        } else if ( index <= 0 ) {
            return values[0].floatValue;
        }
        iIndex = (int)index;                                       // idMath::Ftoi
        iFrac = index - iIndex;
    } else {
        index *= domain;

        if ( index < 0 ) {
            index += domain * ceilf( -index / domain );
        }

        iIndex = (int)floorf( index );                              // idMath::FtoiFast( idMath::Floor( index ) )
        iFrac = index - iIndex;
        iIndex = iIndex % domain;
    }

    if ( !snap ) {
        // we duplicated the 0 index at the end at creation time, so we
        // don't need to worry about wrapping the filter
        return values[iIndex].floatValue * ( 1.0f - iFrac ) + values[iIndex + 1].floatValue * iFrac;
    }

    return values[iIndex].floatValue;
}

/*
===============
idMaterial::EvaluateRegisters

Parameters are taken from the localSpace and the renderView,
then all expressions are evaluated, leaving the material registers
set to their apropriate values.
===============
*/
- (void)evaluateRegisters:(float *)registers shaderParms:(const float *)shaderParms
                floatTime:(float)floatTime globalParms:(const float *)globalParms {
    int        i, b;
    expOp_t    *op;

    // copy the material constants
    for ( i = EXP_REG_NUM_PREDEFINED ; i < numRegisters ; i++ ) {
        registers[i] = expressionRegisters[i];
    }

    // copy the local and global parameters
    registers[EXP_REG_TIME] = floatTime;
    registers[EXP_REG_PARM0] = shaderParms[0];
    registers[EXP_REG_PARM1] = shaderParms[1];
    registers[EXP_REG_PARM2] = shaderParms[2];
    registers[EXP_REG_PARM3] = shaderParms[3];
    registers[EXP_REG_PARM4] = shaderParms[4];
    registers[EXP_REG_PARM5] = shaderParms[5];
    registers[EXP_REG_PARM6] = shaderParms[6];
    registers[EXP_REG_PARM7] = shaderParms[7];
    registers[EXP_REG_PARM8] = shaderParms[8];
    registers[EXP_REG_PARM9] = shaderParms[9];
    registers[EXP_REG_PARM10] = shaderParms[10];
    registers[EXP_REG_PARM11] = shaderParms[11];
    registers[EXP_REG_GLOBAL0] = globalParms[0];
    registers[EXP_REG_GLOBAL1] = globalParms[1];
    registers[EXP_REG_GLOBAL2] = globalParms[2];
    registers[EXP_REG_GLOBAL3] = globalParms[3];
    registers[EXP_REG_GLOBAL4] = globalParms[4];
    registers[EXP_REG_GLOBAL5] = globalParms[5];
    registers[EXP_REG_GLOBAL6] = globalParms[6];
    registers[EXP_REG_GLOBAL7] = globalParms[7];

    op = ops;
    for ( i = 0 ; i < numOps ; i++, op++ ) {
        switch( op->opType ) {
        case OP_TYPE_ADD:
            registers[op->c] = registers[op->a] + registers[op->b];
            break;
        case OP_TYPE_SUBTRACT:
            registers[op->c] = registers[op->a] - registers[op->b];
            break;
        case OP_TYPE_MULTIPLY:
            registers[op->c] = registers[op->a] * registers[op->b];
            break;
        case OP_TYPE_DIVIDE:
            registers[op->c] = registers[op->a] / registers[op->b];
            break;
        case OP_TYPE_MOD:
            b = (int)registers[op->b];
            b = b != 0 ? b : 1;
            registers[op->c] = (int)registers[op->a] % b;
            break;
        case OP_TYPE_TABLE:
            {
                registers[op->c] = [self tableLookup:op->a index:registers[op->b]];
            }
            break;
        case OP_TYPE_SOUND:
            // no soundEmitter
            registers[op->c] = 0;
            break;
        case OP_TYPE_GT:
            registers[op->c] = registers[ op->a ] > registers[op->b];
            break;
        case OP_TYPE_GE:
            registers[op->c] = registers[ op->a ] >= registers[op->b];
            break;
        case OP_TYPE_LT:
            registers[op->c] = registers[ op->a ] < registers[op->b];
            break;
        case OP_TYPE_LE:
            registers[op->c] = registers[ op->a ] <= registers[op->b];
            break;
        case OP_TYPE_EQ:
            registers[op->c] = registers[ op->a ] == registers[op->b];
            break;
        case OP_TYPE_NE:
            registers[op->c] = registers[ op->a ] != registers[op->b];
            break;
        case OP_TYPE_AND:
            registers[op->c] = registers[ op->a ] && registers[op->b];
            break;
        case OP_TYPE_OR:
            registers[op->c] = registers[ op->a ] || registers[op->b];
            break;
        default:
            // common->FatalError( "R_EvaluateExpression: bad opcode" )
            break;
        }
    }

}

/*
==================
idMaterial::CheckForConstantRegisters

As of 5/2/03, about half of the unique materials loaded on typical
maps are constant, but 2/3 of the surface references are.
This is probably an optimization of dubious value.
==================
*/
- (void)checkForConstantRegisters {
    if ( !pd->registersAreConstant ) {
        return;
    }

    // evaluate the registers once, and save them
    constantRegisters = (float *)calloc( MAX( numRegisters, 1 ), sizeof( float ) );

    float shaderParms[MAX_ENTITY_SHADER_PARMS];
    memset( shaderParms, 0, sizeof( shaderParms ) );
    float globalParms[8];
    memset( globalParms, 0, sizeof( globalParms ) );

    [self evaluateRegisters:constantRegisters shaderParms:shaderParms floatTime:0 globalParms:globalParms];
}

- (NSData *)registersAtTime:(float)time {
    NSMutableData *registers = [NSMutableData dataWithLength:MAX( numRegisters, EXP_REG_NUM_PREDEFINED ) * sizeof( float )];
    float shaderParms[MAX_ENTITY_SHADER_PARMS];
    for ( int i = 0; i < MAX_ENTITY_SHADER_PARMS; i++ ) shaderParms[i] = 1;
    float globalParms[8];
    memset( globalParms, 0, sizeof( globalParms ) );
    [self evaluateRegisters:registers.mutableBytes shaderParms:shaderParms floatTime:time globalParms:globalParms];
    return registers;
}

@end
