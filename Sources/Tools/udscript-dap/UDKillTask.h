//
//  UDKillTask.h
//  udscript-dap
//
//  A task that would not end when asked (-terminate) ended outright: on
//  Linux SIGKILL; on Windows -terminate already is TerminateProcess. One
//  implementation for each system (posix/, windows/).
//

#import <Foundation/Foundation.h>

extern void UDKillTask(NSTask *task);
