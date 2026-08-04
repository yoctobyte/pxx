---
summary: "i386: widening a 32-bit value into an Int64 argument leaves the HIGH half uninitialized — silent garbage, and the garbage changes with surrounding code"
type: bug
track: A
prio: 75
---

# i386: an Int64 argument's high half is left uninitialized (silent garbage)

- **Type:** bug — Track A (i386 backend / argument materialization)
- **Status:** urgent
- **Opened:** 2026-08-04
- **Found by:** Track B, cross-targeting `test/lib_format_ge.pas` after a float
  formatting fix. **Pre-existing** — the unmodified file and unmodified RTL fail
  identically on i386.

## Symptom

`i386 only`. x86-64, arm32 and aarch64 are all correct.

```pascal
procedure ShowI64(v: Int64); begin writeln(v); end;
var e: Integer;
begin
  e := -1;
  ShowI64(Abs(e));        { prints -133143986175, not 1 }
end.
```

The low 32 bits are always right; the **high 32 bits are whatever was already
in the slot**. `-133143986175` is `0x1F_00000001` sign-flipped — the value 1
with garbage above it.

## The tell: the garbage MOVES

Running the same matrix twice with different surrounding statements changed
*which* rows failed — `ShowI64(Length('abc'))` was wrong in one arrangement and
right in the next, with no change to that line. That is the signature of an
uninitialized slot rather than a wrong extension instruction: the result depends
on what the previous code happened to leave there.

Consequence for whoever picks this up: **do not trust a passing case**. A form
that looks correct may simply have inherited a zero high half. Only the failures
are evidence.

## Matrix (one arrangement; the ok/WRONG split shifts, the failures are real)

| form | i386 |
| --- | --- |
| `x: Int64; x := e` | ok |
| `x := TakeI64(e)` (result into a var first) | ok |
| **`writeln(TakeI64(e))`** (Int64 result used directly as an argument) | **WRONG** |
| `ShowI64(e)` (plain variable) | ok |
| **`ShowI64(Abs(e))`** (builtin result as the argument) | **WRONG** |
| `ShowI64(MyAbs(e))` (user function returning Integer) | ok |
| `ShowI64(-e)`, `ShowI64(e+0)`, `ShowI64(Ord('a'))` | ok |
| **`x := TakeI64(Abs(e))`** | **WRONG** |

The two reliable triggers are **a builtin's Integer result passed where an
`Int64` is expected**, and **an `Int64` function result used directly in an
argument position** without passing through a variable. Storing to a variable
first fixes both, which is consistent with the store path extending correctly
while the argument-materialization path does not.

## Why it is urgent

- **Silent.** No error, no warning, plausible-looking output.
- **Nondeterministic in effect**, so it will reproduce inconsistently and
  reduce badly.
- **`IntToStr` takes an `Int64`.** So `IntToStr(Abs(n))` — an entirely ordinary
  line — silently produces a wrong number on i386. That is how this was found:
  `Format('%e', ...)` printed `3.333E--4294967295` for an exponent of -1,
  because `IntToStr(Abs(e10))` received garbage.

## Repro

```
cat > /tmp/r.pas <<'P'
program r;
procedure ShowI64(v: Int64); begin writeln(v); end;
var e: Integer;
begin e := -1; ShowI64(Abs(e)); end.
P
./stable_linux_amd64/default/pinned --target=i386 /tmp/r.pas /tmp/r_386 && qemu-i386 /tmp/r_386
# prints garbage; x86-64/arm32/aarch64 print 1
```

## Test coverage note

`test/lib_format_ge.pas` reproduces this on i386 today (6 rows) and is a ready
regression target — but `lib-test` runs **x86-64 only**, which is exactly why a
32-bit codegen bug in a widely-used RTL path went unseen. Worth considering
whether some part of `lib-test` should run under qemu for the 32-bit targets;
this is the second 32-bit-only silent-value bug found by hand-cross-checking
(see bug-32bit-truthiness-high-half, bug-64bit-named-const-truncated-32bit-targets).
