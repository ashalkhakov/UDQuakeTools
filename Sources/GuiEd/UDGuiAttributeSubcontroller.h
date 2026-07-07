/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiAttributeSubcontroller.h — Base class for typed inspector sub-controllers.
 */

#import <AppKit/AppKit.h>
#import "UDEditorControllerContext.h"
#import "../UDCore/UDGuiModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiAttributeSubcontroller : NSObject {
    NSView *_view;
}

@property (nonatomic, strong, readonly) IBOutlet NSView *view;
@property (nonatomic, weak, nullable) id<UDEditorControllerContext> context;

- (instancetype)initWithNibName:(NSString *)nibName;

- (void)syncFromWindow:(nullable UDGuiWindowNode *)window;
- (void)applyToWindow:(UDGuiWindowNode *)window;

- (BOOL)validatePropertiesForWindow:(UDGuiWindowNode *)window;
- (void)refreshValidationHintsForWindow:(nullable UDGuiWindowNode *)window;

// Validation helper
- (BOOL)validateEditorValue:(id)value forKey:(NSString *)key onWindow:(UDGuiWindowNode *)window;

// Sync helpers
- (void)syncBoolButton:(NSButton *)button key:(NSString *)key window:(nullable UDGuiWindowNode *)window defaultOnWhenNil:(BOOL)defaultOnWhenNil;
- (void)syncDoubleField:(NSTextField *)field key:(NSString *)key window:(nullable UDGuiWindowNode *)window;
- (void)syncIntegerField:(NSTextField *)field key:(NSString *)key window:(nullable UDGuiWindowNode *)window;
- (void)syncStringField:(NSTextField *)field key:(NSString *)key window:(nullable UDGuiWindowNode *)window;

// Apply helpers
- (void)applyBoolButton:(NSButton *)button key:(NSString *)key window:(UDGuiWindowNode *)window;
- (void)applyDoubleField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window;
- (void)applyIntegerField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window;
- (void)applyStringField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window;

- (IBAction)commitTypedAttributesPanel:(id)sender;

@end

NS_ASSUME_NONNULL_END
