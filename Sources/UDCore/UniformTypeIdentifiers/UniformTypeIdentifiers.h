//
//  UniformTypeIdentifiers.h
//  UDQuakeTools — GNUstep compatibility shim
//
//  Apple's UniformTypeIdentifiers framework (macOS 11+) and the small slice
//  of the legacy LaunchServices UTType C API that UDQuakeTools uses do not
//  exist on GNUstep. This shim provides just enough of both for our call
//  sites (UDFileItem, UDBaseEditorViewController): mapping filename
//  extensions to type identifiers and answering "is this an image?".
//
//  It resolves the very same
//      #import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
//  line the macOS build uses: the DeclBrowser GNUmakefile passes -I../UDCore
//  and this header lives in UDCore/UniformTypeIdentifiers/, so the angle
//  include finds it on GNUstep — while on macOS the system framework wins
//  and this file is never seen.
//

#if defined(__APPLE__)
#error "GNUstep compatibility shim included on macOS — the system UniformTypeIdentifiers framework should be used there. Check your header search paths."
#else

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Modern (macOS 11-style) API

@interface UTType : NSObject

/** The uniform type identifier string, e.g. "public.png". */
@property (nonatomic, readonly, copy) NSString *identifier;

+ (nullable UTType *)typeWithIdentifier:(NSString *)identifier;
+ (nullable UTType *)typeWithFilenameExtension:(NSString *)filenameExtension;

- (BOOL)conformsToType:(UTType *)type;

@end

/** "public.image" — the abstract image type. */
extern UTType *UTTypeImage;

#pragma mark - Legacy LaunchServices-style C API
//
// Only what our pre-macOS-11 fallback branches reference. On GNUstep the
// `@available(macOS 11.0, *)` checks take the modern branch (the `*` clause
// covers non-Apple platforms), so these mostly exist to satisfy the
// compiler — but they are implemented faithfully anyway.

// If gnustep-corebase is installed, use ITS CFStringRef (guessing at its
// include-guard macro is fragile — a typedef mismatch is a hard error); only
// when there is no CoreFoundation at all do we define an opaque stand-in.
#if defined(__has_include) && __has_include(<CoreFoundation/CFBase.h>)
#include <CoreFoundation/CFBase.h>
#else
typedef const struct UDShimCFString *CFStringRef;
#endif

extern CFStringRef kUTTypeImage;                 // "public.image"
extern CFStringRef kUTTagClassFilenameExtension; // "public.filename-extension"

BOOL UTTypeConformsTo(CFStringRef inUTI, CFStringRef inConformsToUTI);

/** The caller owns the returned string (release with CFBridgingRelease). */
CFStringRef _Nullable UTTypeCreatePreferredIdentifierForTag(CFStringRef inTagClass,
                                                            CFStringRef inTag,
                                                            CFStringRef _Nullable inConformingToUTI);

NS_ASSUME_NONNULL_END

#endif // !__APPLE__
