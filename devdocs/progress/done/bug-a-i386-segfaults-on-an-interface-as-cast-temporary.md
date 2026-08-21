---
track: A
prio: 60
type: bug
blocked-by: []
summary: "i386 SIGSEGVs (rc=139) on an interface `as`-cast temporary and on a single-pointer interface ABI shape. Four tests crash mid-output on i386 alone — arm32, aarch64, riscv32 and x86-64 all print the correct answer. A crash, not a wrong value, so it is loud; it is also the only cross target that dies."
status: done
owner: claude-A
---

# i386 segfaults on an interface as-cast temporary

- **Track A** (`compiler/ir_codegen386.inc` — the interface as-cast temp
  lifetime and the single-pointer interface ABI).
- Found 2026-08-21 by the 53-test dyn-array + interface cross differential.

## Measured

Four tests, i386 ONLY. Every other target (x86-64, arm32, aarch64, riscv32)
matches.

| test | i386 | others |
| --- | --- | --- |
| `test_interface_as_cast_retains` | **rc=139**, no output | 7/7 |
| `test_interface_ascast_temp_lifetime` | **rc=139** after `in P w=` | full output |
| `test_interface_mainbody_ascast_temp` | **rc=139** after `cast=` | `cast=107 / after nil / destroy 7` |
| `test_interface_single_pointer_abi_b337` | **rc=139** after `size-is-one-word: TRUE` | full output |

The first three all die at the point where an `as`-cast TEMPORARY is next
touched — the third gets as far as printing `cast=` and dies before the value.
The fourth dies at the second use of a single-word interface value. That is one
suspect, not four: an as-cast temp's slot on i386.

## Where to start

The three as-cast tests share the shape `(obj as IFoo)` producing a hidden
temp that must be retained for the expression's extent and released after. On
x86-64 that temp is a frame slot with a scope-exit release; check what i386's
IR_AS_CAST lowering does with the slot — in particular whether it writes a
handle into a slot the epilogue then releases at a DIFFERENT width, since i386's
"fat slot" model lays out 8-byte slots and reads only the low 4 bytes.

`test_interface_mainbody_ascast_temp` is the cheapest repro: it is a main-body
program, it prints one line before dying, and the line it prints is correct.

Do not reason about the slot — dump it. `PXXDBG=a.ir:<proc>` for the three that
have a proc, and `-g -O2` + gdb under qemu-i386 for the main-body one; the
playbook is `devdocs/dev/debugging-playbook.md`.

## Gate

All four tests matching the native output under `tools/run_target.sh i386`; the
53-test dyn-array + interface cross differential no worse than baseline;
self-host fixedpoint + `tools/gate.sh quick`.

## Resolution (2026-08-21)

**The as-cast temp was innocent.** The "one suspect, not four" reading above was
right about the count and wrong about the suspect: all four tests die for the
same reason, and it has nothing to do with a temp's lifetime, a scope-exit
release, or a slot width. It is `IR_LOAD_SYM` in `compiler/ir_codegen386.inc`.

### What it actually was

i386 returned the **slot ADDRESS** for *every* `tyRecord` in value position. The
comment sitting on that arm claimed it mirrored x86-64. It does not — x86-64
returns the address only for a record that is genuinely too big to live in a
register pair, and loads the value for anything that fits.

A **COM interface is a one-word record** (`tyRecord` with
`RecId >= REC_UCLASS_BASE`, the FPC single-pointer ABI). So on i386 — and on
i386 alone among five backends — `PXXIntfAddRef` was handed the address of the
slot where every other target hands it the handle. One extra level of
indirection, all the way down: the RTTI walk read `[instance-8]` as a
class-RTTI pointer, got `16`, and dereferenced `0x60`.

gdb under `qemu-i386 -g` on the main-body repro, which is what settled it:

```
0x804e5cf:  mov (%eax),%eax     eax = 0x60      <- SIGSEGV
backtrace:  PXXIntfIMTOf  <-  PXXIntfAddRefRaw  <-  PXXIntfAddRef
rtti = 16
```

`rtti = 16` is the tell: 16 is `PXXH_RTTI_PARENT`-adjacent junk, not a pointer —
it is what you read when you dereference a slot address instead of a handle.

### The fix

Split the blanket `tyRecord` arm in `IR_LOAD_SYM` into the two cases x86-64
already distinguishes:

```pascal
if (tk = tyRecord) and
   (Syms[si].IsArray or (RecSize(SymTR[si].RecId) > 8)) then
```

Only a record larger than one machine pair (or an array of records) yields its
slot address; everything else — the one-word interface included — falls through
to the ordinary 64-bit/record load below, which is what the other four backends
have always done. Global / by-ref-param / local addressing in the big-record arm
is unchanged, just moved.

This is the `normalise-dont-special-case` shape again: i386 had a second path
for a concept the other targets serve with one, and the second path is the one
that stayed broken.

### Verified

- All four tests match native under `tools/run_target.sh i386`
  (`test_interface_as_cast_retains`, `test_interface_ascast_temp_lifetime`,
  `test_interface_mainbody_ascast_temp`, `test_interface_single_pointer_abi_b337`).
- 53-test dyn-array + interface differential over i386/arm32/aarch64/riscv32:
  **broke=0 fixed=4** — the four above, on i386.
- **194-test record + variant sweep on i386**, run BOTH ways (this change in,
  and with `ir_codegen386.inc` stashed and the compiler rebuilt): 101
  disagreements either way, `broke=0 fixed=0 changed=0`. Broadening the record
  load is a no-op across the entire record/variant surface — the pre-existing
  101 are unrelated i386 record gaps, untouched by this.
- `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit 64e5f22d8.
