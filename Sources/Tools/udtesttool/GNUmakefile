TOOL_NAME = udtesttool

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

udtesttool_OBJC_FILES = \
    main.m \
    ../../UDCore/UDGuiModel.m \
    ../../UDCore/UDGuiDocumentCodec.m \
    ../../UDCore/UDDeclLexer.m \
    ../../UDCore/UDDeclParser.m

udtesttool_INCLUDE_DIRS = \
    -I../../UDCore

udtesttool_LIBRARIES = gnustep-base

ADDITIONAL_LDFLAGS += -lobjc

include $(GNUSTEP_MAKEFILES)/tool.make
