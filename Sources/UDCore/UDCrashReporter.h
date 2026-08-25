#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Process-wide crash diagnostics for the GNUstep/Linux builds.
 *
 * On Linux a segfault normally kills the app with NO output at all — no
 * crash dump, nothing on stderr — which makes field crashes undebuggable.
 * This installs:
 *
 *   - signal handlers for SIGSEGV / SIGBUS / SIGILL / SIGFPE / SIGABRT /
 *     SIGTRAP that print the signal, fault address, and a native backtrace
 *     (via backtrace_symbols_fd) to stderr, then re-raise the signal so the
 *     default action (core dump, exit code) still happens;
 *   - an uncaught Objective-C exception handler that prints the exception
 *     name, reason, and +callStackSymbols before aborting;
 *   - an alternate signal stack, so even stack-overflow SIGSEGVs report.
 *
 * Frames resolve to "module(symbol+0x…) [address]"; for stripped binaries
 * the module+address pair still feeds addr2line. Build the app with
 * -rdynamic (see the DeclBrowser GNUmakefile) so the executable's own
 * symbols resolve too.
 *
 * On macOS this is a no-op — the system crash reporter is better.
 *
 * Call once, first thing in main(), before NSApplicationMain.
 */
FOUNDATION_EXPORT void UDInstallCrashDiagnostics(void);

NS_ASSUME_NONNULL_END
