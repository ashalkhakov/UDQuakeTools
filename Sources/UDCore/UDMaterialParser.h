/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDMaterialParser.h — idMaterial::Parse (Material.cpp), ported literally,
 * with idMaterial's state; and, as the parse goes, where in the text each
 * keyword it reads is.
 */

#import <Foundation/Foundation.h>

@class idDeclManager, UDDeclTextProblem;

NS_ASSUME_NONNULL_BEGIN

// Material.h's enums, as the engine has them.
typedef NS_ENUM(int, UDStageLighting) { UDStageLightingAmbient, UDStageLightingBump, UDStageLightingDiffuse, UDStageLightingSpecular };
typedef NS_ENUM(int, UDTexgen) {
    UDTexgenExplicit, UDTexgenDiffuseCube, UDTexgenReflectCube, UDTexgenSkyboxCube, UDTexgenWobbleSkyCube,
    UDTexgenScreen, UDTexgenScreen2, UDTexgenGlassWarp
};
typedef NS_ENUM(int, UDCubeFiles) { UDCubeFiles2D, UDCubeFilesNative, UDCubeFilesCamera };

// tr_local.h's GLS_ bits the stages' drawStateBits are made of.
extern const int UDGLSSrcBlendBits, UDGLSDstBlendBits;
extern const int UDGLSSrcBlendZero, UDGLSSrcBlendOne, UDGLSSrcBlendDstColor, UDGLSSrcBlendOneMinusDstColor,
                 UDGLSSrcBlendSrcAlpha, UDGLSSrcBlendOneMinusSrcAlpha, UDGLSSrcBlendDstAlpha,
                 UDGLSSrcBlendOneMinusDstAlpha, UDGLSSrcBlendAlphaSaturate;
extern const int UDGLSDstBlendZero, UDGLSDstBlendOne, UDGLSDstBlendSrcColor, UDGLSDstBlendOneMinusSrcColor,
                 UDGLSDstBlendSrcAlpha, UDGLSDstBlendOneMinusSrcAlpha, UDGLSDstBlendDstAlpha,
                 UDGLSDstBlendOneMinusDstAlpha;

/// A stage as the parse leaves it (shaderStage_t): its image as
/// ImageFromFile would be asked for it (a name, not loaded), its registers'
/// indexes into the material's.
@interface UDMaterialStageInfo : NSObject
@property (nonatomic, readonly) int conditionRegister;
@property (nonatomic, readonly) UDStageLighting lighting;
@property (nonatomic, readonly) int drawStateBits;
@property (nonatomic, readonly) const int *colorRegisters;        // 4
@property (nonatomic, readonly) BOOL hasAlphaTest;
@property (nonatomic, readonly) int alphaTestRegister;
@property (nonatomic, copy, readonly, nullable) NSString *imageName;
@property (nonatomic, readonly) UDCubeFiles cubeMap;
@property (nonatomic, readonly) UDTexgen texgen;
@property (nonatomic, readonly) BOOL hasMatrix;
@property (nonatomic, readonly) const int *matrix;               // [2][3]
@property (nonatomic, readonly) BOOL dynamic;
@property (nonatomic, readonly) BOOL cinematic;
@property (nonatomic, readonly) BOOL newStage;
/// The stage's place in the text (ParseStage from it, a shortcut counted),
/// -1 for one AddImplicitStages adds.
@property (nonatomic, readonly) NSInteger textIndex;
@end

/// A keyword the parse read from the text, where it is: from its token's
/// whitespace (idLexer's) to where the next one's begins; a stage's keywords
/// are its children.
typedef NS_ENUM(NSInteger, UDMaterialTextKind) {
    UDMaterialTextKeyword,
    UDMaterialTextStage,
    /// What the parse did not get through: the rest of the text, from the
    /// keyword it gave up on, as it is.
    UDMaterialTextUnparsed,
};

@interface UDMaterialTextNode : NSObject
@property (nonatomic, readonly) UDMaterialTextKind kind;
/// The keyword token, as written.
@property (nonatomic, copy, readonly, nullable) NSString *keyword;
/// What the parse read for it: the token it keeps (description's,
/// qer_editorimage's), a stage name's rest of line its quotes taken off
/// (MaterialDoc::ParseStage's), else the text after the keyword.
@property (nonatomic, copy, readonly, nullable) NSString *value;
/// A stage's: its keywords; NO for a stage the parse gave up in (its
/// unparsed rest is its last child).
@property (nonatomic, copy, readonly, nullable) NSArray<UDMaterialTextNode *> *children;
@property (nonatomic, readonly) BOOL closed;
/// Where in the text's UTF-8 bytes its leading begins (its keyword token's
/// whitespace, as idLexer has it); a stage's close brace's, -1 for none.
@property (nonatomic, readonly) NSInteger leadingStart;
@property (nonatomic, readonly) NSInteger closingStart;
@end

@interface UDMaterialParser : NSObject

/// idMaterial::Parse over the material @a text (with or without its name
/// before its brace). Tables are looked up in @a declManager, as the
/// engine's declManager->FindType does.
- (instancetype)initWithText:(NSString *)text name:(NSString *)name declManager:(nullable idDeclManager *)declManager;

/// Its warnings, by line from the text's first; common->Warning's at the
/// line the parse was on.
@property (nonatomic, copy, readonly) NSArray<UDDeclTextProblem *> *problems;
/// MF_DEFAULTED: the engine draws the default material instead.
@property (nonatomic, readonly) BOOL defaulted;

// idMaterial's state.
@property (nonatomic, copy, readonly) NSString *desc;
@property (nonatomic, copy, readonly) NSString *editorImageName;
@property (nonatomic, readonly) int coverage;
@property (nonatomic, readonly) float sort;
@property (nonatomic, readonly) int contentFlags;
@property (nonatomic, readonly) int surfaceFlags;
@property (nonatomic, readonly) int materialFlags;
/// The stages in the engine's order (SortInteractionStages').
@property (nonatomic, copy, readonly) NSArray<UDMaterialStageInfo *> *stages;

/// idMaterial::EvaluateRegisters at @a time, its shader parms all 1 (an
/// entity's default color) and its globals 0, without a sound emitter.
- (NSData *)registersAtTime:(float)time;

/// The text the parse went through: the body's keywords and stages.
@property (nonatomic, copy, readonly) NSArray<UDMaterialTextNode *> *body;

@end

NS_ASSUME_NONNULL_END
