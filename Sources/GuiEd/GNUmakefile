APP_NAME = GuiEd

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

GuiEd_OBJC_FILES = \
    main.m \
    UDGuiEdAppDelegate.m \
    UDGuiEdDocument.m \
    UDInspectableOutlineView.m \
    UDInspectableTableView.m \
    UDGuiEdDocumentWindowController.m \
    UDInspectorController.m \
    UDGuiAttributeSubcontroller.m \
    UDEditDefInspectorController.m \
    UDChoiceDefInspectorController.m \
    UDBindDefInspectorController.m \
    UDListDefInspectorController.m \
    UDSliderDefInspectorController.m \
    UDRenderDefInspectorController.m \
    UDEventsController.m \
    UDVariablesController.m \
    UDOutlinePaneController.m \
    ../UDCore/FormContainerView.m \
    UDInspectorIcons.m

GuiEd_INCLUDE_DIRS = \
    -I../UDCore

GuiEd_RESOURCE_FILES = \
    MainMenu.xib \
    UDGuiEdDocument.xib \
    UDOutlinePane.xib \
    UDInspector.xib \
    UDEditDefInspector.xib \
    UDChoiceDefInspector.xib \
    UDBindDefInspector.xib \
    UDListDefInspector.xib \
    UDSliderDefInspector.xib \
    UDRenderDefInspector.xib \
    UDVariables.xib \
    UDEvents.xib \
    GuiEd-Info.plist

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)
ADDITIONAL_LDFLAGS += -lUDCore -lzip -ldispatch -lBlocksRuntime

include $(GNUSTEP_MAKEFILES)/application.make