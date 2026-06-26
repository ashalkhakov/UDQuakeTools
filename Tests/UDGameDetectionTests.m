/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGameDetectionTests.m — Unit tests for UDGame and UDGameDetectionService.
 */

#import <Foundation/Foundation.h>
#import "UDGame.h"
#import "UDGameDetectionService.h"
#import "UDArchiveEntry.h"

static BOOL UDCheck(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        return NO;
    }
    return YES;
}

BOOL UDRunGameDetectionTests(void) {
    BOOL ok = YES;

    UDGameDetectionService *service = [[UDGameDetectionService alloc] init];

    // Test 1: Auto detect by parent directory (Quake 1)
    NSURL *url1 = [NSURL fileURLWithPath:@"/games/quake/id1/pak0.pak"];
    UDGame *game1 = [service detectGameForURL:url1 entries:@[] codecIdentifier:nil];
    ok = UDCheck(game1.type == UDGameTypeQuake1, @"Should detect Quake 1 for id1 parent folder") && ok;

    // Test 2: Auto detect by parent directory (Doom 3)
    NSURL *url2 = [NSURL fileURLWithPath:@"/games/doom3/base/game00.pk4"];
    UDGame *game2 = [service detectGameForURL:url2 entries:@[] codecIdentifier:nil];
    ok = UDCheck(game2.type == UDGameTypeDoom3, @"Should detect Doom 3 for base parent folder") && ok;

    // Test 3: Auto detect by extension (.pk3 -> Quake 3)
    NSURL *url3 = [NSURL fileURLWithPath:@"/temp/somefile.pk3"];
    UDGame *game3 = [service detectGameForURL:url3 entries:@[] codecIdentifier:nil];
    ok = UDCheck(game3.type == UDGameTypeQuake3, @"Should detect Quake 3 for pk3 extension") && ok;

    // Test 4: Auto detect by extension (.pk4 -> Doom 3)
    NSURL *url4 = [NSURL fileURLWithPath:@"/temp/somefile.pk4"];
    UDGame *game4 = [service detectGameForURL:url4 entries:@[] codecIdentifier:nil];
    ok = UDCheck(game4.type == UDGameTypeDoom3, @"Should detect Doom 3 for pk4 extension") && ok;

    // Test 5: Auto detect by entries (.wal file inside -> Quake 2)
    UDArchiveEntry *entryQ2 = [[UDArchiveEntry alloc] initWithPath:@"textures/wall.wal" size:100 contentType:@"image/x-wal" modifiedAt:[NSDate date] source:nil];
    UDGame *game5 = [service detectGameForURL:nil entries:@[entryQ2] codecIdentifier:nil];
    ok = UDCheck(game5.type == UDGameTypeQuake2, @"Should detect Quake 2 for wal files") && ok;

    // Test 6: Auto detect by entries (.mtr file inside -> Doom 3)
    UDArchiveEntry *entryD3 = [[UDArchiveEntry alloc] initWithPath:@"materials/base.mtr" size:100 contentType:@"text/plain" modifiedAt:[NSDate date] source:nil];
    UDGame *game6 = [service detectGameForURL:nil entries:@[entryD3] codecIdentifier:nil];
    ok = UDCheck(game6.type == UDGameTypeDoom3, @"Should detect Doom 3 for materials/mtr files") && ok;

    // Test 7: Auto detect by codec (com.udquake.daikatana-pak -> Daikatana)
    UDGame *game7 = [service detectGameForURL:nil entries:@[] codecIdentifier:@"com.udquake.daikatana-pak"];
    ok = UDCheck(game7.type == UDGameTypeDaikatana, @"Should detect Daikatana for com.udquake.daikatana-pak codec") && ok;

    if (ok) {
        printf("UDGameDetectionTests passed.\n");
    }

    return ok;
}
