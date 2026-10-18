#
# LSPServerKit: what a language server needs of the protocol, JSON-RPC over
# LSP's base protocol (UDJSONRPCConnection) and LSP's lifecycle and open
# documents (UDLanguageServer); and what a debug adapter needs of DAP, over
# the same framing (UDDAPConnection). Foundation only. A framework on macOS
# (PakManager.xcodeproj), a library here.
#
LIBRARY_NAME = LSPServerKit

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

LSPServerKit_OBJC_FILES = \
    UDDAPConnection.m \
    UDJSONRPCConnection.m \
    UDLanguageServer.m

LSPServerKit_HEADER_FILES_DIR = .
LSPServerKit_HEADER_FILES = \
    UDDAPConnection.h \
    UDJSONRPCConnection.h \
    UDLanguageServer.h

# UDDAPConnection answers on a dispatch queue.
LSPServerKit_LIBRARIES_DEPEND_UPON += -ldispatch

include $(GNUSTEP_MAKEFILES)/library.make
