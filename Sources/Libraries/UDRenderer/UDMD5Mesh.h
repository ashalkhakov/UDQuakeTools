/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDMD5Mesh.h — a model's joints: the modelDef's mesh, and the .md5mesh's
 * joints (idDeclModelDef::Parse up to its mesh, idRenderModelMD5::LoadModel
 * up to its joints).
 */

#import <Foundation/Foundation.h>

@class idDeclManager, idFileSystem;

NS_ASSUME_NONNULL_BEGIN

@interface UDMD5Mesh : NSObject

/// The joints of the .md5mesh at @a path, in order, as LoadModel's
/// ParseJoint reads them: their names; nil when the file is not there or
/// is not one (an error says why).
+ (nullable NSArray<NSString *> *)jointNamesOfMeshAtPath:(NSString *)path
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError * _Nullable * _Nullable)error;

/// The .md5mesh the modelDef @a name gives a model, as idDeclModelDef::Parse
/// finds it: its own "mesh", or the one it inherits; nil when it has none.
+ (nullable NSString *)meshOfModelDef:(NSString *)name declManager:(idDeclManager *)declManager;

/// The joints of the model the modelDef @a name gives (an articulated
/// figure's "model"); nil when there are none to be found.
+ (nullable NSArray<NSString *> *)jointNamesOfModelDef:(NSString *)name
                                           declManager:(idDeclManager *)declManager
                                            fileSystem:(idFileSystem *)fileSystem;

@end

NS_ASSUME_NONNULL_END
