/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDFileActionService.m — Service to handle file actions (previewing, custom tools, or OS open).
 */

#import "UDFileActionService.h"
#import "UDTextPreviewController.h"
#include <unistd.h>

static NSString *UDResolveExecutableInPATH(NSString *name) {
    if (name.length == 0) {
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([name hasPrefix:@"/"]) {
        return [fm isExecutableFileAtPath:name] ? name : nil;
    }

    NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];
    NSArray *components = pathEnv.length > 0 ? [pathEnv componentsSeparatedByString:@":"]
                                             : @[@"/usr/local/bin", @"/usr/bin", @"/bin"];
    for (NSString *dir in components) {
        if (dir.length == 0) {
            continue;
        }
        NSString *candidate = [dir stringByAppendingPathComponent:name];
        if ([fm isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

static BOOL UDLaunchExternalOpenCommand(NSString *launchPath,
                                        NSArray<NSString *> *arguments,
                                        NSString *targetPath,
                                        NSError **error) {
    if (launchPath.length == 0) {
        return NO;
    }

    @try {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:launchPath];
        [task setArguments:arguments ?: @[]];
        [task launch];
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.udquake.error.file-action"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to launch '%@' for '%@': %@",
                                                                                launchPath.lastPathComponent,
                                                                                targetPath.lastPathComponent,
                                                                                exception.reason ?: @"unknown error"]}];
        }
        return NO;
    }
}

@implementation UDFileActionService

- (nullable UDTextPreviewController *)openFileAtPath:(NSString *)tempPath
                                            withData:(NSData *)data
                                        parentWindow:(nullable NSWindow *)parentWindow
                                       modalDelegate:(nullable id)modalDelegate
                                      didEndSelector:(nullable SEL)didEndSelector {
    NSString *ext = [tempPath pathExtension].lowercaseString;

    // 1. Check if the file is plain text data (built-in previewer)
    if ([UDFileActionService isPlainTextData:data extension:ext]) {
        NSString *textString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!textString) {
            textString = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        }
        if (textString && parentWindow) {
            UDTextPreviewController *activeTextPreview = [[UDTextPreviewController alloc] initWithText:textString title:tempPath.lastPathComponent];
            [NSApp beginSheet:[activeTextPreview window]
               modalForWindow:parentWindow
                modalDelegate:modalDelegate
               didEndSelector:didEndSelector
                  contextInfo:NULL];
            return activeTextPreview;
        }
    }

    // 2. Check Custom Mappings from user preferences
    NSString *cmdTemplate = [self customCommandForExtension:ext];
    if (cmdTemplate.length > 0) {
        NSString *cmd = [cmdTemplate stringByReplacingOccurrencesOfString:@"%f" withString:tempPath];
        @try {
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:@"/bin/sh"];
            [task setArguments:@[@"-c", cmd]];
            [task launch];
            return nil;
        } @catch (NSException *exception) {
            NSLog(@"Failed to launch custom command '%@': %@", cmd, exception);
        }
    }

    // 3. Fallback strategy differs between GNUstep/Linux and Cocoa/macOS.
    BOOL success = NO;
#ifdef GNUSTEP
    NSError *openError = nil;
    NSString *xdgOpen = UDResolveExecutableInPATH(@"xdg-open");
    if (xdgOpen.length > 0) {
        success = UDLaunchExternalOpenCommand(xdgOpen, @[tempPath], tempPath, &openError);
    }

    if (!success) {
        NSString *gio = UDResolveExecutableInPATH(@"gio");
        if (gio.length > 0) {
            success = UDLaunchExternalOpenCommand(gio, @[@"open", tempPath], tempPath, &openError);
        }
    }

    if (!success) {
        success = [[NSWorkspace sharedWorkspace] openFile:tempPath];
    }
#else
    success = [[NSWorkspace sharedWorkspace] openFile:tempPath];
#endif

    if (!success) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Failed to Open File"];
#ifdef GNUSTEP
        [alert setInformativeText:[NSString stringWithFormat:@"Could not open '%@'. Tried xdg-open, gio open, and NSWorkspace.", tempPath.lastPathComponent]];
#else
        [alert setInformativeText:[NSString stringWithFormat:@"No application associated with '%@'. Configure a custom helper in preferences.", ext]];
#endif
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }

    return nil;
}

+ (BOOL)isPlainTextData:(NSData *)data extension:(NSString *)ext {
    static NSArray *textExts = nil;
    if (!textExts) {
        textExts = @[@"txt", @"cfg", @"mtr", @"def", @"script", @"shader", @"rc", @"menu", @"qc", @"lst", @"font", @"skin", @"map", @"ini", @"json"];
    }
    if ([textExts containsObject:[ext lowercaseString]]) {
        return YES;
    }

    NSUInteger len = MIN(data.length, 512);
    if (len == 0) {
        return YES;
    }
    const char *bytes = data.bytes;
    for (NSUInteger i = 0; i < len; i++) {
        char c = bytes[i];
        if (c == '\0') {
            return NO;
        }
        if ((unsigned char)c < 32 && c != '\t' && c != '\n' && c != '\r') {
            return NO;
        }
    }
    return YES;
}

- (nullable NSString *)customCommandForExtension:(NSString *)ext {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *associations = [defaults dictionaryForKey:@"UDCustomFileAssociations"];
    if (associations) {
        return [associations objectForKey:[ext lowercaseString]];
    }
    return nil;
}

@end
