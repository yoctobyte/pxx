# Bug: passing a FIXED-size array to an `array of T` open-array parameter stack-copies into the caller's frame

- **Type:** bug — Track A (compiler internals, codegen / calling convention)
- **Status:** done
- **Opened:** 2026-07-01
- **Found by:** building the `-S` x86-64 disassembler (feature-asm-textual-emit-mode
  task #7) — `WriteDisassemblyX64` called `DisOne(Code, pos, CodeLen, ...)`
  passing the compiler's own `Code` array (`array[0..MAX_CODE-1] of Byte`,
  `MAX_CODE` = 8 MB) as a `const code: array of Byte` argument. The self-hosted
  `compiler/pascal26` compiled this cleanly but then **segfaulted at runtime**
  when actually running `-S` on a real program — `WriteDisassemblyX64`'s own
  stack frame turned out to be ~8 MB (matching `MAX_CODE` almost exactly:
  8389256 bytes), blowing the default 8 MB (`ulimit -s`) stack.
- **Relation:** [[feature-warn-oversized-stack-frame]] (done) is the *detector*
  that caught this — its per-frame check is exactly what printed the warning
  that led here. That ticket's own scope, though, was declared locals ("small
  data belongs on the stack, big data on the heap" as a rule you apply when
  *you* write `var buf: array[0..N] of T`). This bug is a different cause the
  detector wasn't built with in mind: nobody declared a large local here at
  all — `Caller`/`WriteDisassemblyX64` have no big locals; they just passed an
  *existing* array by `const`/`var` reference, and the compiler silently
  manufactured an unrequested copy. The warning correctly caught the symptom;
  this ticket is the actual disease (open-array parameter marshalling doing a
  value-copy where Pascal semantics — and the caller's own code — expect
  pass-by-reference). Not a duplicate of the detector ticket, a distinct root
  cause it happened to expose.
- **Scope, verified 2026-07-01: fixed-size arrays only, dynamic arrays are
  unaffected.** Re-ran the minimal repro below with `BigBuf` declared
  `array of Byte` (dynarray) + `SetLength(BigBuf, MAX_BUF)` instead of
  `array[0..MAX_BUF-1] of Byte` — same `Touch(const buf: array of Byte;
  ...)` signature, same call site, same 8 MB size. Result: **no warning at
  all**, even at `--max-stack-frame=64` (`Caller` doesn't appear in a list
  where RTL routines with ~70-180 byte frames do). A dynamic array variable
  is already a handle (pointer + length header on the heap) — passing it to
  an open-array parameter apparently just forwards that handle, no
  marshalling/copy needed, since the argument already has the shape the
  parameter wants. The bug is specifically in how a *fixed-size* array
  (`array[0..N-1] of T`, whose "handle" is just its own address, computed
  fresh at the call site) gets converted into an open-array argument.
  **Practical fallout: this is also the workaround**, and a clean one — same
  element type (`Byte`), same 0-based indexing, same O(1) read/write
  performance; only the declaration changes (`array[0..N-1] of Byte` →
  `array of Byte`) plus one `SetLength` call at whatever point today
  initializes/sizes the buffer. No `Ord`/`Chr` casting needed (unlike the
  AnsiString alternative floated earlier in the same discussion, which
  works too but has an element-type mismatch to bridge at every access
  site — dynarray-of-Byte has none). Doesn't fix the underlying compiler
  bug, but narrows who needs to care about it: only fixed-array buffers
  crossing an open-array parameter boundary, which is a much smaller set
  than "any array passed as `array of T`."

## Repro (minimal, isolated)

```pascal
program ReproStackFrame;
const MAX_BUF = 8388608;
var
  BigBuf: array[0..MAX_BUF-1] of Byte;

function Touch(const buf: array of Byte; idx: Integer): Integer;
begin
  Result := buf[idx];
end;

procedure Caller;
var i: Integer;
begin
  i := Touch(BigBuf, 5);
  writeln(i);
end;

begin
  BigBuf[5] := 42;
  Caller;
end.
```

Compiling this with `pascal26 --debug` prints the compiler's own oversized-
stack-frame warning (feature added for exactly this failure class, see
`project_warn_oversized_stack_frame_done` memory / `bug-fpc-seed-segfault`):

```
warning: routine 'Caller' uses 8388620 bytes of stack frame (> 1048576);
large frames risk stack overflow — move big buffers to the heap (GetMem)
or a global
```

`Caller` itself declares no large locals — it only *passes* `BigBuf` (a
global) to `Touch` as a `const array of Byte` parameter. The frame-size
warning firing on `Caller`, not `Touch`, is the tell: the **caller** is
reserving stack space sized to the array, meaning the open-array argument
is being staged (copied) onto the caller's stack before the call, rather
than passed as the standard Pascal open-array convention (a pointer +
length pair, O(1) regardless of array size).

**Counter-repro — identical shape, `BigBuf` as a dynamic array instead:**

```pascal
program ReproDynArrParam;
const MAX_BUF = 8388608;
var
  BigBuf: array of Byte;

function Touch(const buf: array of Byte; idx: Integer): Integer;
begin
  Result := buf[idx];
end;

procedure Caller;
var i: Integer;
begin
  i := Touch(BigBuf, 5);
  writeln(i);
end;

begin
  SetLength(BigBuf, MAX_BUF);
  BigBuf[5] := 42;
  Caller;
end.
```

Same `Touch` signature, same call, same 8 MB. `pascal26 --debug` prints
**no warning** — not even at `--max-stack-frame=64` (where RTL routines
with 70-180 byte frames *do* show up; `Caller` isn't in that list). Confirms
the bug is specific to the fixed-array-to-open-array conversion at the call
site, not open-array parameter handling in general.

## Impact

Silent, no compile error — just a stack-frame-size **warning** (easy to miss
or ignore, especially since it names the *caller*, not the array or the
callee, as the offender) that becomes a real SIGSEGV at runtime once the
array is large enough relative to the platform's stack limit. Any code
passing a multi-MB fixed array as a `const`/plain `array of T` parameter is
at risk — this is a correctness/safety bug, not just a performance one.

## Workaround used

`compiler/asmdisasm_x64.inc`'s disassembler functions (`DisOneReal`, `DisOne`,
`DisParseModRM`, `DisRead32`, `DisReadI32`) originally took `code: array of
Byte` so they could be unit-tested standalone against a small local buffer.
Since production use only ever passes the global `Code[]` array, removed the
parameter entirely and made them reference `Code[]` directly — sidesteps the
bug completely (no open-array argument, no stack copy) and is arguably
better style anyway (matches this codebase's pervasive direct-global-access
convention over parameter-threading). Verified with a full self-compile:
`pascal26 -S compiler/compiler.pas` (a ~3.5 MB `Code[]`) now runs cleanly to
completion (previously segfaulted) and the oversized-stack-frame warning is
gone.

## Suggested fix

A *fixed-size* array argument to an `array of T` formal parameter (with or
without `const`) should compile to the standard open-array ABI (address of
the array's first element + length, passed as two words), not a value
copy — the dynamic-array case above proves the callee-side open-array
handling itself is fine (it already accepts a handle-shaped argument
correctly); the bug is specifically in how a fixed array's argument gets
*converted into* that shape at the call site. Needs an IR/codegen-level
look at caller-side argument marshalling for this one case (likely
`ir.inc`/`ir_codegen.inc`'s call-argument staging, wherever a fixed-array
actual gets matched against an `array of T` formal) — probably the same
code path for `const array of T` and plain `array of T` (no `const`), worth
checking both. Comparing that code path against whatever the (working)
dynamic-array argument path does differently is probably the fastest way
in.

## Also worth checking while in there

- Does the bug scale with array size, or is it a fixed overhead regardless?
  (The minimal repro's `Caller` frame ≈ `MAX_BUF` exactly, suggesting it
  scales 1:1 with the array's *declared* size at the call site, not some
  fixed buffer.)
- A `grep -rn "array of .*Byte\|array of .*AnsiString" compiler/*.pas
  lib/**/*.pas` sweep for other call sites passing large *fixed* arrays
  (not dynamic arrays — those are confirmed unaffected) as open-array
  parameters, to gauge real-world exposure elsewhere in the compiler/RTL/
  user code today.

## Fixed (2026-07-01, Track A, commit 730b6a75, pinned v113)

Size-gated at a new `MAX_OPEN_ARRAY_STACK_TEMP` (64 KB, `defs.inc`): arrays at
or under the threshold keep the original frame-local `[len:8][data]` buffer
path in `IRLowerCallArg` (`ir.inc`) byte-for-byte unchanged — zero risk to
the overwhelmingly common small-array case, and the compiler's own source
never crosses this threshold, so self-host/cross-bootstrap never exercise
the new path at all (verified: bootstrap byte-identical). Above the
threshold, both the const/value and var/out branches now manufacture a
genuine managed dyn-array-of-byte temp instead (`AllocDynArray` +
synthesized `SetLength` intrinsic call, mirroring `AN_VARREC_ARRAY`'s
existing TVarRec-temp pattern for `array of const`) — heap-backed, bounded
regardless of the source array's size, and released automatically by the
routine's normal managed-local cleanup at scope exit. Its handle already has
the `[len:8][data]` layout the open-array parameter expects, so the callee
side (`Length`/`High`/indexing) needed zero changes. The `var`/`out`
writeback flush sites (two call sites in the `AN_CALL` IR lowering) gained a
small shared helper (`PendOAWBSrcAddr`) that branches on
`Syms[temp].ArrLen < 0` (the existing dynamic-array sentinel) to compute the
copy-back source correctly for either temp kind.

**Landmine caught before landing:** the first attempt copied
`AN_VARREC_ARRAY`'s inline `IR_DEFAULT_MEM` (zero the handle) immediately
before the synthesized `SetLength` call, on the assumption this mirrored a
proven-safe pattern. It doesn't generalize to a call site inside a loop: the
inline zero orphans the *previous* iteration's already-allocated handle
before `SetLength` gets a chance to see/reuse/release it, leaking on every
iteration (~2 MB/call in the repro that caught it — RSS went from 4 MB to
102 MB over 50 iterations of a 2 MB array). Fixed by removing the inline
zero entirely and relying solely on the prologue-level `SymIsHiddenArgTemp`
nil-init (runs once at function entry, correctly leaves a non-nil handle
alone on later loop iterations) plus `SetLength`'s own already-correct
resize-of-an-existing-handle semantics — the same behavior any ordinary
array-growing user code already depends on. `AN_VARREC_ARRAY` itself was not
touched or audited for the same class of bug (out of scope here; worth a
look if anyone hits an array-of-const-inside-a-loop leak later).

**Verified:** full `make test` + all four cross targets (i386/aarch64/arm32/
riscv32) green; self-host bootstrap byte-identical; the original crash repro
and a var/writeback repro both correct with zero stack-frame warning at
`--debug`; new `test/test_big_static_array_open_param.pas` (small+large
arrays, const+var paths, writeback correctness, 50-iteration RSS leak guard)
wired into `make test-core`.

## Log
- 2026-07-01 — resolved, commit 730b6a75.
