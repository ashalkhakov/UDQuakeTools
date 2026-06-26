/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDTextPreviewController — NSWindowController for a simple, read-only
 * text preview sheet.
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDTextPreviewController : NSWindowController {
    NSTextView  *_textView;
    NSTextField *_titleLabel;
}

@property (nonatomic, strong, readonly) NSTextView *textView;
@property (nonatomic, strong, readonly) NSTextField *titleLabel;

- (instancetype)initWithText:(NSString *)text title:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
