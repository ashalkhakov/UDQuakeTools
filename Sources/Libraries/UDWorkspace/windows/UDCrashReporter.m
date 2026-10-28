/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Crash diagnostics for the GNUstep/Windows builds. See UDCrashReporter.h.
 */

#import "../UDCrashReporter.h"

#include <windows.h>
#include <stdio.h>

#define UD_CRASH_MAX_FRAMES 62

/* A frame as module+offset ("Quarry.exe+0x1a2b"), which addr2line takes
   with the module's own load address. */
static void UDCrashPrintFrame(void *address) {
    HMODULE module = NULL;
    char path[MAX_PATH] = "?";
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCSTR)address, &module) && module) {
        GetModuleFileNameA(module, path, sizeof path);
    }
    const char *name = strrchr(path, '\\') ? strrchr(path, '\\') + 1 : path;
    fprintf(stderr, "%s+0x%llx [%p]\n", name,
            (unsigned long long)((uintptr_t)address - (uintptr_t)module), address);
}

static LONG WINAPI UDCrashExceptionFilter(EXCEPTION_POINTERS *exception) {
    EXCEPTION_RECORD *record = exception->ExceptionRecord;
    fprintf(stderr, "\n==== UDCrashReporter: unhandled exception 0x%08lx at %p ====\n",
            (unsigned long)record->ExceptionCode, record->ExceptionAddress);
    void *frames[UD_CRASH_MAX_FRAMES];
    USHORT count = CaptureStackBackTrace(0, UD_CRASH_MAX_FRAMES, frames, NULL);
    for (USHORT i = 0; i < count; i++) UDCrashPrintFrame(frames[i]);
    fprintf(stderr, "==== end of backtrace ====\n");
    fflush(stderr);
    // Windows' own handling goes on: the process ends with the exception's code
    return EXCEPTION_CONTINUE_SEARCH;
}

static void UDCrashUncaughtExceptionHandler(NSException *exception) {
    fprintf(stderr,
            "\n==== UDCrashReporter: uncaught exception %s ====\nreason: %s\n",
            exception.name.UTF8String ?: "?",
            exception.reason.UTF8String ?: "(none)");
    for (NSString *frame in exception.callStackSymbols) {
        fprintf(stderr, "%s\n", frame.UTF8String);
    }
    fprintf(stderr, "==== end of exception backtrace ====\n");
    fflush(stderr);
    abort();
}

void UDInstallCrashDiagnostics(void) {
    SetUnhandledExceptionFilter(UDCrashExceptionFilter);
    NSSetUncaughtExceptionHandler(&UDCrashUncaughtExceptionHandler);
}
