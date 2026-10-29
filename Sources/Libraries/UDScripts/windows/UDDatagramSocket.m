//
//  UDDatagramSocket.m (Windows)
//  UDCore
//
//  Winsock's: started once, before the first socket; a SOCKET is no file
//  descriptor (closesocket, ioctlsocket), and its errors are
//  WSAGetLastError's.
//

#import "../UDDatagramSocket.h"

#include <winsock2.h>
#include <ws2tcpip.h>

static void UDWinsockStart(void) {
    static BOOL started = NO;
    @synchronized ([NSData class]) {
        if (started) return;
        WSADATA data;
        WSAStartup(MAKEWORD(2, 2), &data);
        started = YES;
    }
}

static NSError *UDWinsockError(NSString *what) {
    int code = WSAGetLastError();
    char message[256] = "";
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, (DWORD)code, 0, message, sizeof message, NULL);
    NSString *text = [[NSString stringWithUTF8String:message] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [NSError errorWithDomain:@"Winsock" code:code
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@", what, text]}];
}

UDDatagramSocket UDDatagramOpen(uint16_t localPort, NSError **error) {
    UDWinsockStart();
    SOCKET s = socket(AF_INET, SOCK_DGRAM, 0);
    BOOL yes = 1;
    struct sockaddr_in local = {0};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    local.sin_port = htons(localPort);
    if (s != INVALID_SOCKET) setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (const char *)&yes, sizeof yes);
    if (s == INVALID_SOCKET || bind(s, (struct sockaddr *)&local, sizeof local) != 0) {
        if (error) *error = UDWinsockError(s == INVALID_SOCKET ? @"socket" : [NSString stringWithFormat:@"UDP port %u", localPort]);
        if (s != INVALID_SOCKET) closesocket(s);
        return UDDatagramNone;
    }
    u_long nonblocking = 1;
    ioctlsocket(s, FIONBIO, &nonblocking);
    return (UDDatagramSocket)s;
}

NSData *UDDatagramAddress(NSString *host, uint16_t port) {
    UDWinsockStart();
    struct addrinfo hints = {0}, *found = NULL;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    char service[8];
    snprintf(service, sizeof service, "%u", port);
    if (getaddrinfo(host.UTF8String, service, &hints, &found) != 0 || found == NULL) return nil;
    NSData *address = [NSData dataWithBytes:found->ai_addr length:found->ai_addrlen];
    freeaddrinfo(found);
    return address;
}

void UDDatagramSend(UDDatagramSocket socket, NSData *address, NSData *data) {
    sendto((SOCKET)socket, data.bytes, (int)data.length, 0, address.bytes, (int)address.length);
}

NSData *UDDatagramReceive(UDDatagramSocket socket) {
    char buffer[65536];
    int length = recv((SOCKET)socket, buffer, sizeof buffer, 0);
    return length > 0 ? [NSData dataWithBytes:buffer length:(NSUInteger)length] : nil;
}

BOOL UDDatagramWait(UDDatagramSocket socket, NSTimeInterval timeout) {
    WSAPOLLFD wanted = { (SOCKET)socket, POLLRDNORM, 0 };
    return WSAPoll(&wanted, 1, (int)(timeout * 1000)) > 0;
}

void UDDatagramClose(UDDatagramSocket socket) {
    closesocket((SOCKET)socket);
}
