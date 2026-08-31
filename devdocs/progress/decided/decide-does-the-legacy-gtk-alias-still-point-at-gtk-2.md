---
track: U
prio: 50
type: decide
blocked-by: []
summary: "RULED 2026-08-31 with its sibling decide-which-gtk-a-bare-gtk-gtk-h-means: the `uses gtk` alias moves to GTK 3. The owner named the deeper defect -- `gtk` and `gtk3` are not parallel names: `uses gtk` and `uses gtk3_c` are C header imports resolved through the alias map, while lib/pcl/gtk3.pas is a PASCAL UNIT, so `uses gtk3` finds a source file and not an alias. Renaming without fixing that just moves the confusion. Three files flip from GTK 2 to GTK 3: test/test_c_gtk.pas, test_c_gtk_call.pas, test_c_gtk_types.pas -- nothing else uses the alias."
status: decided
owner: ""
---

# Does the legacy `gtk` alias still point at GTK 2 on purpose?

## The fork

`compiler/pasparser_proc.inc:2477` has **two** GTK paths:

```pascal
  else if lo = 'gtk3_c' then stem := 'gtk-3'          { GTK 3 }
  else if lo = 'gtk'    then stem := 'gtk-x11-2.0'    { GTK 2 }
```

and `compiler/cpreproc.inc:2018` hardcodes the matching GTK 2 include dirs:

```pascal
  AddCSysIncludeDir('/usr/include/gtk-2.0/');
  AddCSysIncludeDir('/usr/lib/x86_64-linux-gnu/gtk-2.0/include/');
```

Everything else in the tree is **GTK 3**: `lib/pcl/gtk3.pas`, `gtk3widgets.pas`
and `gtk3gl.pas` all bind `libgtk-3.so.0`.

`test/test_c_gtk.pas`, `_call`, `_types` and `_window` say `uses gtk`, so they
take the **GTK 2** branch. That is why a freshly provisioned box fails them until
GTK 2 is installed, and why installing GTK **3** does not help.

## Why this is a decision and not a fix

The alias may be deliberate — GTK 2 compat is a real thing to want, and having
both stems is not obviously wrong. But nothing in the tree says so, and the cost
lands on provisioning: **every new test host must install a GTK 2 the project
otherwise does not use, to satisfy an alias nobody has re-examined.**

The four tests are also **not GTK functionality tests.** They are Track C
C-frontend tests of macro soup, attribute discarding and struct alignment, run
against `test/my_gtk.h` — a hand-written stub that defines its own `guint`,
`gint`, `gpointer` and `G_DECLARE_FINAL_TYPE`. Their assertion is *"my_gtk header
parsed and imported successfully"*. So the GTK **2** dependency is incidental to
what they test.

## Options

1. **Retarget `gtk` → `gtk-3`** and update the two include dirs to `gtk-3.0`.
   One alias, matching the rest of the tree. Breaks any real GTK 2 consumer —
   grep says there is none in-tree.
2. **Point the four tests at `gtk3_c`** (or a neutral name) and leave the `gtk`
   alias alone. Smallest change; removes the provisioning cost without deciding
   the compat question. **Recommended** if the alias is wanted.
3. **Keep both, deliberately**, and record it — then GTK 2 belongs in the
   documented host requirements rather than being discovered per box.

## Also worth deciding while here

Those include dirs hardcode **`x86_64-linux-gnu`**, so they are wrong on aarch64
regardless of GTK version. Separate from the fork above; same two lines.

## Provenance — and a correction

Track T on `seven` reported the quartet green after installing GTK 2 and
concluded *"it needs GTK 2, not the libgtk-3-dev I installed first"*. The
coordinator relayed that to the owner as a provisioning item **without checking
it**. The owner challenged it — *"we have been targeting gtk3 all along"* — and
was right.

The observation was accurate: GTK 2 does make those tests pass. The *conclusion*
was not, because it took a legacy alias for the project's target. **A fix that
turns a job green tells you what the job depends on, not what the project
intends** — and provisioning a host to satisfy a stale alias is the
infrastructure form of a compiler-appeasement workaround: it removes the symptom
and the question at the same time.

## seven can no longer produce evidence about this (2026-08-29)

Track T installed `libgtk2.0-dev` on `seven` this afternoon to clear four red
jobs, and reported it here unprompted. The consequence it flagged is the reason
this section exists: **`seven`'s green on `test_c_gtk*` is no longer evidence
about the alias.** A decision ticket asking "is this alias still live?" now has
one host where the answer is masked by provisioning done while the ticket was
open. That is the constant-pass shape, manufactured rather than inherited — and
it was manufactured by the lane that then disclosed it, which is what kept it
cheap.

The package has deliberately NOT been removed: removing it re-reds four jobs
while the decision is pending, which is a worse default than a masked host.
If the decision goes "retire the alias", removing it on `seven` is part of that
change rather than a side effect.

## What makes the decision cheaper than it looks

Those four tests **never touch GTK at runtime.** They compile against
`test/my_gtk.h`, a local stub in this repo, and assert macro expansion and
struct alignment. The GTK **2** dev package is load-bearing only for the
hardcoded `/usr/include/gtk-2.0/` directories the alias drags in — not for
anything the tests exercise.

So the option "retire the alias" does not cost these tests. That removes the
main reason to keep it and shrinks the decision to: does any real code still
write `uses gtk` expecting GTK 2, given `lib/pcl/gtk3*.pas` binds
`libgtk-3.so.0` and the project has targeted GTK 3 throughout?

-- recorded by frank-coordinator from Track T's disclosure

---

# RULED 2026-08-31 — GTK 3 is the default

Owner: *"i think gtk3 is a sane default in 2026."* Everything in the tree already
targets it — `lib/pcl/gtk3.pas`, `gtk3widgets.pas`, `gtk3gl.pas` all bind
`libgtk-3.so.0`. GTK 2 is the anomaly, not the baseline.

## The change is four literals, not a system

- `compiler/cpreproc.inc:2219` and `:2220` — the two default C include roots,
  hardcoded to `/usr/include/gtk-2.0/` and the arch-specific
  `gtk-2.0/include/`.
- `compiler/pasparser_proc.inc:3105` — header paths built from
  `/usr/include/gtk-2.0/gtk/`.
- `compiler/pasparser_proc.inc:2834-2836` — the alias map: `gtk3_c` -> stem
  `gtk-3` -> `libgtk-3.so.0`; `gtk` -> stem `gtk-x11-2.0` ->
  `libgtk-x11-2.0.so.0`.

## THE NAMING IS THE REAL DEFECT — owner, and it is sharper than "rename it"

*"you said 'uses gtk'.. but, logically, that ought to be 'uses gtk3'."*

**`gtk` and `gtk3` are not parallel names — they live in different namespaces**,
which is why this reads wrong and keeps reading wrong:

- `uses gtk3_c` is a **C header import**, resolved through the alias map.
- `uses gtk` is *also* a C header import, resolved through the same map — to
  **GTK 2**.
- `lib/pcl/gtk3.pas` is a **Pascal unit** — a real file holding `SignalConnect`.
  `uses gtk3` finds that file, not an alias.

So the two spellings a reader would take as "version 2 vs version 3 of the same
thing" are actually "a C library alias" and "a Pascal source file". Renaming
without fixing that just moves the confusion.

**Blast radius, and it is small and visible:** three files use `uses gtk` and
flip from GTK 2 to GTK 3 — `test/test_c_gtk.pas`, `test_c_gtk_call.pas`,
`test_c_gtk_types.pas`. Nothing else in the tree does.

## NilPy's tk is NOT affected — checked, not assumed

`lib/pcl/tk.pas` is a thin **Tcl/Tk 8.6** embed: it links the system Tcl/Tk
sonames directly via `external`, *"needs no -dev headers and no change to the
compiler's C-import registry"*, and the whole GUI is command strings through
`TkEval`. It never touches GTK at any version. The tkinter mimicry question is
orthogonal to this ticket.

## What is installed here, for whoever implements it

plexus has headers for `gtk-2.0` and `gtk-3.0`, and runtime libs for **2, 3 and
4**. There is **no `/usr/include/gtk-4.0`** — GTK 4's library is present, its
headers are not, so GTK 4 is unreachable until `libgtk-4-dev` is installed.

## Version selection is a SEPARATE, SCOPED feature

The owner asked for 2/3/4 selectable, defaulting to 3. The resolver half is
cheap — one variable driving the four literals above. **The widgetset half is
not**, and must not be promised with it: `gtk3widgets.pas` and friends bind GTK 3
specifically, and GTK 4 reshaped the container, event and drawing models. So
selecting a version buys the right headers and the right soname; it does **not**
make the PCL widget layer work on 2 or 4. Filed as
[[feature-a-gtk-version-selection-at-the-header-and-soname-layer]].

*Ruled 2026-08-31 by the owner; mechanism and tk backend verified by frank-user.*
