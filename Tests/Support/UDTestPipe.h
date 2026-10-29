//
//  UDTestPipe.h
//  UDQuakeToolsTests
//
//  A pipe as the tests talk to a connection through one: its two ends as C
//  streams, binary (Windows' C runtime would make each \n \r\n), the
//  reading end unbuffered; and a wait for something to read. One
//  implementation for each system (posix/, windows/).
//

#import <Foundation/Foundation.h>
#include <stdio.h>

/// A pipe's reading and writing ends; NO when there is none.
extern BOOL UDTestPipe(FILE *_Nullable *_Nonnull reading, FILE *_Nullable *_Nonnull writing);

/// Whether @a reading (UDTestPipe's) has something to read within
/// @a timeout seconds.
extern BOOL UDTestPipeWait(FILE *_Nonnull reading, NSTimeInterval timeout);
