//
//  UDTestPipe.m (Windows)
//  UDQuakeToolsTests
//
//  The C runtime's pipe (_pipe), binary; a pipe cannot be polled, so the
//  wait peeks at it (PeekNamedPipe) until something is there.
//

#import "../UDTestPipe.h"

#include <windows.h>
#include <fcntl.h>
#include <io.h>

BOOL UDTestPipe(FILE **reading, FILE **writing) {
    int fds[2];
    if (_pipe(fds, 65536, _O_BINARY) != 0) return NO;
    *reading = _fdopen(fds[0], "rb");
    setvbuf(*reading, NULL, _IONBF, 0);
    *writing = _fdopen(fds[1], "wb");
    return YES;
}

BOOL UDTestPipeWait(FILE *reading, NSTimeInterval timeout) {
    HANDLE pipe = (HANDLE)_get_osfhandle(_fileno(reading));
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
    do {
        DWORD available = 0;
        if (!PeekNamedPipe(pipe, NULL, 0, NULL, &available, NULL)) return NO;
        if (available > 0) return YES;
        Sleep(10);
    } while ([until timeIntervalSinceNow] > 0);
    return NO;
}
