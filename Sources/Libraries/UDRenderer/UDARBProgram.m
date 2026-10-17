/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDARBProgram.m — an ARB vertex or fragment program run in software. Not
 * id's code: the ARB extensions' specifications, as far as interaction.vfp
 * goes.
 */

#import "UDARBProgram.h"

typedef enum {
    UDOpDP3, UDOpDP4, UDOpMUL, UDOpMAD, UDOpADD, UDOpSUB, UDOpMOV, UDOpRSQ, UDOpTEX, UDOpTXP
} UDOp;

typedef enum {
    UDRegTemp,          // a TEMP, by index
    UDRegConst,         // a PARAM { … }, by index
    UDRegEnv,           // program.env[n]
    UDRegPosition,      // vertex.position
    UDRegAttrib,        // vertex.attrib[n]
    UDRegColor,         // vertex.color, fragment.color
    UDRegTexcoord,      // fragment.texcoord[n]
    UDRegResultTexcoord,// result.texcoord[n]
    UDRegResultColor,   // result.color
} UDRegKind;

typedef struct {
    UDRegKind kind;
    int index;
    int swizzle[4];     // a source's
    BOOL negate;
    BOOL mask[4];       // a destination's
} UDOperand;

typedef struct {
    UDOp op;
    BOOL saturate;
    UDOperand dst;
    UDOperand src[3];
    int numSrc;
    int unit;           // TEX, TXP
    BOOL cube;
} UDInstruction;

@interface UDARBProgram () {
    UDVec4 envStorage[32];
    UDInstruction *instructions;
    int numInstructions;
    UDVec4 *constants;
    int numConstants;
    int numTemps;
}
@property (nonatomic) BOOL vertex;
@end

static NSError *UDARBError(NSString *message) {
    return [NSError errorWithDomain:@"UDARBProgram" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation UDARBProgram

- (void)dealloc {
    free( instructions );
    free( constants );
}

- (UDVec4 *)env {
    return envStorage;
}

#pragma mark - Reading

static NSString *UDTrim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// "name[n]" → n, or -1.
static int UDIndexOf(NSString *text, NSString *prefix) {
    if (![text hasPrefix:prefix] || ![text hasSuffix:@"]"]) return -1;
    NSString *number = [text substringWithRange:NSMakeRange(prefix.length, text.length - prefix.length - 1)];
    return number.intValue;
}

+ (instancetype)programFromFileText:(NSString *)file vertex:(BOOL)vertex error:(NSError **)error {
    // R_LoadARBProgram: from the header to the END after it
    NSRange start = [file rangeOfString:vertex ? @"!!ARBvp" : @"!!ARBfp"];
    if (start.location == NSNotFound) {
        if (error) *error = UDARBError(@"!!ARB not found");
        return nil;
    }
    NSRange end = [file rangeOfString:@"END" options:0 range:NSMakeRange(start.location, file.length - start.location)];
    if (end.location == NSNotFound) {
        if (error) *error = UDARBError(@"END not found");
        return nil;
    }
    NSString *text = [file substringWithRange:NSMakeRange(start.location, end.location - start.location)];
    // its comments off, its header line's version off
    NSMutableString *body = [NSMutableString string];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSRange comment = [line rangeOfString:@"#"];
        [body appendString:comment.location == NSNotFound ? line : [line substringToIndex:comment.location]];
        [body appendString:@"\n"];
    }
    NSRange header = [body rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *statements = header.location == NSNotFound ? @"" : [body substringFromIndex:header.location];

    UDARBProgram *program = [[UDARBProgram alloc] init];
    program.vertex = vertex;
    NSMutableDictionary<NSString *, NSValue *> *names = [NSMutableDictionary dictionary];
    NSMutableData *code = [NSMutableData data];
    NSMutableData *consts = [NSMutableData data];
    int temps = 0;

    for (NSString *raw in [statements componentsSeparatedByString:@";"]) {
        NSString *statement = UDTrim([raw stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
        if (statement.length == 0) continue;
        NSRange space = [statement rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *word = space.location == NSNotFound ? statement : [statement substringToIndex:space.location];
        NSString *rest = space.location == NSNotFound ? @"" : UDTrim([statement substringFromIndex:space.location]);

        if ([word isEqualToString:@"OPTION"]) {
            continue;                                   // precision hints, position invariance: ours already
        }
        if ([word isEqualToString:@"TEMP"]) {
            for (NSString *name in [rest componentsSeparatedByString:@","]) {
                UDOperand reg = { UDRegTemp, temps++ };
                names[UDTrim(name)] = [NSValue valueWithBytes:&reg objCType:@encode(UDOperand)];
            }
            continue;
        }
        if ([word isEqualToString:@"PARAM"]) {
            NSArray<NSString *> *parts = [rest componentsSeparatedByString:@"="];
            if (parts.count != 2) {
                if (error) *error = UDARBError([NSString stringWithFormat:@"unsupported PARAM: %@", statement]);
                return nil;
            }
            NSString *name = UDTrim(parts[0]), *value = UDTrim(parts[1]);
            UDOperand reg = { 0 };
            if ([value hasPrefix:@"{"] && [value hasSuffix:@"}"]) {
                NSArray<NSString *> *numbers = [[value substringWithRange:NSMakeRange(1, value.length - 2)] componentsSeparatedByString:@","];
                UDVec4 c = { { 0, 0, 0, 1 } };
                for (NSUInteger i = 0; i < MIN(numbers.count, 4U); i++) c.v[i] = UDTrim(numbers[i]).floatValue;
                reg.kind = UDRegConst;
                reg.index = (int)(consts.length / sizeof(UDVec4));
                [consts appendBytes:&c length:sizeof(c)];
            } else if (UDIndexOf(value, @"program.env[") >= 0) {
                reg.kind = UDRegEnv;
                reg.index = UDIndexOf(value, @"program.env[");
            } else {
                if (error) *error = UDARBError([NSString stringWithFormat:@"unsupported PARAM: %@", statement]);
                return nil;
            }
            names[name] = [NSValue valueWithBytes:&reg objCType:@encode(UDOperand)];
            continue;
        }

        // an instruction
        UDInstruction instruction;
        memset(&instruction, 0, sizeof(instruction));
        NSString *opcode = word;
        if ([opcode hasSuffix:@"_SAT"]) {
            instruction.saturate = YES;
            opcode = [opcode substringToIndex:opcode.length - 4];
        }
        NSDictionary<NSString *, NSNumber *> *ops = @{ @"DP3": @(UDOpDP3), @"DP4": @(UDOpDP4), @"MUL": @(UDOpMUL), @"MAD": @(UDOpMAD),
                                                      @"ADD": @(UDOpADD), @"SUB": @(UDOpSUB), @"MOV": @(UDOpMOV), @"RSQ": @(UDOpRSQ),
                                                      @"TEX": @(UDOpTEX), @"TXP": @(UDOpTXP) };
        if (ops[opcode] == nil) {
            if (error) *error = UDARBError([NSString stringWithFormat:@"unsupported instruction: %@", word]);
            return nil;
        }
        instruction.op = (UDOp)ops[opcode].intValue;
        NSMutableArray<NSString *> *operands = [NSMutableArray array];
        for (NSString *operand in [rest componentsSeparatedByString:@","]) [operands addObject:UDTrim(operand)];
        BOOL texture = instruction.op == UDOpTEX || instruction.op == UDOpTXP;
        if (texture) {
            // dst, coord, texture[n], 2D|CUBE
            if (operands.count != 4 || UDIndexOf(operands[2], @"texture[") < 0 ||
                !([operands[3] isEqualToString:@"2D"] || [operands[3] isEqualToString:@"CUBE"])) {
                if (error) *error = UDARBError([NSString stringWithFormat:@"unsupported texture instruction: %@", statement]);
                return nil;
            }
            instruction.unit = UDIndexOf(operands[2], @"texture[");
            instruction.cube = [operands[3] isEqualToString:@"CUBE"];
            [operands removeObjectsInRange:NSMakeRange(2, 2)];
        }
        if (operands.count < 2 || operands.count > 4) {
            if (error) *error = UDARBError([NSString stringWithFormat:@"bad instruction: %@", statement]);
            return nil;
        }
        for (NSUInteger i = 0; i < operands.count; i++) {
            NSString *operand = operands[i];
            UDOperand reg;
            memset(&reg, 0, sizeof(reg));
            if ((reg.negate = [operand hasPrefix:@"-"])) operand = UDTrim([operand substringFromIndex:1]);
            // name[.suffix]: the last dot after any bracket
            NSString *name = operand, *suffix = nil;
            NSRange bracket = [operand rangeOfString:@"]" options:NSBackwardsSearch];
            NSRange dot = [operand rangeOfString:@"." options:NSBackwardsSearch];
            if (dot.location != NSNotFound && (bracket.location == NSNotFound || dot.location > bracket.location)) {
                NSString *candidate = [operand substringFromIndex:dot.location + 1];
                if ([candidate rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"xyzwrgba"] invertedSet]].location == NSNotFound) {
                    name = [operand substringToIndex:dot.location];
                    suffix = candidate;
                }
            }
            NSValue *declared = names[name];
            if (declared != nil) {
                [declared getValue:&reg];
                reg.negate = [operands[i] hasPrefix:@"-"];
            } else if ([name isEqualToString:@"vertex.position"]) {
                reg.kind = UDRegPosition;
            } else if (UDIndexOf(name, @"vertex.attrib[") >= 0) {
                reg.kind = UDRegAttrib;
                reg.index = UDIndexOf(name, @"vertex.attrib[");
            } else if ([name isEqualToString:@"vertex.color"] || [name isEqualToString:@"fragment.color"]) {
                reg.kind = UDRegColor;
            } else if (UDIndexOf(name, @"fragment.texcoord[") >= 0) {
                reg.kind = UDRegTexcoord;
                reg.index = UDIndexOf(name, @"fragment.texcoord[");
            } else if (UDIndexOf(name, @"result.texcoord[") >= 0) {
                reg.kind = UDRegResultTexcoord;
                reg.index = UDIndexOf(name, @"result.texcoord[");
            } else if ([name isEqualToString:@"result.color"]) {
                reg.kind = UDRegResultColor;
            } else if (UDIndexOf(name, @"program.env[") >= 0) {
                reg.kind = UDRegEnv;
                reg.index = UDIndexOf(name, @"program.env[");
            } else {
                if (error) *error = UDARBError([NSString stringWithFormat:@"unsupported operand: %@", operands[i]]);
                return nil;
            }
            if (i == 0) {
                // the destination's write mask
                for (int c = 0; c < 4; c++) reg.mask[c] = suffix == nil;
                for (NSUInteger c = 0; c < suffix.length; c++) {
                    NSUInteger component = [@"xyzw" rangeOfString:[suffix substringWithRange:NSMakeRange(c, 1)]].location;
                    if (component == NSNotFound) component = [@"rgba" rangeOfString:[suffix substringWithRange:NSMakeRange(c, 1)]].location;
                    if (component != NSNotFound) reg.mask[component] = YES;
                }
                instruction.dst = reg;
            } else {
                // a source's swizzle: one component is all four
                for (int c = 0; c < 4; c++) reg.swizzle[c] = c;
                if (suffix != nil) {
                    for (int c = 0; c < 4; c++) {
                        NSString *letter = [suffix substringWithRange:NSMakeRange(MIN((NSUInteger)c, suffix.length - 1), 1)];
                        NSUInteger component = [@"xyzw" rangeOfString:letter].location;
                        if (component == NSNotFound) component = [@"rgba" rangeOfString:letter].location;
                        reg.swizzle[c] = (int)component;
                    }
                }
                instruction.src[instruction.numSrc++] = reg;
            }
        }
        [code appendBytes:&instruction length:sizeof(instruction)];
    }

    program->numInstructions = (int)(code.length / sizeof(UDInstruction));
    program->instructions = malloc(MAX(code.length, 1));
    memcpy(program->instructions, code.bytes, code.length);
    program->numConstants = (int)(consts.length / sizeof(UDVec4));
    program->constants = malloc(MAX(consts.length, 1));
    memcpy(program->constants, consts.bytes, consts.length);
    program->numTemps = temps;
    return program;
}

#pragma mark - Running

static UDVec4 *UDRegister(const UDOperand *reg, UDARBState *state, UDVec4 *temps, UDVec4 *constants, UDVec4 *env) {
    switch (reg->kind) {
        case UDRegTemp: return &temps[reg->index];
        case UDRegConst: return &constants[reg->index];
        case UDRegEnv: return &env[reg->index & 31];
        case UDRegPosition: return &state->position;
        case UDRegAttrib: return &state->attrib[reg->index & 15];
        case UDRegColor: return &state->color;
        case UDRegTexcoord: return &state->texcoord[reg->index & 7];
        case UDRegResultTexcoord: return &state->texcoord[reg->index & 7];
        case UDRegResultColor: return &state->resultColor;
    }
    return &temps[0];
}

- (void)run:(UDARBState *)state texture:(UDARBTextureFunction)texture context:(void *)context {
    UDVec4 temps[MAX(numTemps, 1)];
    memset(temps, 0, sizeof(temps));
    for (int i = 0; i < numInstructions; i++) {
        const UDInstruction *in = &instructions[i];
        UDVec4 s[3];
        for (int k = 0; k < in->numSrc; k++) {
            const UDVec4 *r = UDRegister(&in->src[k], state, temps, constants, envStorage);
            for (int c = 0; c < 4; c++) {
                float v = r->v[in->src[k].swizzle[c]];
                s[k].v[c] = in->src[k].negate ? -v : v;
            }
        }
        UDVec4 result = { { 0, 0, 0, 0 } };
        switch (in->op) {
            case UDOpDP3: {
                float d = s[0].v[0] * s[1].v[0] + s[0].v[1] * s[1].v[1] + s[0].v[2] * s[1].v[2];
                for (int c = 0; c < 4; c++) result.v[c] = d;
                break;
            }
            case UDOpDP4: {
                float d = s[0].v[0] * s[1].v[0] + s[0].v[1] * s[1].v[1] + s[0].v[2] * s[1].v[2] + s[0].v[3] * s[1].v[3];
                for (int c = 0; c < 4; c++) result.v[c] = d;
                break;
            }
            case UDOpMUL: for (int c = 0; c < 4; c++) result.v[c] = s[0].v[c] * s[1].v[c]; break;
            case UDOpMAD: for (int c = 0; c < 4; c++) result.v[c] = s[0].v[c] * s[1].v[c] + s[2].v[c]; break;
            case UDOpADD: for (int c = 0; c < 4; c++) result.v[c] = s[0].v[c] + s[1].v[c]; break;
            case UDOpSUB: for (int c = 0; c < 4; c++) result.v[c] = s[0].v[c] - s[1].v[c]; break;
            case UDOpMOV: result = s[0]; break;
            case UDOpRSQ: {
                // the scalar's (its .x), of its absolute value
                float r = 1.0f / sqrtf(fabsf(s[0].v[0]));
                for (int c = 0; c < 4; c++) result.v[c] = r;
                break;
            }
            case UDOpTEX:
            case UDOpTXP: {
                UDVec4 coord = s[0];
                if (in->op == UDOpTXP && coord.v[3] != 0) {
                    for (int c = 0; c < 3; c++) coord.v[c] /= coord.v[3];
                }
                if (texture != NULL) result = texture(context, in->unit, in->cube, coord);
                break;
            }
        }
        if (in->saturate) {
            for (int c = 0; c < 4; c++) result.v[c] = result.v[c] < 0 ? 0 : result.v[c] > 1 ? 1 : result.v[c];
        }
        UDVec4 *dst = UDRegister(&in->dst, state, temps, constants, envStorage);
        for (int c = 0; c < 4; c++) {
            if (in->dst.mask[c]) dst->v[c] = result.v[c];
        }
    }
}

@end
