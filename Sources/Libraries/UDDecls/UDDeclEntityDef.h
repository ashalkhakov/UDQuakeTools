/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclEntityDef.h — entityDefs and mapDefs (idDeclEntityDef).
 */

#import "UDDeclElement.h"

NS_ASSUME_NONNULL_BEGIN

/// One of an entityDef's key/value pairs (a spawnArg).
@interface UDEntityKeyValue : UDDeclElement
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *value;
+ (instancetype)keyValueWithKey:(NSString *)key value:(NSString *)value;
@end

/// An inherited pair: the key/value, and the entityDef it comes from.
@interface UDInheritedKeyValue : NSObject
@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly, copy) NSString *value;
@property (nonatomic, readonly, copy) NSString *from;
@end

/// An entityDef (and a mapDef, which the engine parses as one): its own
/// key/value pairs, in order, as idDeclEntityDef::Parse reads them before it
/// merges in what it inherits. TRANSIENT, as a table's values are.
@interface UDDeclEntityDef : UDDeclBase
@property (nonatomic, copy, nullable) NSArray<UDEntityKeyValue *> *keyValues;

/// The "inherit" pair's value, or nil; setting it sets, adds (first) or,
/// with nil or "", removes that pair.
@property (nonatomic, copy, nullable) NSString *inherit;

/// What it inherits and does not set itself, as idDeclEntityDef::Parse
/// merges it (each "inherit…" key's entityDef, its own inheritance
/// resolved, filling in the keys not yet set), from the decls in its
/// context. @a unknown gets the inherited names no entityDef has.
- (NSArray<UDInheritedKeyValue *> *)ud_inheritedKeyValuesUnknown:(NSArray<NSString *> * _Nullable * _Nullable)unknown;

/// The spawnArgs' help, from the editor_* keys of the decl and what it
/// inherits, as Radiant's EClass_InitFromDict reads them: the entity's
/// editor_usage, and each key's editor_var (editor_int, editor_bool, ...).
- (nullable NSString *)ud_usage;
- (nullable NSString *)ud_helpForKey:(NSString *)key;
/// The type the editor_* key that gives @a key's help names: "var",
/// "int", "float", "bool", "color", "mat", "model", "gui" or "snd"; nil
/// for none.
- (nullable NSString *)ud_editorTypeForKey:(NSString *)key;
@end

@interface UDDeclMapDef : UDDeclEntityDef
@end

NS_ASSUME_NONNULL_END
