/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclSound.h — sound shaders (idSoundShader).
 */

#import "UDDeclElement.h"

NS_ASSUME_NONNULL_BEGIN

/// One of a sound shader's samples or leadins: a .wav or .ogg path.
@interface UDSoundSample : UDDeclElement
@property (nonatomic, copy) NSString *path;
+ (instancetype)sampleWithPath:(NSString *)path;
@end

/// A sound shader, as idSoundShader::ParseShader reads it. A parameter it
/// does not set is nil (the engine's default then); the flags are its
/// SSF_* keywords and speaker masks. ordered, plain, onDemand and reverb are
/// no longer supported by the engine, kept so that an edit does not drop
/// them. samples and leadins are TRANSIENT, as a table's values are.
@interface UDDeclSound : UDDeclBase
@property (nonatomic, copy, nullable) NSString *soundDescription;
@property (nonatomic, copy, nullable) NSNumber *minSamples;
@property (nonatomic, copy, nullable) NSNumber *minDistance;
@property (nonatomic, copy, nullable) NSNumber *maxDistance;
@property (nonatomic, copy, nullable) NSNumber *volume;
@property (nonatomic, copy, nullable) NSNumber *leadinVolume;
@property (nonatomic, copy, nullable) NSNumber *shakes;
@property (nonatomic, copy, nullable) NSNumber *soundClass;
@property (nonatomic, copy, nullable) NSString *altSound;
@property (nonatomic, copy, nullable) NSString *reverb;
@property (nonatomic) BOOL noDups, noFlicker, looping, noOcclusion, privateSound, antiPrivate,
                           playOnce, global, unclamped, omnidirectional;
@property (nonatomic) BOOL maskCenter, maskLeft, maskRight, maskBackLeft, maskBackRight, maskLFE;
@property (nonatomic) BOOL ordered, plain, onDemand;
@property (nonatomic, copy, nullable) NSArray<UDSoundSample *> *samples;
@property (nonatomic, copy, nullable) NSArray<UDSoundSample *> *leadins;
@end

NS_ASSUME_NONNULL_END
