# Decl Browser's headers, in its folders: a build of its sources (the app,
# its tests) sets DECLBROWSER_DIR (the path to Sources/DeclBrowser from its
# own directory), includes this, and adds $(DECLBROWSER_INCLUDE_DIRS) to its
# include directories.
DECLBROWSER_SUBDIRS = App Model Documents Window Editors Editors/Decls Preview GUIEditor Scripts ThirdParty/DMTabBar
DECLBROWSER_INCLUDE_DIRS = -I$(DECLBROWSER_DIR) $(addprefix -I$(DECLBROWSER_DIR)/,$(DECLBROWSER_SUBDIRS))
