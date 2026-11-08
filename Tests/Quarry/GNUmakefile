# QuarryTests — Quarry's editors in UDCode's UDQuakeTools extension, driven as
# a user drives them, in a window that is a UDCode window to the extension
# (UQTestWindow).
#
#   xvfb-run -a make run-tests              (the root GNUmakefile's make check
#   UD_DOOM3_PATH=<install> ... run-tests    runs it too, under Xvfb)
#
# The Doom 3 cases look for a retail install at $UD_DOOM3_PATH (default
# /Volumes/ExtraSSD/games/DOOM 3) and check nothing when there is none.

BUNDLE_NAME = QuarryTests
# Built and run, never installed.
QuarryTests_STANDARD_INSTALL = no

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make
QUARRY_DIR = ../../Sources/Quarry
include $(QUARRY_DIR)/Quarry.include.make

include $(QUARRY_DIR)/files.make

# The extension's sources compiled in (its XIBs found in this bundle, as in
# UDQuakeTools.bundle), and the window they are tested in (UQTestWindow).
QuarryTests_OBJC_FILES = \
    UQTestWindow.m \
    UDQuarryTestCase.m \
    UDPDAEditorTests.m \
    UDTableSkinEditorTests.m \
    UDDeclEditorTests.m \
    UDDoom3WorkspaceTests.m \
    UDPakInstallTests.m \
    UDGuiViewerTests.m \
    $(addprefix $(QUARRY_DIR)/,$(QUARRY_OBJC_FILES))
QuarryTests_C_FILES = $(addprefix $(QUARRY_DIR)/,$(QUARRY_C_FILES))

QuarryTests_INCLUDE_DIRS = \
    -I. \
    -I../Support \
    $(QUARRY_INCLUDE_DIRS) \
    $(UDLIBS_INCLUDE_DIRS)

QuarryTests_RESOURCE_FILES = $(addprefix $(QUARRY_DIR)/,$(QUARRY_RESOURCE_FILES))
ADDITIONAL_CFLAGS += -w

QuarryTests_XCDATAMODELD_FILES = ../../Sources/Libraries/UDDecls/DeclModel.xcdatamodeld
QuarryTests_NEEDS_GUI = yes

# the libraries from the tree, built first (the root GNUmakefile); Core Data the stack's.
ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS)
QuarryTests_BUNDLE_LIBS += $(UDLIBS_LIBS) -lCoreData -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch $(UD_BLOCKS_LIBS)

# The GUI viewer draws with GL (UDGuiGLView) where the stack's backend has
# GLX and GL's headers are here (libgl-dev); without them it draws in
# software.
ifneq ($(wildcard /usr/include/GL/glx.h),)
ADDITIONAL_CPPFLAGS += -DUD_HAVE_GL
ADDITIONAL_LDFLAGS += -lGL
endif

XCTEST ?= xctest

# Bounded: a modal editor waiting for an event that never comes would
# otherwise hang the run (the cases abort their own modals after 20s).
TEST_TIMEOUT ?= 900

.PHONY: run-tests
run-tests: all $(BUNDLE_NAME).bundle
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(UDLIBS_LD_PATH):$(CURDIR)/../../Sources/LSPServerKit/$(GNUSTEP_OBJ_DIR_NAME)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	PATH="$(UDLIBS_LD_PATH):$(CURDIR)/../../Sources/LSPServerKit/$(GNUSTEP_OBJ_DIR_NAME):$$PATH" \
	UD_PLUGINS_PATH="$(GNUSTEP_LOCAL_LIBRARY)/Bundles/UDCodeKit:$(CURDIR)/../../tree-sitter-idscript:$(CURDIR)/../../tree-sitter-iddecl" \
	UD_SCRIPT_LSP="$(CURDIR)/../../Sources/Tools/udscript-lsp/$(GNUSTEP_OBJ_DIR_NAME)/udscript-lsp" \
	UD_SCRIPT_DAP="$(CURDIR)/../../Sources/Tools/udscript-dap/$(GNUSTEP_OBJ_DIR_NAME)/udscript-dap" \
	timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) "$(BUNDLE_NAME).bundle"

include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/bundle.make
