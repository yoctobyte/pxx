# Exception Implementation Plan

Target: Delphi-compatible `try/except/finally/raise` via `setjmp`/`longjmp`.
No DWARF unwind tables. No destructors. Correct Pascal semantics.

**Status (2026-05-27):** Phase 1 implemented. PXX supports untyped
`try/except` catch-all blocks, optional `else` on that catch-all form,
`raise <expr>`, generic unhandled diagnostics, and
`--no-unhandled-handler` / `-fno-unhandled-handler`. Typed `on` handlers,
`finally`, `raise;`, exception classes, and class/message diagnostics remain
planned below. `Exit` unlinks active Phase 1 frames; `break` and `continue`
inside a protected body are rejected until loop-target unwinding is added.

---

## Syntax supported

```pascal
{ Implemented Phase 1 form }
try
  <statements>
except
  <catch-all statements>
end;

try
  <statements>
except
else
  <catch-all statements>
end;

raise <expr>;

{ Planned forms }
try
  <statements>
except
  on E: EClass do <handler>;   { typed handler }
  else <handler>;               { catch-all }
end;

try
  <statements>
finally
  <cleanup>                     { always runs }
end;

raise ESomeException.Create('msg');
raise;                          { re-raise inside except block }
```

---

## Compiler switch

```
-fno-unhandled-handler    disable default unhandled-exception message
                          (for minimal binaries; exits with code 1 silently)
```

Phase 1 default: unhandled exception prints `Unhandled exception`, then exits
with status 1. Phase 3 extends this to class name and message.

Stored as `Boolean` flag alongside `DebugTrace` / `StrictOverload` in `defs.inc`.

---

## Runtime data structures (emitted into BSS/data by compiler)

### jmp_buf layout (x86-64 Linux, 200 bytes)

Compiler uses its own layout — does NOT link libc setjmp. Emitted inline in asm.

```
jmp_buf:
  [0]   rbx
  [8]   rbp
  [16]  r12
  [24]  r13
  [32]  r14
  [40]  r15
  [48]  rsp
  [56]  rip  (return address)
```

64 bytes total. Smaller than libc's 200-byte version; sufficient since we control
all registers and don't need FP state per-frame (floats not yet implemented).
Expand to include mxcsr/x87 when floats land.

### Exception frame (per try block, on stack)

```
ExcFrame:
  [0]   prev_frame  : pointer   { linked list, NULL = bottom }
  [8]   jmp_buf     : 64 bytes
  [72]  frame_kind  : byte      { 0=except, 1=finally }
```

80 bytes per try block. Stack-allocated at try entry.

### Active frame pointer

One global variable `__exc_top : pointer` (BSS). Points to innermost ExcFrame.
Single-threaded — no TLS needed yet.

### Active exception object

Two globals:
- `__exc_obj  : pointer`   { heap pointer to raised exception object }
- `__exc_cls  : pointer`   { pointer to class descriptor for type matching }

---

## setjmp / longjmp — inline asm (no libc)

Emitted once as internal labels `__frankon_setjmp` / `__frankon_longjmp`.

```nasm
__frankon_setjmp:          ; rdi = pointer to jmp_buf
  mov [rdi+0],  rbx
  mov [rdi+8],  rbp
  mov [rdi+16], r12
  mov [rdi+24], r13
  mov [rdi+32], r14
  mov [rdi+40], r15
  lea rax, [rsp+8]         ; rsp before call
  mov [rdi+48], rax
  mov rax, [rsp]           ; return address = our rip
  mov [rdi+56], rax
  xor eax, eax             ; return 0 = normal path
  ret

__frankon_longjmp:         ; rdi = jmp_buf, rsi = value (always 1)
  mov rbx, [rdi+0]
  mov rbp, [rdi+8]
  mov r12, [rdi+16]
  mov r13, [rdi+24]
  mov r14, [rdi+32]
  mov r15, [rdi+40]
  mov rsp, [rdi+48]
  mov rax, 1               ; setjmp returns 1 = raise path
  jmp qword [rdi+56]
```

---

## Codegen — try/except block

### Enter try

```nasm
  ; allocate ExcFrame on stack
  sub rsp, 80
  mov rdi, rsp             ; ExcFrame address
  ; link into chain
  mov rax, [__exc_top]
  mov [rdi+0], rax         ; prev_frame = old top
  mov [__exc_top], rdi     ; new top = this frame
  mov byte [rdi+72], 0     ; kind = except
  ; call setjmp
  lea rdi, [rsp+8]         ; jmp_buf inside ExcFrame
  call __frankon_setjmp
  test eax, eax
  jnz .except_handler      ; raised → go to handler
  ; fall through → try body
```

### Exit try (normal path, before except)

```nasm
  ; unlink frame
  mov rdi, [rsp+0]         ; prev_frame
  mov [__exc_top], rdi
  add rsp, 80
  jmp .try_end
```

### except handler block (.except_handler)

For `on E: EClass do`:
- Load `__exc_cls`, compare against EClass descriptor pointer
- Match → execute handler body; clear `__exc_obj`/`__exc_cls`; jmp .try_end
- No match → re-raise (call `__frankon_raise` which longjmps to prev frame)

For `else` → unconditional catch-all.

### .try_end

Unlink frame if not already done, continue normal execution.

---

## Codegen — try/finally block

Same frame setup, `frame_kind = 1`.

On both paths (normal and raise) the finally body must run.

### Normal exit from try

```nasm
  ; unlink frame (but run finally first)
  ; ... finally body inline ...
  ; restore __exc_top to prev
  add rsp, 80
```

### Raise path into finally

`__frankon_raise` checks frame_kind:
- If `finally`: execute finally body inline via a call, then continue raising
  (longjmp to prev frame's jmp_buf).

Implementation: raise saves current `__exc_top` prev pointer, runs finally body
(via a label), then re-raises.

---

## Raise

```pascal
raise ESomeException.Create('msg');
```

Codegen:
1. Allocate exception object (heap) — `New` or constructor call.
2. Store ptr in `__exc_obj`, class descriptor in `__exc_cls`.
3. Call `__frankon_raise`.

```nasm
__frankon_raise:
  mov rdi, [__exc_top]     ; current frame
  test rdi, rdi
  jz .unhandled            ; no handler → unhandled path
  cmp byte [rdi+72], 1     ; finally?
  je .do_finally
  ; except frame: longjmp to it
  lea rsi, [rdi+8]         ; jmp_buf
  call __frankon_longjmp   ; never returns
.do_finally:
  ; pop frame, run finally body (call via stored label/ptr), then re-raise
  ; (this requires finally body to be in a sub-procedure or emitted with a
  ;  callable label — see "finally body as internal proc" below)
  ...
.unhandled:
  ; see unhandled section below
```

### Re-raise (`raise;` inside except)

Just call `__frankon_raise` with `__exc_obj`/`__exc_cls` already set.

---

## finally body as internal proc

Problem: finally body must be callable from two paths (normal + raise).

Solution: emit finally body as a nested internal label, called via `call` on both
paths. No closure needed — it's in the same stack frame scope.

```nasm
  jmp .finally_done        ; skip over body during normal flow
.finally_body:
  ; ... user finally statements ...
  ret
.finally_done:
  ; normal path: call .finally_body
  call .finally_body
  ; ... continue ...
```

---

## Unhandled exception path

### With handler enabled (default)

Emit call to `__frankon_unhandled`:

```nasm
__frankon_unhandled:
  ; write class name + message to stderr (fd=2)
  ; syscall write(2, "Unhandled exception: ", 21)
  ; write class name from descriptor
  ; write '\n'
  ; exit(1)
```

Class name stored in class descriptor (already planned for OOP).
Message: exception object has a `Message` field (AnsiString).

### With -fno-unhandled-handler

Skip `__frankon_unhandled` entirely. Emit:

```nasm
  mov rax, 60              ; SYS_EXIT
  mov rdi, 1
  syscall
```

Controlled by `NoUnhandledHandler: Boolean` flag. Checked at codegen time —
if flag set, `__frankon_unhandled` is never emitted into the binary.

---

## Exception class hierarchy

Minimal root class `Exception`:
```pascal
type
  Exception = class
    Message: AnsiString;
    constructor Create(const msg: AnsiString);
  end;
```

Compiler built-in or user-definable (Delphi-compatible).

Class descriptor needs: class name string, parent descriptor pointer.
Type matching in `on E: EClass` walks the parent chain.

---

## Implementation phases

### Phase 1 — infrastructure (no class hierarchy yet)
- Implemented: tokens and lexer entries for the exception grammar.
- Implemented: `__exc_top`, `__exc_obj`, and reserved `__exc_cls` BSS state.
- Implemented: inline integer-state `setjmp` / `longjmp` and raise dispatch.
- Implemented: untyped catch-all `try/except`, with or without explicit `else`.
- Implemented: `raise <expr>` and generic unhandled diagnostics.
- Implemented: `NoUnhandledHandler` flag and both CLI option spellings.

### Phase 2 — finally
- Codegen for `try/finally`
- finally-body-as-internal-proc pattern
- raise-through-finally chain

### Phase 3 — typed handlers + class hierarchy
- `Exception` base class in compiler builtins
- Class descriptor with name + parent
- `on E: EClass do` type matching (walk parent chain)
- Re-raise (`raise;`)
- `__frankon_unhandled` prints class name + Message

### Phase 4 — float integration
- Expand `jmp_buf` to 72 bytes (add mxcsr)
- SIGFPE handler → calls `__frankon_raise` with `EFloatError`

---

## Files to touch

| File | Change |
|------|--------|
| `compiler/defs.inc` | Add `tkTry/Except/Finally/Raise/On`, `NoUnhandledHandler: Boolean`, ExcFrame layout constants |
| `compiler/lexer.inc` | Register 5 new keywords |
| `compiler/parser.inc` | Parse `try/except/finally/raise/on` statements |
| `compiler/codegen.inc` | Emit setjmp/longjmp stubs, frame push/pop, raise, unhandled handler |
| `compiler/symtab.inc` | Built-in `Exception` class descriptor (Phase 3) |
| Makefile / CLI | `--no-unhandled-handler` / `-fno-unhandled-handler` flag |

---

## Size impact

| Component | Bytes (approx) |
|-----------|---------------|
| `__frankon_setjmp` | ~30 |
| `__frankon_longjmp` | ~25 |
| `__frankon_raise` | ~40 |
| `__frankon_unhandled` (default on) | ~80 + strings |
| `__frankon_unhandled` (-fno-unhandled-handler) | 0 |
| Per try/except block (stack frame) | 80 bytes stack, ~20 bytes code |

No try in source = none of the above stubs emitted (except possibly unhandled).
With `-fno-unhandled-handler` and no try blocks: zero overhead vs current.
