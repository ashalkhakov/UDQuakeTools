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
