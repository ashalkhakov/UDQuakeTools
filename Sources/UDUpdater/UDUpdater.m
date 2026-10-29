//
//  UDUpdater.m
//  UDQuakeTools
//
//  GNUstep: the stack's GSUpdater, which is WinSparkle on Windows and
//  nothing on Linux, where the AppImage is updated from outside it
//  (UDUpdater.h).
//

#import "UDUpdater.h"
#import <GSUpdater/GSUpdater.h>

@implementation UDUpdater {
    GSUpdater *_updater;
}

- (instancetype)initStarting:(BOOL)start {
    if ((self = [super init])) _updater = [[GSUpdater alloc] initStarting:start];
    return self;
}

- (BOOL)available {
    return [_updater available];
}

- (BOOL)canCheckForUpdates {
    return [_updater canCheckForUpdates];
}

- (IBAction)checkForUpdates:(id)sender {
    [_updater checkForUpdates:sender];
}

@end
