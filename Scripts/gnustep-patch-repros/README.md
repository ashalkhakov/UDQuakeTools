# Repro samples for the GNUstep patches (+ FreeCoreData bug description)

Two self-contained samples, one per gnustep-gui patch. Each was verified in
the Linux test environment against the **pristine** gnustep-gui from your
AppImage and against the **patched** build; the observed outputs below are
verbatim.

Build both the same way (adjust `PREFIX` to your GNUstep install, e.g.
`/opt/gnustep-prefix`):

```sh
PREFIX=/opt/gnustep-prefix
clang <sample>.m -o <sample> \
  -fobjc-runtime=gnustep-2.0 -fexceptions -fblocks \
  -I$PREFIX/Local/Library/Headers \
  -L$PREFIX/lib -L$PREFIX/Local/Library/Libraries \
  -Wl,-rpath-link,$PREFIX/lib \
  -Wl,--no-as-needed -lgnustep-gui -lgnustep-base -lobjc
```

---

## 1. `contentset-binding-test.m`
### patch: `gnustep-gui-contentset-binding.patch`

**The bug.** Cocoa's NSArrayController exposes three content bindings:
`contentArray`, `contentSet`, `contentObject`. gnustep-gui only exposes
`contentArray`. Xcode emits **contentSet** bindings whenever a table is
driven by a to-many Core Data relationship (an `NSSet`) — Decl Browser's PDA
editor does exactly that:

```xml
<binding destination="Yof-46-Pvq" name="contentSet" keyPath="selection.emails"/>
```

On GNUstep the nib loader then logs
`No binding exposed on <NSArrayController: 0x...> for contentSet`
and the binding is silently dropped: the controller's content stays empty and
every such table renders zero rows, even though the relationship has objects.
This is one of the reasons the PDA editor showed no data.

The sample does programmatically what the nib loader does: it binds
`contentSet` of an array controller to a keyPath that holds an `NSSet` of
three objects, then counts `arrangedObjects`. No display needed.

**Observed, unpatched gui:**
```
No binding exposed on <NSArrayController: 0x55f38fe84a78> for contentSet
arrangedObjects count = 0 (expected 3)
FAIL: contentSet binding ignored
```

**Observed, patched gui:**
```
arrangedObjects count = 3 (expected 3)
PASS
```

**The fix.** Expose `NSContentSetBinding` (`@"contentSet"`) and route it
through the same `GSKeyValueBinding` machinery as `contentArray` (the
controller's `-arrangeObjects:` already handles set content, since
`-[NSSet sortedArrayUsingDescriptors:]` exists). Also adds the missing
`NSContentSetBinding` constant to `NSKeyValueBinding.h` / `externs.m`.

---

## 2. `viewcontroller-uaf-test.m` (+ `ViewControllerUAF.xib`)
### patch: `gnustep-gui-nsviewcontroller-toplevelobjects.patch`

**The bug.** `-[NSViewController loadView]` in gnustep-gui is:

```objc
[nib instantiateNibWithOwner: self topLevelObjects: &_topLevelObjects];
...
[self viewDidLoad];          // may raise
...
RETAIN(_topLevelObjects);    // only reached if viewDidLoad returned normally
```

`NSNib` hands back an **autoreleased** array. If anything raises inside
`-viewDidLoad` (an unrecognized selector, a KVC failure while wiring
bindings, ...), the exception unwinds `loadView` *before* the `RETAIN`. The
next pool drain frees the array while the `_topLevelObjects` ivar still
points at it. When the view controller is later deallocated, its `-dealloc`
runs

```objc
[_topLevelObjects makeObjectsPerformSelector: @selector(release)];
```

on the freed array — a use-after-free that surfaces as heap corruption or a
segfault at some *later, unrelated* pool drain, which makes it miserable to
trace back. This is exactly how a decl-editor exception turned into Decl
Browser's mysterious pool-drain crash: the app-level exception was caught and
logged by an NSTimer, but the view controller it had unwound through was left
booby-trapped.

The sample is an `NSViewController` subclass whose `viewDidLoad` raises. It
loads a trivial xib (a bare `NSView`, needs `ViewControllerUAF.xib` next to
the binary), catches the exception, drains the pool, then releases the
controller. Needs a display connection for AppKit startup (Xvfb is fine); no
window is created.

**Observed, unpatched gui:**
```
caught expected exception: simulated failure inside -viewDidLoad
releasing the view controller...
Segmentation fault                       (exit 139)
```
and with `NSZombieEnabled=YES` the corpse is named instead of crashing:
```
*** -[GSMutableArray makeObjectsPerformSelector:]: message sent to
    deallocated instance 0x557e86f085c8
```

**Observed, patched gui:**
```
caught expected exception: simulated failure inside -viewDidLoad
releasing the view controller...
PASS: survived view controller dealloc   (exit 0)
```

**The fix.** Move the `RETAIN(_topLevelObjects)` to immediately after the
successful `instantiateNibWithOwner:` call, so the ivar owns the array before
`viewDidLoad` gets a chance to raise. No behavior change on the normal path.

---

## 3. Why FreeCoreData needs `freecoredata-xcdatamodel-loader.patch`

Two related gaps, both hit by Decl Browser on Linux:

**(a) FreeCoreData could not read the app's data model at all.**
`-[NSManagedObjectModel initWithContentsOfURL:]` only understood keyed
archives produced by FreeCoreData's *own* encoder. Apple's compiled `.mom`
(momc output) is a different, incompatible archive format — and on Linux
there is no `momc` anyway, so the only thing an Xcode project can ship is the
**raw `.xcdatamodeld` bundle**, whose `contents` file is plain XML. FreeCoreData
had no loader for that XML, so Decl Browser's `DeclModel.xcdatamodeld` loaded
as a model with **0 entities**: the persistent store coordinator had nothing
to map, every fetch came back empty, and the whole PDA editor sat on top of
no data. The patch adds an `NSXMLParser`-based loader that builds the
`NSEntityDescription` / `NSAttributeDescription` / `NSRelationshipDescription`
graph straight from the XML — entities (`representedClassName`, `isAbstract`,
`parentEntity` inheritance via `setSubentities:`), attributes (all the Xcode
type names, `optional`, `transient`, `defaultValueString`), and relationships
(destination, inverse, `toMany` → unbounded max count, deletion rules) — and
routes `initWithContentsOfURL:` for `.xcdatamodeld` / `.xcdatamodel` paths
through it (honoring `.xccurrentversion` to pick the current model version).

**(b) Entities built programmatically never got their `@dynamic` accessors.**
FreeCoreData generates the getter/setter (and to-many mutator) IMPs for
`@dynamic` NSManagedObject properties with `class_addMethod` — but only from
inside `-[NSEntityDescription initWithCoder:]`, i.e. only for entities
*decoded from an archive*. Entities built any other way (the XML loader
above, or plain programmatic model construction, which Apple supports) never
get accessors installed on their represented classes. The result: KVC access
(`valueForKey:`) works, which masks the gap, but any plain property send —
`pda.sourceText`, `decl.name` — raises `doesNotRecognizeSelector`. In Decl
Browser, that exception fired during editor loading... and then detonated
gnustep-gui bug #2 above, producing the delayed pool-drain crash. The patch
factors the accessor installation out of `initWithCoder:` into
`_fcd_installDynamicAccessors` and calls it for XML-loaded entities once the
entity graph (properties + inheritance) is complete.

The two fixes are one patch because (a) without (b) produces models whose
objects throw on every property access — you need both for a model loaded
from `.xcdatamodel` XML to actually behave like Core Data.
