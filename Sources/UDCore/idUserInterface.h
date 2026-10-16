/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idUserInterface.h — a GUI and the manager of the GUIs (ui/UserInterface.h,
 * UserInterfaceLocal.h, UserInterface.cpp), ported.
 *
 * What the engine's globals give the GUI code, the manager has instead:
 * the file system and decl manager (fileSystem, declManager), the strings
 * (common->GetLanguageDict), the cvars it reads (cvarSystem), the keys held
 * (idKeyInput::IsDown), the tic (com_ticNumber), the render system its
 * device context draws through and the screen's size (glConfig), whether
 * the GUI editor is on (com_editors & EDITOR_GUI), the sounds localSound
 * plays (session->sw) and the warnings common->Warning prints.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"
#import "idWindow.h"
#import "idLangDict.h"
#import "idCVarSystem.h"

@class idFileSystem, idDeclManager, idDict, idDeviceContext, idGuiModel, idMaterial, UDSoftwareRenderer;

NS_ASSUME_NONNULL_BEGIN

/// USERCMD_MSEC (framework/UsercmdGen.h): 1000 / USERCMD_HZ (60).
#define USERCMD_MSEC    16

@interface idUserInterfaceManager : NSObject <idUIWarnings>

- (instancetype)initWithFileSystem:(nullable idFileSystem *)fileSystem declManager:(nullable idDeclManager *)declManager;

@property (nonatomic, weak, readonly, nullable) idFileSystem *fileSystem;
@property (nonatomic, weak, readonly, nullable) idDeclManager *declManager;

/// idUserInterfaceManagerLocal::Init: the device context made, its fonts.
- (void)managerInit;
- (void)shutdown;
- (void)setSize:(float)width height:(float)height;
- (BOOL)checkGui:(NSString *)qpath;
- (idUserInterfaceLocal *)allocGui;
- (void)deAlloc:(idUserInterfaceLocal *)gui;
- (nullable idUserInterfaceLocal *)findGui:(NSString *)qpath autoLoad:(BOOL)autoLoad needUnique:(BOOL)needUnique forceNOTUnique:(BOOL)forceNOTUnique;

@property (nonatomic, readonly) idRectangle screenRect;
@property (nonatomic, strong, readonly) idDeviceContext *dc;
@property (nonatomic, strong, readonly) NSMutableArray<idUserInterfaceLocal *> *guis;

#pragma mark The engine's, here

/// common->GetLanguageDict()
@property (nonatomic, strong, readonly) idLangDict *languageDict;
/// cvarSystem: the cvars the GUIs read and set.
@property (nonatomic, strong, readonly) idCVarSystem *cvars;
/// com_editors & EDITOR_GUI: no simple windows, every window kept.
@property (nonatomic) BOOL editing;
/// idKeyInput::IsDown
- (BOOL)isKeyDown:(int)key;
- (void)setKey:(int)key down:(BOOL)down;
/// com_ticNumber
@property (nonatomic) int ticNumber;
/// glConfig.vidWidth, vidHeight, winWidth, winHeight: the view's size.
@property (nonatomic) int screenWidth;
@property (nonatomic) int screenHeight;
/// The render system: its materials and images, and what it draws the
/// GUI model's surfaces with.
@property (nonatomic, strong, readonly) UDSoftwareRenderer *renderer;
/// renderSystem's guiModel
@property (nonatomic, strong, readonly) idGuiModel *guiModel;
/// declManager->FindMaterial( name ): never nil, the same for a name.
- (idMaterial *)findMaterial:(NSString *)name;
/// declManager->FindType( DECL_TABLE, name, false ) != NULL
- (BOOL)tableExists:(NSString *)name;
/// session->sw->PlayShaderDirectly( name ): noted (-playedSounds).
- (void)playShaderDirectly:(NSString *)name;
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *playedSounds;
/// common->Warning, common->Printf: their messages, in order.
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *warnings;
- (void)uiWarning:(NSString *)message;
/// cmdSystem->BufferCommandText: the commands GUIs ran (endGame's).
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *bufferedCommands;

@end

@interface idUserInterfaceLocal : NSObject

- (instancetype)initWithManager:(idUserInterfaceManager *)manager;
@property (nonatomic, weak, readonly) idUserInterfaceManager *manager;

- (NSString *)name;
- (NSString *)comment;
- (BOOL)isInteractive;
- (BOOL)initFromFile:(NSString *)qpath rebuild:(BOOL)rebuild cache:(BOOL)cache;
- (BOOL)initFromFile:(NSString *)qpath;
/// The same over @a text, as if it were @a qpath's (an editor's, unsaved).
- (BOOL)initFromText:(NSString *)text path:(NSString *)qpath;
- (NSString *)handleEvent:(const sysEvent_t *)event time:(int)time updateVisuals:(BOOL *_Nullable)updateVisuals;
- (void)handleNamedEvent:(NSString *)namedEvent;
- (void)redraw:(int)time;
- (void)drawCursor;
- (idDict *)state;
- (void)deleteStateVar:(NSString *)varName;
- (void)setStateString:(NSString *)varName value:(NSString *)value;
- (void)setStateBool:(NSString *)varName value:(BOOL)value;
- (void)setStateInt:(NSString *)varName value:(int)value;
- (void)setStateFloat:(NSString *)varName value:(float)value;
- (NSString *)getStateString:(NSString *)varName defaultString:(NSString *)defaultString;
- (BOOL)getStateBool:(NSString *)varName defaultString:(NSString *)defaultString;
- (int)getStateInt:(NSString *)varName defaultString:(NSString *)defaultString;
- (float)getStateFloat:(NSString *)varName defaultString:(NSString *)defaultString;
- (void)stateChanged:(int)time redraw:(BOOL)redraw;
- (NSString *)activate:(BOOL)activate time:(int)time;
- (void)trigger:(int)time;
- (void)setKeyBindingNames;
- (BOOL)isUniqued;
- (void)setUniqued:(BOOL)b;
- (void)setCursor:(float)x y:(float)y;
- (float)cursorX;
- (float)cursorY;

- (idDict *)getStateDict;
- (NSString *)getSourceFile;
- (nullable idWindow *)getDesktop;
- (void)setBindHandler:(nullable idWindow *)win;
- (BOOL)active;
- (int)getTime;
- (void)setTime:(int)_time;
- (void)clearRefs;
- (void)addRef;
- (int)getRefs;
- (void)recurseSetKeyBindingNames:(idWindow *)window;
/// GetPendingCmd, GetReturnCmd: the strings themselves, to append to.
- (NSMutableString *)getPendingCmd;
- (NSMutableString *)getReturnCmd;

/// Its parse's errors and warnings (idParser's, with "file" and "line").
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *diagnostics;

@end

NS_ASSUME_NONNULL_END
