/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Descriptor and registry for known id Tech 4 decl types.
 */

#import "UDDeclType.h"

// ---------------------------------------------------------------------------
// UDDeclTypeDescriptor
// ---------------------------------------------------------------------------

@implementation UDDeclTypeDescriptor

@synthesize identifier = _identifier;
@synthesize displayName = _displayName;
@synthesize sourceFileExtensions = _sourceFileExtensions;
@synthesize defaultDirectory = _defaultDirectory;
@synthesize supportedGameTypes = _supportedGameTypes;

- (instancetype)initWithIdentifier:(NSString *)identifier
                       displayName:(NSString *)displayName
              sourceFileExtensions:(NSArray<NSString *> *)sourceFileExtensions
                  defaultDirectory:(NSString *)defaultDirectory {
    return [self initWithIdentifier:identifier
                        displayName:displayName
               sourceFileExtensions:sourceFileExtensions
                   defaultDirectory:defaultDirectory
                supportedGameTypes:[NSSet set]];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                       displayName:(NSString *)displayName
              sourceFileExtensions:(NSArray<NSString *> *)sourceFileExtensions
                  defaultDirectory:(NSString *)defaultDirectory
               supportedGameTypes:(NSSet<NSNumber *> *)supportedGameTypes {
    NSParameterAssert(identifier.length > 0);
    NSParameterAssert(displayName.length > 0);
    NSParameterAssert(sourceFileExtensions.count > 0);
    NSParameterAssert(defaultDirectory.length > 0);

    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _displayName = [displayName copy];
        _sourceFileExtensions = [sourceFileExtensions copy];
        _defaultDirectory = [defaultDirectory copy];
        _supportedGameTypes = [supportedGameTypes copy];
    }
    return self;
}

- (BOOL)supportsGameType:(UDGameType)gameType {
    if (_supportedGameTypes.count == 0) {
        return YES;
    }
    if ([_supportedGameTypes containsObject:@(UDGameTypeUnknown)]) {
        return YES;
    }
    return [_supportedGameTypes containsObject:@(gameType)];
}

- (BOOL)hasExclusiveFileExtension {
    // A type has an exclusive extension when none of its source file extensions
    // is the shared generic .def format.
    for (NSString *ext in _sourceFileExtensions) {
        if ([ext isEqualToString:@"def"]) {
            return NO;
        }
    }
    return YES;
}

@end

// ---------------------------------------------------------------------------
// UDDeclTypeRegistry
// ---------------------------------------------------------------------------

@implementation UDDeclTypeRegistry

/**
 * The canonical decl type table.
 *
 * Registration order mirrors how idDeclManager registers types during Doom 3
 * startup and Quake 3 asset browsing: types with dedicated file extensions
 * come first (shader → .shader, material → .mtr, skin → .skin, etc.),
 * followed by the types that share the generic .def format (entityDef,
 * modelDef, table).
 *
 * When the parser encounters a decl block without an explicit type keyword
 * (common in .mtr, .skin, and .sndshd files) the enclosing file's extension
 * is used to infer the type via -exclusiveDescriptorForFileExtension:.
 */
+ (NSArray<UDDeclTypeDescriptor *> *)allDescriptors {
    static NSArray<UDDeclTypeDescriptor *> *descriptors = nil;
    if (!descriptors) {
        descriptors = @[
            // --- Types with exclusive file extensions ---

            // .shader → scripts/  (Quake 3 shader decls)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"shader"
                                                 displayName:@"Shader"
                                        sourceFileExtensions:@[@"shader"]
                                                          defaultDirectory:@"scripts"
                                                      supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeQuake3), nil]],

            // .mtr  →  materials/  (idDeclMaterial)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"material"
                                                 displayName:@"Material"
                                        sourceFileExtensions:@[@"mtr"]
                                                          defaultDirectory:@"materials"
                                                      supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // .skin  →  skins/  (idDeclSkin)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"skin"
                                                 displayName:@"Skin"
                                        sourceFileExtensions:@[@"skin"]
                                                          defaultDirectory:@"skins"
                                                      supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeQuake3), @(UDGameTypeDoom3), nil]],

            // .sounds  →  sound/  (Quake 3 sound decls)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"sound"
                                                 displayName:@"Sound Shader"
                                        sourceFileExtensions:@[@"sounds"]
                                                          defaultDirectory:@"sound"
                                         supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeQuake3), nil]],

            // .sndshd  →  sound/  (Doom 3 sound shader decls)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"sound"
                                                 displayName:@"Sound Shader"
                                        sourceFileExtensions:@[@"sndshd"]
                                            defaultDirectory:@"sound"
                                         supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // .fx  →  fx/  (idDeclFX)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"fx"
                                                 displayName:@"Effect"
                                        sourceFileExtensions:@[@"fx"]
                                                          defaultDirectory:@"fx"
                                                      supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // .prt  →  particles/  (idDeclParticle)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"particle"
                                                 displayName:@"Particle"
                                        sourceFileExtensions:@[@"prt"]
                                                          defaultDirectory:@"particles"
                                                      supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // .af  →  af/  (idDeclAF)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"articulatedFigure"
                                                 displayName:@"Articulated Figure"
                                        sourceFileExtensions:@[@"af"]
                                                          defaultDirectory:@"af"
                                                      supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // .pda  →  pda/  (idDeclPDA)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"pda"
                                                 displayName:@"PDA"
                                        sourceFileExtensions:@[@"pda"]
                                                          defaultDirectory:@"pda"
                                                      supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // .xdata  →  xdata/  (resurrection-of-evil / BFG extra data)
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"xdata"
                                                 displayName:@"Extra Data"
                                        sourceFileExtensions:@[@"xdata"]
                                                          defaultDirectory:@"xdata"
                                                      supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // --- Types that share the .def format ---

            // entityDef is the primary .def inhabitant (idDeclEntityDef).
            // .def files also carry modelDef, table, exportDef, and custom
            // types registered by game code, so the extension alone is not
            // enough to determine the type — the keyword inside the block must
            // be read.
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"entityDef"
                                                 displayName:@"Entity Definition"
                                        sourceFileExtensions:@[@"def"]
                                            defaultDirectory:@"def"
                                         supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // modelDef lives in .def alongside entityDef (idDeclModelDef).
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"modelDef"
                                                 displayName:@"Model Definition"
                                        sourceFileExtensions:@[@"def"]
                                            defaultDirectory:@"def"
                                         supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],

            // table is an inline lookup table also declared in .def files.
            [[UDDeclTypeDescriptor alloc] initWithIdentifier:@"table"
                                                 displayName:@"Table"
                                        sourceFileExtensions:@[@"def"]
                                            defaultDirectory:@"def"
                                         supportedGameTypes:[NSSet setWithObjects:@(UDGameTypeDoom3), nil]],
        ];
    }
    return descriptors;
}

+ (NSSet<NSString *> *)allSourceFileExtensions {
    static NSSet<NSString *> *extensions = nil;
    if (!extensions) {
        NSMutableSet<NSString *> *mutable = [NSMutableSet set];
        for (UDDeclTypeDescriptor *descriptor in [self allDescriptors]) {
            [mutable addObjectsFromArray:descriptor.sourceFileExtensions];
        }
        extensions = [mutable copy];
    }
    return extensions;
}

+ (NSArray<UDDeclTypeDescriptor *> *)descriptorsForGameType:(UDGameType)gameType {
    if (gameType == UDGameTypeUnknown) {
        return [self allDescriptors];
    }

    NSMutableArray<UDDeclTypeDescriptor *> *descriptors = [NSMutableArray array];
    for (UDDeclTypeDescriptor *descriptor in [self allDescriptors]) {
        if ([descriptor supportsGameType:gameType]) {
            [descriptors addObject:descriptor];
        }
    }
    return descriptors;
}

+ (NSSet<NSString *> *)sourceFileExtensionsForGameType:(UDGameType)gameType {
    if (gameType == UDGameTypeUnknown) {
        return [self allSourceFileExtensions];
    }

    NSMutableSet<NSString *> *extensions = [NSMutableSet set];
    for (UDDeclTypeDescriptor *descriptor in [self descriptorsForGameType:gameType]) {
        [extensions addObjectsFromArray:descriptor.sourceFileExtensions];
    }
    return [extensions copy];
}

+ (nullable UDDeclTypeDescriptor *)descriptorForIdentifier:(NSString *)identifier {
    NSString *lower = identifier.lowercaseString;
    for (UDDeclTypeDescriptor *descriptor in [self allDescriptors]) {
        if ([descriptor.identifier.lowercaseString isEqualToString:lower]) {
            return descriptor;
        }
    }
    return nil;
}

+ (nullable UDDeclTypeDescriptor *)exclusiveDescriptorForFileExtension:(NSString *)extension {
    NSString *lower = extension.lowercaseString;
    // Explicitly exclude .def: multiple types share this extension and the
    // type can only be determined by reading the keyword inside each block.
    if ([lower isEqualToString:@"def"]) {
        return nil;
    }
    for (UDDeclTypeDescriptor *descriptor in [self allDescriptors]) {
        if ([descriptor.sourceFileExtensions containsObject:lower]) {
            return descriptor;
        }
    }
    return nil;
}

+ (nullable NSString *)defaultDeclIdentifierForFileExtension:(NSString *)extension {
    return [self exclusiveDescriptorForFileExtension:extension].identifier;
}

+ (NSString *)canonicalIdentifierForIdentifier:(NSString *)identifier {
    UDDeclTypeDescriptor *descriptor = [self descriptorForIdentifier:identifier];
    return descriptor ? descriptor.identifier : identifier;
}

@end
