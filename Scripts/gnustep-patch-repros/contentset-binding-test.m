/*
 * Repro for: NSArrayController does not expose the Cocoa "contentSet"
 * binding (gnustep-gui-contentset-binding.patch).
 *
 * Cocoa's NSArrayController exposes three content bindings: contentArray,
 * contentSet and contentObject. Xcode emits contentSet bindings whenever a
 * table is driven by a to-many Core Data relationship (an NSSet), e.g.:
 *
 *   <binding destination="objectController" name="contentSet"
 *            keyPath="selection.emails"/>
 *
 * gnustep-gui only exposes contentArray, so loading such a xib logs
 *
 *   No binding exposed on <NSArrayController: 0x...> for contentSet
 *
 * and the controller's content silently stays empty: every table bound to a
 * to-many relationship renders zero rows even though the relationship has
 * objects in it.
 *
 * Build (adjust paths to your GNUstep install):
 *   clang contentset-binding-test.m -o contentset-binding-test \
 *     -fobjc-runtime=gnustep-2.0 -fexceptions -fblocks \
 *     -I$PREFIX/Local/Library/Headers \
 *     -L$PREFIX/lib -L$PREFIX/Local/Library/Libraries \
 *     -Wl,--no-as-needed -lgnustep-gui -lgnustep-base -lobjc
 *
 * Run:
 *   Unpatched gui: logs "No binding exposed ... for contentSet",
 *                  arrangedObjects count = 0  -> FAIL
 *   Patched gui:   arrangedObjects count = 3  -> PASS
 */
#import <AppKit/AppKit.h>

@interface Owner : NSObject
{
  NSMutableSet *things;
}
- (NSMutableSet *) things;
- (void) setThings: (NSMutableSet *)set;
@end

@implementation Owner
- (NSMutableSet *) things { return things; }
- (void) setThings: (NSMutableSet *)set
{
  [set retain];
  [things release];
  things = set;
}
- (void) dealloc { [things release]; [super dealloc]; }
@end

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];

  Owner *owner = [Owner new];
  [owner setThings: [NSMutableSet setWithObjects:
    @"first", @"second", @"third", nil]];

  NSArrayController *ac = [[NSArrayController alloc] initWithContent: nil];

  /* Exactly what nib loading does for
   *   <binding name="contentSet" keyPath="things" destination=Owner>
   */
  [ac bind: @"contentSet" toObject: owner withKeyPath: @"things" options: nil];

  NSUInteger count = [[ac arrangedObjects] count];
  NSLog(@"arrangedObjects count = %lu (expected 3)", (unsigned long)count);
  NSLog(@"%@", count == 3 ? @"PASS" : @"FAIL: contentSet binding ignored");

  [pool drain];
  return count == 3 ? 0 : 1;
}
