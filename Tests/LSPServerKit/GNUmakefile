# LSPServerKit's, udscript-lsp's server's and udscript-dap's adapter's unit tests.
BUNDLE_NAME = LSPServerKitTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make

LSPServerKitTests_OBJC_FILES = \
    UDJSONRPCConnectionTests.m \
    UDScriptLanguageServerTests.m \
    UDDAPConnectionTests.m \
    UDScriptDebugAdapterTests.m \
    ../../Sources/Tools/udscript-lsp/UDScriptLanguageServer.m \
    ../../Sources/Tools/udscript-dap/UDScriptDebugAdapter.m \
    ../../Sources/Tools/udscript-dap/UDScriptExpression.m \
    ../Support/UDFakeScriptDebugger.m

LSPServerKitTests_INCLUDE_DIRS = \
    $(UDLIBS_INCLUDE_DIRS) \
    -I../../Sources/LSPServerKit \
    -I../../Sources/Tools/udscript-lsp \
    -I../../Sources/Tools/udscript-dap \
    -I../Support

# LSPServerKit, and udscript-lsp's server and udscript-dap's adapter
# (compiled in), are tested here.
TESTS_LIB_DIRS = -L../../Sources/LSPServerKit/$(GNUSTEP_OBJ_DIR_NAME)
TESTS_LIBS = -lLSPServerKit -ldispatch
TESTS_LD_PATH = :$(CURDIR)/../../Sources/LSPServerKit/$(GNUSTEP_OBJ_DIR_NAME)

include ../UnitTests.make
