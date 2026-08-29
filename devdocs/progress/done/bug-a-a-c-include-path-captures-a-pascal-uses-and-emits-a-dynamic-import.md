---
track: A
prio: 65
type: bug
blocked-by: []
summary: "`-Ilib/crtl/include` makes `uses strings` bind to the C header strings.h instead of lib/rtl/strings.pas: StrPas becomes `undefined variable`, and a call the header DOES declare compiles into a dynamic import of a nonexistent libstrings.so, so the binary dies at load. Three RTL units collide by basename with a shipped crtl header — math, netdb, strings — and `uses math` + that flag loses Floor the same way. Five-line pure-Pascal repro."
status: done
owner: pxx-a5
---

# A C include path captures a Pascal `uses`, and the result is a binary that cannot load

- **Type:** bug (unit resolution / flag handling) — **Track A**. Possibly C's
  (`-I` is cfront's flag) but the damage is to Pascal unit binding, so filing
  in A; re-lane if the fix lands in the C side.
- **Filed:** 2026-08-29 by the wasm lane while measuring
  [[feature-demo-songformatter-pxx-target]], whose standing instruction is to
  pass this exact flag.

## Repro

```pascal
program S;
uses strings;
begin
  writeln(StrPas(PChar('hi')));
end.
```

```
$ pascal26 s.pas /tmp/s                             # ok, prints hi
$ pascal26 -Ilib/crtl/include s.pas /tmp/s
pascal26:4: error: undefined variable (StrPas)
```

`uses math` loses `Floor` to `math.h` in exactly the same way. Measured against
pin v392 (`60b060bb54a8`).

## The severe half: it does not always fail loudly

`undefined variable` is what you get when the Pascal unit's symbol is *missing*
from the C header. When the header does declare something, the reference binds
and the build succeeds:

```c
/* probe/strings.h */
static int pxx_probe_marker(void) { return 4242; }
```
```pascal
program Probe;
uses strings;
begin
  writeln(pxx_probe_marker());
end.
```
```
$ pascal26 -Iprobe probe.pas /tmp/probe
ok: /tmp/probe  [ ... ]
$ /tmp/probe
/tmp/probe: error while loading shared libraries: libstrings.so: cannot open
shared object file: No such file or directory
```

So `uses <name>` resolved through the include path is treated as an **external
shared library**, and the compiler emits a dynamic import of `lib<name>.so`. The
program links, reports `ok:`, and cannot start. A Pascal program that says `uses
strings` has no business acquiring a DT_NEEDED on `libstrings.so`, and nothing
in the build says it did.

## Scope: three units collide with headers we ship

```
math      lib/rtl/math.pas      vs  lib/crtl/include/math.h
netdb     lib/rtl/netdb.pas     vs  lib/crtl/include/netdb.h
strings   lib/rtl/strings.pas   vs  lib/crtl/include/strings.h
```

`math` is the one that matters — it is in ordinary use, and the failure is a
missing `Floor`/`Ceil`/`Power` rather than anything that names an include path.

## What is NOT the cause (measured, so nobody re-walks it)

The obvious theory is "`-I` adds a search root and a same-named file wins".
Two controls kill the simple form of it:

* `-I` pointing at an **empty** directory: fine.
* `-I` pointing at a directory containing an empty file named `strings.h`: also
  fine.

It takes a header with *content* to capture the name, which is what identifies
this as the C-unit compilation path claiming the `uses` rather than a plain
path-precedence bug. Worth knowing before reading the resolver: the shape that
looks like a search-order fix is not one.

## Why it surfaced now, and the cost it has already had

[[feature-demo-songformatter-pxx-target]] carries the instruction *"any
measurement of this app must pass `-Ilib/crtl/include …` or it is measuring
glibc's headers"*, written 2026-07-31 to work around
[[bug-crtl-headers-lost-when-cwd-is-not-the-repo-root]]. **That bug is now
done**, so the flag is obsolete — and following the instruction today produces
`undefined variable (StrPas)` from inside `lib/pcl/tk.pas`, which reads as a
broken Tk façade rather than as a flag that should no longer be passed. Three of
the app's five modules "fail" that way and compile fine without it. The
instruction has been corrected in that ticket.

That is the second-order damage worth stating plainly: **a workaround that
outlives the bug it worked around does not go quiet, it starts lying.** The
measurement it protects is the one it corrupts.

## Fix sketch

A `uses` clause names a PASCAL unit. The include path is for `#include`, and the
two namespaces should not share a resolver — or, if a C header may legitimately
back a `uses` (that is how some shims work), it must lose to a real `.pas` of the
same name, and it must not silently become a shared-library import.

## Gate

Track A's: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
plus both repros above — `uses strings` and `uses math` with and without
`-Ilib/crtl/include` — and the probe binary above must either fail to compile or
run, never link against a `lib<unit>.so` that does not exist.

> **Read the resolution below before acting on this section.** Its `png`
> row was re-measured during the fix and does **not** reproduce: `png`
> captures exactly like `strings`, and survives only when `-Fulib/rtl`
> precedes the include roots. The "header must compile as a unit"
> narrowing rests on that row and does not hold either. Kept verbatim
> because the fourth collision it found is real and because a corrected
> claim is worth more than a deleted one.

## A second exposed site, and it narrows the trigger

`apps/ide/build.sh` passes `GTK3_INC="$(pkg-config --cflags-only-I gtk+-3.0)"`
next to Pascal `uses` — the same shape, in our own tooling, added the same day
this was filed. frankB checked the three names above against the gtk-3.0 header
roots and reported it clean. **It is clean, and the way it is clean is the
useful part.**

Re-checked here by cross-producting every RTL unit name against every header on
those roots rather than the three known ones, which finds a fourth collision
frankB's narrower test could not:

```
lib/rtl/png.pas   vs   /usr/include/libpng16/png.h      (on gtk+-3.0's -I path)
```

And yet:

```
$ pascal26 $GTK3_INC png_test.pas /tmp/p        # uses png
ok
```

**A name collision is necessary but NOT sufficient.** `strings.h` captures and
`png.h` does not, on the same compiler, through the same flag. The difference
that fits every observation so far: pxx's own `lib/crtl/include/strings.h` is
written to be compiled by cfront and parses as a unit, while `/usr/include/libpng16/png.h`
is a real system header that does not — and an empty `strings.h` does not
capture either (the control at the top of this ticket). So the capture happens
when the header **successfully compiles as a unit**, and falls back correctly
when it does not.

That is where to look, and it also says what the fix must not break: whatever
makes `png.h` fall back to `lib/rtl/png.pas` is already doing the right thing.

**Known-exposed sites, both verified:**

| site | flag | status |
| --- | --- | --- |
| `feature-demo-songformatter-pxx-target` measurement instruction | `-Ilib/crtl/include` | **captures** — three of five modules mis-fail; instruction superseded |
| `apps/ide/build.sh` | `GTK3_INC` (gtk+-3.0 roots) | **clean today** — `png` collides by name, does not capture |

The second row is worth as much as the first: it is the passing test case, and a
fix that makes `png` start capturing would be a regression nothing else would
catch.

---

## Fixed — 2026-08-29, `compiler/pasparser_proc.inc`

Self-host fixedpoint `62714dc5eb06`, `gate.sh quick` GREEN.

## It IS search-order precedence. The control that said otherwise could not discriminate.

The ticket's "what is NOT the cause" section says the empty-`strings.h` control
rules out a plain path-precedence bug and points at the C-unit compilation path
claiming the `uses`. **That inference does not hold, and the reason is worth
more than the conclusion.**

The unit search loads each candidate with `LoadFile` and accepts it on
`Length(UnitContent) > 0` — on **content**, never on existence. An empty
`strings.h` is therefore indistinguishable from a missing one, by construction.
The control produced the right observation and could not have produced any
other, whatever the cause was. A contaminated control that fails by agreeing.

The actual mechanism, in three lines of existing code:

1. `compiler.pas` — `-I<dir>` calls **both** `AddCIncludeDir` and
   `AddPasUnitDir` (deliberately, `feature-dynamic-include-paths-config`), so
   a C include root is also a Pascal unit root.
2. `pasparser_proc.inc` — the `PasUnitDirs` loop probes `.pas`, `.pp`, `.c`,
   `.h` **per root, in flag order**, and runs *before* the compiler-anchored
   RTL directory.
3. `lib/crtl/include/strings.h` is non-empty, so it is taken, and
   `lib/rtl/strings.pas` is never reached.

"Header with content" was the right observation; *parseable* content is not
required and neither is any C-side behaviour — non-empty is the entire
threshold.

## The `png` negative row does not reproduce. It is flag order.

Checked rather than inherited, and it inverts:

| invocation | pinned (v392) |
| --- | --- |
| `pascal26 usepng.pas` | ok |
| `pascal26 -I/usr/include/libpng16 usepng.pas` | **`undefined variable (PngLastError)`** |
| `pascal26 $(pkg-config --cflags-only-I gtk+-3.0) usepng.pas` | **captured** |
| `pascal26 -Fulib/rtl -I/usr/include/libpng16 usepng.pas` | ok |
| `pascal26 -I/usr/include/libpng16 -Fulib/rtl usepng.pas` | **captured** |

`png` captures exactly like `strings`. It survives only when `-Fulib/rtl`
precedes the include roots — `PasUnitDirs` is searched in flag order, so an
earlier `-Fu` holding the real unit reaches it first. That is the whole
difference, and it means the negative was a property of the command line, not
of the header.

Two things follow. **`apps/ide/build.sh` is in the capturing order** —
`$GTK3_INC` is passed before `-Fu"$ROOT/lib/rtl"` — so it was exposed, not
clean. And a name-collision survey run with `-Fu` first will report no
collisions no matter how many there are.

(One false start of my own on the way: the first `uses png` probe was a program
named `png.pas`, so the source-directory probe found the program itself and
reported `Expected: unit, but got: program`. Renaming the probe file was the
whole fix. Same shape as the control above — a measurement that answers a
question you did not ask.)

## The fix

A Pascal unit **anywhere** on the chain outranks a C header found in a **search
root**; among C candidates the existing order is untouched.

- In the `PasUnitDirs` loop, a `.c`/`.h` hit is **held back** rather than
  taken — recorded in `deferredCPath`/`deferredCContent`/`deferredCIsHeader`
  and the search continues.
- After the CWD-relative fallback, the held-back candidate is adopted if the
  whole Pascal chain missed. So a real FFI `uses <header>` resolves exactly as
  before whenever no `.pas` of that name exists — which is every case in the
  tree except the four collisions.
- The five later C probes (`rtldir` `.h`, `lcldir` `.c`/`.h`, the CWD-fallback
  `.h` group and `.c`) are guarded so a held-back candidate still outranks
  them.

**Not extended to the `SourceFileDir` probes.** A `.c`/`.h` next to the file you
are compiling is an explicit local choice; a root reached through a flag is not.
Deliberate, stated in the code, and visible in the test — `strings` is left out
of the regression program because `test/strings.pas` is a test *program* that
shadows the RTL unit from that directory through exactly this arm.

## The first cut was wrong in the silent direction, and nothing could see it

Deferring C behind Pascal also deferred it behind **other C**, so
`-Futest/gtk3stock`'s `gtk3_c.h` lost to `lib/pcl/gtk3_c.h` and the shadow that
test exists for was **silently defeated**.

`test_c_gtk3_stock` could not detect it. Both headers now `#include` the
installed GTK surface, so the two builds are byte-identical — the test's own
comment already says its `readelf` row asserts the link and "structurally
cannot" assert the version. It took a `#error` poison probe in a copy of the
shadow to find, and the poison is decisive where the byte count is not:

```
pinned      -Fu<poisoned shadow> ...  -> POISON fires   (shadow used)
first cut   -Fu<poisoned shadow> ...  -> silent         (shadow defeated)
fixed       -Fu<poisoned shadow> ...  -> POISON fires   (shadow used)
```

So the fix grew a second half and the suite grew a witness:
`test/uses_shadow/math_ext.h` declares `abs` and omits `labs`, and
`test/test_uses_shadow_root_beats_the_rtl_header.pas` calls `labs` — it
compiles against the RTL header and fails against the shadow, which answers
"which file did the `uses` resolve to" from outside the compiler. **Verified
against a rebuild of the broken first cut, where it wrongly compiles.** A guard
that has never failed is not yet a guard.

## Tests

`test/test_uses_beats_a_c_header_on_the_include_path.pas` — `uses math, netdb`,
every value FPC 3.2.2's, wired at four flag orders (none / `-I` / `-I -Fu` /
`-Fu -I`) all asserted equal. **RED at the pin** on the two orders where `-I`
comes first, green on the two where it does not — which is the flag-order
finding above, pinned. It **runs** the binary rather than only compiling it,
because the silent arm compiles clean and dies at load.

`test/test_uses_shadow_root_beats_the_rtl_header.pas` + `test/uses_shadow/` —
the opposite polarity, above. Six new Makefile rows in total; all six corrupted
with a sentinel and confirmed to go red.

Spot-checked one by one, all green: `crtl_tiny_regex_match.c` (`-I` ×2),
`creinc_proto_reinclude_b172.c` (`-I` ×3), `test_c_def_hijack`,
`unit_c_bridge`'s driver, `-Itest/builtin_shadow`, `-Itest/cinc/inc`,
`-Futest/case_units`, `-Futest/generic_spec_units`, `-Futest/modeunits`,
`-Futest/shims`, `-Itest/unitpath/posix`, `-Futest/gtk3stock`, and
`examples/tk/uses_tkinter_and_configparser.pas` in **both** `uses` orders.

## What this fix does NOT cover

The unloadable binary has a second, independent cause that survives it: a
`static` or `static inline` function **defined** in a header reached by `uses`
has its body discarded, becomes an external, and the compiler synthesises a
`lib<header-stem>.so` to import it from. The identical function in a `.c`
compiles and runs. The ticket's own probe hit this — `pxx_probe_marker` is
`static` — which is why the DT_NEEDED looked like part of the same defect.

Filed as
[[bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead]]
(Track C, p55) with the `.h`-vs-`.c` pair, the `static inline` case, and the
two comments in `cparser.inc` that assert the invariant it breaks.

## Lane note

The edit is in `compiler/pasparser_proc.inc` — unit-resolution machinery living
in a Track P file. It does **not** touch `cparser.inc`, `cpreproc.inc`,
`symtab.inc`, or `ParseTypeRef`, so it does not collide with the C refactor or
with the NilPy import-order work.

## Log
- 2026-08-29 — resolved, commit 4576ad4d1.
