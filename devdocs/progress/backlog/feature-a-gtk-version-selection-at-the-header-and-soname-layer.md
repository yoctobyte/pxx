---
track: A
prio: 40
type: feature
status: open
found: 2026-08-31
found-by: frank-user, at the owner's request
owner: ""
blocked-by: []
summary: "The owner asked for GTK 2/3/4 user-selectable, defaulting to 3. SPLIT DELIBERATELY, because the two halves have wildly different costs. The RESOLVER half is cheap: one version variable driving four hardcoded literals -- the two default include roots (cpreproc.inc:2219-2220), the header path stem (pasparser_proc.inc:3105) and the alias map (pasparser_proc.inc:2834-2836). The WIDGETSET half is a PORT and is NOT in scope: gtk3widgets.pas, gtk3.pas and gtk3gl.pas bind GTK 3 specifically, and GTK 4 reshaped the container, event and drawing models. So this feature buys the right headers and the right soname -- it does NOT make the PCL widget layer work on 2 or 4, and saying it does would promise work nobody has done. GTK 4 additionally needs libgtk-4-dev: plexus has the GTK 4 runtime but no /usr/include/gtk-4.0."
---

# GTK version selection at the header and soname layer

Follows `decided/decide-which-gtk-a-bare-gtk-gtk-h-means` (GTK 3 is now the
default). This is the *selectable* half the owner asked for: *"if we (easily)
_can_, gtk 2/3/4 should actually be user selectable, defaulting to 3.. but maybe
this creates a library hell."*

**It does not create library hell at this layer**, which is why it is worth
doing. It would at the widgetset layer, which is why that is excluded.

## In scope

A single version selector — flag or directive — driving the four sites the
parent ticket enumerates. Default 3.

## Explicitly OUT of scope, and say so in the docs

The PCL widget layer stays GTK 3 only. Selecting 2 or 4 gives a C program the
right headers and the right `DT_NEEDED`; it does not port `gtk3widgets.pas`.

## Naming, from the parent ruling

`gtk` and `gtk3` are not parallel names today — the first two are alias-map
entries, `gtk3` is a Pascal unit file (`lib/pcl/gtk3.pas`). Whoever builds the
selector should settle that, or the version flag inherits the same confusion.

## Blocked in practice for GTK 4

No `/usr/include/gtk-4.0` on plexus. `libgtk-4-dev` is needed before the 4 arm
is testable at all — until then, build and test the 2 and 3 arms and refuse 4
with a diagnostic that says why.
