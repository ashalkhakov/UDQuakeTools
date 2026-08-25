# Repro samples for the GNUstep patches

Self-contained samples, one per gnustep-gui patch. Each was verified in the
Linux test environment against the **pristine** gnustep-gui master and
against the **patched** build; observed outputs are verbatim.

Build all of them the same way (adjust `PREFIX` to your GNUstep install,
e.g. `/opt/gnustep-prefix`):

```sh
PREFIX=/opt/gnustep-prefix
clang <sample>.m -o <sample> \
  -fobjc-runtime=gnustep-2.0 -fexceptions -fblocks \
  -I$PREFIX/Local/Library/Headers \
  -L$PREFIX/lib -L$PREFIX/Local/Library/Libraries \
  -Wl,-rpath-link,$PREFIX/lib \
  -Wl,--no-as-needed -lgnustep-gui -lgnustep-base -lobjc
```

## tableview-selection-push-test.m — PENDING
Patch: `Scripts/gnustep-gui-tableview-selection-push.patch`

A window with an `NSTableView` bound to an `NSArrayController` exactly the
way nib/xib loading does it (the table view / table column are the binding
*source* objects):

- column `value` → `arrangedObjects.name`
- table `content` → `arrangedObjects`
- table `selectionIndexes` → `selectionIndexes`

Run it and **click the second row ("beta")**. The app compares
`tableView.selectedRow` against `controller.selectionIndexes` half a second
later, prints PASS/FAIL, and exits.

Apple semantics: the `selectionIndexes` binding is bidirectional — a user
click must update the controller's selection. On pristine master the
reverse push never happens: `-_postSelectionDidChangeNotification` looks up
the `selectionIndexes` binding with the observed *controller* as the
binding's source object, but `GSKeyValueBinding` keys bindings by the
object that called `-bind:` — the *table view*. The controller's selection
therefore stays stale, and anything driven by
`controller.selectedObjects` (remove buttons, detail panes) acts on the
wrong objects. In Decl Browser this made the PDA editor's "−" button a
no-op (and, before the selection-init fix, an infinite loop).

Pristine gnustep-gui master (62b646a), clicking row "beta":

```
tvtest[6647:6647] table selectedRow=1
tvtest[6647:6647] controller selectionIndexes=<NSIndexSet: 0x...>(no indexes) selectedObjects=()
tvtest[6647:6647] RESULT: FAIL
```

Patched (same click):

```
tvtest[9209:9209] table selectedRow=1
tvtest[9209:9209] controller selectionIndexes=<NSIndexSet: 0x...>[number of indexes: 1 (in 1 ranges), indexes: 1] selectedObjects=(beta)
tvtest[9209:9209] RESULT: PASS
```

## contentset-binding-test.m — UPSTREAMED
`NSArrayController` did not expose/accept the `contentSet` binding, so a
controller bound to a to-many relationship set showed nothing. Merged
upstream; sample kept for regression testing.

## viewcontroller-uaf-test.m — UPSTREAMED
`NSViewController` released its nib top-level objects before use
(use-after-free with ARC nib owners; see also `ViewControllerUAF.xib`).
Merged upstream; sample kept for regression testing.
