/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDSliderDefInspectorController.h — Controller for sliderDef attributes.
 */

#import "UDGuiAttributeSubcontroller.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDSliderDefInspectorController : UDGuiAttributeSubcontroller

@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrSliderCvarField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrSliderLowField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrSliderHighField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrSliderStepField;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrSliderVerticalButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrSliderScrollBarButton;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrSliderThumbShaderField;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrSliderLiveUpdateButton;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrSliderCvarGroupField;

@end

NS_ASSUME_NONNULL_END
