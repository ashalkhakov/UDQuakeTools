# The libraries UDCore was, bottom up: each its own, depending only on
# those under it. A build of one sets UDLIBS_DIR (the path to
# Sources/Libraries from its directory) and includes this; so does
# anything that links them, which adds $(UDLIBS_INCLUDE_DIRS) to its
# include directories, $(UDLIBS_LIB_DIRS) to its library directories and
# $(UDLIBS_LIBS) to what it links (and, to run from the tree,
# $(UDLIBS_LD_PATH) to LD_LIBRARY_PATH).
UDLIBS = UDIdLib UDCommon UDArchives UDImages UDDecls UDRenderer UDUI UDGUIEditor UDScripts UDWorkspace
UDIdLib_UDDEPS = 
UDCommon_UDDEPS = UDIdLib
UDArchives_UDDEPS = UDIdLib UDCommon
UDImages_UDDEPS = UDIdLib UDCommon
UDDecls_UDDEPS = UDIdLib UDCommon UDImages
UDRenderer_UDDEPS = UDIdLib UDCommon UDImages UDDecls
UDUI_UDDEPS = UDIdLib UDCommon UDImages UDDecls UDRenderer
UDGUIEditor_UDDEPS = UDIdLib UDCommon UDImages UDDecls UDRenderer UDUI
UDScripts_UDDEPS = UDIdLib
UDWorkspace_UDDEPS = UDIdLib UDCommon UDArchives UDImages UDDecls

# A library's headers' folders (UDArchives' codecs are in Formats/).
ud_lib_includes = -I$(UDLIBS_DIR)/$(1) $(if $(filter UDArchives,$(1)),-I$(UDLIBS_DIR)/UDArchives/Formats)

UDLIBS_INCLUDE_DIRS = $(foreach l,$(UDLIBS),$(call ud_lib_includes,$(l)))
UDLIBS_LIB_DIRS = $(foreach l,$(UDLIBS),-L$(UDLIBS_DIR)/$(l)/$(GNUSTEP_OBJ_DIR_NAME))
UDLIBS_LIBS = $(foreach l,$(UDLIBS),-l$(l))
empty :=
space := $(empty) $(empty)
UDLIBS_LD_PATH = $(subst $(space),:,$(foreach l,$(UDLIBS),$(abspath $(UDLIBS_DIR)/$(l)/$(GNUSTEP_OBJ_DIR_NAME))))

# For a library's own build: its folder and its dependencies' only, so a
# header from above it is not found; it links what it depends on.
ud_own_includes = $(call ud_lib_includes,$(1)) $(foreach d,$($(1)_UDDEPS),$(call ud_lib_includes,$(d)))
ud_own_lib_dirs = $(foreach d,$($(1)_UDDEPS),-L$(UDLIBS_DIR)/$(d)/$(GNUSTEP_OBJ_DIR_NAME))
ud_own_libs = $(foreach d,$($(1)_UDDEPS),-l$(d))
