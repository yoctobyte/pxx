---
track: A
prio: 65
type: bug
blocked-by: []
summary: "`-Ilib/crtl/include` makes `uses strings` bind to the C header strings.h instead of lib/rtl/strings.pas: StrPas becomes `undefined variable`, and a call the header DOES declare compiles into a dynamic import of a nonexistent libstrings.so, so the binary dies at load. Three RTL units collide by basename with a shipped crtl header — math, netdb, strings — and `uses math` + that flag loses Floor the same way. Five-line pure-Pascal repro."
status: new
owner: ""
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
