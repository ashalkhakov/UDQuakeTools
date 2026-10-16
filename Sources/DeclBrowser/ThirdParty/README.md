# Vendored third-party code

## DMTabBar

`DMTabBar/` — an Xcode-style icon tab bar, by Daniele Margutti, 2012,
<http://www.danielemargutti.com>. **MIT licensed**; the copyright and licence
notices in each file are the author's and are left as they stand. MIT permits
relicensing into a GPL work, so Decl Browser ships it under its GPL-3.0-or-later
while those notices remain.

Taken as RDLKit's RDLDesigner vendors it (github.com/ashalkhakov/RDLKit,
`RDLDesigner/ThirdParty/DMTabBar`), with its changes for GNUstep and dark
appearances, which its README lists: `<AppKit/AppKit.h>` rather than
`<Cocoa/Cocoa.h>`; the bar's gradient from `windowBackgroundColor`; a tab that
shows its icon and nothing else (a GNUstep button without a title reads
"Button").

The bar draws icons, not labels: Decl Browser draws them with `UDTabBadge`
(RDLKit's `RDLTabBadge`).
