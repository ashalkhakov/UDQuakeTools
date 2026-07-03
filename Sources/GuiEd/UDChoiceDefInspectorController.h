/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDChoiceDefInspectorController.h — Controller for choiceDef attributes.
 */

#import "UDGuiAttributeSubcontroller.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDChoiceDefInspectorController : UDGuiAttributeSubcontroller

@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrChoiceCvarField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrChoiceChoiceTypeField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrChoiceChoicesField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrChoiceValuesField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrChoiceCurrentField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrChoiceGuiField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrChoiceCvarGroupField;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrChoiceLiveUpdateButton;

@end

NS_ASSUME_NONNULL_END
