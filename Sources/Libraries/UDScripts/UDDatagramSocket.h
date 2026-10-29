//
//  UDDatagramSocket.h
//  UDCore
//
//  A UDP socket, as the game's script debugger and its client talk over
//  one: bound to a local port on every address, never blocking, its handle
//  what a dispatch source watches. One implementation for each system, in a
//  folder of its own (posix/: BSD sockets; windows/: Winsock).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A socket's handle: a file descriptor, on Windows a SOCKET.
typedef intptr_t UDDatagramSocket;
static const UDDatagramSocket UDDatagramNone = -1;

/// A socket bound to UDP @a localPort, non-blocking; UDDatagramNone and
/// @a error when it cannot be had.
extern UDDatagramSocket UDDatagramOpen(uint16_t localPort, NSError **error);

/// @a host's (a name or an address) UDP @a port, as a socket sends to it;
/// nil when there is no such host.
extern NSData *_Nullable UDDatagramAddress(NSString *host, uint16_t port);

/// @a data sent to @a address (UDDatagramAddress's).
extern void UDDatagramSend(UDDatagramSocket socket, NSData *address, NSData *data);

/// A datagram that has come, nil when none has.
extern NSData *_Nullable UDDatagramReceive(UDDatagramSocket socket);

/// Whether a datagram comes within @a timeout seconds.
extern BOOL UDDatagramWait(UDDatagramSocket socket, NSTimeInterval timeout);

extern void UDDatagramClose(UDDatagramSocket socket);

NS_ASSUME_NONNULL_END
