/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDListDefInspectorController.h — Controller for listDef attributes.
 */

#import "UDGuiAttributeSubcontroller.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDListDefInspectorController : UDGuiAttributeSubcontroller

@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrListHorizontalButton;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrListNameField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrListTabStopsField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrListTabAlignsField;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrListMultipleSelButton;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrListTabStopsHintLabel;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrListTabAlignsHintLabel;

@end

NS_ASSUME_NONNULL_END
