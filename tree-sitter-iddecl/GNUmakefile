#
# The decl grammar bundle on GNUstep: the principal class, the
# generated parser, LanguageInfo.plist and the highlights query. Its
# references to UDCodeKit are left for the app, which links it, to resolve
# when it loads the bundle; Decl Browser copies it into its PlugIns.
#
BUNDLE_NAME = TreeSitterIdDecl
BUNDLE_EXTENSION = .bundle

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

TreeSitterIdDecl_OBJC_FILES = Sources/TreeSitterIdDeclPlugin.m
TreeSitterIdDecl_C_FILES = src/parser.c
TreeSitterIdDecl_PRINCIPAL_CLASS = TreeSitterIdDeclPlugin
TreeSitterIdDecl_RESOURCE_FILES = Resources/LanguageInfo.plist Resources/highlights.scm
TreeSitterIdDecl_INCLUDE_DIRS = -Isrc
TreeSitterIdDecl_STANDARD_INSTALL = no
# Generated C: its warnings are not ours.
ADDITIONAL_CFLAGS += -w

include $(GNUSTEP_MAKEFILES)/bundle.make
