# Quarry's headers, in its folders (and Pak Manager's): a build of its
# sources (the extension, its tests) sets QUARRY_DIR (the path to Sources/Quarry from its
# own directory), includes this, and adds $(QUARRY_INCLUDE_DIRS) to its
# include directories.
QUARRY_SUBDIRS = Compat Extension Model Documents Window Editors Editors/Decls Preview GUIEditor Scripts ThirdParty/DMTabBar
QUARRY_INCLUDE_DIRS = -I$(QUARRY_DIR) $(addprefix -I$(QUARRY_DIR)/,$(QUARRY_SUBDIRS)) -I$(QUARRY_DIR)/../PakManager
