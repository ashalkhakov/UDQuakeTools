/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idWindow.h — a GUI's windows (ui/Window.h, Window.cpp, SimpleWindow.h),
 * ported. idWindow's members are public ivars, so its friends (the scripts,
 * the simple windows, the GUI) reach them as they do in C++. What was
 * savegame and demo support is not here; nor is the GUI editor's wrapper
 * (rvGEWindowWrapper), which the editor here replaces.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"
#import "idWinVar.h"
#import "idRegExp.h"
#import "idGuiScript.h"

@class idParser, idDeviceContext, idUserInterfaceLocal, idSimpleWindow, idMaterial, idDict, idWindow;

NS_ASSUME_NONNULL_BEGIN

enum {
    WIN_CHILD           = 0x00000001,
    WIN_CAPTION         = 0x00000002,
    WIN_BORDER          = 0x00000004,
    WIN_SIZABLE         = 0x00000008,
    WIN_MOVABLE         = 0x00000010,
    WIN_FOCUS           = 0x00000020,
    WIN_CAPTURE         = 0x00000040,
    WIN_HCENTER         = 0x00000080,
    WIN_VCENTER         = 0x00000100,
    WIN_MODAL           = 0x00000200,
    WIN_INTRANSITION    = 0x00000400,
    WIN_CANFOCUS        = 0x00000800,
    WIN_SELECTED        = 0x00001000,
    WIN_TRANSFORM       = 0x00002000,
    WIN_HOLDCAPTURE     = 0x00004000,
    WIN_NOWRAP          = 0x00008000,
    WIN_NOCLIP          = 0x00010000,
    WIN_INVERTRECT      = 0x00020000,
    WIN_NATURALMAT      = 0x00040000,
    WIN_NOCURSOR        = 0x00080000,
    WIN_MENUGUI         = 0x00100000,
    WIN_ACTIVE          = 0x00200000,
    WIN_SHOWCOORDS      = 0x00400000,
    WIN_SHOWTIME        = 0x00800000,
    WIN_WANTENTER       = 0x01000000,

    WIN_DESKTOP         = 0x10000000,

    WIN_SCALETO43       = 0x20000000, // DG: for the "scaleto43" window flag (=> scale window to 4:3 with "empty" bars left/right or above/below)
};

#define CAPTION_HEIGHT      "16.0"
#define SCROLLER_SIZE       "16.0"
#define SCROLLBAR_SIZE      16

#define MAX_WINDOW_NAME     32
#define MAX_LIST_ITEMS      1024

#define MAX_EXPRESSION_OPS          4096
#define MAX_EXPRESSION_REGISTERS    4096

#define DEFAULT_BACKCOLOR   "1 1 1 1"
#define DEFAULT_FORECOLOR   "0 0 0 1"
#define DEFAULT_BORDERCOLOR "0 0 0 1"
#define DEFAULT_TEXTSCALE   "0.4"

typedef enum {
    WOP_TYPE_ADD,
    WOP_TYPE_SUBTRACT,
    WOP_TYPE_MULTIPLY,
    WOP_TYPE_DIVIDE,
    WOP_TYPE_MOD,
    WOP_TYPE_TABLE,
    WOP_TYPE_GT,
    WOP_TYPE_GE,
    WOP_TYPE_LT,
    WOP_TYPE_LE,
    WOP_TYPE_EQ,
    WOP_TYPE_NE,
    WOP_TYPE_AND,
    WOP_TYPE_OR,
    WOP_TYPE_VAR,
    WOP_TYPE_VARS,
    WOP_TYPE_VARF,
    WOP_TYPE_VARI,
    WOP_TYPE_VARB,
    WOP_TYPE_COND
} wexpOpType_t;

typedef enum {
    WEXP_REG_TIME,
    WEXP_REG_NUM_PREDEFINED
} wexpRegister_t;

/// An op: its a and b registers (a var, unretained, for the VAR ops; a
/// name, for one not found yet, b -2), c its result's, d COND's else.
typedef struct {
    wexpOpType_t opType;
    intptr_t a, b, c, d;
} wexpOp_t;

typedef struct {
    __unsafe_unretained NSString *name;
    idRegisterType type;
} idRegEntry;

/// drawWin_t: a child, a full window or a simple one.
@interface idDrawWin : NSObject
@property (nonatomic, strong, nullable) idWindow *win;
@property (nonatomic, strong, nullable) idSimpleWindow *simp;
@end

@interface idTimeLineEvent : NSObject {
@public
    int time;
    idGuiScriptList *event;
    BOOL pending;
}
@end

@interface rvNamedEvent : NSObject {
@public
    NSString *mName;
    idGuiScriptList *mEvent;
}
- (instancetype)initWithName:(NSString *)name;
@end

@interface idTransitionData : NSObject {
@public
    idWinVar *_Nullable data;
    int offset;
    idInterpolateAccelDecelLinearVec4 interp;
}
@end

enum {
    ON_MOUSEENTER = 0,
    ON_MOUSEEXIT,
    ON_ACTION,
    ON_ACTIVATE,
    ON_DEACTIVATE,
    ON_ESC,
    ON_FRAME,
    ON_TRIGGER,
    ON_ACTIONRELEASE,
    ON_ENTER,
    ON_ENTERRELEASE,
    SCRIPT_COUNT
};

enum {
    ADJUST_MOVE = 0,
    ADJUST_TOP,
    ADJUST_RIGHT,
    ADJUST_BOTTOM,
    ADJUST_LEFT,
    ADJUST_TOPLEFT,
    ADJUST_BOTTOMRIGHT,
    ADJUST_TOPRIGHT,
    ADJUST_BOTTOMLEFT
};

/// sysEvent_t, the part a GUI reads: SE_KEY (evValue the key, evValue2
/// down), SE_CHAR (evValue the character), SE_MOUSE (deltas), SE_MOUSE_ABS.
typedef enum {
    SE_NONE,
    SE_KEY,
    SE_CHAR,
    SE_MOUSE,
    SE_MOUSE_ABS,
    SE_JOYSTICK,
    SE_CONSOLE
} sysEventType_t;

typedef struct {
    sysEventType_t  evType;
    int             evValue;
    int             evValue2;
} sysEvent_t;

/// keyNum_t (framework/KeyInput.h), its keyboard and mouse keys.
typedef enum {
    K_TAB = 9,
    K_ENTER = 13,
    K_ESCAPE = 27,
    K_SPACE = 32,

    K_BACKSPACE = 127,

    K_COMMAND = 128,
    K_CAPSLOCK,
    K_SCROLL,
    K_POWER,
    K_PAUSE,

    K_UPARROW = 133,
    K_DOWNARROW,
    K_LEFTARROW,
    K_RIGHTARROW,

    // The 3 windows keys
    K_LWIN = 137,
    K_RWIN,
    K_MENU,

    K_ALT = 140,
    K_CTRL,
    K_SHIFT,
    K_INS,
    K_DEL,
    K_PGDN,
    K_PGUP,
    K_HOME,
    K_END,

    K_F1 = 149,
    K_F2,
    K_F3,
    K_F4,
    K_F5,
    K_F6,
    K_F7,
    K_F8,
    K_F9,
    K_F10,
    K_F11,
    K_F12,
    K_INVERTED_EXCLAMATION = 161,   // upside down !
    K_F13,
    K_F14,
    K_F15,

    K_KP_HOME = 165,
    K_KP_UPARROW,
    K_KP_PGUP,
    K_KP_LEFTARROW,
    K_KP_5,
    K_KP_RIGHTARROW,
    K_KP_END,
    K_KP_DOWNARROW,
    K_KP_PGDN,
    K_KP_ENTER,
    K_KP_INS,
    K_KP_DEL,
    K_KP_SLASH,
    K_SUPERSCRIPT_TWO = 178,        // superscript 2
    K_KP_MINUS,
    K_ACUTE_ACCENT = 180,           // accute accent
    K_KP_PLUS,
    K_KP_NUMLOCK,
    K_KP_STAR,
    K_KP_EQUALS,

    K_MASCULINE_ORDINATOR = 186,
    // K_MOUSE enums must be contiguous (no char codes in the middle)
    K_MOUSE1 = 187,
    K_MOUSE2,
    K_MOUSE3,
    K_MOUSE4,
    K_MOUSE5,
    K_MOUSE6,
    K_MOUSE7,
    K_MOUSE8,

    K_MWHEELDOWN = 195,
    K_MWHEELUP,
} keyNum_t;

extern NSString *_Nonnull const idWindow_ScriptNames[SCRIPT_COUNT];
extern const idRegEntry idWindow_RegisterVars[];
extern const int idWindow_NumRegisterVars;

@interface idWindow : NSObject <idWinBackgroundTarget> {
@public
    NSMutableString *cmd;

    float actualX;                  // physical coords
    float actualY;                  // ''
    int   childID;                  // this childs id
    unsigned int flags;             // visible, focus, mouseover, cursor, border, etc..
    int lastTimeRun;                //
    idRectangle drawRect;           // overall rect
    idRectangle clientRect;         // client area
    idVec2  origin;

    int timeLine;                   // time stamp used for various fx
    float xOffset;
    float yOffset;
    float forceAspectWidth;
    float forceAspectHeight;
    float matScalex;
    float matScaley;
    float borderSize;
    float textAlignx;
    float textAligny;
    NSString *name;
    NSString *comment;
    idVec2  shear;

    signed char textShadow;
    unsigned char fontNum;
    unsigned char cursor;                   //
    signed char textAlign;

    idWinBool *noTime;                  //
    idWinBool *visible;                 //
    idWinBool *noEvents;
    idWinRectangle *rect;               // overall rect
    idWinVec4 *backColor;
    idWinVec4 *matColor;
    idWinVec4 *foreColor;
    idWinVec4 *hoverColor;
    idWinVec4 *borderColor;
    idWinFloat *textScale;
    idWinFloat *rotate;
    idWinStr *text;
    idWinBackground *backGroundName;          //

    NSMutableArray<idWinVar *> *definedVars;
    NSMutableArray<idWinVar *> *updateVars;

    idRectangle textRect;           // text extented rect
    idMaterial *_Nullable background;         // background asset

    __weak idWindow *_Nullable parent;               // parent window
    NSMutableArray<idWindow *> *children;     // child windows
    NSMutableArray<idDrawWin *> *drawWindows;

    __weak idWindow *_Nullable focusedChild;         // if a child window has the focus
    __weak idWindow *_Nullable captureChild;         // if a child window has mouse capture
    __weak idWindow *_Nullable overChild;            // if a child window has mouse capture
    BOOL hover;

    idDeviceContext *_Nullable dc;

    __weak idUserInterfaceLocal *gui;

    idGuiScriptList *_Nullable scripts[SCRIPT_COUNT];
    BOOL *_Nullable saveTemps;

    NSMutableArray<idTimeLineEvent *> *timeLineEvents;
    NSMutableArray<idTransitionData *> *transitions;

    // ops: evaluate to make expressionRegisters
    wexpOp_t *ops;
    int numOps, maxOps;
    float *expressionRegisters;
    int numExpressionRegisters, maxExpressionRegisters;
    NSMutableArray<rvNamedEvent *> *namedEvents;        //  added named events

    idRegisterList *regList;

    idWinBool *hideCursor;

    //#modified-fva; BEGIN
    idWinInt *cstAnchor;
    idWinInt *cstAnchorTo;          // for anchor transitions
    idWinFloat *cstAnchorFactor;    // for anchor transitions
    BOOL cstNoClipBackground;
    //#modified-fva; END

    // The tables WOP_TYPE_TABLE's a indexes (declManager's index, as names).
    NSMutableArray<NSString *> *tables;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)gui;
- (instancetype)initWithDC:(nullable idDeviceContext *)d gui:(idUserInterfaceLocal *)gui;

- (void)setDC:(idDeviceContext *)d;
- (nullable idDeviceContext *)getDC;

- (nullable idWindow *)setFocus:(idWindow *)w scripts:(BOOL)scripts;
- (nullable idWindow *)setFocus:(idWindow *)w;

- (nullable idWindow *)setCapture:(idWindow *)w;
- (void)setParent:(nullable idWindow *)w;
- (void)setFlag:(unsigned int)f;
- (void)clearFlag:(unsigned int)f;
- (unsigned)getFlags;
- (void)move:(float)x y:(float)y;
- (void)bringToTop:(nullable idWindow *)w;
- (void)size:(float)x y:(float)y w:(float)w h:(float)h;
- (void)setupFromState;
- (void)setupBackground;
- (nullable idDrawWin *)findChildByName:(NSString *)name;
- (nullable idSimpleWindow *)findSimpleWinByName:(NSString *)_name;
- (nullable idWindow *)getParent;
- (idUserInterfaceLocal *)getGui;
- (BOOL)contains:(float)x y:(float)y;
- (BOOL)containsRect:(idRectangle)sr x:(float)x y:(float)y;

- (nullable idWinVar *)getWinVarByName:(NSString *)_name fixup:(BOOL)fixup owner:(idDrawWin *_Nullable *_Nullable)owner;
- (nullable idWinVar *)getWinVarByName:(NSString *)_name;

- (float)getMaxCharHeight;
- (float)getMaxCharWidth;
- (void)setFont;
- (void)setInitialState:(NSString *)_name;
- (void)addChild:(idWindow *)win;
- (void)debugDraw:(int)time x:(float)x y:(float)y;
- (void)calcClientRect:(float)xofs yofs:(float)yofs;
- (void)windowCommonInit;
- (void)cleanUp;
- (void)drawBorderAndCaption:(idRectangle)drawRect;
- (void)setupTransforms:(float)x y:(float)y;
- (NSString *)getName;

- (BOOL)parse:(idParser *)src rebuild:(BOOL)rebuild;
- (NSString *)handleEvent:(const sysEvent_t *)event updateVisuals:(BOOL *_Nullable)updateVisuals;
- (void)calcRects:(float)x y:(float)y;
- (void)redraw:(float)x y:(float)y;

- (void)archiveToDictionary:(idDict *)dict useNames:(BOOL)useNames;
- (void)initFromDictionary:(idDict *)dict byName:(BOOL)byName;
- (void)postParse;
- (void)activate:(BOOL)activate act:(NSMutableString *)act;
- (void)trigger;
- (void)gainFocus;
- (void)loseFocus;
- (void)gainCapture;
- (void)loseCapture;
- (void)sized;
- (void)moved;
- (void)draw:(int)time x:(float)x y:(float)y;
- (void)mouseExit;
- (void)mouseEnter;
- (void)drawBackground:(idRectangle)drawRect;
- (NSString *)routeMouseCoords:(float)xd yd:(float)yd;
- (void)setBuddy:(idWindow *)buddy;
- (void)handleBuddyUpdate:(idWindow *)buddy;
- (void)stateChanged:(BOOL)redraw;

- (void)fixupParms;
- (BOOL)hasOps;
- (float)evalRegs:(int)test force:(BOOL)force;
- (float)evalRegs;
- (void)startTransition;
- (void)addTransition:(idWinVar *)dest from:(idVec4)from to:(idVec4)to time:(int)time accelTime:(float)accelTime decelTime:(float)decelTime;
- (void)resetTime:(int)time;
- (void)resetCinematics;
- (int)numTransitions;

- (BOOL)parseScript:(idParser *)src list:(idGuiScriptList *)list timeParm:(int *_Nullable)timeParm elseBlock:(BOOL)elseBlock;
- (BOOL)runScript:(int)n;
- (BOOL)runScriptList:(nullable idGuiScriptList *)src;
- (intptr_t)parseExpression:(idParser *)src var:(nullable idWinVar *)var component:(intptr_t)component;
- (intptr_t)parseExpression:(idParser *)src;
- (int)expressionConstant:(float)f;
- (idRegisterList *)regList;
- (void)addCommand:(NSString *)cmd;
- (void)addUpdateVar:(idWinVar *)var;
- (BOOL)interactive;
- (BOOL)containsStateVars;
- (void)setChildWinVarVal:(NSString *)name var:(NSString *)var val:(NSString *)val;
- (nullable idWindow *)getFocusedChild;
- (nullable idWindow *)getCaptureChild;
- (NSString *)getComment;
- (void)setComment:(NSString *)p;

- (void)runNamedEvent:(NSString *)eventName;

- (void)addDefinedVar:(idWinVar *)var;

- (nullable idWindow *)findChildByPoint:(float)x y:(float)y below:(nullable idWindow *)below;
- (int)getChildIndex:(idWindow *)window;
- (int)getChildCount;
- (nullable idWindow *)getChild:(int)index;
- (void)removeChild:(idWindow *)win;
- (BOOL)insertChild:(idWindow *)win before:(nullable idWindow *)before;

- (void)screenToClient:(idRectangle *)rect;
- (void)clientToScreen:(idRectangle *)rect;

- (BOOL)updateFromDictionary:(idDict *)dict;

// protected
- (void)setDefaults;
- (BOOL)isSimple;
- (void)updateWinVars;
- (void)disableRegister:(NSString *)_name;
- (void)transition;
- (void)time;
- (BOOL)runTimeEvents:(int)time;

- (BOOL)parseInternalVar:(NSString *)name parser:(idParser *)src;
- (BOOL)parseRegEntry:(NSString *)name parser:(idParser *)src;
- (BOOL)parseScriptEntry:(NSString *)name parser:(idParser *)src;
- (NSString *)parseString:(idParser *)src;
- (void)parseVec4:(idParser *)src out:(idVec4 *)out;
- (void)saveExpressionParseState;
- (void)restoreExpressionParseState;

@end

/// idSimpleWindow: a window with no scripts, events, registers or children,
/// drawn and nothing else.
@interface idSimpleWindow : NSObject <idWinBackgroundTarget> {
@public
    NSString *name;

    __weak idUserInterfaceLocal *gui;
    idDeviceContext *_Nullable dc;
    int             flags;
    idRectangle     drawRect;           // overall rect
    idRectangle     clientRect;         // client area
    idRectangle     textRect;
    idVec2          origin;
    int             fontNum;
    float           matScalex;
    float           matScaley;
    float           borderSize;
    int             textAlign;
    float           textAlignx;
    float           textAligny;
    int             textShadow;

    idWinStr        *text;
    idWinBool       *visible;
    idWinRectangle  *rect;               // overall rect
    idWinVec4       *backColor;
    idWinVec4       *matColor;
    idWinVec4       *foreColor;
    idWinVec4       *borderColor;
    idWinFloat      *textScale;
    idWinFloat      *rotate;
    idWinVec2       *shear;
    idWinBackground *backGroundName;

    idMaterial *_Nullable background;

    __weak idWindow *_Nullable mParent;

    idWinBool   *hideCursor;

    //#modified-fva; BEGIN
    idWinInt    *cstAnchor;
    idWinInt    *cstAnchorTo;       // for anchor transitions
    idWinFloat  *cstAnchorFactor;   // for anchor transitions
    BOOL        cstNoClipBackground;
    //#modified-fva; END
}
- (instancetype)initWithWindow:(idWindow *)win;
- (void)redraw:(float)x y:(float)y;
- (void)stateChanged:(BOOL)redraw;
- (nullable idWinVar *)getWinVarByName:(NSString *)_name;
- (nullable idWindow *)getParent;
@end

NS_ASSUME_NONNULL_END
