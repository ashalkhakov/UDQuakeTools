/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclType.h — Descriptor and registry for known id Tech 4 decl types.
 *
 * In idLib / Doom 3 BFG the decl system maintains a list of registered
 * idDeclType objects, each associating a type name ("entityDef", "material",
 * etc.) with a typed allocator callback.  This file mirrors that concept as
 * static, read-only descriptors: a UDDeclTypeDescriptor carries everything a
 * browser or editor needs to know about a decl type without requiring live
 * game-engine classes — the canonical identifier, a human-readable name, which
 * file extensions hold decls of this type, and the virtual directory they
 * conventionally live in.
 *
 * UDDeclTypeRegistry is the authoritative table of all known id Tech 3 / 4
 * decl types and replaces the scattered static lookup functions that were
 * previously spread across UDAssetIndex.m and UDDeclManager.m.
 */

#import <Foundation/Foundation.h>

#import "UDGame.h"

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// UDDeclTypeDescriptor
// ---------------------------------------------------------------------------

/**
 * Static descriptor for one id Tech 4 decl type.
 *
 * Describes the metadata a browser needs to understand a decl type: its
 * canonical string identifier (as written in source files), a display name,
 * the file extensions whose content is parsed into decls of this type, and
 * the virtual path directory where those source files conventionally live.
 *
 * Descriptor objects are immutable and are owned by UDDeclTypeRegistry; callers
 * should not create them directly.
 */
@interface UDDeclTypeDescriptor : NSObject {
    NSString *_identifier;
    NSString *_displayName;
    NSArray<NSString *> *_sourceFileExtensions;
    NSString *_defaultDirectory;
    NSSet<NSNumber *> *_supportedGameTypes;
}

/**
 * Canonical type identifier exactly as written in decl source files.
 * Examples: @"entityDef", @"material", @"sound", @"articulatedFigure".
 */
@property (nonatomic, readonly, copy) NSString *identifier;

/**
 * Human-readable display name suitable for UI labels.
 * Examples: @"Entity Definition", @"Material", @"Sound Shader".
 */
@property (nonatomic, readonly, copy) NSString *displayName;

/**
 * File extensions (lowercase, without leading dot) whose content is parsed
 * into decls of this type.
 *
 * For types that have their own dedicated extension(s) (.shader, .mtr,
 * .skin, .sndshd, .sounds, .fx, .prt, .af, .pda, .xdata) this array contains
 * only dedicated extensions and -hasExclusiveFileExtension returns YES.
 *
 * For types that share the generic .def format (entityDef, modelDef, table)
 * the array is @[@"def"] but -hasExclusiveFileExtension returns NO.
 */
@property (nonatomic, readonly, copy) NSArray<NSString *> *sourceFileExtensions;

/**
 * Game types that can use this decl type.
 * If the set is empty or contains UDGameTypeUnknown, the type is treated as
 * available for any game.
 */
@property (nonatomic, readonly, copy) NSSet<NSNumber *> *supportedGameTypes;

/**
 * Virtual path directory where source files for this decl type conventionally
 * reside (e.g. @"def", @"materials", @"sound", @"particles").
 * Does not carry a trailing slash.
 */
@property (nonatomic, readonly, copy) NSString *defaultDirectory;

/**
 * YES if the decl type has its own exclusive file extension so that the
 * extension alone identifies the type without needing to inspect the content.
 * NO for types such as entityDef, modelDef, and table that all share .def.
 */
@property (nonatomic, readonly, getter=hasExclusiveFileExtension) BOOL exclusiveFileExtension;

- (instancetype)initWithIdentifier:(NSString *)identifier
                       displayName:(NSString *)displayName
              sourceFileExtensions:(NSArray<NSString *> *)sourceFileExtensions
                  defaultDirectory:(NSString *)defaultDirectory;

- (instancetype)initWithIdentifier:(NSString *)identifier
                       displayName:(NSString *)displayName
              sourceFileExtensions:(NSArray<NSString *> *)sourceFileExtensions
                  defaultDirectory:(NSString *)defaultDirectory
               supportedGameTypes:(NSSet<NSNumber *> *)supportedGameTypes NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

// ---------------------------------------------------------------------------
// UDDeclTypeRegistry
// ---------------------------------------------------------------------------

/**
 * The canonical table of known id Tech 4 / Doom 3 decl types.
 *
 * All methods are class-level and operate on a lazily-built, immutable
 * descriptor table.  This is the single authoritative source for extension-
 * to-type mappings, canonical identifier normalisation, and the set of
 * extensions that the asset indexer should scan.
 */
@interface UDDeclTypeRegistry : NSObject

/**
 * All registered descriptors in canonical registration order:
 * first the types with exclusive file extensions (shader, material, skin,
 * sound, fx, particle, articulatedFigure, pda, xdata), then the types that
 * share .def (entityDef, modelDef, table).
 */
+ (NSArray<UDDeclTypeDescriptor *> *)allDescriptors;

/**
 * The union of all sourceFileExtensions across all registered descriptors.
 * Suitable for use as the extension filter in the asset indexer.
 */
+ (NSSet<NSString *> *)allSourceFileExtensions;

/**
 * All source file extensions for the specified game type.  Unknown means the
 * union of all registered extensions.
 */
+ (NSSet<NSString *> *)sourceFileExtensionsForGameType:(UDGameType)gameType;

/**
 * All registered descriptors that apply to the specified game type.
 */
+ (NSArray<UDDeclTypeDescriptor *> *)descriptorsForGameType:(UDGameType)gameType;

/**
 * Returns the descriptor whose identifier matches the given string
 * case-insensitively, or nil if no such descriptor is registered.
 */
+ (nullable UDDeclTypeDescriptor *)descriptorForIdentifier:(NSString *)identifier;

/**
 * For file extensions that map exclusively to one decl type (.mtr → material,
 * .skin → skin, .sndshd → sound, etc.) returns the corresponding descriptor.
 *
 * Returns nil for @"def" because .def files can contain entityDef, modelDef,
 * table, and other types simultaneously, and for any unrecognised extension.
 */
+ (nullable UDDeclTypeDescriptor *)exclusiveDescriptorForFileExtension:(NSString *)extension;

/**
 * For file extensions with an exclusive type mapping, returns the canonical
 * identifier string (equivalent to -exclusiveDescriptorForFileExtension:
 * .identifier).  Returns nil for .def and unrecognised extensions.
 *
 * Used by the parser when a decl block has no explicit type keyword: the
 * enclosing file's extension implies the type.
 */
+ (nullable NSString *)defaultDeclIdentifierForFileExtension:(NSString *)extension;

/**
 * Normalises a type identifier string to its canonical mixed-case form.
 * Examples:
 *   @"EntityDef"          → @"entityDef"
 *   @"articulatedfigure"  → @"articulatedFigure"
 *   @"MATERIAL"           → @"material"
 *
 * If the identifier is not a known registered type the original string is
 * returned unchanged so that unknown custom types from mods are preserved.
 */
+ (NSString *)canonicalIdentifierForIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
