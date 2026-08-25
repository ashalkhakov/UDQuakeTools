/* Repro for the gnustep-gui NSTableView selectionIndexes-push patch.
 *
 * Setup mirrors exactly what nib/xib loading does for a table bound to an
 * NSArrayController (NSNibBindingConnector -establishConnection calls
 * [_src bind: ...] with the table view / table column as source):
 *
 *   [column    bind: NSValueBinding            -> arrangedObjects.name]
 *   [tableView bind: NSContentBinding          -> arrangedObjects]
 *   [tableView bind: NSSelectionIndexesBinding -> selectionIndexes]
 *
 * Expected (Apple semantics): the selectionIndexes binding is
 * bidirectional - when the user CLICKS a row, the controller's
 * selectionIndexes must follow.
 *
 * Observed on pristine gnustep-gui master: the click selects the row in
 * the table, but the controller's selection never changes.
 * -[NSTableView _postSelectionDidChangeNotification] only looks for a
 * selectionIndexes binding registered with the *observed controller* as
 * the binding's SOURCE object - but GSKeyValueBinding's table keys
 * bindings by the object that called -bind:, which for a nib-established
 * binding is the TABLE VIEW. So the reverse push never fires, and every
 * controller-selection-driven action (e.g. NSSegmentedControl "-" removing
 * controller.selectedObjects) operates on a stale/empty selection.
 *
 * Run it, then CLICK the second row ("beta"). Or let the built-in
 * self-test click for you: pass a display with xdotool/XTEST available and
 * click row 1 within 10 seconds. The app prints PASS/FAIL on Ctrl-C or
 * automatically 3 seconds after the first selection change.
 *
 *   pristine: table selectedRow=1  controller selectionIndexes={}  -> FAIL
 *   patched:  table selectedRow=1  controller selectionIndexes={1} -> PASS
 */
#import <AppKit/AppKit.h>

@interface Delegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTableView *tableView;
@property (strong) NSArrayController *controller;
@end

@implementation Delegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
  NSWindow *w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(100, 100, 300, 200)
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [w setTitle:@"selection-push repro"];
  self.window = w;

  self.controller = [[NSArrayController alloc] init];
  [self.controller addObject:
      [NSMutableDictionary dictionaryWithObject:@"alpha" forKey:@"name"]];
  [self.controller addObject:
      [NSMutableDictionary dictionaryWithObject:@"beta" forKey:@"name"]];
  [self.controller addObject:
      [NSMutableDictionary dictionaryWithObject:@"gamma" forKey:@"name"]];
  [self.controller setSelectionIndexes:[NSIndexSet indexSet]];

  NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  [col setWidth:280];
  [[col headerCell] setStringValue:@"Name"];
  [tv addTableColumn:col];
  self.tableView = tv;

  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:
      [[w contentView] bounds]];
  [sv setDocumentView:tv];
  [[w contentView] addSubview:sv];

  /* Exactly the three bindings a xib with a bound table establishes,
     with the same source objects nib loading uses. */
  [col bind:NSValueBinding
        toObject:self.controller
     withKeyPath:@"arrangedObjects.name"
         options:nil];
  [tv bind:NSContentBinding
        toObject:self.controller
     withKeyPath:@"arrangedObjects"
         options:nil];
  [tv bind:NSSelectionIndexesBinding
        toObject:self.controller
     withKeyPath:@"selectionIndexes"
         options:nil];

  [w makeKeyAndOrderFront:nil];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(tableSelectionChanged:)
             name:NSTableViewSelectionDidChangeNotification
           object:tv];

  NSLog(@"READY - click the second row (\"beta\") in the window");
}

- (void)tableSelectionChanged:(NSNotification *)note {
  /* Give the binding machinery the rest of the event, then compare. */
  [self performSelector:@selector(report) withObject:nil afterDelay:0.5];
}

- (void)report {
  NSInteger row = [self.tableView selectedRow];
  NSIndexSet *acSel = [self.controller selectionIndexes];
  NSArray *selObjs = [self.controller selectedObjects];
  NSLog(@"table selectedRow=%ld", (long)row);
  NSLog(@"controller selectionIndexes=%@ selectedObjects=%@",
        acSel, [selObjs valueForKey:@"name"]);
  BOOL pass = (row >= 0)
      && ([acSel count] == 1)
      && ((NSInteger)[acSel firstIndex] == row);
  NSLog(@"RESULT: %@", pass ? @"PASS" : @"FAIL");
  [NSApp terminate:nil];
}

@end

int main(void) {
  NSApplication *app = [NSApplication sharedApplication];
  Delegate *delegate = [[Delegate alloc] init];
  [app setDelegate:delegate];
  [app run];
  return 0;
}
