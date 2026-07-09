TOOL_NAME = udpaktool

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

udpaktool_OBJC_FILES = main.m

udpaktool_INCLUDE_DIRS = \
    -I../../UDCore \
    -I../../UDFormats

udpaktool_LIBRARIES = UDCore UDFormats

ADDITIONAL_LDFLAGS += -lzip

include $(GNUSTEP_MAKEFILES)/tool.make
