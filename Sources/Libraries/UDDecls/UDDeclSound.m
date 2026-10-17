/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclSound.m — sound shaders (idSoundShader).
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclSound.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

#pragma mark - Sound shaders

@implementation UDSoundSample

+ (instancetype)sampleWithPath:(NSString *)path {
    UDSoundSample *sample = [[self alloc] init];
    sample->_path = [path copy];
    return sample;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[self class] sampleWithPath:_path];
}

- (void)setPath:(NSString *)path {
    UDSoundSample *edited = [self copy];
    edited->_path = [path copy];
    if (![self ud_replaceInOwnerWith:edited]) {
        _path = [path copy];
    }
}

- (BOOL)validatePath:(id *)ioValue error:(NSError **)error {
    return UDValidateName(ioValue, @"sample", error);
}

@end

// The flags' keywords, ParseShader's, by the attribute each sets.
static NSArray<NSArray<NSString *> *> *UDSoundFlagKeywords(void) {
    return @[
        @[@"noDups", @"no_dups"], @[@"noFlicker", @"no_flicker"], @[@"looping", @"looping"],
        @[@"noOcclusion", @"no_occlusion"], @[@"privateSound", @"private"], @[@"antiPrivate", @"antiPrivate"],
        @[@"playOnce", @"playonce"], @[@"global", @"global"], @[@"unclamped", @"unclamped"],
        @[@"omnidirectional", @"omnidirectional"],
        @[@"maskCenter", @"mask_center"], @[@"maskLeft", @"mask_left"], @[@"maskRight", @"mask_right"],
        @[@"maskBackRight", @"mask_backright"], @[@"maskBackLeft", @"mask_backleft"], @[@"maskLFE", @"mask_lfe"],
        @[@"ordered", @"ordered"], @[@"plain", @"plain"], @[@"onDemand", @"onDemand"],
    ];
}

@implementation UDDeclSound

@dynamic soundDescription, minSamples, minDistance, maxDistance, volume, leadinVolume, shakes, soundClass, altSound, reverb;
@dynamic noDups, noFlicker, looping, noOcclusion, privateSound, antiPrivate, playOnce, global, unclamped, omnidirectional;
@dynamic maskCenter, maskLeft, maskRight, maskBackLeft, maskBackRight, maskLFE, ordered, plain, onDemand;
@dynamic samples, leadins;

UD_ELEMENT_ARRAY_SETTER(setSamples, @"samples")
UD_ELEMENT_ARRAY_SETTER(setLeadins, @"leadins")

// samples and leadins are transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSDictionary *parsed = UDParsedSourceText(self);
    for (NSString *key in @[@"samples", @"leadins"]) {
        NSArray *elements = parsed[key] ?: @[];
        [self setPrimitiveValue:elements forKey:key];
        UDAdoptElements(elements, self, key);
    }
}

/// A parameter typed in: a number (a whole one for @a integer), or nothing,
/// which leaves it unset.
static BOOL UDValidateParameter(id *ioValue, BOOL integer, NSString *what, NSError **error) {
    id value = *ioValue;
    if (value == nil || value == [NSNull null]) {
        *ioValue = nil;
        return YES;
    }
    NSString *text = [[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (text.length == 0) {
        *ioValue = nil;
        return YES;
    }
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double d = 0;
    int i = 0;
    BOOL scanned = integer ? [scanner scanInt:&i] : [scanner scanDouble:&d];
    if (scanned && scanner.isAtEnd) {
        *ioValue = integer ? @(i) : @((float)d);
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclSound" code:1 userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"%@ is a %@number, or nothing for the engine's default.", what, integer ? @"whole " : @""]}];
    }
    return NO;
}

- (BOOL)validateMinDistance:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Min distance", error); }
- (BOOL)validateMaxDistance:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Max distance", error); }
- (BOOL)validateVolume:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Volume", error); }
- (BOOL)validateLeadinVolume:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Leadin volume", error); }
- (BOOL)validateShakes:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, NO, @"Shakes", error); }
- (BOOL)validateMinSamples:(id *)ioValue error:(NSError **)error { return UDValidateParameter(ioValue, YES, @"Min samples", error); }

- (BOOL)validateSoundClass:(id *)ioValue error:(NSError **)error {
    if (!UDValidateParameter(ioValue, YES, @"Sound class", error)) return NO;
    // SOUND_MAX_CLASSES: "SoundClass out of range" past it.
    if (*ioValue == nil || ([*ioValue integerValue] >= 0 && [*ioValue integerValue] < 4)) return YES;
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclSound" code:1 userInfo:@{NSLocalizedDescriptionKey: @"A sound class is 0 to 3."}];
    }
    return NO;
}

// idSoundShader::DefaultDefinition
+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"_default.wav\n"
        @"}";
}

/// MakeDefault()'s shader: the default definition's one sample.
static NSDictionary<NSString *, id> *UDDefaultSoundValues(void) {
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *flag in UDSoundFlagKeywords()) values[flag[0]] = @NO;
    values[@"samples"] = @[[UDSoundSample sampleWithPath:@"_default.wav"]];
    values[@"leadins"] = @[];
    return values;
}

// A port of idSoundShader::ParseShader (neo/sound/snd_shader.cpp), keeping
// the keywords' values rather than the sound system's parms (so minSamples
// is what it says, not clamped; the samples are their names, not found in
// the sound cache, with no sys_lang voice-over substitution). Where it
// returns false, idSoundShader::Parse calls MakeDefault(): the values are
// the default definition's.
+ (NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)text
                                                    name:(NSString *)name
                                                fileName:(NSString *)fileName
                                                 lineNum:(int)lineNum
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError **)error {
    idLexer *src = UDDeclCodecLexer(text, name, fileName, lineNum, fileSystem, error);
    if (src == nil) {
        return nil;
    }
    idToken token;
    idToken_Init(&token);

    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    NSMutableArray<UDSoundSample *> *samples = [NSMutableArray array];
    NSMutableArray<UDSoundSample *> *leadins = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *flags = [NSMutableDictionary dictionary];
    for (NSArray<NSString *> *flag in UDSoundFlagKeywords()) {
        flags[flag[1].lowercaseString] = flag[0];
        values[flag[0]] = @NO;
    }

    while (1) {
        if (![src expectAnyToken:&token error:NULL]) {
            return UDDefaultSoundValues();
        }
        // end of definition
        else if (!strcmp(token.text, "}")) {
            break;
        }
        NSString *keyword = UDTokenString(&token);
        // minimum number of sounds
        if (!strcasecmp(token.text, "minSamples")) {
            int v = 0;
            [src parseInt:&v error:NULL];
            values[@"minSamples"] = @(v);
        }
        // description
        else if (!strcasecmp(token.text, "description")) {
            [src readTokenOnLine:&token error:NULL];
            values[@"soundDescription"] = UDTokenString(&token);
        }
        // mindistance, maxdistance, volume, leadinVolume
        else if (!strcasecmp(token.text, "mindistance") || !strcasecmp(token.text, "maxdistance") ||
                 !strcasecmp(token.text, "volume") || !strcasecmp(token.text, "leadinVolume")) {
            float f = 0;
            [src parseFloat:&f error:NULL];
            NSString *key = !strcasecmp(token.text, "mindistance") ? @"minDistance"
                          : !strcasecmp(token.text, "maxdistance") ? @"maxDistance"
                          : !strcasecmp(token.text, "volume") ? @"volume" : @"leadinVolume";
            values[key] = @(f);
        }
        // shakes screen
        else if (!strcasecmp(token.text, "shakes")) {
            [src expectAnyToken:&token error:NULL];
            if (token.type == TT_NUMBER) {
                values[@"shakes"] = @(idToken_FloatValue(&token));
            } else {
                [src unreadToken:&token error:NULL];
                values[@"shakes"] = @1.0f;
            }
        }
        // reverb, no longer supported: kept
        else if (!strcasecmp(token.text, "reverb")) {
            float a = 0, b = 0;
            [src parseFloat:&a error:NULL];
            if (![src expectTokenString:@"," error:NULL]) {
                [src freeSource];
                return UDDefaultSoundValues();
            }
            [src parseFloat:&b error:NULL];
            values[@"reverb"] = [NSString stringWithFormat:@"%g, %g", a, b];
        }
        // soundClass
        else if (!strcasecmp(token.text, "soundClass")) {
            int v = 0;
            [src parseInt:&v error:NULL];
            if (v < 0 || v >= 4) {                          // SOUND_MAX_CLASSES
                [src warning:@"SoundClass out of range"];
                return UDDefaultSoundValues();
            }
            values[@"soundClass"] = @(v);
        }
        // altSound
        else if (!strcasecmp(token.text, "altSound")) {
            if (![src expectAnyToken:&token error:NULL]) {
                return UDDefaultSoundValues();
            }
            values[@"altSound"] = UDTokenString(&token);
        }
        // the flags and speaker masks (ordered, plain and onDemand no longer supported: kept)
        else if (flags[keyword.lowercaseString] != nil) {
            values[flags[keyword.lowercaseString]] = @YES;
        }
        // the wave files
        else if (!strcasecmp(token.text, "leadin")) {
            // add to the leadin list
            if (![src readToken:&token error:NULL]) {
                [src warning:@"Expected sound after leadin"];
                return UDDefaultSoundValues();
            }
            [leadins addObject:[UDSoundSample sampleWithPath:UDTokenString(&token)]];
        } else if ([keyword rangeOfString:@".wav" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                   [keyword rangeOfString:@".ogg" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            // add to the wav list
            [samples addObject:[UDSoundSample sampleWithPath:[keyword stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]]];
        } else {
            [src warning:@"unknown token '%s'", token.text];
            return UDDefaultSoundValues();
        }
    }
    values[@"samples"] = samples;
    values[@"leadins"] = leadins;
    return values;
}

static NSString *UDFloatText(NSNumber *number) {
    return [NSString stringWithFormat:@"%g", number.doubleValue];
}

// What ParseShader reads, a keyword a line: the parameters set, the flags,
// then the leadins and the samples.
+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString stringWithFormat:@"sound %@\n{\n", name];
    NSString *description = values[@"soundDescription"];
    if (description.length > 0) [out appendFormat:@"\tdescription\t\t\"%@\"\n", description];
    if (values[@"minSamples"] != nil) [out appendFormat:@"\tminSamples\t\t%ld\n", (long)[values[@"minSamples"] integerValue]];
    for (NSArray<NSString *> *parameter in @[@[@"minDistance", @"minDistance"], @[@"maxDistance", @"maxDistance"],
                                             @[@"volume", @"volume"], @[@"leadinVolume", @"leadinVolume"], @[@"shakes", @"shakes"]]) {
        NSNumber *value = values[parameter[0]];
        if (value != nil) [out appendFormat:@"\t%@\t\t%@\n", parameter[1], UDFloatText(value)];
    }
    if (values[@"soundClass"] != nil) [out appendFormat:@"\tsoundClass\t\t%ld\n", (long)[values[@"soundClass"] integerValue]];
    NSString *altSound = values[@"altSound"];
    if (altSound.length > 0) [out appendFormat:@"\taltSound\t\t%@\n", altSound];
    NSString *reverb = values[@"reverb"];
    if (reverb.length > 0) [out appendFormat:@"\treverb\t\t\t%@\n", reverb];
    for (NSArray<NSString *> *flag in UDSoundFlagKeywords()) {
        if ([values[flag[0]] boolValue]) [out appendFormat:@"\t%@\n", flag[1]];
    }
    for (UDSoundSample *leadin in values[@"leadins"]) {
        if (leadin.path.length > 0) [out appendFormat:@"\tleadin %@\n", leadin.path];
    }
    for (UDSoundSample *sample in values[@"samples"]) {
        if (sample.path.length > 0) [out appendFormat:@"\t%@\n", sample.path];
    }
    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end
