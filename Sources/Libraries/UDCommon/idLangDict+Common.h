/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idLangDict+Common.h — idCommonLocal's language dictionary (InitLanguageDict):
 * the framework's, as it lists the language's files with its file system.
 */

#import "idLangDict.h"

@class idFileSystem;

NS_ASSUME_NONNULL_BEGIN

@interface idLangDict (Common)
/// idCommonLocal::InitLanguageDict, for @a language (sys_lang's).
- (void)initLanguage:(NSString *)language fileSystem:(idFileSystem *)fileSystem;
@end

NS_ASSUME_NONNULL_END
