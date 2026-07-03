/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@class UDGuiWindowNode;

typedef NS_ENUM(NSInteger, UDGuiAttributeTypeTab) {
    UDGuiAttributeTypeTabEdit = 0,
    UDGuiAttributeTypeTabChoice,
    UDGuiAttributeTypeTabBind,
    UDGuiAttributeTypeTabList,
    UDGuiAttributeTypeTabSlider,
    UDGuiAttributeTypeTabRender,
};

@interface UDGuiEdDocumentWindowController (TypedPanels)

- (void)updateAttributeGroupVisibilityForWindow:(nullable UDGuiWindowNode *)window;
- (void)refreshTypedValidationHintsForWindow:(nullable UDGuiWindowNode *)window;
- (void)syncCommonInfoPanelFromWindow:(nullable UDGuiWindowNode *)window;
- (void)syncTypedPanelsFromWindow:(nullable UDGuiWindowNode *)window;

- (void)applyCommonInfoPanelToWindow:(UDGuiWindowNode *)window;
- (void)applySizePanelToWindow:(UDGuiWindowNode *)window;
- (void)applyTypedPanelsToWindow:(UDGuiWindowNode *)window;

- (BOOL)validateSizePanelForWindow:(UDGuiWindowNode *)window;
- (BOOL)validateTypedPanelsForWindow:(UDGuiWindowNode *)window;

- (UDGuiAttributeTypeTab)attributeTypeTabForWindow:(nullable UDGuiWindowNode *)window;

@end

NS_ASSUME_NONNULL_END
