---
summary: "`uses sysutils|baseunix|unix` degrades to a SILENT no-op when the unit is not on the search path, so a build outside the repo root reports `undefined variable (Format)` instead of naming the missing RTL"
type: bug
track: A
prio: 45
---

# `uses SysUtils` silently no-ops when the RTL is not reachable

- **Type:** bug — Track A (`compiler/parser.inc`, the `uses` resolver)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** a Track B `fpc_diff_probe` session — as a *harness* failure,
  which is exactly the point: the diagnostic sent me looking for a missing
  `Format` in the RTL for several minutes.

## Repro

```
$ cd /tmp
$ cat > t.pas <<'EOF'
program t;
uses SysUtils;
begin
  writeln(Format('%d', [42]));
end.
EOF
$ <repo>/stable_linux_amd64/default/pinned t.pas t
pascal26:4: error: undefined variable (Format)
```

The same file from the repo root compiles and runs. Nothing in the output
mentions `sysutils`; `strace` shows the compiler never opens a sysutils source.

A unit name that is not on the soft-miss list behaves correctly:

```
pascal26:2: error: uses: unit source not found: thisunitdoesnotexistanywhere
```

## Root cause

`compiler/parser.inc:28423`

```pascal
softMissOK := (lo = 'sysutils') or (lo = 'baseunix') or (lo = 'unix');
```

and at `:28886`, when every search root came up empty:

```pascal
{ sysutils/baseunix/unix with no source on the path: pass as a no-op so
  builtin-only FPC code keeps compiling (the historical behavior). }
if softMissOK then begin CurrentCLibrary := savedCurrentCLibrary; Exit; end;
```

So the miss is deliberate and compat-motivated — FPC code that says `uses
SysUtils` but only touches builtins must keep compiling. What is *not*
deliberate is that it is **silent**: the `uses` clause vanishes and every
symbol it should have supplied fails individually, at a line far from the
cause, with a message that accuses the program.

Why it does not bite in-tree: the RTL is anchored to `ExeDir/../lib/rtl/`, and
`ExeDir` for the stable binary is `<root>/stable_linux_amd64/default/`, whose
`../lib/rtl` does not exist. Every in-tree invocation is rescued by the
CWD-relative fallback at `:28797`. Change the CWD and the rescue is gone. Any
installed-elsewhere pxx has the same shape.

## Suggested fix

Keep the soft miss (it is load-bearing for FPC compat) and make it audible —
one note naming the unit, in the spirit of the shim-substitution note the
NilPy path already prints:

```
note: sysutils not found on the unit search path; continuing with builtins only
```

That alone turns this from a misdirection into a one-line diagnosis. An
`--no-soft-uses` that promotes it to an error would be a reasonable second
step, and a strict-mode flag is the established place for it.

Orthogonal but adjacent, worth a separate ticket if wanted: the RTL anchor
should probably also try `ExeDir/../../lib/rtl/` so the stable binary resolves
the RTL by its own path rather than by the caller's CWD.

## Gate

Track A: `make test` + self-host fixedpoint. The note goes to stdout like the
shim note, so any expectation file capturing combined output for a build with
a genuinely missing sysutils would need updating — in-tree there should be
none, since in-tree builds find it.
