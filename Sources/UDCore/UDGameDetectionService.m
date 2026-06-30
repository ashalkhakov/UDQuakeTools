/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGameDetectionService.m — Service for auto-detecting the active game profile.
 */

#import "UDGameDetectionService.h"
#import "UDArchiveEntry.h"

@implementation UDGameDetectionService

- (UDGame *)detectGameForURL:(nullable NSURL *)url
                     entries:(NSArray<UDArchiveEntry *> *)entries
             codecIdentifier:(nullable NSString *)formatIdentifier {
    UDGameType detectedType = UDGameTypeUnknown;

    // 1. Analyze parent directory name
    if (url) {
        NSString *parentDirName = [[url.path stringByDeletingLastPathComponent] lastPathComponent].lowercaseString;
        if ([parentDirName isEqualToString:@"id1"]) {
            detectedType = UDGameTypeQuake1;
        } else if ([parentDirName isEqualToString:@"baseq2"] || [parentDirName isEqualToString:@"rogue"] || [parentDirName isEqualToString:@"xatrix"]) {
            detectedType = UDGameTypeQuake2;
        } else if ([parentDirName isEqualToString:@"baseq3"] || [parentDirName isEqualToString:@"missionpack"]) {
            detectedType = UDGameTypeQuake3;
        } else if ([parentDirName isEqualToString:@"base"] || [parentDirName isEqualToString:@"d3xp"]) {
            detectedType = UDGameTypeDoom3;
        } else if ([parentDirName isEqualToString:@"data"]) {
            detectedType = UDGameTypeDaikatana;
        }
    }

    // 2. Analyze filename if not detected yet
    if (detectedType == UDGameTypeUnknown && url) {
        NSString *ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"pk4"]) {
            detectedType = UDGameTypeDoom3;
        } else if ([ext isEqualToString:@"pk3"]) {
            detectedType = UDGameTypeQuake3;
        }
    }

    // 3. Analyze internal file structure by probing entry paths
    if (detectedType == UDGameTypeUnknown) {
        if ([formatIdentifier isEqualToString:@"com.udquake.daikatana-pak"]) {
            detectedType = UDGameTypeDaikatana;
        } else if (entries.count > 0) {
            NSUInteger walCount = 0;
            NSUInteger mtrCount = 0;
            NSUInteger d3Folders = 0;
            NSUInteger q2Folders = 0;

            for (UDArchiveEntry *entry in entries) {
                NSString *path = entry.path.lowercaseString;
                if ([path hasSuffix:@".wal"]) {
                    walCount++;
                } else if ([path hasSuffix:@".mtr"] || [path hasSuffix:@".def"] || [path hasSuffix:@".script"]) {
                    mtrCount++;
                }
                if ([path hasPrefix:@"materials/"] || [path hasPrefix:@"def/"] || [path hasPrefix:@"script/"]) {
                    d3Folders++;
                }
                if ([path hasPrefix:@"pics/"] || [path hasPrefix:@"players/"]) {
                    q2Folders++;
                }
            }

            if (d3Folders > 0 || mtrCount > 0) {
                detectedType = UDGameTypeDoom3;
            } else if (walCount > 0 || q2Folders > 0) {
                detectedType = UDGameTypeQuake2;
            }
        }
    }

    if (detectedType == UDGameTypeUnknown) {
        detectedType = UDGameTypeQuake1; // Default fallback for pak files
    }

    return [UDGame gameWithType:detectedType];
}

@end
