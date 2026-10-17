#import "idLangDict+Common.h"
#import "idFileSystem.h"
#import "idStr.h"

@implementation idLangDict (Common)

/*
===============
idCommonLocal::FilterLangList, InitLanguageDict
===============
*/
- (void)initLanguage:(NSString *)langName fileSystem:(idFileSystem *)fileSystem {
    [self clear];

    //D3XP: Instead of just loading a single lang file for each language
    //we are going to load all files that begin with the language name
    //similar to the way pak files work. So you can place english001.lang
    //to add new strings to the english language dictionary
    idFileList *langFiles = [fileSystem listFilesTree:@"strings" extension:@".lang" sorted:YES inGameDir:nil error:NULL];
    NSMutableArray<NSString *> *currentLangList = [NSMutableArray array];
    for ( NSString *file in langFiles.list ) {
        // temp.Right( temp.Length() - strlen( "strings/" ) ).Left( lang.Length() )
        NSString *temp = file.length >= 8 ? [file substringFromIndex:8] : @"";
        temp = temp.length > langName.length ? [temp substringToIndex:langName.length] : temp;
        if ( [temp ud_iequals:langName] ) {
            [currentLangList addObject:file];
        }
    }
    for ( NSString *file in currentLangList ) {
        [self load:file clear:NO fileSystem:fileSystem];
    }
}

@end
