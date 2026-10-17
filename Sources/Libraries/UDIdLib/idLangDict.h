/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idLangDict.h — the localized string table (idlib/LangDict.cpp), loaded as
 * idCommonLocal::InitLanguageDict loads it: every strings/<sys_lang>*.lang.
 */

#import <Foundation/Foundation.h>
#import "idFileAccess.h"


NS_ASSUME_NONNULL_BEGIN

#define STRTABLE_ID             @"#str_"
#define STRTABLE_ID_LENGTH      5

/// Who hears common->Warning: -uiWarning: with the message.
@protocol idUIWarnings <NSObject>
- (void)uiWarning:(NSString *)message;
@end

@interface idLangDict : NSObject

- (void)clear;
/// idLangDict::Load( fileName, clear )
- (BOOL)load:(NSString *)fileName clear:(BOOL)clear fileSystem:(id<idFileSystemReading>)fileSystem;
/// idLangDict::GetString: the string of a "#str_" id; any other string
/// itself; an unknown id itself, with a warning.
- (NSString *)getString:(NSString *)str;
- (int)numKeyVals;

@property (nonatomic, weak, nullable) id<idUIWarnings> warnings;

@end

NS_ASSUME_NONNULL_END
