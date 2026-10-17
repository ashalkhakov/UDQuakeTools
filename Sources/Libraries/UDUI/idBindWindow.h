/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idBindWindow.h — a bindDef (ui/BindWindow.h, BindWindow.cpp), ported.
 */

#import "idWindow.h"

NS_ASSUME_NONNULL_BEGIN

@interface idBindWindow : idWindow {
@public
    idWinStr *bindName;
    BOOL waitingOnKey;
}
@end

NS_ASSUME_NONNULL_END
