//
//  UDTestPipe.m (POSIX)
//  UDQuakeToolsTests
//

#import "../UDTestPipe.h"

#include <poll.h>
#include <unistd.h>

BOOL UDTestPipe(FILE **reading, FILE **writing) {
    int fds[2];
    if (pipe(fds) != 0) return NO;
    *reading = fdopen(fds[0], "rb");
    setvbuf(*reading, NULL, _IONBF, 0);
    *writing = fdopen(fds[1], "wb");
    return YES;
}

BOOL UDTestPipeWait(FILE *reading, NSTimeInterval timeout) {
    struct pollfd wanted = { fileno(reading), POLLIN, 0 };
    return poll(&wanted, 1, (int)(timeout * 1000)) > 0;
}
