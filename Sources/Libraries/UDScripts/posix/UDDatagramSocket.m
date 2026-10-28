//
//  UDDatagramSocket.m (POSIX)
//  UDCore
//

#import "../UDDatagramSocket.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

UDDatagramSocket UDDatagramOpen(uint16_t localPort, NSError **error) {
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    int yes = 1;
    struct sockaddr_in local = {0};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    local.sin_port = htons(localPort);
    if (s >= 0) setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    if (s < 0 || bind(s, (struct sockaddr *)&local, sizeof local) != 0) {
        if (error) {
            NSString *what = s < 0 ? @"socket" : [NSString stringWithFormat:@"UDP port %u", localPort];
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %s", what, strerror(errno)]}];
        }
        if (s >= 0) close(s);
        return UDDatagramNone;
    }
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    return s;
}

NSData *UDDatagramAddress(NSString *host, uint16_t port) {
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
    sendto((int)socket, data.bytes, data.length, 0, address.bytes, (socklen_t)address.length);
}

NSData *UDDatagramReceive(UDDatagramSocket socket) {
    uint8_t buffer[65536];
    ssize_t length = recv((int)socket, buffer, sizeof buffer, 0);
    return length > 0 ? [NSData dataWithBytes:buffer length:(NSUInteger)length] : nil;
}

BOOL UDDatagramWait(UDDatagramSocket socket, NSTimeInterval timeout) {
    struct pollfd wanted = { (int)socket, POLLIN, 0 };
    return poll(&wanted, 1, (int)(timeout * 1000)) > 0;
}

void UDDatagramClose(UDDatagramSocket socket) {
    close((int)socket);
}
