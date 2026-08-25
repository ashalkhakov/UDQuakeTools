#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A small reusable one-line text prompt dialog: title, explanatory message,
 * a text field, and OK/Cancel buttons, run as a modal panel.
 *
 * Built programmatically (no xib) on purpose: the obvious alternative —
 * NSAlert with an accessoryView — does not exist on GNUstep, while a plain
 * modal NSPanel works identically on both platforms.
 *
 * Used by Save As… to ask for the new decl name; reusable anywhere a single
 * string needs prompting.
 */
@interface UDTextPromptPanel : NSPanel

/**
 * Runs the prompt modally. Returns the entered string (unvalidated,
 * untrimmed — the caller decides what's acceptable), or nil on cancel.
 */
+ (nullable NSString *)runModalPromptWithTitle:(NSString *)title
                                       message:(nullable NSString *)message
                                  initialValue:(nullable NSString *)initialValue
                                 okButtonTitle:(NSString *)okButtonTitle;

@end

NS_ASSUME_NONNULL_END
