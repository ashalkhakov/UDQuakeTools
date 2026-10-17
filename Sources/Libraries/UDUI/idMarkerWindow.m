/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idMarkerWindow.m — ui/MarkerWindow.cpp, ported. See idMarkerWindow.h.
 */

#import "idFileSystem.h"
#import "idMarkerWindow.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "UDDeclCodec.h"
#import "idDeviceContext.h"
#import "idDict.h"
#import "idParser.h"
#import "idFile.h"
#import "UDSoftwareRenderer.h"
#import "UDMaterialParser.h"
#import "UDImageProgram.h"

@implementation idMarkerWindow

- (markerData_t *)markers { return (markerData_t *)markerTimes.mutableBytes; }
- (int)numMarkers { return (int)( markerTimes.length / sizeof( markerData_t ) ); }

- (void)markerCommonInit {
    numStats = 0;
    currentTime = -1;
    currentMarker = -1;
    stopTime = -1;
    imageBuff = NULL;
    markerMat = nil;
    markerStop = nil;
}

- (void)constructMarkerMembers {
    loggedStats = calloc( MAX_LOGGED_STATS, sizeof( logStats_t ) );
    markerTimes = [NSMutableData data];
    statData = @"";
    markerColor = idVec4_Make( 0, 0, 0, 0 );
}

- (instancetype)initWithDC:(idDeviceContext *)d gui:(idUserInterfaceLocal *)g {
    self = [super initWithDC:d gui:g];
    if (self) {
        [self constructMarkerMembers];
        dc = d;
        gui = g;
        [self markerCommonInit];
    }
    return self;
}

- (instancetype)initWithGui:(idUserInterfaceLocal *)g {
    self = [super initWithGui:g];
    if (self) {
        [self constructMarkerMembers];
        gui = g;
        [self markerCommonInit];
    }
    return self;
}


- (void)dealloc {
    free( loggedStats );
}

- (BOOL)parseInternalVar:(NSString *)_name parser:(idParser *)src {
    if ([_name ud_iequals:@"markerMat"]) {
        NSString *str = [self parseString:src] ?: @"";
        markerMat = [[gui manager] findMaterial:str];
        [markerMat setSort:SS_GUI];
        return YES;
    }
    if ([_name ud_iequals:@"markerStop"]) {
        NSString *str = [self parseString:src] ?: @"";
        markerStop = [[gui manager] findMaterial:str];
        [markerStop setSort:SS_GUI];
        return YES;
    }
    if ([_name ud_iequals:@"markerColor"]) {
        [self parseVec4:src out:&markerColor];
        return YES;
    }
    return [super parseInternalVar:_name parser:src];
}

- (NSString *)handleEvent:(const sysEvent_t *)event updateVisuals:(BOOL *)updateVisuals {

    if (!(event->evType == SE_KEY && event->evValue2)) {
        return @"";
    }

    idWindow *desktop = [gui getDesktop];
    int key = event->evValue;
    if (event->evValue2 && key == K_MOUSE1) {
        [desktop setChildWinVarVal:@"markerText" var:@"text" val:@""];
        int c = [self numMarkers];
        int i;
        for (i = 0; i < c; i++) {
            markerData_t *md = &[self markers][i];
            if (idRectangle_Contains( &md->rect, [gui cursorX], [gui cursorY] )) {
                currentMarker = i;
                [gui setStateInt:@"currentMarker" value:md->time];
                stopTime = md->time;
                [desktop setChildWinVarVal:@"markerText" var:@"text" val:[NSString stringWithFormat:@"Marker set at %.2i:%.2i", md->time / 60 / 60, (md->time / 60) % 60]];
                [desktop setChildWinVarVal:@"markerText" var:@"visible" val:@"1"];
                [desktop setChildWinVarVal:@"markerBackground" var:@"matcolor" val:@"1 1 1 1"];
                [desktop setChildWinVarVal:@"markerBackground" var:@"text" val:@""];
                [desktop setChildWinVarVal:@"markerBackground" var:@"background" val:md->mat.name];
                break;
            }
        }
        if ( i == c ) {
            // no marker selected;
            currentMarker = -1;
            [gui setStateInt:@"currentMarker" value:currentTime];
            stopTime = currentTime;
            [desktop setChildWinVarVal:@"markerText" var:@"text" val:[NSString stringWithFormat:@"Marker set at %.2i:%.2i", currentTime / 60 / 60, (currentTime / 60) % 60]];
            [desktop setChildWinVarVal:@"markerText" var:@"visible" val:@"1"];
            [desktop setChildWinVarVal:@"markerBackground" var:@"matcolor" val:@"0 0 0 0"];
            [desktop setChildWinVarVal:@"markerBackground" var:@"text" val:@"No Preview"];
        }
        float pct = [[gui state] getFloat:@"loadPct"];
        int len = [[gui state] getInt:@"loadLength"];
        if (stopTime > len * pct) {
            return @"cmdDemoGotoMarker";
        }
    } else if (key == K_MOUSE2) {
        stopTime = -1;
        [desktop setChildWinVarVal:@"markerText" var:@"text" val:@""];
        [gui setStateInt:@"currentMarker" value:-1];
        return @"cmdDemoGotoMarker";
    } else if (key == K_SPACE) {
        return @"cmdDemoPauseFrame";
    }

    return @"";
}

- (void)postParse {
    [super postParse];
}

static const int HEALTH_MAX = 100;
static const int COMBAT_MAX = 100;
static const int RATE_MAX = 125;
static const int STAMINA_MAX = 12;
- (void)draw:(int)time x:(float)x y:(float)y {
    float pct;
    idRectangle r = clientRect;
    int len = [[gui state] getInt:@"loadLength"];
    if (len == 0) {
        len = 1;
    }
    if (numStats > 1) {
        int c = [self numMarkers];
        if (c > 0) {
            for (int i = 0; i < c; i++) {
                markerData_t *md = &[self markers][i];
                if (md->rect.w == 0) {
                    md->rect.x = (r.x + r.w * ((float)md->time / len)) - 8;
                    md->rect.y = r.y + r.h - 20;
                    md->rect.w = 16;
                    md->rect.h = 16;
                }
                [dc drawMaterial:md->rect.x y:md->rect.y w:md->rect.w h:md->rect.h mat:markerMat color:markerColor];
            }
        }
    }

    r.y += 10;
    if (r.w > 0 && idRectangle_Contains( &r, [gui cursorX], [gui cursorY] )) {
        pct = ([gui cursorX] - r.x) / r.w;
        currentTime = len * pct;
        r.x = ([gui cursorX] > r.x + r.w - 40) ? [gui cursorX] - 40 : [gui cursorX];
        r.y = [gui cursorY] - 15;
        r.w = 40;
        r.h = 20;
        [dc drawText:[NSString stringWithFormat:@"%.2i:%.2i", currentTime / 60 / 60, (currentTime / 60) % 60] textScale:0.25 textAlign:0 color:idDeviceContext_colorWhite rectDraw:r wrap:NO];
    }

    if (stopTime >= 0 && markerStop) {
        r = clientRect;
        r.y += (r.h - 32) / 2;
        pct = (float)stopTime / len;
        r.x += (r.w * pct) - 16;
        idVec4 color = idVec4_Make(1, 1, 1, 0.65f);
        [dc drawMaterial:r.x y:r.y w:32 h:32 mat:markerStop color:color];
    }

}



- (NSString *)routeMouseCoords:(float)xd yd:(float)yd {
    NSString * ret = [super routeMouseCoords:xd yd:yd];
    idWindow *desktop = [gui getDesktop];
    int i, c = [self numMarkers];
    int len = [[gui state] getInt:@"loadLength"];
    if (len == 0) {
        len = 1;
    }
    for (i = 0; i < c; i++) {
        markerData_t *md = &[self markers][i];
        if (idRectangle_Contains( &md->rect, [gui cursorY], [gui cursorX] )) {
            [desktop setChildWinVarVal:@"markerBackground" var:@"background" val:md->mat.name];
            [desktop setChildWinVarVal:@"markerBackground" var:@"matcolor" val:@"1 1 1 1"];
            [desktop setChildWinVarVal:@"markerBackground" var:@"text" val:@""];
            break;
        }
    }

    if (i >= c) {
        if (currentMarker == -1) {
            [desktop setChildWinVarVal:@"markerBackground" var:@"matcolor" val:@"0 0 0 0"];
            [desktop setChildWinVarVal:@"markerBackground" var:@"text" val:@"No Preview"];
        } else {
            markerData_t *md = &[self markers][currentMarker];
            [desktop setChildWinVarVal:@"markerBackground" var:@"background" val:md->mat.name];
            [desktop setChildWinVarVal:@"markerBackground" var:@"matcolor" val:@"1 1 1 1"];
            [desktop setChildWinVarVal:@"markerBackground" var:@"text" val:@""];
        }
    }
    return ret;
}

- (void)point:(int)x y:(int)y out:(uint32_t *)out color:(uint32_t)color {
    int index = (63-y) * 512 + x;
    if (index >= 0 && index < 512 * 64) {
        out[index] = color;
    } else {
        [[gui manager] uiWarning:[NSString stringWithFormat:@"Out of bounds on point %i : %i", x, y]];
    }
}

- (void)line:(int)x1 y1:(int)y1 x2:(int)x2 y2:(int)y2 out:(uint32_t *)out color:(uint32_t)color {
    int deltax = abs(x2 - x1);
    int deltay = abs(y2 - y1);
    int incx = (x1 > x2) ? -1 : 1;
    int incy = (y1 > y2) ? -1 : 1;
    int right, up, dir;
    if (deltax > deltay) {
        right = deltay * 2;
        up = right - deltax * 2;
        dir = right - deltax;
        while (deltax-- >= 0) {
            [self point:x1 y:y1 out:out color:color];
            x1 += incx;
            y1 += (dir > 0) ? incy : 0;
            dir += (dir > 0) ? up : right;
        }
    } else {
        right = deltax * 2;
        up = right - deltay * 2;
        dir = right - deltay;
        while ( deltay-- >= 0) {
            [self point:x1 y:y1 out:out color:color];
            x1 += (dir > 0) ? incx : 0;
            y1 += incy;
            dir += (dir > 0) ? up : right;
        }
    }
}


- (void)activate:(BOOL)activate act:(NSMutableString *)act {
    [super activate:activate act:act];
    if (activate) {
        int i;
        idUserInterfaceManager *manager = [gui manager];
        idFileSystem *fileSystem = manager.fileSystem;
        [[gui getDesktop] setChildWinVarVal:@"markerText" var:@"text" val:@""];
        imageBuff = (uint32_t*)malloc(512*64*4);
        markerTimes.length = 0;
        currentMarker = -1;
        currentTime = -1;
        stopTime = -1;
        statData = [[gui state] getString:@"statData"];
        numStats = 0;
        if (statData.length) {
            idFile *file = [fileSystem openFileRead:statData allowCopyFiles:YES gamedir:nil error:NULL];
            if (file) {
                [file read:&numStats length:sizeof(numStats) error:NULL];
                if ( numStats < 0 || numStats > MAX_LOGGED_STATS ) {
                    numStats = 0;   // (the engine reads past its array)
                }
                [file read:loggedStats length:numStats * (int)sizeof(loggedStats[0]) error:NULL];
                for (i = 0; i < numStats; i++) {
                    if (loggedStats[i].health < 0) {
                        loggedStats[i].health = 0;
                    }
                    if (loggedStats[i].stamina < 0) {
                        loggedStats[i].stamina = 0;
                    }
                    if (loggedStats[i].heartRate < 0) {
                        loggedStats[i].heartRate = 0;
                    }
                    if (loggedStats[i].combat < 0) {
                        loggedStats[i].combat = 0;
                    }
                }
                [fileSystem closeFile:file error:NULL];
            }
        }

        if (numStats > 1 && background) {
            // markerPath.StripFilename()
            NSString *markerPath = statData.stringByDeletingLastPathComponent;
            idFileList *markers = [fileSystem listFiles:markerPath extension:@".tga" sorted:NO fullRelativePath:YES error:NULL];
            for ( i = 0; i < [markers numFiles]; i++ ) {
                NSString *fileName = [markers fileByIndex:i];
                markerData_t md;
                memset( &md, 0, sizeof( md ) );
                md.mat = [manager findMaterial:fileName];
                [md.mat setSort:SS_GUI];
                // name.StripPath(); name.StripFileExtension();
                md.time = atoi(fileName.lastPathComponent.stringByDeletingPathExtension.UTF8String);
                [markerTimes appendBytes:&md length:sizeof( md )];
            }
            [fileSystem freeFileList:markers];
            memset(imageBuff, 0, 512*64*4);
            float step = 511.0f / (numStats - 1);
            float x1, y1, x2, y2;
            x1 = 0 - step;
            for (i = 0; i < numStats-1; i++) {
                x1 += step;
                x2 = x1 + step;
                y1 = 63 * ((float)loggedStats[i].health / HEALTH_MAX);
                y2 = 63 * ((float)loggedStats[i+1].health / HEALTH_MAX);
                [self line:x1 y1:y1 x2:x2 y2:y2 out:imageBuff color:0xff0000ff];
                y1 = 63 * ((float)loggedStats[i].heartRate / RATE_MAX);
                y2 = 63 * ((float)loggedStats[i+1].heartRate / RATE_MAX);
                [self line:x1 y1:y1 x2:x2 y2:y2 out:imageBuff color:0xff00ff00];
                // stamina not quite as high on graph so health does not get obscured with both at 100%
                y1 = 62 * ((float)loggedStats[i].stamina / STAMINA_MAX);
                y2 = 62 * ((float)loggedStats[i+1].stamina / STAMINA_MAX);
                [self line:x1 y1:y1 x2:x2 y2:y2 out:imageBuff color:0xffff0000];
                y1 = 63 * ((float)loggedStats[i].combat / COMBAT_MAX);
                y2 = 63 * ((float)loggedStats[i+1].combat / COMBAT_MAX);
                [self line:x1 y1:y1 x2:x2 y2:y2 out:imageBuff color:0xff00ffff];
            }
            UDMaterialStageInfo *stage = [background parser].stages.firstObject;
            if (stage && stage.imageName) {
                // stage->texture.image->UploadScratch( imageBuff, 512, 64 ): the
                // dwords' bytes, R G B A
                NSData *pixels = [NSData dataWithBytes:imageBuff length:512*64*4];
                [manager.renderer setImage:[[UDImage alloc] initWithWidth:512 height:64 pixels:pixels] forName:stage.imageName];
            }
        }
        free(imageBuff);
        imageBuff = NULL;
    }
}

- (void)mouseExit {
    [super mouseExit];
}

- (void)mouseEnter {
    [super mouseEnter];
}

@end
