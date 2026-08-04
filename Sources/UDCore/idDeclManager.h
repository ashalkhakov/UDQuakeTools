// Copyright (C) 2004 Id Software, Inc.
//

#import <Foundation/Foundation.h>
#import "UDLexer.h"

@class UDWorkspace;

/*
===============================================================================

    Declaration Manager

    All "small text" data types, like materials, sound shaders, fx files,
    entity defs, etc. are managed uniformly, allowing reloading, purging,
    listing, printing, etc. All "large text" data types that never have more
    than one declaration in a given file, like maps, models, AAS files, etc.
    are not handled here.

    A decl will never, ever go away once it is created. The manager is
    garranteed to always return the same decl pointer for a decl type/name
    combination. The index of a decl in the per type list also stays the
    same throughout the lifetime of the engine. Although the pointer to
    a decl always stays the same, one should never maintain pointers to
    data inside decls. The data stored in a decl is not garranteed to stay
    the same for more than one engine frame.

    The decl indexes of explicitely defined decls are garrenteed to be
    consistent based on the parsed decl files. However, the indexes of
    implicit decls may be different based on the order in which levels
    are loaded.

    The decl namespaces are separate for each type. Comments for decls go
    above the text definition to keep them associated with the proper decl.

    During decl parsing, errors should never be issued, only warnings
    followed by a call to MakeDefault().

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


@interface idDeclBase : NSObject

-(NSString *)name;
-(declType_t)declType;
-(declState_t)state;
-(BOOL)isImplicit;
-(BOOL)isValid;
-(void)invalidate;
-(void)reload;
-(void)ensureNotPurged;
-(int)index;
-(int)lineNum;
-(NSString *)fileName;
-(void)text:(NSMutableData *)text;
-(int)textLength;

// RAVEN BEGIN
-(int)compressedLength;
// RAVEN END

-(void)setText:(NSMutableData *)newText;
-(BOOL)replaceSourceFileText:(NSError **)error;
-(BOOL)sourceFileChanged;
-(BOOL)makeDefault:(NSError **)error;
-(BOOL)everReferenced;

// RAVEN BEGIN
-(void)setReferencedThisLevel;
// RAVEN END

-(BOOL)setDefaultText;
-(NSString *)defaultDefinition;
-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error;
-(void)freeData;
-(size_t)size;
-(void)list;
-(void)print;
// RAVEN BEGIN
// jscott: to prevent a recursive crash
-(BOOL)rebuildTextSource;
// scork: Validation call for detailed error-reporting
-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo;
// RAVEN END
@end

// RAVEN BEGIN
// jscott: for guides
/*
#define MAX_GUIDE_PARMS                20
#define    MAX_GUIDE_SHADER_SIZE        20480

class rvDeclGuide
{
private:
    idStr        mName;
    idStr        mParms[MAX_GUIDE_PARMS];
    idStr        mDefinition;
    int            mNumParms;

public:
                rvDeclGuide( idStr &name );
                ~rvDeclGuide( void );

    const char    *GetName( void ) const { return( mName.c_str() ); }
    int            GetNumParms( void ) const { return( mNumParms ); }
    const char    *GetParm( int index ) const { assert( index < mNumParms ); return( mParms[index].c_str() ); }

    void        SetParm( int index, const char *value );
    void        RemoveOuterBracing( void );
    void        Parse( idLexer *src );
    bool        Evaluate( idLexer *src, idStr &definition );
};
 */
// RAVEN END

@class idDeclManager;

@interface idDecl : NSObject

@property (weak, nonatomic, readonly) idDeclManager *declManager;

// The constructor should initialize variables such that
// an immediate call to FreeData() does no harm.

// Returns the name of the decl.
-(NSString *)name;

// Returns the decl type.
-(declType_t)declType;

// Returns the decl state which is usefull for finding out if a decl defaulted.
-(declState_t)state;

// Returns true if the decl was defaulted or the text was created with a call to SetDefaultText.
-(BOOL)isImplicit;

// The only way non-manager code can have an invalid decl is if the *ByIndex()
// call was used with forceParse = false to walk the lists to look at names
// without touching the media.
-(BOOL)isValid;

// Sets state back to unparsed.
// Used by decl editors to undo any changes to the decl.
-(void)invalidate;

// if a pointer might possible be stale from a previous level,
// call this to have it re-parsed
-(void)ensureNotPurged;

// Returns the index in the per-type list.
-(int)index;

// Returns the line number the decl starts.
-(int)lineNum;

// Returns the name of the file in which the decl is defined.
-(NSString *)fileName;

// Returns the decl text.
-(void)text:(NSMutableData *)text;

// Returns the length of the decl text.
-(int)textLength;

// Returns the compressed length of the decl text.
-(int)compressedLength;

// Sets new decl text.
-(void)setText:(NSMutableData *)text;

// Saves out new text for the decl.
// Used by decl editors to replace the decl text in the source file.
-(BOOL)replaceSourceFileText:(NSError **)error;

// Returns true if the source file changed since it was loaded and parsed.
-(BOOL)sourceFileChanged;

// Frees data and makes the decl a default.
-(BOOL)makeDefault:(NSError **)error;

// Returns true if the decl was ever referenced.
-(BOOL)everReferenced;

// Sets textSource to a default text if necessary.
// This may be overridden to provide a default definition based on the
// decl name. For instance materials may default to an implicit definition
// using a texture with the same name as the decl.
-(BOOL)setDefaultText;

// Each declaration type must have a default string that it is guaranteed
// to parse acceptably. When a decl is not explicitly found, is purged, or
// has an error while parsing, MakeDefault() will do a FreeData(), then a
// Parse() with DefaultDefinition(). The defaultDefintion should start with
// an open brace and end with a close brace.
-(NSString *)defaultDefinition;

// The manager will have already parsed past the type, name and opening brace.
// All necessary media will be touched before return.
// The manager will have called FreeData() before issuing a Parse().
// The subclass can call MakeDefault() internally at any point if
// there are parse errors.
-(BOOL)parse:(NSMutableData *)text error:(NSError **)error;
-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error;

// Frees any pointers held by the subclass. This may be called before
// any Parse(), so the constructor must have set sane values. The decl will be
// invalid after issuing this call, but it will always be immediately followed
// by a Parse()
-(void)freeData;

// Returns the size of the decl in memory.
-(size_t)size;

// If this isn't overridden, it will just print the decl name.
// The manager will have printed 7 characters on the line already,
// containing the reference state and index number.
-(void)list;

// The print function will already have dumped the text source
// and common data, subclasses can override this to dump more
// explicit data.
-(void)print;

// RAVEN BEGIN
// Rebuilds the text source of the decl for saving
-(BOOL)rebuildTextSource;

// Marks this decl as referenced this level
-(void)setReferencedThisLevel;

// scork: for detailed error reporting
-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo;
// RAVEN END

-(idDeclBase*)base;
-(void)setBase:(idDeclBase *)base;
@end

static inline BOOL DeclManager_ValidateParsedDecl(const idDecl *decl, declType_t type, BOOL parsed) {
    // Doom 3 / Quake 4 skin parsing reports success through the defaulted state
    // rather than a true return value.
    if (type == DECL_SKIN) {
        return decl == nil || [decl state] != DS_DEFAULTED;
    }

    return parsed && (decl == nil || [decl state] != DS_DEFAULTED);
}

static inline void DeclManager_FreeAllocatedDecl(idDecl *decl) {
    if (decl == nil) {
        return;
    }

    idDeclBase *base = [decl base];
    [decl setBase:nil];
    decl = nil; // delete decl;
    base = nil; // delete base;
}

/*
template< class type >
ID_INLINE idDecl *idDeclAllocator( void ) {
    return new type;
}

// RAVEN BEGIN
// jsinger: added to allow support for serialization/deserialization of binary decls
#ifdef RV_BINARYDECLS
template< class type >
ID_INLINE SerializableBase *idDeclStreamAllocator( SerialInputStream &stream ) {
    type *ptr = new type(stream);

    return dynamic_cast<SerializableBase *>(ptr);
}
#endif
*/

@class idDeclMaterial, idDeclTable, idDeclSkin, idSoundShader;

@class idFile;

typedef idDecl *(*idDeclAllocator_t)(void);

// RAVEN BEGIN
// jscott: new decl types
@class rvDeclMatType, rvDeclLipSync, rvDeclPlayback, rvDeclEffect, rvDeclPlayerModel;
// RAVEN END

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
-(void)registerDeclType:(declType_t)type typeName:(NSString *)typeName allocator:(idDeclAllocator_t)allocator;
// jsinger: Added to support loading all decls from a single file
-(void)startLoadingDecls;
-(void)finishLoadingDecls;
-(BOOL)loadDeclsFromFile:(NSError **)error;
-(BOOL)writeDeclFile:(NSError **)error;
-(void)flushDecls;
// RAVEN END

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
// if an explicit one isn't found. If makeDefault is false, NULL will be returned
// if the decl wasn't explcitly defined.
-(idDecl *)findType:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault noCaching:(BOOL)noCaching error:(NSError **)error;
-(idDecl *)findType:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error;
-(idDecl *)findType:(declType_t)type name:(NSString *)name noCaching:(BOOL)noCaching error:(NSError **)error;
-(idDecl *)findType:(declType_t)type name:(NSString *)name error:(NSError **)error;

-(idDecl *)findDeclWithoutParsing:(declType_t)type name:(NSString *)name;
-(idDecl *)findDeclWithoutParsing:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault;

-(void)reloadFile:(NSString *)filename force:(BOOL)force;

// Returns the number of decls of the given type.
-(int)numDecls:(declType_t)type;

// The complete lists of decls can be walked to populate editor browsers.
// If forceParse is set false, you can get the decl to check name / filename / etc.
// without causing it to parse the source and load media.
-(idDecl *)declByIndex:(int)index type:(declType_t)type forceParse:(BOOL)forceParse error:(NSError **)error;
-(idDecl *)declByIndex:(int)index type:(declType_t)type error:(NSError **)error;

// List and print decls.
//-(void)listType:(declType_t)type;
//-(void)printType:(declType_t)type;

// Creates a new default decl of the given type with the given name in
// the given file used by editors to create a new decls.
-(idDecl *)createNewDecl:(declType_t)type name:(NSString *)name fileName:(NSString *)fileName;

// BSM - Added for the material editors rename capabilities
-(BOOL)renameDecl:(declType_t)type fromName:(NSString *)oldName toName:(NSString *)newName;

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

// Convenience functions for specific types.
-(idDeclMaterial *)findMaterial:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error;
-(idDeclMaterial *)findMaterial:(NSString *)name error:(NSError **)error; // makeDefault=YES
-(idDeclTable *)findTable:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error;
-(idDeclTable *)findTable:(NSString *)name error:(NSError **)error; // makeDefault=YES
-(idDeclSkin *)findSkin:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error;
-(idDeclSkin *)findSkin:(NSString *)name error:(NSError **)error; // makeDefault=YES
/*
virtual const idSoundShader *    FindSound( const char *name, bool makeDefault = true ) = 0;

// RAVEN BEGIN
// jscott: for new Raven decls
virtual const rvDeclMatType *    FindMaterialType( const char *name, bool makeDefault = true ) = 0;
virtual    const rvDeclLipSync *    FindLipSync( const char *name, bool makeDefault = true ) = 0;
virtual    const rvDeclPlayback *    FindPlayback( const char *name, bool makeDefault = true ) = 0;
virtual    const rvDeclEffect *    FindEffect( const char *name, bool makeDefault = true ) = 0;
// RAVEN END
*/
-(idDeclMaterial *)materialByIndex:(int)index forceParse:(BOOL)forceParse error:(NSError **)error;
-(idDeclMaterial *)materialByIndex:(int)index error:(NSError **)error; // forceParse=YES
-(idDeclTable *)tableByIndex:(int)index forceParse:(BOOL)forceParse error:(NSError **)error;
-(idDeclTable *)tableByIndex:(int)index error:(NSError **)error; // forceParse=YES
-(idDeclSkin *)skinByIndex:(int)index forceParse:(BOOL)forceParse error:(NSError **)error;
-(idDeclSkin *)skinByIndex:(int)index error:(NSError **)error; // forceParse=YES

/*
virtual const idSoundShader *    SoundByIndex( int index, bool forceParse = true ) = 0;

 // RAVEN BEGIN
// jscott: for new Raven decls
virtual const rvDeclMatType *    MaterialTypeByIndex( int index, bool forceParse = true ) = 0;
virtual const rvDeclLipSync *    LipSyncByIndex( int index, bool forceParse = true ) = 0;
virtual    const rvDeclPlayback *    PlaybackByIndex( int index, bool forceParse = true ) = 0;
virtual const rvDeclEffect *    EffectByIndex( int index, bool forceParse = true ) = 0;

virtual void                    StartPlaybackRecord(rvDeclPlayback* playback) = 0;
virtual bool                    SetPlaybackData(rvDeclPlayback* playback, int now, int control, class rvDeclPlaybackData* pbd) = 0;
virtual bool                    GetPlaybackData( const rvDeclPlayback *playback, int control, int now, int last, class rvDeclPlaybackData *pbd ) = 0;
virtual bool                    FinishPlayback( rvDeclPlayback *playback ) = 0;
*/

// jmarshall - used by the quake 4 tools.
-(NSString *)newName:(declType_t)type base:(NSString *)base;
-(NSString *)declTypeName:(declType_t)type;
-(size_t)listDeclSummary;
-(void)removeDeclFile:(NSString *)file;
// jmarshall end

// scork: Validation call for detailed error-reporting
-(BOOL)validate:(declType_t)type index:(int)iIndex reportTo:(NSMutableString *)strReportTo;
-(idDecl *)allocateDecl:(declType_t)type;

/*
// interface wrapper over MT_GetMaterialTypeArray so the renderer module
// reaches the material-type decl data across the DLL boundary (Phase B8,
// docs/dev/plans/2026-07-16-vulkan-renderer-phase-b.md); const char*
// because idStr must never cross the module ABI by value
virtual byte *                    GetMaterialTypeArray( const char *image, int &width, int &height ) = 0;

#if defined(_XENON)
// mwhitlock: Xenon texture streaming
    virtual void                    SetLightMaterialList(idList<idMaterial*>* materialList) = 0;
    virtual void                    SetEntityMaterialList(idList<idMaterial*>* materialList) = 0;
    virtual void                    PurgeType( declType_t type ) = 0;
#endif
*/
// RAVEN END
@end

/*
extern idDeclManager *        declManager;

template< declType_t type >
ID_INLINE void idListDecls_f( const idCmdArgs &args ) {
    declManager->ListType( args, type );
}

template< declType_t type >
ID_INLINE void idPrintDecls_f( const idCmdArgs &args ) {
    declManager->PrintType( args, type );
}
*/
