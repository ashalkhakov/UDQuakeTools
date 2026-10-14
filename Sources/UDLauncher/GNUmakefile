APP_NAME = UDLauncher

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLauncher_OBJC_FILES = \
    main.m \
    UDLauncherAppDelegate.m \
    ../UDUpdater/UDUpdater.m

# The app's updates (none on GNUstep: UDUpdater.h).
UDLauncher_INCLUDE_DIRS = -I../UDUpdater

UDLauncher_RESOURCE_FILES = \
    MainMenu.xib \
    UDLauncher-Info.plist

include $(GNUSTEP_MAKEFILES)/application.make
