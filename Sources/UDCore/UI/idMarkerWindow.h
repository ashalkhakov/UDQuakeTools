/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idMarkerWindow.h — a markerDef (ui/MarkerWindow.h, MarkerWindow.cpp),
 * ported: the logged stats' graph, uploaded into its background's image.
 */

#import "idWindow.h"

NS_ASSUME_NONNULL_BEGIN

// needed by the gui system for the load game menu (framework/Session.h)
typedef struct {
    short       health;
    short       heartRate;
    short       stamina;
    short       combat;
} logStats_t;

#define MAX_LOGGED_STATS    ( 60 * 120 )        // log every half second

typedef struct {
    int time;
    __unsafe_unretained idMaterial *mat;
    idRectangle rect;
} markerData_t;

@interface idMarkerWindow : idWindow {
@public
    logStats_t *loggedStats;            // [MAX_LOGGED_STATS]
    NSMutableData *markerTimes;         // markerData_t
    NSString *statData;
    int numStats;
    uint32_t *imageBuff;
    idMaterial *_Nullable markerMat;
    idMaterial *_Nullable markerStop;
    idVec4 markerColor;
    int currentMarker;
    int currentTime;
    int stopTime;
}
@end

NS_ASSUME_NONNULL_END
