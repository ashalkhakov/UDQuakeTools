/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDARBProgram.h — an ARB vertex or fragment program run in software, as
 * GL_ARB_vertex_program and GL_ARB_fragment_program specify it: as much of
 * them as the engine's glprogs/interaction.vfp uses (TEMP, PARAM, OPTION;
 * DP3, DP4, MUL, MAD, ADD, SUB, MOV, RSQ, TEX, TXP, and _SAT). The program is
 * the user's own, read from the game's files; anything else in it is said
 * to be unsupported.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct { float v[4]; } UDVec4;

/// What a program reads and writes, by its names: vertex.position,
/// vertex.attrib[0–15], vertex.color; fragment.texcoord[0–7],
/// fragment.color; result.texcoord[0–7], result.color; program.env[0–31].
typedef struct {
    UDVec4 position;
    UDVec4 attrib[16];
    UDVec4 color;
    UDVec4 texcoord[8];         // a fragment program's inputs, a vertex program's outputs
    UDVec4 resultColor;
} UDARBState;

/// A texture unit's lookup: unit @a unit, its target 2D (NO) or CUBE (YES),
/// at @a coord (already divided by q for TXP).
typedef UDVec4 (*UDARBTextureFunction)(void *context, int unit, BOOL cube, UDVec4 coord);

@interface UDARBProgram : NSObject

/// The program of @a text from its "!!ARBvp1.0" or "!!ARBfp1.0" (@a vertex)
/// to its END, as R_LoadARBProgram cuts it out of the file; nil, and @a error
/// what is wrong or unsupported, when it does not read.
+ (nullable instancetype)programFromFileText:(NSString *)text vertex:(BOOL)vertex
                                       error:(NSError * _Nullable * _Nullable)error;

/// program.env[0–31] (a vertex and a fragment program each have their own).
@property (nonatomic, readonly) UDVec4 *env;

/// The program run over @a state: its inputs read, its outputs written.
- (void)run:(UDARBState *)state texture:(nullable UDARBTextureFunction)texture context:(nullable void *)context;

@end

NS_ASSUME_NONNULL_END
