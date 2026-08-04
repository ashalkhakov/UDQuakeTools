// Copyright (C) 2004 Id Software, Inc.
//

#import "idDeclManager.h"

/*
===============================================================================

    idDeclSkin

===============================================================================
*/

@interface idSkinMapping : NSObject

@property (strong, nonatomic) idDeclMaterial *from; // nil == any unmatched shader
@property (strong, nonatomic) idDeclMaterial *to;

@end

@interface idDeclSkin : idDecl

// virtual so the renderer module reaches it across the DLL boundary
// (Phase B8, docs/dev/plans/2026-07-16-vulkan-renderer-phase-b.md)
-(idDeclMaterial *)remapShaderBySkin:(idDeclMaterial *)shader;

// model associations are just for the preview dialog in the editor
// RAVEN BEGIN
// jscott: inlined for access from tools dll
-(int)numModelAssociations; // { return( associatedModels.Num() ); }
// jscott: to prevent a recursive crash
-(BOOL)rebuildTextSource; // { return( false ); }
// scork: validation member for more detailed error-checks
//virtual bool            Validate( const char *psText, int iTextLength, idStr &strReportTo ) const;
// RAVEN END
-(NSString *)associatedModelByIndex:(int)index;

@end

idDeclSkin *idDeclSkin_Allocator(void);
