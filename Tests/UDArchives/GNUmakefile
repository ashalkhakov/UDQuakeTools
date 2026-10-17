# UDArchives's unit tests.
BUNDLE_NAME = UDArchivesTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make

UDArchivesTests_OBJC_FILES = \
    UDArchiveEntryTests.m \
    UDArchiveEditorTests.m \
    UDArchiveWorkflowTests.m \
    UDPAKCodecTests.m \
    UDPK3CodecTests.m \
    UDZipWriterTests.m \
    ../Support/UDZipFixture.m

UDArchivesTests_INCLUDE_DIRS = \
    $(UDLIBS_INCLUDE_DIRS) \
    -I../Support

include ../UnitTests.make
