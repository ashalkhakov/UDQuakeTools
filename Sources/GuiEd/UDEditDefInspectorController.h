/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDEditDefInspectorController.h — Controller for editDef attributes.
 */

#import "UDGuiAttributeSubcontroller.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDEditDefInspectorController : UDGuiAttributeSubcontroller

@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrEditCvarField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrEditSourceField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrEditCvarGroupField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrEditMaxCharsField;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrEditNumericButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrEditWrapButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrEditReadOnlyButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrEditForceScrollButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrEditPasswordButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrEditLiveUpdateButton;

@end

NS_ASSUME_NONNULL_END
