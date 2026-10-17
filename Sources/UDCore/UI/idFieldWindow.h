/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idFieldWindow.h — a fieldDef (ui/FieldWindow.h, FieldWindow.cpp), ported.
 */

#import "idWindow.h"

NS_ASSUME_NONNULL_BEGIN

@interface idFieldWindow : idWindow {
@public
    int cursorPos;
    int lastTextLength;
    int lastCursorPos;
    int paintOffset;
    BOOL showCursor;
    NSString *cursorVar;
}
@end

NS_ASSUME_NONNULL_END
