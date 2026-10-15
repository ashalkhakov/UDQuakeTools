/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclTextChecker — what is wrong with a decl's text, by line, the way the
 * decl manager's lexer sees it: lexer errors and warnings (an unterminated
 * string or comment, a bad number…), braces that do not balance, a missing
 * name or '{', and text after the decl's closing brace. One pass of the
 * lexer: linear in the text.
 */

#import <Foundation/Foundation.h>

@class idFileSystem;

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclTextProblem : NSObject
@property (nonatomic, readonly) NSInteger line;        // 1-based
@property (nonatomic, readonly, copy) NSString *message;
@property (nonatomic, readonly) BOOL isError;          // NO: a warning
@end

@interface UDDeclTextChecker : NSObject

/// The problems in one decl's text: either its braced body ("{ … }") or the
/// whole decl ("[type] name { … }"), as the decl editors show and save it.
/// Sorted by line.
+ (NSArray<UDDeclTextProblem *> *)problemsInDeclText:(NSString *)text
                                          fileSystem:(nullable idFileSystem *)fileSystem;

@end

NS_ASSUME_NONNULL_END
