/*
 * Repro for: use-after-free of NSViewController's _topLevelObjects when
 * -viewDidLoad raises (gnustep-gui-nsviewcontroller-toplevelobjects.patch).
 *
 * In gnustep-gui, -[NSViewController loadView] does:
 *
 *   [nib instantiateNibWithOwner: self topLevelObjects: &_topLevelObjects];
 *   ...
 *   [self viewDidLoad];      // may raise
 *   ...
 *   RETAIN(_topLevelObjects);   // <-- only reached if viewDidLoad returns
 *
 * NSNib hands back an AUTORELEASED array. If -viewDidLoad raises (an
 * unresolved selector, a KVC error, anything), the exception unwinds
 * loadView before the RETAIN, the autorelease pool drains and frees the
 * array — but the _topLevelObjects ivar still points at it. When the view
 * controller is later deallocated, its -dealloc runs
 *
 *   [_topLevelObjects makeObjectsPerformSelector: @selector(release)];
 *
 * on the freed array: heap corruption / segfault at some later pool drain.
 * This is exactly how a decl-editor exception turned into the mysterious
 * pool-drain crash in Decl Browser.
 *
 * Build (needs ViewControllerUAF.xib next to the binary):
 *   clang viewcontroller-uaf-test.m -o viewcontroller-uaf-test \
 *     -fobjc-runtime=gnustep-2.0 -fexceptions -fblocks \
 *     -I$PREFIX/Local/Library/Headers \
 *     -L$PREFIX/lib -L$PREFIX/Local/Library/Libraries \
 *     -Wl,--no-as-needed -lgnustep-gui -lgnustep-base -lobjc
 *
 * Run (headless: DISPLAY can point at Xvfb; the nib has only a bare NSView):
 *   Unpatched gui, NSZombieEnabled=YES:
 *     *** -[GSMutableArray makeObjectsPerformSelector:]: message sent to
 *         deallocated instance 0x...          -> the UAF, made visible
 *   Unpatched gui, zombies off: crash or silent corruption at dealloc.
 *   Patched gui: prints PASS and exits 0 either way.
 */
#import <AppKit/AppKit.h>

@interface CrashVC : NSViewController
@end

@implementation CrashVC
- (void) viewDidLoad
{
  [super viewDidLoad];
  /* Any exception here reproduces the bug. In the real app this was a
   * doesNotRecognizeSelector raised while wiring Cocoa bindings. */
  [NSException raise: NSInternalInconsistencyException
              format: @"simulated failure inside -viewDidLoad"];
}
@end

int main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];

  /* AppKit wants an application object before nib loading. */
  [NSApplication sharedApplication];

  /* Find the xib next to the executable. */
  NSString *exePath = [NSString stringWithUTF8String: argv[0]];
  if (![exePath isAbsolutePath])
    {
      exePath = [[[NSFileManager defaultManager] currentDirectoryPath]
          stringByAppendingPathComponent: exePath];
    }
  NSBundle *bundle = [NSBundle bundleWithPath:
      [[exePath stringByStandardizingPath] stringByDeletingLastPathComponent]];

  CrashVC *vc = [[CrashVC alloc] initWithNibName: @"ViewControllerUAF"
                                          bundle: bundle];

  @try
    {
      (void)[vc view];   // triggers loadView -> nib load -> viewDidLoad raise
    }
  @catch (NSException *e)
    {
      NSLog(@"caught expected exception: %@", [e reason]);
    }

  /* Drain the pool: with the unpatched gui this frees the autoreleased
   * top-level-objects array while the ivar still points at it. */
  [pool drain];
  pool = [NSAutoreleasePool new];

  NSLog(@"releasing the view controller...");
  [vc release];   // dealloc broadcasts release over _topLevelObjects

  [pool drain];
  NSLog(@"PASS: survived view controller dealloc");
  return 0;
}
