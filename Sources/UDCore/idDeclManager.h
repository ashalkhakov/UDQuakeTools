// Copyright (C) 2004 Id Software, Inc.
//

#import <Foundation/Foundation.h>
#import "idLexer.h"

@class UDWorkspace;
@class idFile;

/*
===============================================================================

    Declaration Manager

    All "small text" data types, like materials, sound shaders, fx files,
    entity defs, etc. are managed uniformly, allowing reloading, purging,
    listing, printing, etc. All "large text" data types that never have more
    than one declaration in a given file, like maps, models, AAS files, etc.
    are not handled here.

    The manager is a dumb repository / persistence layer: it tracks decl
    source files, and for every decl it stores the raw text definition plus
    bookkeeping (name, type, source file, offsets, checksum). It never
    interprets the decl text beyond locating the braced sections. Structured
    views over the decl text (a PDA's fields, a particle's stages, ...) live
    in the Core Data layer (UDDeclIncrementalStore + UDDeclManagedObjects),
    which parses/unparses decl text on demand.

    A decl will never, ever go away once it is created. The manager is
    guaranteed to always return the same idDeclBase pointer for a decl
    type/name combination. Decl namespaces are separate for each type.

===============================================================================
*/

typedef enum {
    DECL_TABLE                = 0,
    DECL_MATERIAL,
    DECL_SKIN,
    DECL_SOUND,
    DECL_ENTITYDEF,
    DECL_MODELDEF,
// RAVEN BEGIN
// jscott: added new decls
    DECL_MATERIALTYPE,
    DECL_LIPSYNC,
    DECL_PLAYBACK,
    DECL_EFFECT,
// rjohnson: camera is now contained in a def for frame commands
    DECL_CAMERADEF,
// jscott: don't use these
    DECL_FX,
    DECL_PARTICLE,
// RAVEN END
    DECL_AF,
    DECL_PDA,
    DECL_VIDEO,
    DECL_AUDIO,
    DECL_EMAIL,
    DECL_MODELEXPORT,
    DECL_MAPDEF,

    // new decl types can be added here
    DECL_PLAYER_MODEL,

    DECL_MAX_TYPES            = 32
} declType_t;

typedef enum {
    DS_UNPARSED,
    DS_DEFAULTED,            // set if a parse failed due to an error, or the lack of any source
    DS_PARSED
} declState_t;

// multiple strings seperated by whitespaces are not concatenated
// no escape characters inside strings
// allow path seperators in names
// allow multi character literals
// allow multiple strings seperated by '\' to be concatenated
// just set a flag instead of fatal erroring
#define DECL_LEXER_FLAGS        (LEXFL_NOSTRINGCONCAT | \
                                LEXFL_NOSTRINGESCAPECHARS | \
                                LEXFL_ALLOWPATHNAMES | \
                                LEXFL_ALLOWMULTICHARLITERALS | \
                                LEXFL_ALLOWBACKSLASHSTRINGCONCAT | \
                                LEXFL_NOFATALERRORS)

/*
 * The one and only decl representation the manager hands out. Every decl,
 * regardless of type, is a text-backed record; there are no typed
 * subclasses (the concrete implementation is the manager-private
 * idDeclLocal).
 */
@interface idDeclBase : NSObject

// Returns the name of the decl.
-(NSString *)name;

// Returns the decl type.
-(declType_t)type;

// Returns the decl state which is useful for finding out if a decl defaulted.
-(declState_t)state;

// Returns true if the decl was defaulted (has no explicit source).
-(BOOL)isImplicit;

-(BOOL)isValid;

// Sets state back to unparsed.
// Used by decl editors to undo any changes to the decl.
-(void)invalidate;

-(void)reload;

-(void)ensureNotPurged;

// Returns the line number the decl starts.
-(int)lineNum;

// Returns the name of the file in which the decl is defined.
-(NSString *)fileName;

// Returns the decl text.
-(void)text:(NSMutableData *)text;

// Returns the length of the decl text.
-(int)textLength;

// RAVEN BEGIN
-(int)compressedLength;
// RAVEN END

// Sets new decl text.
-(void)setText:(NSMutableData *)newText;

// Saves out new text for the decl.
// Used by decl editors to replace the decl text in the source file.
-(BOOL)replaceSourceFileText:(NSError **)error;

// Returns true if the source file changed since it was loaded and parsed.
-(BOOL)sourceFileChanged;

// Flags the decl as defaulted; installs a minimal default body if the decl
// has no text at all.
-(BOOL)makeDefault:(NSError **)error;

-(BOOL)everReferenced;

// RAVEN BEGIN
-(void)setReferencedThisLevel;
// RAVEN END

// Checks that the given text is a well-formed decl body (a braced section).
-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error;
-(void)freeData;
-(size_t)size;
-(void)list;
-(void)print;
// RAVEN BEGIN
// scork: Validation call for detailed error-reporting
-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo;
// RAVEN END
@end

@class idDeclManager;

@interface UDDeclEnumerator : NSObject <NSFastEnumeration>

- (instancetype)initWithManager:(idDeclManager *)manager
                           type:(declType_t)type
                     forceParse:(BOOL)forceParse;

@end

@interface idDeclManager : NSObject

// the workspace that owns this file system instance
@property (nonatomic, weak, readonly) UDWorkspace *workspace;

@property (assign, nonatomic) BOOL insideLoad;

-(instancetype)initWithWorkspace:(UDWorkspace *)workspace;
-(BOOL)startup:(NSError **)error;
-(void)shutdown;
-(void)reload:(BOOL)force error:(NSError **)error;

-(void)beginLevelLoad;
-(void)endLevelLoad;

// Registers a new decl type.
-(void)registerDeclType:(declType_t)type typeName:(NSString *)typeName;
// jsinger: Added to support loading all decls from a single file
-(void)startLoadingDecls;
-(void)finishLoadingDecls;
-(BOOL)loadDeclsFromFile:(NSError **)error;
-(BOOL)writeDeclFile:(NSError **)error;
-(void)flushDecls;
// RAVEN END

-(NSString *)defaultFileNameForDeclType:(declType_t)type name:(NSString *)name;

// RAVEN BEGIN
// jscott: for timing
// Registers a new folder with decl files.
-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType unique:(BOOL)unique nonrecursive:(BOOL)norecurse error:(NSError **)error;
-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType unique:(BOOL)unique error:(NSError **)error; // nonrecursive=NO
-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType nonrecursive:(BOOL)norecurse error:(NSError **)error; // unique=NO
-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType error:(NSError **)error; // unique=NO, nonrecursive=NO
// RAVEN END

-(BOOL)registerDeclFolder:(NSString *)folder extension:(NSString *)extension declType:(declType_t)defaultType error:(NSError **)error;

// Returns a checksum for all loaded decl text.
-(int)checksum;

// Returns the number of decl types.
-(int)numDeclTypes;

// Returns the type name for a decl type.
-(NSString *)declNameFromType:(declType_t)type;

// Returns the decl type for a type name.
-(declType_t)declTypeFromName:(NSString *)typeName;

// If makeDefault is true, a default decl of appropriate type will be created
// if an explicit one isn't found. If makeDefault is false, NULL will be returned.
// if the decl wasn't explcitly defined.
-(idDeclBase *)findType:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault noCaching:(BOOL)noCaching error:(NSError **)error;
-(idDeclBase *)findType:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error;
-(idDeclBase *)findType:(declType_t)type name:(NSString *)name noCaching:(BOOL)noCaching error:(NSError **)error;
-(idDeclBase *)findType:(declType_t)type name:(NSString *)name error:(NSError **)error;

-(idDeclBase *)findDeclWithoutParsing:(declType_t)type name:(NSString *)name;
-(idDeclBase *)findDeclWithoutParsing:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault;

// The complete lists of decls can be walked to populate editor browsers.
// If forceParse is set false, you can get the decl to check name / filename / etc.
// without causing it to load the source text.
-(idDeclBase *)declByName:(NSString *)name type:(declType_t)type forceParse:(BOOL)forceParse error:(NSError **)error;
-(idDeclBase *)declByName:(NSString *)name type:(declType_t)type error:(NSError **)error; // forceParse = NO

- (id<NSFastEnumeration>)declsOfType:(declType_t)type;
- (id<NSFastEnumeration>)declsOfType:(declType_t)type forceParse:(BOOL)forceParse;

// Creates a new decl of the given type with the given name in
// the given file used by editors to create a new decls.
-(idDeclBase *)createNewDecl:(declType_t)type name:(NSString *)name fileName:(NSString *)fileName;
// Set the new source text of the decl
-(BOOL)updateDecl:(declType_t)type name:(NSString *)name sourceText:(NSMutableData *)text;
// Rename the decl.
-(BOOL)renameDecl:(declType_t)type fromName:(NSString *)oldName toName:(NSString *)newName;
// Move decl from its file to the new file.
-(BOOL)moveDecl:(declType_t)type name:(NSString *)name toFileName:(NSString *)fileName;
// Completely remove the decl.
-(BOOL)removeDecl:(declType_t)type name:(NSString *)name;

// Use this after creating, updating, renaming, moving, or removing decls.
// Writes modified decls out to disk
-(BOOL)writeDecls:(NSError **)error;

// Returns the file names of every decl source file currently loaded (including
// files created via createNewDecl:name:fileName: that have not been written
// to disk yet). Used by editors/adapters that need to present decl files
// without reaching into the manager's private bookkeeping.
-(NSArray<NSString *> *)loadedDeclFileNames;

// Returns YES and fills in the checksum/timestamp of the last load for the
// given loaded decl file name, or returns NO if no such file is loaded.
-(BOOL)declFileInfoForName:(NSString *)fileName checksum:(int *)outChecksum timestamp:(NSUInteger *)outTimestamp;

// Returns every decl defined in the given loaded decl file (any type), using
// the manager's per-file bookkeeping — no scanning of the per-type lists and
// no parsing. Empty if no such file is loaded.
-(NSArray<idDeclBase *> *)declsInFileName:(NSString *)fileName;

// When media files are loaded, a reference line can be printed at a
// proper indentation if decl_show is set
-(void)mediaPrint:(NSString *)fmt, ...;

-(void)writePrecacheCommands:(idFile *)f;

// RAVEN BEGIN
// jscott: precache any guide (template) files
-(void)parseGuides;
-(void)shutdownGuides;
-(BOOL)evaluateGuide:(NSMutableString *)name source:(idLexer *)src definition:(NSMutableString *)definition error:(NSError **)error;
-(BOOL)evaluateInlineGuide:(NSMutableString *)name definition:(NSMutableString *)definition error:(NSError **)error;
// RAVEN END

// jmarshall - used by the quake 4 tools.
-(NSString *)newName:(declType_t)type base:(NSString *)base;
-(NSString *)declTypeName:(declType_t)type;
-(size_t)listDeclSummary;
-(void)removeDeclFile:(NSString *)file;
// jmarshall end

// scork: Validation call for detailed error-reporting
-(BOOL)validate:(declType_t)type name:(NSString *)name reportTo:(NSMutableString *)strReportTo;

@end
