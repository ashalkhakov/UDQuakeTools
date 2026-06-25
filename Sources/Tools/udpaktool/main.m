/*
 * udpaktool — Command-line tool for inspecting and extracting game archives.
 *
 * Usage:
 *   udpaktool list    <archive> [--format <id>]
 *   udpaktool extract <archive> [<dest-dir>] [--format <id>]
 *
 * --format selects a codec by its format identifier, e.g.:
 *   com.udquake.pak            Quake I   (default for .pak files)
 *   com.udquake.pak2           Quake II
 *   com.udquake.daikatana-pak  Daikatana
 *   com.udquake.pk3            Quake III (default for .pk3 files)
 *   com.udquake.pk4            Doom 3    (default for .pk4 files)
 *
 * When --format is omitted the codec registry auto-detects based on the file
 * extension and signature.  Pass --format explicitly to tag archives with the
 * correct game label when the extension alone is ambiguous.
 */

#import <Foundation/Foundation.h>

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDArchiveCodec.h"
#import "UDCodecRegistry.h"
#import "UDPAKCodec.h"
#import "UDPAK2Codec.h"
#import "UDDaikatanaPAKCodec.h"
#import "UDPK3Codec.h"
#import "UDPK4Codec.h"

/* ------------------------------------------------------------------ */
#pragma mark - Helpers

static void printUsage(void) {
    fprintf(stderr,
        "Usage:\n"
        "  udpaktool list    <archive> [--format <id>]\n"
        "  udpaktool extract <archive> [<dest-dir>] [--format <id>]\n"
        "\n"
        "Format identifiers:\n"
        "  com.udquake.pak             Quake I (default for .pak)\n"
        "  com.udquake.pak2            Quake II\n"
        "  com.udquake.daikatana-pak   Daikatana\n"
        "  com.udquake.pk3             Quake III (default for .pk3)\n"
        "  com.udquake.pk4             Doom 3 (default for .pk4)\n"
    );
}

/** Register every supported codec with the shared registry. */
static void registerCodecs(void) {
    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];
    [reg registerCodec:[[UDPAKCodec alloc] init]];
    [reg registerCodec:[[UDPAK2Codec alloc] init]];
    [reg registerCodec:[[UDDaikatanaPAKCodec alloc] init]];
    [reg registerCodec:[[UDPK3Codec alloc] init]];
    [reg registerCodec:[[UDPK4Codec alloc] init]];
}

/**
 * Open and parse an archive at @p url.
 *
 * If @p formatIdentifier is non-nil, look up the codec by that identifier
 * explicitly (useful for Q2 / Daikatana variants that share the Q1 magic).
 * Otherwise fall back to signature-based auto-detection.
 *
 * Returns nil and prints an error message on failure.
 */
static UDArchive *openArchive(NSURL *url,
                               NSString * _Nullable formatIdentifier) {
    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];
    id<UDArchiveCodec> codec = nil;

    if (formatIdentifier.length > 0) {
        codec = [reg codecForFormatIdentifier:formatIdentifier];
        if (!codec) {
            fprintf(stderr, "error: unknown format identifier '%s'\n",
                    formatIdentifier.UTF8String);
            return nil;
        }
    } else {
        codec = [reg codecForURL:url typeName:nil];
        if (!codec) {
            fprintf(stderr, "error: no codec found for '%s'\n",
                    url.path.UTF8String);
            return nil;
        }
    }

    NSError *err = nil;
    UDArchive *archive = [codec readArchiveFromURL:url error:&err];
    if (!archive) {
        fprintf(stderr, "error: could not read archive: %s\n",
                err.localizedDescription.UTF8String);
        return nil;
    }

    return archive;
}

/* ------------------------------------------------------------------ */
#pragma mark - list

static int cmdList(NSArray *args) {
    /* args: list <file> [--format <id>] */
    if (args.count < 1) {
        fprintf(stderr, "error: 'list' requires an archive path.\n");
        printUsage();
        return 1;
    }

    NSString *archivePath = [args objectAtIndex:0];
    NSString *formatIdentifier = nil;

    for (NSUInteger i = 1; i < args.count; i++) {
        if ([[args objectAtIndex:i] isEqualToString:@"--format"] && i + 1 < args.count) {
            formatIdentifier = [args objectAtIndex:i + 1];
            i++;
        }
    }

    NSURL *url = [NSURL fileURLWithPath:archivePath];
    UDArchive *archive = openArchive(url, formatIdentifier);
    if (!archive) {
        return 1;
    }

    printf("Archive: %s  (%lu entries)\n",
           archive.displayName.UTF8String,
           (unsigned long)archive.entries.count);

    NSString *game = [archive.metadata objectForKey:@"game"];
    if (game.length > 0) {
        printf("Game:    %s\n", game.UTF8String);
    }

    printf("\n");
    printf("%12s  %s\n", "SIZE", "PATH");
    printf("%12s  %s\n", "------------", "----");

    for (UDArchiveEntry *entry in archive.entries) {
        printf("%12llu  %s\n", (unsigned long long)entry.size,
               entry.path.UTF8String);
    }

    return 0;
}

/* ------------------------------------------------------------------ */
#pragma mark - extract

static int cmdExtract(NSArray *args) {
    /* args: extract <file> [<dest-dir>] [--format <id>] */
    if (args.count < 1) {
        fprintf(stderr, "error: 'extract' requires an archive path.\n");
        printUsage();
        return 1;
    }

    NSString *archivePath = [args objectAtIndex:0];
    NSString *destDir = nil;
    NSString *formatIdentifier = nil;

    for (NSUInteger i = 1; i < args.count; i++) {
        if ([[args objectAtIndex:i] isEqualToString:@"--format"] && i + 1 < args.count) {
            formatIdentifier = [args objectAtIndex:i + 1];
            i++;
        } else if (destDir == nil) {
            destDir = [args objectAtIndex:i];
        }
    }

    if (destDir == nil) {
        destDir = [[NSFileManager defaultManager] currentDirectoryPath];
    }

    NSURL *url = [NSURL fileURLWithPath:archivePath];
    UDArchive *archive = openArchive(url, formatIdentifier);
    if (!archive) {
        return 1;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *destURL = [NSURL fileURLWithPath:destDir isDirectory:YES];

    NSError *mkdirError = nil;
    if (![fm createDirectoryAtURL:destURL
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&mkdirError]) {
        fprintf(stderr, "error: could not create destination directory: %s\n",
                mkdirError.localizedDescription.UTF8String);
        return 1;
    }

    printf("Extracting %lu entries to %s ...\n",
           (unsigned long)archive.entries.count,
           destDir.UTF8String);

    int failures = 0;
    for (UDArchiveEntry *entry in archive.entries) {
        /* Build the output path relative to destDir. */
        NSURL *outURL = [destURL URLByAppendingPathComponent:entry.path];

        /* Create intermediate directories for this entry. */
        NSURL *parentURL = [outURL URLByDeletingLastPathComponent];
        NSError *dirError = nil;
        if (![fm createDirectoryAtURL:parentURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&dirError]) {
            fprintf(stderr, "warning: could not create directory for '%s': %s\n",
                    entry.path.UTF8String,
                    dirError.localizedDescription.UTF8String);
            failures++;
            continue;
        }

        /* Read the full entry payload. */
        NSError *readError = nil;
        NSData *data = nil;

        if ([entry.source respondsToSelector:@selector(readAll:)]) {
            data = [entry.source readAll:&readError];
        } else {
            data = [entry.source readRange:NSMakeRange(0, (NSUInteger)entry.source.length)
                                     error:&readError];
        }

        if (!data) {
            fprintf(stderr, "warning: could not read '%s': %s\n",
                    entry.path.UTF8String,
                    readError.localizedDescription.UTF8String);
            failures++;
            continue;
        }

        /* Write the file. */
        NSError *writeError = nil;
        if (![data writeToURL:outURL options:NSDataWritingAtomic error:&writeError]) {
            fprintf(stderr, "warning: could not write '%s': %s\n",
                    entry.path.UTF8String,
                    writeError.localizedDescription.UTF8String);
            failures++;
            continue;
        }

        printf("  %s\n", entry.path.UTF8String);
    }

    if (failures > 0) {
        fprintf(stderr, "\n%d %s failed to extract.\n",
                failures, failures == 1 ? "entry" : "entries");
        return 1;
    }

    printf("\nDone.\n");
    return 0;
}

/* ------------------------------------------------------------------ */
#pragma mark - main

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int exitCode = 0;

    registerCodecs();

    if (argc < 2) {
        printUsage();
        exitCode = 1;
    } else {
        NSString *command = [NSString stringWithUTF8String:argv[1]];

        /* Collect remaining arguments as an NSArray. */
        NSMutableArray *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        if ([command isEqualToString:@"list"]) {
            exitCode = cmdList(args);
        } else if ([command isEqualToString:@"extract"]) {
            exitCode = cmdExtract(args);
        } else {
            fprintf(stderr, "error: unknown command '%s'\n", argv[1]);
            printUsage();
            exitCode = 1;
        }
    }

    [pool drain];
    return exitCode;
}
