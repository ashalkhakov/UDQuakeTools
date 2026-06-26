/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDFileActionService.h — Service to handle file actions (previewing, custom tools, or OS open).
 */

#import <AppKit/AppKit.h>

@class UDTextPreviewController;

NS_ASSUME_NONNULL_BEGIN

@interface UDFileActionService : NSObject

- (nullable UDTextPreviewController *)openFileAtPath:(NSString *)tempPath
                                            withData:(NSData *)data
                                        parentWindow:(nullable NSWindow *)parentWindow
                                       modalDelegate:(nullable id)modalDelegate
                                      didEndSelector:(nullable SEL)didEndSelector;

+ (BOOL)isPlainTextData:(NSData *)data extension:(NSString *)ext;
- (nullable NSString *)customCommandForExtension:(NSString *)ext;

@end

NS_ASSUME_NONNULL_END
