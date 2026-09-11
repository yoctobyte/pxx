---
slug: feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags
title: "`sysutils` declares neither `TExecuteProcess` nor `TExecuteFlags`, and it is the FPC-compiler-source march's current wall"
track: B
prio: 40
type: feature
status: done
owner: frankH
created: 2026-09-09
found-by: frankH
blocked-by: []
summary: "DONE 2026-09-11. `lib/rtl/sysutils.pas` now declares `EOSError` (with `ErrorCode`), `TExecuteFlags = set of (ExecInheritsHandles)` and both `ExecuteProcess` overloads, over the already-present `PalVforkAndExec` / `PalWait4` / `EnvironmentBlock` -- a surface, not new capability. Every expected value in `test/lib_sysutils_executeprocess.pas` was read off fpc 3.2.2 on the same source; fpc and pxx both pass it whole. The FPC-compiler march clears `cfileutl.pas:136 unknown type: TExecuteFlags`, which was ONE wall counted three times (cfileutl, rgobj, aasmbase all stopped at that same line) and becomes two -- `TDoubleRec` and `comptty.pas:66 termio.IsATTY`, the latter again one wall counted twice. Units-compiling moved by ZERO. Both new walls are unowned. Filed on the way: bug-p-an-array-constructor-in-argument-position-is-typed-as-a-set."
---

# The wall, and how to stand in front of it

```
$ pascal26 --mimic-fpc-compiler \
    -Fu/usr/share/fpcsrc/3.2.2/compiler \
    -Fu/usr/share/fpcsrc/3.2.2/compiler/x86_64 cf.pas
pascal26:136: error: unknown type: TExecuteFlags
  in: /usr/share/fpcsrc/3.2.2/compiler/cfileutl.pas
  near: ComLine : AnsiString ; Flags : >>> TExecuteFlags = [
pascal26:137: error: unknown type: TExecuteFlags
```

`cf.pas` is `program cf; uses comphook, finput, cfileutl; begin WriteLn('cf ok') end.`
The second `-Fu` is not optional — without it `cpuinfo` is not found first and
you never reach this. **Writing the configuration down is the point of this
ticket**: the march is driven by hand, and frankB's standing note is that *"a
substitute for a flag is a configuration nobody else runs, so every number it
produces is unshared."*

# What it is NOT

The parse is fine. Two overloads with a defaulted set after an open-array
parameter compile and run:

```pascal
type TEF = set of (efInheritsHandles);
function A(const P: AnsiString; const C: AnsiString;       F: TEF = []): LongInt;
function B(const P: AnsiString; const C: array of AnsiString; F: TEF = []): LongInt;
```
prints `1 2`. The type is simply absent from our RTL.

# What FPC declares

`rtl/objpas/sysutils/sysutilh.inc`:

```pascal
type
  TExecuteFlags = set of (ExecInheritsHandles);
function ExecuteProcess(const Path, ComLine: AnsiString; Flags: TExecuteFlags = []): Integer;
function ExecuteProcess(const Path: AnsiString; const ComLine: array of AnsiString;
                        Flags: TExecuteFlags = []): Integer;
```
plus `RawByteString`/`UnicodeString` spellings and `EOSError`.

# The machinery is already here

`lib/rtl/subprocess.pas:102` builds `Popen` on `PalVforkAndExec(prog, argvp,
envp, ...)` and waits with `Popen.wait`. `ExecuteProcess` is the same three
steps with a different argument shape — split `ComLine` on whitespace for the
string overload, take the array directly for the other. **A type-only stub is
worse than nothing**: `cfileutl`'s implementation section calls
`ExecuteProcess`, so parsing further only moves the failure to link time.

# Where it came from

The march's previous wall, `cclasses.pas:2909`, is gone — see
[[bug-p-a-double-deref-in-fpcs-cclasses-is-refused-and-the-obvious-reduction-compiles]],
attributed to `a4cbaa1de`. Four walls have now fallen in this unit in sequence
(`TFPCHeapStatus`, the forward pointer-to-array, `Prefetch`, the double deref);
each was invisible until the one in front of it cleared, which is why a march
wall is worth a ticket only once it is the frontier.

# 2026-09-11, frankS — it is the frontier again, and now it is the WHOLE frontier

Attempt 7 of [[umbrella-pxx-compiles-fpc-itself]] (probe #11, whole corpus,
`e013c4344`): **119 of 207 units stop here**, up from a handful when this was
filed, because everything that used to stop earlier in `cclasses.pas` now walks
past it. `cclasses.pas` itself compiles.

**DO NOT RANK THIS ON 119.** The same attempt measured what clearing a wall of
that size is actually worth: the `Finalize(x, n)` wall had 150 units stacked on
it and clearing it moved BOTH-OK by **three** — the unit itself plus its two
direct dependents. The walls are stacked in a few shared units, so a blocker's
unit count is a queue position. Rank this on the fact that it is a small surface
over machinery that already exists, which is what the section above says.

Nothing in this ticket's diagnosis has changed and none of it needed re-deriving
— including the part that matters most, and it is easy to skip on a reread: **a
type-only stub is worse than nothing**, because `cfileutl`'s implementation
calls `ExecuteProcess` and adding the type alone only moves the failure to link
time. A second, smaller thing sits immediately behind it and is unmeasured
because nothing reaches it today: `cfileutl` then writes
`const ExecuteProcess = 'Do not use' deprecated '<msg>'` to hide the sysutils
name — a const carrying a `deprecated` directive. Whoever clears the type should
expect it and not read it as a regression.

## Resolved 2026-09-11 (frankH, Track B)

`lib/rtl/sysutils.pas` gains `EOSError` (with `ErrorCode`), `TExecuteFlags =
set of (ExecInheritsHandles)`, and both `ExecuteProcess` overloads — the
string form (whitespace-split, quote-naive, as fpc's is) and the
`array of AnsiString` form. Built on `PalVforkAndExec` + `PalWait4` +
`EnvironmentBlock`, which were all already here; no new capability, a surface.

Exit-code convention is `(status shr 8) and 255`. A failed spawn and a child
that could not exec both raise `EOSError` carrying the code, matching fpc.

### The corpus moved, and the delta was A/B'd on ONE binary

Same `compiler/pascal26`, the change stashed and restored between the two
halves, so this is not a pull's delta read as mine:

| unit | before | after |
| --- | --- | --- |
| cfileutl | `cfileutl.pas:136 unknown type: TExecuteFlags` | `unknown type: TDoubleRec` |
| rgobj | `cfileutl.pas:136 unknown type: TExecuteFlags` | `comptty.pas:66 undefined variable (IsATTY)` |
| aasmbase | `cfileutl.pas:136 unknown type: TExecuteFlags` | `comptty.pas:66 undefined variable (IsATTY)` |

**Both columns are one wall counted three times, and then one wall counted
twice.** All three "before" rows are the SAME LINE of the same file, and the
two `IsATTY` rows are both `comptty.pas:66` — `termio.IsATTY(t)` — reached
through a shared dependency. Units-compiling moved by ZERO, which is the
umbrella's own finding for the fifth time: a wall's population is a queue
position, not a size. The two new walls (`TDoubleRec`, `termio.IsATTY`) are
unowned and unfiled as of this resolution.

### Verification

- **Oracle**: every expected value in `test/lib_sysutils_executeprocess.pas`
  was read off fpc 3.2.2 on that same source, not predicted. fpc passes the
  fixture whole (`EXECPROC OK`); so does pxx under the pin.
- **Positive control**: with `lib/rtl/sysutils.pas` stashed the fixture cannot
  compile — `pascal26:60: error: undefined variable (ExecuteProcess)`, rc=1.
- **Row control**: `tools/expect_same.sh` rejects a wrong expectation for this
  row (rc=1), so the row can fail.
- **An earlier draft's `array-argc-0` row was a guard that could not fail** and
  was replaced. It put the space inside the COMMAND STRING and expected 0:
  `[sh,-c,'exit $#']` and its re-split `[sh,-c,exit,$#]` both leave `$#` at 0,
  so the row certified the property it was written to test in either direction.
  The row now puts the space in a POSITIONAL — `$0=zero`, `$1='a b'`, `$2=c`,
  so `$#` is 2 and a re-split would answer 3.
- **`make lib-test` does not reach this row**: it dies ~180 lines earlier at
  `Makefile:33417`, `lib-units: FAIL mimic_queue — unknown type: TPyDeque`,
  the standing owner-only pin cliff. The row was run by executing the recipe's
  two lines verbatim against the same `$(TESTTMP)`.

### Filed on the way

[[bug-p-an-array-constructor-in-argument-position-is-typed-as-a-set]] — `['x']`
in argument position is typed as a set, so an `array of T` overload is
unreachable for it. Against these declarations it does not refuse, it selects
the WRONG overload silently. That is why no row here uses a `[...]` literal.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 70220c6f4.
