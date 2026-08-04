/*
===========================================================================

Doom 3 GPL Source Code
Copyright (C) 1999-2011 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 GPL Source Code.

===========================================================================
*/

#import "idDeclMaterial.h"

@implementation idDeclMaterial

-(instancetype)init {
    return [super init];
}

-(BOOL)setDefaultText {
    // if there exists an image with the same name
    if (YES) { //fileSystem->ReadFile( GetName(), NULL ) != -1 ) {
        NSString *noPicMip = @""; // R_MaterialNeedsImplicitGuiAtlasNoPicMip( GetName() ) ? "nopicmip\n" : "";
        
        NSString *generated = [NSString stringWithFormat:@"material %@ // IMPLICITLY GENERATED\n{\n\nblend blend\ncolored\nmap \"%@\"\nclamp\n%@}\n}\n", [self name], [self name], noPicMip];
        
        [self setText:[[generated dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]];
        return YES;
    } else {
        return NO;
    }
}

-(NSString *)defaultDefinition {
    return
        @"{\n"
        @"\t"    @"{\n"
        @"\t\t"        @"blend\tblend\n"
        @"\t\t"        @"map\t\t_default\n"
        @"\t"    @"}\n"
        @"}";
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error {
    return YES;
}

-(void)freeData {
    
}

-(size_t)size {
    return sizeof(idDeclMaterial *);
}

-(void)print {
    
}

-(BOOL)rebuildTextSource {
    return NO;
}

-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo {
    idDecl *decl = [self.declManager allocateDecl:DECL_MATERIAL];
    const BOOL valid = DeclManager_ValidateParsedDecl(decl, DECL_MATERIAL, decl != nil && [decl parse:psText noCaching:NO error:nil]);
    DeclManager_FreeAllocatedDecl(decl);
    return valid;
}

@end

idDeclMaterial *idDeclMaterial_Allocator(void) {
    return [[idDeclMaterial alloc] init];
}
