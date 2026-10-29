//
//  UDStandardStreams.h
//  LSPServerKit
//
//  The standard input and output as a server's messages go over them: as
//  bytes. Windows' C runtime opens them as text, making each \n written
//  \r\n and each \r\n read \n, which a message's Content-Length does not
//  count. One implementation for each system (posix/, windows/).
//

#import <Foundation/Foundation.h>

/// Called first in a server's main, before a message is read or written.
extern void UDStandardStreamsForMessages(void);
