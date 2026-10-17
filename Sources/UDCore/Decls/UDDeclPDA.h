/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclPDA.h — PDAs, emails, audio logs and videos (idDeclPDA and its kin).
 */

#import "UDDeclBase.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclPDA : UDDeclBase

@property (nonatomic, copy, nullable) NSString *pdaName;
@property (nonatomic, copy, nullable) NSString *fullName;
@property (nonatomic, copy, nullable) NSString *icon;
@property (nonatomic, copy, nullable) NSString *ident;
@property (nonatomic, copy, nullable) NSString *post;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *security;

@property (nonatomic, strong, nullable) NSSet<__kindof UDDeclBase *> *audios;
@property (nonatomic, strong, nullable) NSSet<__kindof UDDeclBase *> *emails;
@property (nonatomic, strong, nullable) NSSet<__kindof UDDeclBase *> *videos;

@end

@interface UDDeclEmail : UDDeclBase

@property (nonatomic, copy, nullable) NSString *from;
@property (nonatomic, copy, nullable) NSString *to;
@property (nonatomic, copy, nullable) NSString *subject;
@property (nonatomic, copy, nullable) NSString *date;
@property (nonatomic, copy, nullable) NSString *body;
@property (nonatomic, copy, nullable) NSString *image;

@property (nonatomic, strong, nullable) UDDeclPDA *pda;

@end

@interface UDDeclAudio : UDDeclBase

@property (nonatomic, copy, nullable) NSString *audioName;
@property (nonatomic, copy, nullable) NSString *audio;
@property (nonatomic, copy, nullable) NSString *info;
@property (nonatomic, copy, nullable) NSString *preview;

@property (nonatomic, strong, nullable) UDDeclPDA *pda;

@end

@interface UDDeclVideo : UDDeclBase

@property (nonatomic, copy, nullable) NSString *videoName;
@property (nonatomic, copy, nullable) NSString *video;
@property (nonatomic, copy, nullable) NSString *audio;
@property (nonatomic, copy, nullable) NSString *info;
@property (nonatomic, copy, nullable) NSString *preview;

@property (nonatomic, strong, nullable) UDDeclPDA *pda;

@end

NS_ASSUME_NONNULL_END
