#import "idDeclManager.h"

@interface idDeclMaterial : idDecl

-(BOOL)setDefaultText;
-(NSString *)defaultDefinition;
-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error;
-(void)freeData;
-(size_t)size;
-(void)print;
-(BOOL)rebuildTextSource;
-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo;

@end

idDeclMaterial *idDeclMaterial_Allocator(void);
