/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Quarry — standalone declaration browser app entry point.
 */

#import <AppKit/AppKit.h>

#if !defined(__APPLE__)
#import "UDCrashReporter.h"
#endif

int main(int argc, const char *argv[]) {
#if !defined(__APPLE__)
    // Linux, Windows: print a backtrace on a crash/uncaught exception instead of
    // dying silently. No-op on macOS (guarded so the Xcode target does not
    // need the file at all).
    UDInstallCrashDiagnostics();
#endif
    return NSApplicationMain(argc, argv);
}
