//
//  UniformTypeIdentifiers.m
//  UDQuakeTools — GNUstep compatibility shim (see the header for the story).
//
//  Compiled only on GNUstep; on macOS the system framework provides all of
//  this and the whole file preprocesses to nothing.
//

#if !defined(__APPLE__)

#import "UniformTypeIdentifiers.h"

// The identifiers we hand out for the filename extensions idTech assets
// actually use (real UTI strings where Apple defined one). Anything unknown
// gets a dynamic "dyn.<ext>" identifier, mirroring Apple's behavior of never
// returning nil for an extension.
static NSDictionary<NSString *, NSString *> *UDShimExtensionToIdentifier(void) {
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"png":  @"public.png",
            @"jpg":  @"public.jpeg",
            @"jpeg": @"public.jpeg",
            @"gif":  @"com.compuserve.gif",
            @"bmp":  @"com.microsoft.bmp",
            @"ico":  @"com.microsoft.ico",
            @"tif":  @"public.tiff",
            @"tiff": @"public.tiff",
            @"tga":  @"com.truevision.tga-image",
            @"dds":  @"com.microsoft.directdraw-surface",
            @"pcx":  @"cx.c3.pcx",
            @"webp": @"org.webmproject.webp",
            @"psd":  @"com.adobe.photoshop-image",
            @"txt":  @"public.plain-text",
        };
    });
    return map;
}

static NSString * const UDShimImageIdentifier = @"public.image";

// Every identifier that "conforms to public.image" as far as we care.
static NSSet<NSString *> *UDShimImageIdentifiers(void) {
    static NSSet<NSString *> *identifiers = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *set = [NSMutableSet setWithObject:UDShimImageIdentifier];
        NSArray<NSString *> *imageExtensions =
            @[@"png", @"jpg", @"jpeg", @"gif", @"bmp", @"ico", @"tif", @"tiff",
              @"tga", @"dds", @"pcx", @"webp", @"psd"];
        for (NSString *extension in imageExtensions) {
            [set addObject:UDShimExtensionToIdentifier()[extension]];
        }
        identifiers = [set copy];
    });
    return identifiers;
}

UTType *UTTypeImage = nil;
CFStringRef kUTTypeImage = NULL;
CFStringRef kUTTagClassFilenameExtension = NULL;

@implementation UTType {
    NSString *_identifier;
}

// Globals are initialized from +load (the ObjC runtime is fully up by then,
// which a plain __attribute__((constructor)) cannot promise across TUs).
+ (void)load {
    UTTypeImage = [UTType typeWithIdentifier:UDShimImageIdentifier];
    kUTTypeImage = (__bridge CFStringRef)UDShimImageIdentifier;
    kUTTagClassFilenameExtension = (__bridge CFStringRef)@"public.filename-extension";
}

+ (UTType *)typeWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }
    UTType *type = [[UTType alloc] init];
    type->_identifier = [identifier copy];
    return type;
}

+ (UTType *)typeWithFilenameExtension:(NSString *)filenameExtension {
    if (filenameExtension.length == 0) {
        return nil;
    }
    NSString *extension = filenameExtension.lowercaseString;
    NSString *identifier = UDShimExtensionToIdentifier()[extension]
        ?: [@"dyn." stringByAppendingString:extension];
    return [self typeWithIdentifier:identifier];
}

- (NSString *)identifier {
    return _identifier;
}

- (BOOL)conformsToType:(UTType *)type {
    if (type == nil) {
        return NO;
    }
    if ([_identifier isEqualToString:type.identifier]) {
        return YES;
    }
    if ([type.identifier isEqualToString:UDShimImageIdentifier]) {
        return [UDShimImageIdentifiers() containsObject:_identifier];
    }
    return NO;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[UTType class]] &&
           [_identifier isEqualToString:((UTType *)object).identifier];
}

- (NSUInteger)hash {
    return _identifier.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<UTType: %@>", _identifier];
}

@end

#pragma mark - Legacy C API

BOOL UTTypeConformsTo(CFStringRef inUTI, CFStringRef inConformsToUTI) {
    NSString *uti = (__bridge NSString *)inUTI;
    NSString *target = (__bridge NSString *)inConformsToUTI;
    if (uti.length == 0 || target.length == 0) {
        return NO;
    }
    return [[UTType typeWithIdentifier:uti] conformsToType:[UTType typeWithIdentifier:target]];
}

CFStringRef UTTypeCreatePreferredIdentifierForTag(CFStringRef inTagClass,
                                                  CFStringRef inTag,
                                                  CFStringRef inConformingToUTI) {
    (void)inConformingToUTI;
    NSString *tagClass = (__bridge NSString *)inTagClass;
    NSString *tag = (__bridge NSString *)inTag;
    if (![tagClass isEqualToString:@"public.filename-extension"] || tag.length == 0) {
        return NULL;
    }
    NSString *identifier = [UTType typeWithFilenameExtension:tag].identifier;
    // "Create" semantics: the caller owns the result (CFBridgingRelease).
    return (__bridge_retained CFStringRef)identifier;
}

#endif // !__APPLE__
