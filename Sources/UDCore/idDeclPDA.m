/*
===========================================================================

Doom 3 GPL Source Code
Copyright (C) 1999-2011 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 GPL Source Code.

===========================================================================
*/

#include <string.h>

#import "idDeclPDA.h"
#import "UDLexer.h"
#import "UDWorkspace.h"

#define DECL_PDA_RECORD_LEXER_FLAGS (LEXFL_NOSTRINGCONCAT | \
    LEXFL_ALLOWPATHNAMES | \
    LEXFL_ALLOWMULTICHARLITERALS | \
    LEXFL_ALLOWBACKSLASHSTRINGCONCAT | \
    LEXFL_NOFATALERRORS)

idDeclEmail *idDeclEmail_Allocator(void) {
    return [[idDeclEmail alloc] init];
}

idDeclVideo *idDeclVideo_Allocator(void) {
    return [[idDeclVideo alloc] init];
}

idDeclAudio *idDeclAudio_Allocator(void) {
    return [[idDeclAudio alloc] init];
}

idDeclPDA *idDeclPDA_Allocator(void) {
    return [[idDeclPDA alloc] init];
}

/*
static size_t DeclPDA_StringListSize( const idStrList &list ) {
    return list.Allocated();
}*/

static idDecl *DeclPDA_FindReferencedDecl(idDeclManager *declManager, declType_t declType, NSString *name, bool makeDefault, NSError **error) {
    return [declManager findType:declType name:name makeDefault:makeDefault error:error];
}

static idDecl *DeclPDA_FindReferencedDeclByIndex(idDeclManager *declManager, NSMutableArray<NSString *> *list, declType_t declType, int index, NSError **error) {
    if (index < 0 || index >= list.count) {
        return nil;
    }
    return DeclPDA_FindReferencedDecl(declManager, declType, [list objectAtIndex:index], NO, error);
}

static void DeclPDA_AddRuntimeReferencedDecl(idDeclManager *declManager, NSMutableArray *list, NSString *name, BOOL unique, declType_t declType, NSString *notFoundFormat, NSError **error) {
    idDecl *decl = DeclPDA_FindReferencedDecl(declManager, declType, name, NO, error);

    if (decl == nil) {
        NSLog(notFoundFormat, name);
        return;
    }
    if (unique && [list containsObject:decl] != NO) {
        return;
    }
    [list addObject:decl];
}

static void DeclPDA_RemoveAddedStringRefs(NSMutableArray<NSString *> *list, NSInteger originalCount) {
    if (originalCount < 0) {
        originalCount = 0;
    }
    while (list.count > originalCount) {
        [list removeLastObject];
    }
}

/*
static void DeclPDA_PrintStub() {
    common->Printf( "Implement me\n" );
}*/

static BOOL DeclPDA_FinishParse(idLexer *src, const idDecl *decl, NSString *typeName) {
    if ([src hadError]) {
        [src warning:@"%@ decl '%@' had a parse error", typeName, [decl name]];
        return NO;
    }
    return YES;
}
/*
size_t idDeclPDA::Size( void ) const {
    return sizeof( idDeclPDA )
        + DeclPDA_StringListSize( videos )
        + DeclPDA_StringListSize( audios )
        + DeclPDA_StringListSize( emails )
        + pdaName.Allocated()
        + fullName.Allocated()
        + icon.Allocated()
        + id.Allocated()
        + post.Allocated()
        + title.Allocated()
        + security.Allocated();
}*/

/*
void idDeclPDA::Print( void ) const {
    DeclPDA_PrintStub();
}

void idDeclPDA::List( void ) const {
    DeclPDA_PrintStub();
}
*/

@implementation idDeclPDA

-(BOOL)parse:(NSMutableData *)text error:(NSError **)error {
    return [self parse:text noCaching:NO error:error];
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error {
    idLexer *src;
    idToken token;

    (void)noCaching;
    
    src = [[idLexer alloc] initWithFileSystem:self.declManager.workspace.fileSystem];
    if (![src loadMemory:text.bytes length:text.length-1 name:[self fileName] startLine:[self lineNum] error:error]) {
        return NO;
    }
    
    idToken_Init(&token);
    
    [src setFlags:DECL_LEXER_FLAGS];
    [src skipUntilString:@"{" error:error];

    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "}")) {
            break;
        }

        if (!strcasecmp(token.text, "name")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.pdaName = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "fullname")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.fullName = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "icon")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.icon = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "id")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.ident = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "post")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.post = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "title")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.title = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "security")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.security = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "pda_email")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            idDeclEmail *email = (idDeclEmail *)DeclPDA_FindReferencedDecl(self.declManager, DECL_EMAIL, [NSString stringWithUTF8String:token.text], YES, error);
            if (!self.emails) {
                self.emails = [[NSMutableArray alloc] init];
            }
            [self.emails addObject:email];
            continue;
        }

        if (!strcasecmp(token.text, "pda_audio")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            idDeclAudio *audio = (idDeclAudio *)DeclPDA_FindReferencedDecl(self.declManager, DECL_AUDIO, [NSString stringWithUTF8String:token.text], YES, error);
            if (!self.audios) {
                self.audios = [[NSMutableArray alloc] init];
            }
            [self.audios addObject:audio];
            continue;
        }

        if (!strcasecmp(token.text, "pda_video")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            idDeclVideo *video = (idDeclVideo *)DeclPDA_FindReferencedDecl(self.declManager, DECL_VIDEO, [NSString stringWithUTF8String:token.text], YES, error);
            if (!self.videos) {
                self.videos = [[NSMutableArray alloc] init];
            }
            [self.videos addObject:video];
        }
    }

    if (!DeclPDA_FinishParse(src, self, @"PDA")) {
        return NO;
    }

    return YES;
}

-(NSString *)defaultDefinition {
    return @"{\n\tname  \"default pda\"\n}";
}

-(void)freeData {
    if (self.videos) {
        [self.videos removeAllObjects];
    }
    if (self.audios) {
        [self.audios removeAllObjects];
    }
    if (self.emails) {
        [self.emails removeAllObjects];
    }
}

-(void)addVideoByName:(NSString *)name unique:(BOOL)unique {
    DeclPDA_AddRuntimeReferencedDecl(self.declManager, self.videos, name, unique, DECL_VIDEO, @"Video %@ not found\n", nil);
}

-(void)addAudioByName:(NSString *)name unique:(BOOL)unique {
    DeclPDA_AddRuntimeReferencedDecl(self.declManager, self.audios, name, unique, DECL_AUDIO, @"Audio log %@ not found\n", nil);
}

-(void)addEmailByName:(NSString *)name unique:(BOOL)unique {
    DeclPDA_AddRuntimeReferencedDecl(self.declManager, self.emails, name, unique, DECL_EMAIL, @"Email %@ not found\n", nil);
}

@end

@implementation idDeclEmail

-(size_t)size {
    /*
     return sizeof( idDeclEmail )
         + text.Allocated()
         + subject.Allocated()
         + date.Allocated()
         + to.Allocated()
         + from.Allocated()
         + image.Allocated();
     */
    return 0;
}

/*
void idDeclEmail::Print( void ) const {
    DeclPDA_PrintStub();
}

void idDeclEmail::List( void ) const {
    DeclPDA_PrintStub();
}
*/

-(BOOL)parse:(NSMutableData *)text error:(NSError **)error {
    return [self parse:text noCaching:NO error:error];
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error {
    idLexer *src;
    idToken token;

    idToken_Init(&token);
    
    src = [[idLexer alloc] initWithFileSystem:self.declManager.workspace.fileSystem];
    if (![src loadMemory:text.bytes length:text.length-1 name:[self fileName] startLine:[self lineNum] error:error]) {
        return NO;
    }
    
    [src setFlags:DECL_PDA_RECORD_LEXER_FLAGS];
    [src skipUntilString:@"{" error:error];

    NSMutableData *textbuf = [[NSMutableData alloc] init];

    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "}")) {
            break;
        }

        if (!strcasecmp(token.text, "subject")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.subject = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "to")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.to = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "from")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.from = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "date")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.date = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "text")) {
            if (![src readToken:&token error:error] || strcmp(token.text, "{")) {
                [src warning:@"Email decl '%@' had a parse error", [self name]];
                return NO;
            }
            while ([src readToken:&token error:error] && strcmp(token.text, "}")) {
                 [textbuf appendUTF8StringAndNullTerminate:token.text];
            }
            continue;
        }

        if (!strcasecmp(token.text, "image")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.image = [NSString stringWithUTF8String:token.text];
        }
    }
    
    self.body = [NSString stringWithUTF8String:textbuf.bytes];

    return DeclPDA_FinishParse(src, self, @"Email");
}

-(NSString *)defaultDefinition {
    return @"{\n\t{\n\t\tto\t5Mail recipient\n\t\tsubject\t5Nothing\n\t\tfrom\t5No one\n\t}\n}";
}

-(void)freeData {
}

@end

@implementation idDeclVideo

-(size_t)size {
    return 0;
    /*
    return sizeof( idDeclVideo )
        + preview.Allocated()
        + video.Allocated()
        + videoName.Allocated()
        + info.Allocated()
        + audio.Allocated();
     */
}

/*
void idDeclVideo::Print( void ) const {
    DeclPDA_PrintStub();
}

void idDeclVideo::List( void ) const {
    DeclPDA_PrintStub();
}*/

-(BOOL)parse:(NSMutableData *)text error:(NSError **)error {
    return [self parse:text noCaching:NO error:error];
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error {
    idLexer *src;
    idToken token;

    idToken_Init(&token);
    
    src = [[idLexer alloc] initWithFileSystem:self.declManager.workspace.fileSystem];

    if (![src loadMemory:text.bytes length:text.length-1 name:[self fileName] startLine:[self lineNum] error:error]) {
        return NO;
    }
    
    [src setFlags:DECL_PDA_RECORD_LEXER_FLAGS];
    [src skipUntilString:@"{" error:error];

    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "}")) {
            break;
        }

        if (!strcasecmp(token.text, "name")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.videoName = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "preview")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.preview = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "video")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.video = [NSString stringWithUTF8String:token.text];
            if (![self.declManager findMaterial:self.video error:error]) {
                return NO;
            }
            continue;
        }

        if (!strcasecmp(token.text, "info")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.info = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "audio")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.audio = [NSString stringWithUTF8String:token.text];
            //[self.declManager findSound:audio]; // FIXME
        }
    }

    return DeclPDA_FinishParse(src, self, @"Video");
}

-(NSString *)defaultDefinition {
    return @"{\n\t{\n\t\tname\t5Default Video\n\t}\n}";
}

-(void)freeData {
}

@end

@implementation idDeclAudio

-(size_t)size {
    return 0;
    /*
    return sizeof( idDeclAudio )
        + audio.Allocated()
        + audioName.Allocated()
        + info.Allocated()
        + preview.Allocated();*/
}

/*
void idDeclAudio::Print( void ) const {
    DeclPDA_PrintStub();
}

void idDeclAudio::List( void ) const {
    DeclPDA_PrintStub();
}*/

-(BOOL)parse:(NSMutableData *)text error:(NSError **)error {
    return [self parse:text noCaching:NO error:error];
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error {
    idLexer *src;
    idToken token;

    idToken_Init(&token);
    
    src = [[idLexer alloc] initWithFileSystem:self.declManager.workspace.fileSystem];

    if (![src loadMemory:text.bytes length:text.length-1 name:[self fileName] startLine:[self lineNum] error:error]) {
        return NO;
    }
    
    [src setFlags:DECL_PDA_RECORD_LEXER_FLAGS];
    [src skipUntilString:@"{" error:error];

    while ([src readToken:&token error:error]) {
        if (!strcmp(token.text, "}")) {
            break;
        }

        if (!strcasecmp(token.text, "name")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.audioName = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "audio")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.audio = [NSString stringWithUTF8String:token.text];
            //[self.declManager findSound:audio]; // FIXME
            continue;
        }

        if (!strcasecmp(token.text, "info")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.info = [NSString stringWithUTF8String:token.text];
            continue;
        }

        if (!strcasecmp(token.text, "preview")) {
            if (![src readToken:&token error:error]) {
                break;
            }
            self.preview = [NSString stringWithUTF8String:token.text];
        }
    }

    return DeclPDA_FinishParse(src, self, @"Audio");
}

-(NSString *)defaultDefinition {
    return @"{\n\t{\n\t\tname\t5Default Audio\n\t}\n}";
}

-(void)freeData {
}

@end
