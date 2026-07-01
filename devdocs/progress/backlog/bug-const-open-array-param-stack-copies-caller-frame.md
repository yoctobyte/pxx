# Bug: `const array of T` open-array parameter stack-copies into the caller's frame

- **Type:** bug — Track A (compiler internals, codegen / calling convention)
- **Status:** backlog
- **Opened:** 2026-07-01
- **Found by:** building the `-S` x86-64 disassembler (feature-asm-textual-emit-mode
  task #7) — `WriteDisassemblyX64` called `DisOne(Code, pos, CodeLen, ...)`
  passing the compiler's own `Code` array (`array[0..MAX_CODE-1] of Byte`,
  `MAX_CODE` = 8 MB) as a `const code: array of Byte` argument. The self-hosted
  `compiler/pascal26` compiled this cleanly but then **segfaulted at runtime**
  when actually running `-S` on a real program — `WriteDisassemblyX64`'s own
  stack frame turned out to be ~8 MB (matching `MAX_CODE` almost exactly:
  8389256 bytes), blowing the default 8 MB (`ulimit -s`) stack.

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

`array of T` parameter passing (with or without `const`) should compile to
the standard open-array ABI (pointer + length, passed as two words / one
struct — however this compiler's calling convention already threads other
by-reference data), not a value copy. Needs an IR/codegen-level
investigation of how open-array parameters lower to caller-side argument
marshalling (likely in `ir.inc`/`ir_codegen.inc`'s call-argument staging,
wherever an `array of T` formal parameter's `TCallFix`/argument-copy logic
lives) — probably the same code path handles both `const array of T` and
plain `array of T` (no `const`), worth checking both.

## Also worth checking while in there

- Does the bug scale with array size, or is it a fixed overhead regardless?
  (The minimal repro's `Caller` frame ≈ `MAX_BUF` exactly, suggesting it
  scales 1:1 with the array's *declared* size at the call site, not some
  fixed buffer.)
- A `grep -rn "array of .*Byte\|array of .*AnsiString" compiler/*.pas
  lib/**/*.pas` sweep for other call sites passing large fixed arrays as
  open-array parameters, to gauge real-world exposure elsewhere in the
  compiler/RTL/user code today.
