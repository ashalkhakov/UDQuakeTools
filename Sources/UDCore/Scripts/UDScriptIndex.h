//
//  UDScriptIndex.h
//  UDCore
//
//  Where each name in a mod's scripts is defined, for go to definition:
//  every function, object, method, scriptEvent, namespace and global
//  variable. A script's definitions are read by walking its tokens as
//  idCompiler's ParseDefs does (ParseNamespace, ParseObjectDef,
//  ParseFunctionDef, ParseVariableDef), skipping bodies; the preprocessor's
//  lines are skipped.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDScriptDefinitionKind) {
    UDScriptDefinitionFunction,
    UDScriptDefinitionFunctionPrototype,
    UDScriptDefinitionObject,
    UDScriptDefinitionMethod,               // defined, in or out of its object
    UDScriptDefinitionMethodPrototype,      // declared in its object
    UDScriptDefinitionField,
    UDScriptDefinitionEvent,                // scriptEvent
    UDScriptDefinitionNamespace,
    UDScriptDefinitionVariable,
};

@interface UDScriptDefinition : NSObject
@property (nonatomic, readonly) UDScriptDefinitionKind kind;
/// The name as written: "flicker".
@property (nonatomic, copy, readonly) NSString *name;
/// With its scope: "lamp::flicker", "lamps::glow"; the name, at global scope.
@property (nonatomic, copy, readonly) NSString *qualifiedName;
/// The script's path in the file system ("script/lamp.script").
@property (nonatomic, copy, readonly) NSString *path;
/// Where the name is, 0-based; the column in UTF-16 units.
@property (nonatomic, readonly) NSInteger line;
@property (nonatomic, readonly) NSInteger column;
@property (nonatomic, readonly) NSInteger length;
/// A function's or method's parameters, as written between its parentheses
/// ("float times", "" for none); nil for what is no function.
@property (nonatomic, copy, readonly, nullable) NSString *parameters;
@end

@interface UDScriptIndex : NSObject

/// The definitions in @a text, the script at @a path, replacing any it had.
- (void)setText:(NSString *)text forPath:(NSString *)path;
- (void)removePath:(NSString *)path;
- (BOOL)hasPath:(NSString *)path;

/// The definitions of @a name: "lamp::flicker" or "ns::name" names one
/// scope's; a bare name, any scope's. Definitions before prototypes.
- (NSArray<UDScriptDefinition *> *)definitionsOfName:(NSString *)name;

/// Every definition, path by path, as read.
@property (nonatomic, readonly) NSArray<UDScriptDefinition *> *allDefinitions;

/// The definitions in one script, as read.
+ (NSArray<UDScriptDefinition *> *)definitionsInText:(NSString *)text path:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
