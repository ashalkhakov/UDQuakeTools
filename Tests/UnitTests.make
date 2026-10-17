# What a library's unit tests' bundle (Tests/<library>/GNUmakefile) has
# in common: it sets BUNDLE_NAME, its sources and include directories
# (Libraries.make's, and anything more), then includes this. Built and run
# (make run-tests), never installed.

$(BUNDLE_NAME)_STANDARD_INSTALL = no

# The decl store's tests, and any that make a workspace, need the
# compiled data model in the bundle's resources (Xcode's are in UDDecls').
$(BUNDLE_NAME)_XCDATAMODELD_FILES = $(UDLIBS_DIR)/UDDecls/DeclModel.xcdatamodeld

# CoreData is provided by FreeCoreData on GNUstep.
ADDITIONAL_NATIVE_LIBS += CoreData

# The libraries from the tree, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS) $(TESTS_LIB_DIRS)
ADDITIONAL_LDFLAGS += $(UDLIBS_LIBS) $(TESTS_LIBS) -lXCTest -lBlocksRuntime

XCTEST ?= xctest

.PHONY: run-tests
run-tests: all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(UDLIBS_LD_PATH)$(TESTS_LD_PATH)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	$(XCTEST) "$(BUNDLE_NAME).bundle"

# Compiles the data model with momc and bundles the .momd (FreeCoreData's);
# included after run-tests so that run-tests stays the default goal.
include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/bundle.make
