//
//  UDKillTask.m (Windows)
//  udscript-dap
//

#import "../UDKillTask.h"

void UDKillTask(NSTask *task) {
    // TerminateProcess, which no process can refuse
    [task terminate];
}
