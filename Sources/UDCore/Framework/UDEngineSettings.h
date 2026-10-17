/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDEngineSettings.h — the settings the framework (idFileSystem,
 * idDeclManager) reads: in the engine, cvars (fs_basepath, fs_game,
 * com_singleDeclFile, ...); here a workspace's, which adopts this, so the
 * framework needs nothing of the workspace's.
 */

#import <Foundation/Foundation.h>
#import "UDGame.h"

NS_ASSUME_NONNULL_BEGIN

@protocol UDEngineSettings <NSObject>
/// The game whose files these are (the decl types it registers).
@property (assign, nonatomic) UDGameType game;
@property (strong, nonatomic) NSString *pakFileExtension;
@property (strong, nonatomic) NSString *gamedir;
@property (assign, nonatomic) BOOL fs_debug;
@property (assign, nonatomic) BOOL fs_restrict;
@property (assign, nonatomic) int fs_copyfiles;
@property (strong, nonatomic) NSString *fs_basepath;
@property (strong, nonatomic) NSString *fs_homepath;
@property (strong, nonatomic) NSString *fs_savepath;
@property (strong, nonatomic) NSString *fs_cdpath;
@property (strong, nonatomic) NSString *fs_game;
@property (strong, nonatomic) NSString *fs_game_base;
@property (assign, nonatomic) BOOL fs_caseSensitiveOS;
@property (assign, nonatomic) NSInteger decl_show;
@property (assign, nonatomic) BOOL com_SingleDeclFile;
@property (strong, nonatomic, nullable) NSString *com_singleDeclFileName;
@property (assign, nonatomic) NSInteger com_singleDeclFileWriteMode;
@end

NS_ASSUME_NONNULL_END
