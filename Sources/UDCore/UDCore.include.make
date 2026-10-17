# UDCore's headers, in its folders: a client sets UDCORE_DIR (the path to
# Sources/UDCore from its own directory), includes this, and adds
# $(UDCORE_INCLUDE_DIRS) to its include directories.
UDCORE_SUBDIRS = idLib Framework Renderer UI GUIEditor Decls Archives Scripts Workspace
UDCORE_INCLUDE_DIRS = -I$(UDCORE_DIR) $(addprefix -I$(UDCORE_DIR)/,$(UDCORE_SUBDIRS))
