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
//  REQUIRES gnustep-corebase (CoreFoundation) — assumed installed, like the
//  rest of the GNUstep stack this project builds against.
//

#if defined(__APPLE__)
#error "GNUstep compatibility shim included on macOS — the system UniformTypeIdentifiers framework should be used there. Check your header search paths."
#else

#import <Foundation/Foundation.h>
#import <CoreFoundation/CFBase.h> // gnustep-corebase: the real CFStringRef

#pragma mark - Modern (macOS 11-style) API

NS_ASSUME_NONNULL_BEGIN

@interface UTType : NSObject

/** The uniform type identifier string, e.g. "public.png". */
@property (nonatomic, readonly, copy) NSString *identifier;

+ (nullable UTType *)typeWithIdentifier:(NSString *)identifier;
+ (nullable UTType *)typeWithFilenameExtension:(NSString *)filenameExtension;

- (BOOL)conformsToType:(UTType *)type;

@end

/** "public.image" — the abstract image type. */
extern UTType *UTTypeImage;

NS_ASSUME_NONNULL_END

#pragma mark - Legacy LaunchServices-style C API
//
// Only what our pre-macOS-11 fallback branches reference. On GNUstep the
// `@available(macOS 11.0, *)` checks take the modern branch (the `*` clause
// covers non-Apple platforms), so these mostly exist to satisfy the
// compiler — but they are implemented faithfully anyway.
// (Annotated explicitly, outside the assume_nonnull region.)

extern CFStringRef _Nonnull kUTTypeImage;                 // "public.image"
extern CFStringRef _Nonnull kUTTagClassFilenameExtension; // "public.filename-extension"

BOOL UTTypeConformsTo(CFStringRef _Nullable inUTI, CFStringRef _Nullable inConformsToUTI);

/** The caller owns the returned string (release with CFBridgingRelease). */
CFStringRef _Nullable UTTypeCreatePreferredIdentifierForTag(CFStringRef _Nonnull inTagClass,
                                                            CFStringRef _Nonnull inTag,
                                                            CFStringRef _Nullable inConformingToUTI);

#endif // !__APPLE__
