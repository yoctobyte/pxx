---
track: U
prio: 50
type: decide
blocked-by: []
summary: "`uses gtk` maps to stem gtk-x11-2.0 (GTK 2) while everything else in the tree targets GTK 3 — lib/pcl/gtk3.pas, gtk3widgets.pas and gtk3gl.pas all bind libgtk-3.so.0, and `uses gtk3_c` maps to stem gtk-3. The four test_c_gtk*.pas tests use the legacy alias, so a box must install GTK 2 to make them green. Fork: retarget the alias, rename the tests, or keep GTK 2 deliberately."
status: backlog
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
