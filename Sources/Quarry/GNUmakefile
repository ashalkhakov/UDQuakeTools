# UDCode's UDQuakeTools extension (docs/UDCODE.md): UDQuakeTools.bundle,
# Quarry's and Pak Manager's editors in UDCode's windows. Built against
# UDCode's SDK (its udcodekit archive, .github/pins.env's UDCODEKIT_VERSION)
# on the GNUstep stack, which carries Core Data (FreeCoreData). The
# libraries of the tree beside it (Sources/Libraries) and the tools it
# starts (udscript-lsp, udscript-dap, udpaktool) go inside it;
# Scripts/udcx.sh packages it.
BUNDLE_NAME = UDQuakeTools
BUNDLE_EXTENSION = .bundle

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../Libraries
QUARRY_DIR = .
include Quarry.include.make
include $(UDLIBS_DIR)/Libraries.make

UDQuakeTools_PRINCIPAL_CLASS = UQExtension
UDQuakeTools_NEEDS_GUI = yes
UDQuakeTools_STANDARD_INSTALL = no

include files.make
UDQuakeTools_OBJC_FILES = $(QUARRY_OBJC_FILES)
UDQuakeTools_C_FILES = $(QUARRY_C_FILES)
UDQuakeTools_RESOURCE_FILES = $(QUARRY_RESOURCE_FILES)
UDQuakeTools_INCLUDE_DIRS = \
    $(QUARRY_INCLUDE_DIRS) \
    $(UDLIBS_INCLUDE_DIRS)

# Generated C: its warnings are not ours.
ADDITIONAL_CFLAGS += -w

# The libraries from the tree beside this one, built first (the root
# GNUmakefile), found from where the binary is; UDCode's own (UDCodeKit,
# GNUstep's, Core Data) are the running UDCode's: on Linux left for it, as
# its own plug-ins leave them; a Windows DLL is linked against all it uses.
ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS)
UDQuakeTools_BUNDLE_LIBS += $(UDLIBS_LIBS) -lCoreData -ldispatch $(UD_BLOCKS_LIBS)
ifneq ($(OS),Windows_NT)
UDQuakeTools_LDFLAGS += -Wl,-rpath,'$$ORIGIN'
else
UDQuakeTools_BUNDLE_LIBS += -lUDCodeKit -lUDPieceTable -lLSPKit -lgnustep-gui -lgnustep-base -lobjc
endif

# The GUI viewer draws with GL (UDGuiGLView) where the stack's backend has
# GLX and GL's headers are here (libgl-dev); without them it draws in
# software.
ifneq ($(wildcard /usr/include/GL/glx.h),)
ADDITIONAL_CPPFLAGS += -DUD_HAVE_GL
ADDITIONAL_LDFLAGS += -lGL
endif

# Compiles DeclModel.xcdatamodeld with momc into the bundle's resources.
UDQuakeTools_XCDATAMODELD_FILES = ../Libraries/UDDecls/DeclModel.xcdatamodeld
include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/bundle.make
