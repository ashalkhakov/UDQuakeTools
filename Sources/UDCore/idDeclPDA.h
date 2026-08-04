#import "idDeclManager.h"

/*
===========================================================================

Doom 3 GPL Source Code
Copyright (C) 1999-2011 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 GPL Source Code.

===========================================================================
*/

/*
===============================================================================

    idDeclPDA

===============================================================================
*/

@interface idDeclEmail : idDecl

@property (nonatomic, strong) NSString *from;
@property (nonatomic, strong) NSString *body;
@property (nonatomic, strong) NSString *subject;
@property (nonatomic, strong) NSString *date;
@property (nonatomic, strong) NSString *to;
@property (nonatomic, strong) NSString *image;

@end

idDeclEmail *idDeclEmail_Allocator(void);

@interface idDeclVideo : idDecl

@property (nonatomic, strong) NSString *preview;
@property (nonatomic, strong) NSString *video;
@property (nonatomic, strong) NSString *videoName;
@property (nonatomic, strong) NSString *info;
@property (nonatomic, strong) NSString *audio;

@end

idDeclVideo *idDeclVideo_Allocator(void);

@interface idDeclAudio : idDecl

@property (nonatomic, strong) NSString *audio;
@property (nonatomic, strong) NSString *audioName;
@property (nonatomic, strong) NSString *info;
@property (nonatomic, strong) NSString *preview;

@end

idDeclAudio *idDeclAudio_Allocator(void);

@interface idDeclPDA : idDecl {
    NSMutableArray<NSString *> *videos;
    NSMutableArray<NSString *> *audios;
    NSMutableArray<NSString *> *emails;
    NSInteger                   originalVideos;
    NSInteger                   originalAudios;
    NSInteger                   originalEmails;
}

-(instancetype)init;

-(void)addVideo:(NSString *)name unique:(BOOL)unique;
-(void)addAudio:(NSString *)name unique:(BOOL)unique;
-(void)addEmail:(NSString *)name unique:(BOOL)unique;
-(void)removeAddedEmailsAndVideos;

-(int)numVideos;
-(int)numAudios;
-(int)numEmails;
-(idDeclVideo *)videoByIndex:(int)index;
-(idDeclAudio *)audioByIndex:(int)index;
-(idDeclEmail *)emailByIndex:(int)index;

-(void)setSecurity:(NSString *)security;

@property (nonatomic, strong) NSString *pdaName;
@property (nonatomic, strong) NSString *fullName;
@property (nonatomic, strong) NSString *icon;
@property (nonatomic, strong) NSString *post;
@property (nonatomic, strong) NSString *ident;
@property (nonatomic, strong) NSString *title;

@end

idDeclPDA *idDeclPDA_Allocator(void);
