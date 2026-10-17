/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclMaterial.h — materials (idMaterial), kept as their tokens.
 */

#import "UDDeclBase.h"

@class idDeclManager, UDSourceTokens, UDDeclMaterial;

NS_ASSUME_NONNULL_BEGIN

// A material is its body's tokens as idLexer reads them, each with the
// whitespace and comments before it (UDSourceTokens): written back, the
// text as it was. What is what in them is idMaterial::Parse's to say
// (UDMaterialParser, ported): the tokens it reads for a keyword are that
// keyword's, a stage's braces and what is between them that stage's. An
// edit puts tokens in, changes them or takes them out; the rest stay as
// they were.

/// One of a material's stages, as the parse finds them in the text (a
/// "diffusemap", "specularmap" or "bumpmap" keyword of the material is one,
/// as ParseMaterial makes one). It is its material's: two of the same
/// material at the same place are equal.
///
/// Its values, by KVC: name, blend, map, cubeMap, cameraCubeMap, videomap,
/// soundmap, remoteRenderMap, mirrorRenderMap, xrayRenderMap, texGen,
/// scroll, translate, scale, centerScale, shear, rotate, color, red, green,
/// blue, alpha, rgb, rgba, alphaTest, condition ("if"), program,
/// vertexProgram, fragmentProgram, megaTexture; one of: filter (nearest,
/// linear), clampMode (clamp, noclamp, zeroclamp, alphazeroclamp); its
/// flags: ignoreAlphaTest, vertexColor, inverseVertexColor, colored,
/// maskRed, maskGreen, maskBlue, maskAlpha, maskColor, maskDepth,
/// ignoreDepth, uncompressed, highquality, forceHighQuality, nopicmip,
/// screen, screen2, glassWarp, privatePolygonOffset. Setting one is an edit
/// of its material's tokens.
@interface UDMaterialStage : NSObject
@property (nonatomic, weak, readonly, nullable) UDDeclMaterial *material;
@property (nonatomic, readonly) NSUInteger index;
/// The shortcut keyword it is ("diffusemap"…), nil for a braced stage.
@property (nonatomic, copy, readonly, nullable) NSString *shortcut;
/// Its text: "{ … }", or its shortcut keyword and image.
@property (nonatomic, copy, readonly) NSString *text;
@end

/// A material. Its values, by KVC: materialDescription ("description"),
/// qerEditorImage, sort, deform, decalInfo, renderbump, guisurf, spectrum,
/// lightFalloffImage; one of: surfaceType (metal … surftype15), clampMode
/// (clamp, zeroclamp, alphazeroclamp); its flags: noShadows, noSelfShadow,
/// forceShadows, twoSided, backSided, translucent, forceOpaque,
/// forceOverlays, noOverlays, noFog, noPortalFog, fogLight, blendLight,
/// ambientLight, mirror, unsmoothedTangents, suppressInSubview, portalSky,
/// polygonOffset, decalMacro, and CheckSurfaceParm's (solid, water,
/// playerclip, monsterclip, moveableclip, ikclip, blood, trigger, aassolid,
/// aasobstacle, flashlightTrigger, nonsolid, nullNormal, areaportal,
/// qerNoCarve, discrete, noFragment, slick, collision, noimpact, nodamage,
/// ladder, nosteps). Setting one is an edit of its tokens.
@interface UDDeclMaterial : UDDeclBase
/// Its body's tokens, from its open brace. TRANSIENT, as a table's values.
@property (nonatomic, strong, nullable) UDSourceTokens *tokens;
/// Its stages, in the text's order.
@property (nonatomic, readonly) NSArray<UDMaterialStage *> *stages;

/// A stage, its text @a text ("{ … }" or a shortcut keyword and its image),
/// put in before stage @a index (after the last for the stages' count).
- (void)ud_insertStageText:(NSString *)text atIndex:(NSUInteger)index;
- (void)ud_removeStageAtIndex:(NSUInteger)index;
/// Stages @a index and @a otherIndex, each where the other was.
- (void)ud_exchangeStageAtIndex:(NSUInteger)index withStageAtIndex:(NSUInteger)otherIndex;

/// The keys a material's and a stage's values are under.
+ (NSArray<NSString *> *)ud_materialValueKeys;
+ (NSArray<NSString *> *)ud_stageValueKeys;
@end

NS_ASSUME_NONNULL_END
