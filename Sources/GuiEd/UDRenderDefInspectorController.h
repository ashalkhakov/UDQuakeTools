/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDRenderDefInspectorController.h — Controller for renderDef attributes.
 */

#import "UDGuiAttributeSubcontroller.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDRenderDefInspectorController : UDGuiAttributeSubcontroller

@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrRenderModelField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrRenderAnimField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrRenderAnimClassField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrRenderLightOriginField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrRenderLightColorField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrRenderModelOriginField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrRenderModelRotateField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *attrRenderViewOffsetField;
@property (nonatomic, weak, nullable) IBOutlet NSButton    *attrRenderNeedsRenderButton;

@end

NS_ASSUME_NONNULL_END
