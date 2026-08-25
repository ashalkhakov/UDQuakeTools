/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Crash diagnostics for the GNUstep/Linux builds. See UDCrashReporter.h.
 */

#import "UDCrashReporter.h"

#if !defined(__APPLE__)

#include <execinfo.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define UD_CRASH_MAX_FRAMES 64

// write() the whole buffer to stderr; async-signal-safe (unlike fprintf).
static void UDCrashWrite(const char *text) {
    size_t remaining = strlen(text);
    while (remaining > 0) {
        ssize_t written = write(STDERR_FILENO, text, remaining);
        if (written <= 0) {
            return;
        }
        text += written;
        remaining -= (size_t)written;
    }
}

static void UDCrashWriteUnsigned(unsigned long long value, int base) {
    char digits[] = "0123456789abcdef";
    char buffer[24];
    char *cursor = buffer + sizeof(buffer);
    *--cursor = '\0';
    do {
        *--cursor = digits[value % (unsigned)base];
        value /= (unsigned)base;
    } while (value != 0 && cursor > buffer);
    UDCrashWrite(cursor);
}

static void UDCrashSignalHandler(int signalNumber, siginfo_t *info, void *context) {
    (void)context;

    UDCrashWrite("\n==== UDCrashReporter: caught signal ");
    UDCrashWrite(strsignal(signalNumber) ? strsignal(signalNumber) : "?");
    UDCrashWrite(" (");
    UDCrashWriteUnsigned((unsigned long long)signalNumber, 10);
    UDCrashWrite(")");
    if (signalNumber == SIGSEGV || signalNumber == SIGBUS || signalNumber == SIGILL || signalNumber == SIGFPE) {
        UDCrashWrite(", fault address 0x");
        UDCrashWriteUnsigned((unsigned long long)(uintptr_t)info->si_addr, 16);
    }
    UDCrashWrite(" ====\n");

    // backtrace() is not formally async-signal-safe, but for a crash-and-die
    // diagnostic that trade-off is standard practice (it is what every
    // in-process crash reporter does).
    void *frames[UD_CRASH_MAX_FRAMES];
    int frameCount = backtrace(frames, UD_CRASH_MAX_FRAMES);
    backtrace_symbols_fd(frames, frameCount, STDERR_FILENO);
    UDCrashWrite("==== end of backtrace ====\n");

    // Restore the default action and re-raise, so the exit status / core
    // dump behave exactly as without the handler.
    signal(signalNumber, SIG_DFL);
    raise(signalNumber);
}

static void UDCrashUncaughtExceptionHandler(NSException *exception) {
    // Not a signal context — Foundation calls are fine here.
    fprintf(stderr,
            "\n==== UDCrashReporter: uncaught exception %s ====\nreason: %s\n",
            exception.name.UTF8String ?: "?",
            exception.reason.UTF8String ?: "(none)");
    for (NSString *frame in exception.callStackSymbols) {
        fprintf(stderr, "%s\n", frame.UTF8String);
    }
    fprintf(stderr, "==== end of exception backtrace ====\n");
    fflush(stderr);
    abort(); // funnels into the SIGABRT handler above for the native trace
}

void UDInstallCrashDiagnostics(void) {
    // Alternate stack: lets the SIGSEGV handler run even when the crash IS a
    // stack overflow.
    static char alternateStack[SIGSTKSZ];
    stack_t stackInfo;
    memset(&stackInfo, 0, sizeof(stackInfo));
    stackInfo.ss_sp = alternateStack;
    stackInfo.ss_size = sizeof(alternateStack);
    sigaltstack(&stackInfo, NULL);

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = UDCrashSignalHandler;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);

    const int signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP };
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
        sigaction(signals[i], &action, NULL);
    }

    NSSetUncaughtExceptionHandler(&UDCrashUncaughtExceptionHandler);
}

#else /* __APPLE__ */

void UDInstallCrashDiagnostics(void) {
    // macOS: the system crash reporter already produces full reports.
}

#endif
