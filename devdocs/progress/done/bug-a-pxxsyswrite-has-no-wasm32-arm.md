---
track: A
prio: 70
type: bug
blocked-by: []
summary: "PXXSysWrite in compiler/builtin/builtinheap.pas is a chain of per-target {$ifdef}s over __pxxrawsyscall with no wasm32 arm, so on wasm32 it returns 0 having written nothing. Every console path bottoms out there — writeln, the RTL error reporters, PXXDbg — so a wasm32 program compiles, lowers correctly, runs, and is silent. Fix is one additive arm behind {$ifdef CPU_WASM32} calling a WASI fd_write import; the wasm backend already lowers `external 'lib' name 'sym'` to a wasm import. VERIFIED: with the patch below applied, a Pascal program compiled to wasm32 prints under node's WASI and its output is byte-identical to the native build. The compiler's own self-host fixedpoint sha is UNCHANGED with and without the patch (c9817ce01cbc both ways), because CPU_WASM32 is never defined while building for any other target."
status: done
owner: "wasm32 lane (narrow grant)"
commit: b78e8f9bc
resolved: 1a0ab35b3
---

# `PXXSysWrite` has no wasm32 arm, so a wasm32 program is silent

- **Type:** bug (RTL / builtin) — **Track A** (`compiler/builtin/**`).
- **Filed:** 2026-08-28 by the wasm32 lane (branch `wasm`), which cannot fix it
  under its own standing rule: a phase needing a shared-file edit files a
  Track A ticket rather than making the edit.
- **Blocks:** every console output on wasm32 — `writeln`, the RTL error
  reporters (`PXXDivZero`, `PXXRangeError`, `PXXNilRef`, …), `PXXDbg`. It is
  the last inch between a wasm module and being able to report its own answer.

## The bug

`PXXSysWrite(fd, buf, count)` (`compiler/builtin/builtinheap.pas:1526`) is a
chain of per-target `{$ifdef}`s over `__pxxrawsyscall`:

```pascal
function PXXSysWrite(fd, buf, count: NativeInt): Int64;
begin
  Result := 0;
{$ifdef CPUX86_64}  Result := __pxxrawsyscall(1,  fd, buf, count); {$endif}
{$ifdef CPU_I386}   Result := __pxxrawsyscall(4,  fd, buf, count); {$endif}
{$ifdef CPU_ARM32}  Result := __pxxrawsyscall(4,  fd, buf, count); {$endif}
{$ifdef CPUAARCH64} Result := __pxxrawsyscall(64, fd, buf, count); {$endif}
{$ifdef CPU_RISCV32} Result := __pxxrawsyscall(64, fd, buf, count); {$endif}
end;
```

There is no `CPU_WASM32` arm, and there cannot be one of this shape: wasm has
no syscall instruction. So on wasm32 the function returns its initialiser —
zero — having written nothing, and **reports success while doing so** (a
0-byte short write is not an error). This is the same failure shape as
`bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero`, one
function along: an ifdef chain that fails OPEN.

The consequence is a program that compiles cleanly, lowers correctly, runs to
completion, and prints nothing. Nothing anywhere reports a problem.

## What is already in place

Nothing else is missing. As of `3f99f2034` on branch `wasm`:

- `IR_WRITE` / `IR_WRITELN` lower on wasm32, by dispatching to the RTL's
  target-neutral console family (`PXXWriteNL`, `PXXWriteDecW`,
  `PXXWriteCharW`, `PXXWriteBoolW`, `PXXWriteStrMW`, `PXXWriteFrozenW`,
  `PXXWriteCStr`) — the same helpers hosted riscv32 adopted, unchanged.
- The wasm backend lowers `external 'lib' name 'sym'` to a **wasm import**,
  using `ProcLibrary` as the module and `ProcExtName` as the field. Both
  fields were already recorded by the Pascal parser
  (`pasparser_proc.inc:1298`) and read until now only by the ELF writers, so
  no shared file changed to get this.

So the whole path from `writeln` down to `PXXSysWrite` works. Only the last
call does nothing.

## The fix — additive, and measured

Twelve lines, all inside `{$ifdef CPU_WASM32}`:

```pascal
{$ifdef CPU_WASM32}
{ wasm has no syscall instruction: the host is reached through an IMPORT, and
  `external 'lib' name 'sym'` is exactly a wasm import's module/field pair. }
function __wasi_fd_write(fd: NativeInt; iovs: Pointer; iovsLen: NativeInt;
                         nwritten: Pointer): NativeInt;
  external 'wasi_snapshot_preview1' name 'fd_write';
{$endif}

function PXXSysWrite(fd, buf, count: NativeInt): Int64;
{$ifdef CPU_WASM32}
var iov: array[0..1] of Integer; nw: Integer;
{$endif}
begin
  Result := 0;
{$ifdef CPU_WASM32}
  { one iovec: [ptr, len]. WASI returns an errno, not a byte count — the count
    is written to *nwritten. }
  iov[0] := Integer(buf);
  iov[1] := Integer(count);
  nw := 0;
  if __wasi_fd_write(fd, @iov[0], 1, @nw) = 0 then Result := nw
  else Result := -1;
{$endif}
  ... existing arms unchanged ...
end;
```

**Verified with the patch applied locally on branch `wasm`, then reverted:**

```
$ cat hello.pas
program Hello;
begin
  writeln('hello from wasm'); writeln(42); writeln(-7); writeln(True);
end.

$ pascal26 --target=wasm32 hello.pas hello.wasm
$ node --experimental-wasi hello.js hello.wasm     # node:wasi, preview1
hello from wasm
42
-7
TRUE

$ pascal26 hello.pas hello_native && ./hello_native
hello from wasm
42
-7
TRUE
```

Byte-identical to the native build, including the signed case and FPC's
`TRUE` spelling.

**Safety, measured rather than argued:** `make compiler/pascal26` produced the
self-host fixedpoint sha **`c9817ce01cbc` both with and without the patch**.
`CPU_WASM32` is defined only when `--target=wasm32` is selected
(`lexer.inc:987`), so the arm is invisible to every other target — the
compiler's own binary is unchanged byte for byte. There is no `-O` level or
target at which this can alter existing codegen.

## Why the wasm32 lane did not just commit it

`compiler/builtin/builtinheap.pas` is a shared file. Branch `wasm`'s standing
rule (`devdocs/dev/wasm/CHARTER.md`) is that a phase needing a shared-file edit
files a Track A ticket and brings the shape, not the patch — even when the
patch is proven and provably inert elsewhere. The exception would be a
combined-track assignment, which this lane does not hold.

## Notes for whoever takes it

- `fd` stays a parameter, so `PXXSysWrite(2, …)` — the debug and error paths —
  works for free once this lands.
- `PXXSysRead` (`builtinheap.pas:1505`) has the identical hole and the
  identical fix shape via `fd_read`. It is not filed separately because
  nothing on wasm32 reads yet; fold it in if it is convenient, or leave it.
- Declaring the import costs nothing for programs that never write: the wasm
  backend emits an import only for an external routine that is actually
  **called**, which matters because a wasm host must supply every declared
  import or instantiation fails.
- Once this lands, `test/wasm/check_write.sh` on branch `wasm` will FAIL by
  design — it asserts writeln's silence as the current known limitation. That
  failure is the signal to replace the assertion with a real native-vs-wasm
  diff of the output.

## Resolution — 2026-08-28

Fixed by the wasm32 lane under a **narrow grant** from the coordinator, rather
than by a Track A holder, on the strength of one measurement: the property
Track A's file-and-wait rule exists to protect is that the compiler can
reproduce itself, and the evidence offered here **is** that property stated
directly — `make compiler/pascal26` produces the same self-host fixedpoint sha
with and without the change, because `CPU_WASM32` is defined only under
`--target=wasm32` (`lexer.inc:998`). Re-verified on the tree actually pushed
(`ea689da902bb` both ways), `gate.sh quick` GREEN.

**The framing in the original report was one level too shallow**, and the
coordinator's independent check is what sharpened it. `Result := 0` is assigned
*before* the ifdef chain and the chain has no terminal `else`, so the defect is
not "wasm32 is missing from a list" — it is that **the list fails OPEN**. A
target with no arm reports *"wrote nothing, and no error"*, which is
indistinguishable from a successful zero-length write. That is a generator
shape, not a typo: the same day, a `{$ifdef}` chain of 34 arms with no final
else was filed against Track P for silently ignoring a compiler directive. Two
instances of one class in one day.

`HeapMmap` (`bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero`,
p70) is the third instance and was deliberately **not** granted: its fix adds a
BSS arena and a size constant — new storage in a file every target compiles —
so the sha-identity argument would be a weaker claim about a larger change. The
line was drawn at the strength of the evidence, not the ticket's priority.

## Log
- 2026-08-29 — fix landed as commit b78e8f9bc (`fix(A): PXXSysWrite gets its
  wasm32 arm — a WASI fd_write import`); the ticket move landed separately as
  commit 1a0ab35b3. Both are ancestors of origin/master, verified with
  `git merge-base --is-ancestor`.
- 2026-08-29 — this ticket spent a day citing `resolved: PENDING-COMMIT`, a
  field **no tool reads**: the citation machinery's frontmatter spelling is
  `commit:` (`progress.py:99`), and only 16 of 2642 done tickets ever used
  `resolved:`. So `progress.py pending` never listed this file and
  `sync.sh fill_pending_commits` never filled it. Corrected to `commit:` above.
