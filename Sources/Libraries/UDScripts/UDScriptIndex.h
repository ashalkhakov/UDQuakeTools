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
/// An object's superclass, as its declaration names it ("weapon_base" for
/// "object weapon_shotgun : weapon_base"); nil for none, and for what is
/// no object.
@property (nonatomic, copy, readonly, nullable) NSString *superclassName;
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

/// The variables of the function or method whose body holds @a line
/// (1-based, as the compiler numbers them) of @a text: its parameters, then
/// what its body declares (ParseVariableDef's "<type> <name>", "a, b"), each
/// once, in order; nil where no body holds the line. What a debugger asks
/// the game's interpreter for, which can read a variable by name but not
/// list them.
+ (nullable NSArray<NSString *> *)variablesOfFunctionAtLine:(NSInteger)line inText:(NSString *)text;
/// The lines (1-based, its braces' first to last) of the function or
/// method whose body holds @a line; {NSNotFound, 0} where none does.
+ (NSRange)linesOfFunctionAtLine:(NSInteger)line inText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
