---
summary: "An OPEN ARRAY value parameter (`x: array of Integer`) aliases the caller's data — the callee's `x[0] := n` is visible to the caller. FPC copies. A NAMED dynamic-array value param correctly aliases in both."
type: bug
track: A
prio: 50
status: done
owner: claude-A-N
---

# An open-array VALUE parameter aliases the caller's array instead of copying it

- **Type:** bug — Track A (parameter passing / open arrays).
- **Found:** 2026-08-06, closing out
  `bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing`, which listed this
  row and asked for it to be checked once the assignment direction was settled.
- **Pre-existing:** identical on `stable_linux_amd64/default/pinned`, and
  unchanged by the aliasing fix.

## Repro

```pascal
program vparam;
type TIntArr = array of Integer;

procedure TakesNamed(x: TIntArr);        { named DYNAMIC ARRAY, by value }
begin x[0] := 555; end;

procedure TakesOpen(x: array of Integer); { OPEN ARRAY, by value }
begin x[0] := 666; end;

var a: TIntArr;
begin
  SetLength(a, 2); a[0] := 1; a[1] := 2;
  TakesNamed(a);  writeln('after TakesNamed(a) a[0]=', a[0]);
  a[0] := 1;
  TakesOpen(a);   writeln('after TakesOpen(a)  a[0]=', a[0]);
end.
```

| | `TakesNamed` (named dynarray) | `TakesOpen` (open array) |
| --- | --- | --- |
| **FPC** | `555` — caller sees it | `1` — **caller unaffected** |
| **pxx** | `555` — agrees | `666` — **diverges** |

## Why these two rows are NOT the same question

The original ticket noted these run "the opposite way" from assignment and said
whatever was decided should leave them consistent. Having measured both, they are
consistent already — the divergence is narrower than it looked:

- a **named dynamic-array** value parameter passes the reference, so the callee's
  write reaches the caller. That is FPC's reference semantics and the same rule as
  `b := a` aliasing, and pxx now matches on both.
- an **open array** parameter is a different construct: FPC passes `{data, high}`
  and a by-value open array gets a *copy* the callee may scribble on. Only this
  one is wrong in pxx.

So this is not "pick a direction" — the direction is FPC's and is already
decided. It is a plain missing copy on one parameter kind.

## Blast radius, and why the priority is not higher

Silent (no error, no crash — the caller's array quietly changes), which is the
expensive shape. But it only bites code that WRITES through a by-value open-array
parameter, which is unusual: the idiom is to read from an open array and take
`var`/`out` when mutation is intended. Reads are unaffected.

The fix costs a copy on every by-value open-array call, so it should be emitted
only when the callee actually writes to the parameter, or the cost lands on the
common read-only case. Whether that write-detection is worth it, versus always
copying, is the implementation call to make with a benchmark rather than by
reasoning.

## Gate
The repro above matching FPC on every target, plus a read-only open-array
parameter benchmark showing no regression from whatever copy strategy is chosen.

## 2026-08-07 — FIXED

The ticket's reading was right: not a direction to pick, a missing copy on one
parameter kind. Emitted in **`IRLowerCallArg`**, not at the call sites — every
call funnels through that one function, while the parser builds argument lists
in a dozen places (plain calls, method calls, inherited, indexed properties) and
patching each would be the second path that stays broken. Spelled as the same
`AN_DYN_COPY` node `Copy(a)` builds, so it inherits that path's allocation and
temp lifetime rather than growing a new lowering.

Four conditions, each load-bearing and each measured against FPC rather than
reasoned about:

| condition | why |
| --- | --- |
| `IsArray` and **not** by-ref | a `var`/`out` open array must keep aliasing — it already did (`888`) |
| `ProcParamDynDepth = 0` | a NAMED dynamic-array value param passes the reference in FPC too, and pxx already agreed (`555`) |
| **not `const`** | `const` cannot be written, so a copy is pure cost |
| the argument carries a length header | a dyn array, **or an open-array PARAM being forwarded** |

## Two things the differential caught that the ticket did not list

1. **Forwarding.** `procedure Outer(x: array of Integer); begin Inner(x)` must
   give `Inner` its own copy as well. The first attempt keyed on
   `CopySrcDynDepth = 1`, which is 0 for a parameter (AllocParam stamps the
   `ArrLen = 1000` "length unknown" placeholder), so the inner write was still
   visible to `Outer` — FPC answers the caller's original value. An open-array
   param is now an eligible source in its own right; it is distinguished from a
   named dyn-array param by depth 0 and from a named FIXED array param by the
   1000 placeholder.
2. **The empty array.** Not a compiler bug in the end — the first probe wrote
   `x[0]` to a zero-length array, which is out of bounds in both compilers and
   only happened not to fault under FPC. `Copy` of an empty array is fine on
   `pinned` and at HEAD. The test now checks `Length` on an empty array instead
   of indexing it.

## The `const` answer to the ticket's open question

The ticket asked whether write-detection is worth it "versus always copying",
to be settled "with a benchmark rather than by reasoning". Measured, and the
question dissolves: **`const` IS the write-detection**, declared by the
programmer, and it is already the idiom. Every one of the 29 open-array
parameters in the compiler's own source is `const` (the single exception is
`var`), so **self-host never reaches the copying path at all** — the same
argument the `var` open-array note made about its path.

Benchmark, 3M calls of a routine summing a 64-element open array:

| | time |
| --- | --- |
| `const` open array, `pinned` | 0.47–0.49 s |
| `const` open array, HEAD | 0.48–0.49 s — **no regression** |
| the same routine WITHOUT `const`, HEAD | 2.93 s |

So the cost is real (6x here) but it is the honest cost of FPC's semantics, it
lands only where the programmer declined `const`, and `const` is both the fix
and FPC's own advice. No write-detection analysis was needed.

## Left on the old aliasing path, deliberately

Nested and managed element types. `AN_DYN_COPY` byte-copies, so an
`array of AnsiString` would duplicate handles without retaining them and free
them twice — a wrong VALUE beats a double free until `Copy` itself learns
element-aware retain ([[feature-dynarray-copy-nested-element-type]]). The `Copy`
intrinsic already refuses the nested case for the same reason; the managed case
is added here because this copy is emitted implicitly rather than asked for, so
a crash would arrive unannounced.

## Verified

`test/test_open_array_value_param_copies.pas` (new, registered in the Makefile)
diffs **byte-identical against FPC** — the ticket's two rows plus: `var` open
array, `const` open array with `Length`/`High`, a named FIXED array by value, a
static-array argument to an open array, `Length`/`High`/last-element inside the
callee (the copy carries a real header), a METHOD taking an open array by value
(a different argument path — this is what the IR-level placement buys),
forwarding a param onward, a single-element array, and an empty one.

Cross: compiles for i386, aarch64 and arm32; the i386 and aarch64 binaries run
under qemu and produce output identical to FPC's. `tools/gate.sh quick` GREEN.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
