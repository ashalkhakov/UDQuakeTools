/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idListWindow.h — a listDef (ui/ListWindow.h, ListWindow.cpp), ported.
 */

#import "idWindow.h"

@class idSliderWindow;

NS_ASSUME_NONNULL_BEGIN

enum {
    TAB_TYPE_TEXT = 0,
    TAB_TYPE_ICON = 1
};

typedef struct {
    int x;
    int w;
    int align;
    int valign;
    int type;
    idVec2 iconSize;
    float iconVOffset;
} idTabRect;

@interface idListWindow : idWindow {
@public
    NSMutableData *     tabInfo;            // idTabRect
    int                 top;
    float               sizeBias;
    BOOL                horizontal;
    NSString *          tabStopStr;
    NSString *          tabAlignStr;
    NSString *          tabVAlignStr;
    NSString *          tabTypeStr;
    NSString *          tabIconSizeStr;
    NSString *          tabIconVOffsetStr;
    NSMutableDictionary<NSString *, idMaterial *> *iconMaterials;
    BOOL                multipleSel;
    NSMutableArray<NSString *> *listItems;  // idStrList, Latin-1
    idSliderWindow *    scroller;
    NSMutableArray<NSNumber *> *currentSel;
    NSString *          listName;
    int                 clickTime;
    int                 typedTime;
    NSMutableString *   typed;
}
- (void)updateList;
@end

NS_ASSUME_NONNULL_END
