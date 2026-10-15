#
# The idScript grammar bundle on GNUstep: the principal class, the
# generated parser, LanguageInfo.plist and the highlights query. Its
# references to UDCodeKit are left for the app, which links it, to resolve
# when it loads the bundle; Decl Browser copies it into its PlugIns.
#
BUNDLE_NAME = TreeSitterIdScript
BUNDLE_EXTENSION = .bundle

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

TreeSitterIdScript_OBJC_FILES = Sources/TreeSitterIdScriptPlugin.m
TreeSitterIdScript_C_FILES = src/parser.c
TreeSitterIdScript_PRINCIPAL_CLASS = TreeSitterIdScriptPlugin
TreeSitterIdScript_RESOURCE_FILES = Resources/LanguageInfo.plist Resources/highlights.scm
TreeSitterIdScript_INCLUDE_DIRS = -Isrc
TreeSitterIdScript_STANDARD_INSTALL = no
# Generated C: its warnings are not ours.
ADDITIONAL_CFLAGS += -w

include $(GNUSTEP_MAKEFILES)/bundle.make
