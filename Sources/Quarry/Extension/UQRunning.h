/*---------------------------------------------------------------------------------------------
 *  UQRunning.h
 *
 *  A Quarry project run and debugged as UDCode runs a project (Product >
 *  Run, Debug; its debug bar, navigator and area): UQBuildSystem says what
 *  runs, the game its .qworkspace names (gameExecutable, gameArguments),
 *  with nothing to build; UQScriptDebugger is its debugger, udscript-dap,
 *  the scripts' (Quarry's Run, with the script debugger on). Its launch is
 *  given the workspace's settings, the game's paths, so that the adapter
 *  knows a script by its game path; a breakpoint in a script read out of a
 *  pak is named by its quarry:/file/ URL, as UDCode's document of it is.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UQBuildSystem : UDBuildSystem
/// The settings of the first .qworkspace in @a folder; nil: it has none.
+ (nullable NSDictionary *)workspaceSettingsInFolder:(NSString *)folder;
@end

@interface UQScriptDebugger : UDDebugger
@end

NS_ASSUME_NONNULL_END
