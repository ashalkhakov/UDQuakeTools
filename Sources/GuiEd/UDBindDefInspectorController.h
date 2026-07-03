/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDBindDefInspectorController.h — Controller for bindDef attributes.
 */

#import "UDGuiAttributeSubcontroller.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDBindDefInspectorController : UDGuiAttributeSubcontroller

@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrBindField;

@end

NS_ASSUME_NONNULL_END
