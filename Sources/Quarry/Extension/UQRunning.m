/*---------------------------------------------------------------------------------------------
 *  UQRunning.m
 *--------------------------------------------------------------------------------------------*/

#import "UQRunning.h"

@implementation UQBuildSystem

+ (NSDictionary *)workspaceSettingsInFolder:(NSString *)folder {
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL]
                         sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if (![name.pathExtension isEqualToString:@"qworkspace"]) continue;
        NSData *data = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:name]];
        id settings = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        return [settings isKindOfClass:[NSDictionary class]] ? settings : nil;
    }
    return nil;
}

+ (BOOL)buildsProject:(UDProject *)project {
    return [self workspaceSettingsInFolder:project.folderURL.path] != nil;
}

+ (NSString *)name {
    return @"Quarry";
}

/// The game the workspace names, run from the project's folder (where the
/// debugger finds the .qworkspace), under the scripts' debugger; nothing built.
- (NSDictionary *)inferredSettings {
    NSDictionary *settings = [UQBuildSystem workspaceSettingsInFolder:self.project.folderURL.path];
    NSString *game = [settings[@"gameExecutable"] isKindOfClass:[NSString class]] ? settings[@"gameExecutable"] : nil;
    NSMutableDictionary *inferred = [@{ @"debugger": [UQScriptDebugger name] } mutableCopy];
    if (game.length) {
        NSString *arguments = [settings[@"gameArguments"] isKindOfClass:[NSString class]] ? settings[@"gameArguments"] : @"";
        inferred[@"run"] = @{ @"program": game, @"arguments": arguments, @"directory": self.project.folderURL.path };
    }
    return inferred;
}

- (NSString *)product {
    return self.inferredSettings[@"run"][@"program"];
}

@end

@implementation UQScriptDebugger

+ (NSString *)name {
    return @"udscript";
}

+ (NSString *)displayName {
    return @"idScript (udscript-dap)";
}

/// udscript-dap, beside the extension's binary ($UD_SCRIPT_DAP, a test's).
+ (NSArray<NSString *> *)adapterCommand {
    NSString *tool = NSProcessInfo.processInfo.environment[@"UD_SCRIPT_DAP"]
        ?: [[NSBundle bundleForClass:[UQScriptDebugger class]] pathForAuxiliaryExecutable:@"udscript-dap"];
    return tool ? @[ tool ] : nil;
}

+ (NSArray<NSString *> *)adapterCommandWithExecutable:(NSString *)executable {
    return @[ executable ];
}

+ (BOOL)isAdapterCommand:(NSArray<NSString *> *)command {
    return [[command.firstObject lastPathComponent] hasPrefix:@"udscript-dap"];
}

/// The game started with the script debugger on (as Quarry's Run): its
/// program and arguments, and the workspace's settings (its paths), from
/// the .qworkspace of the project's folder, the run's directory; with what
/// the workspace keeps for the adapter (its "Debugger" tool's settings).
+ (NSDictionary *)launchArgumentsForProgram:(NSString *)program arguments:(NSArray<NSString *> *)arguments
                                  directory:(NSString *)directory
                                environment:(NSDictionary<NSString *, NSString *> *)environment {
    NSMutableDictionary *launch = [NSMutableDictionary dictionary];
    NSDictionary *settings = [UQBuildSystem workspaceSettingsInFolder:directory];
    NSDictionary *tools = [settings[@"tools"] isKindOfClass:[NSDictionary class]] ? settings[@"tools"] : nil;
    if ([tools[@"Debugger"] isKindOfClass:[NSDictionary class]]) [launch addEntriesFromDictionary:tools[@"Debugger"]];
    if (settings) launch[@"settings"] = settings;
    launch[@"program"] = program;
    launch[@"args"] = arguments ?: @[];
    return launch;
}

@end
