//
//  UDStandardStreams.m (Windows)
//  LSPServerKit
//

#import "../UDStandardStreams.h"

#include <fcntl.h>
#include <io.h>
#include <stdio.h>

void UDStandardStreamsForMessages(void) {
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
}
