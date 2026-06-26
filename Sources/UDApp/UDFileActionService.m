/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDFileActionService.m — Service to handle file actions (previewing, custom tools, or OS open).
 */

#import "UDFileActionService.h"
#import "UDTextPreviewController.h"

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

    // 3. Fallback to NSWorkspace openFile
    BOOL success = [[NSWorkspace sharedWorkspace] openFile:tempPath];
    if (!success) {
        // 4. GNUstep/Linux fallback: xdg-open
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:@"/usr/bin/xdg-open"] || [fm fileExistsAtPath:@"/usr/local/bin/xdg-open"]) {
            @try {
                NSTask *task = [[NSTask alloc] init];
                [task setLaunchPath:@"/usr/bin/xdg-open"];
                [task setArguments:@[tempPath]];
                [task launch];
            } @catch (NSException *exception) {
                NSLog(@"Failed to launch xdg-open: %@", exception);
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Failed to Open File"];
                [alert setInformativeText:[NSString stringWithFormat:@"Neither the default application nor xdg-open could open '%@'.", tempPath.lastPathComponent]];
                [alert addButtonWithTitle:@"OK"];
                [alert runModal];
            }
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Failed to Open File"];
            [alert setInformativeText:[NSString stringWithFormat:@"No application associated with '%@'. Configure a custom helper in preferences.", ext]];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
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
