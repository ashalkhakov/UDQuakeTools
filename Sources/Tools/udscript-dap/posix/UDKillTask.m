//
//  UDKillTask.m (POSIX)
//  udscript-dap
//

#import "../UDKillTask.h"

#include <signal.h>

void UDKillTask(NSTask *task) {
    kill(task.processIdentifier, SIGKILL);
}
