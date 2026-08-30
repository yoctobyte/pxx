---
slug: bug-wasm-hosted-compiler-faults-on-a-garbage-string-handle-in-the-unit-resolver
title: "The wasm-hosted compiler faults on a non-nil garbage AnsiString handle in ParseUsesUnitBody"
track: A
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-08-30
found-by: frankwasm (running compiler.pas under node's WASI)
summary: "compiler.pas now lowers COMPLETELY for wasm32 (3780 of 3780 bodies) and the module validates, instantiates and answers --version / --where / usage. Compiling anything faults: `memory access out of bounds` in PXXStrSetLen, reading [oldData-8] where oldData is the non-nil garbage contents of ParseUsesUnitBody's `path` slot, reached through PyTryHostHeader -> ConcatThree. Five plausible causes ruled out by measurement. Wasm-only; the same source is what the native compiler runs on every build."
---

# What runs, so the boundary is clear

Branch `wasm`, module built from `compiler/compiler.pas` with
`--target=wasm32 -Fulib/rtl/platform/wasi`:

* `wasm32: 3780 of 3780 bodies lowered — op coverage is complete for this
  program.` No refusals.
* `wasm-validate` passes on the 6.5 MB module.
* Under `node --no-warnings test/wasm/wasihost.js`, it instantiates and answers
  `--version`, `--where` and the bare-invocation usage text, correctly.

So this is not a lowering gap and not a missing feature. It is a wrong value at
run time, which is the expensive kind (`devdocs/dev/debugging-playbook.md`).

# The fault

Sandbox staged with the source tree the compiler resolves against (its roots are
CWD-relative when argv[0] is a bare name — `--where` confirms). Input:

```
program t; begin end.
```

```
RuntimeError: memory access out of bounds
  func[100]  <PXXStrSetLen>
  func[1867] <ConcatThree>
  func[1883] <PyTryHostHeader>
  func[1896] <ParseUsesUnitBody>
  func[1895] <ParseUsesUnit>
  func[1897] <ParseUsesUnitAmbient>
  func[1927] <ParseProgram>
```

The trapping instruction, from `wasm-objdump -d` at the reported offset, is
inside PXXStrSetLen's `if oldData <> nil then oldLen := PWord(oldData - 8)^`:

```
local.get 2 ; i32.const 36 ; i32.add ; i32.load   ; oldData, from its frame
i64.extend_i32_u ; i64.const 0 ; i64.add
i32.const 8 ; i64.extend_i32_s ; i64.sub ; i32.wrap_i64
i32.load 2 0                                      ; <-- traps
```

`strSlot` is `@path` in ParseUsesUnitBody, handed down as a `var` parameter
through PyTryHostHeader to ConcatThree's `SetLength(dst, ...)`. So **`path`'s
slot holds a non-nil pointer that is not a managed-string handle** — the guard
sees a non-zero value and dereferences it.

It is not the first use of that slot: `test/wasm/wasitrace.js` (added with this
work) shows the resolver completing its whole `.pas`/`.pp`/`.c`/`.h` probe chain
through the same `path` variable first, so the slot was valid and then became
garbage.

An earlier symptom of what is very likely the same defect: with a unit present
in the sandbox, the fault instead lands in `CaseEqual`'s `Length(s1)` — again a
non-nil garbage handle, again reached through the unit resolver.

# Ruled out BY MEASUREMENT, not by argument

Each of these was a live hypothesis and each was tested; none is the cause.

| hypothesis | how it was ruled out |
| --- | --- |
| shadow-stack overflow corrupting data | the stack was moved below the globals so an overflow TRAPS (dc37e13e9); the fault is unchanged and lands mid-string, not in a prologue. Frames also fit: ParseUsesUnitBody is 11216 bytes against 1 MiB. |
| dynamic-array growth carrying managed record fields (the token table) | a probe growing `array of record Kind: Integer; SVal: AnsiString; N: Integer end` from 4 to 201 entries agrees with native, 0 bad. |
| `var`-parameter `SetLength` chains | a probe reproducing ConcatThree's exact shape — 8 managed locals, a dirtied stack beforehand, two `var` hops — agrees with native. |
| the new `LoadFile` arm writing through the wrong slot | probed with the destination as a local, a global, a `var` parameter, and after a miss; all agree with native (`test/wasm/check_loadfile.sh` covers the first). |
| short prologue zero-init | ParseUsesUnitBody's prologue emits 77 zero-stores against 24 declared managed locals in the first half of its var block. Generous, not short. |

# Where to look next

The slot is written correctly and later becomes wrong, so the question is WHO
ELSE writes there. Two shapes worth measuring before anything else:

1. **A release that frees a handle still held by another slot**, leaving a
   dangling pointer rather than nil — this is what a non-nil garbage handle
   looks like, and it is the failure mode `-dPXX_HEAP_DEBUG` was built for on
   the native side (freed bytes become `$DD`). There is no equivalent on wasm
   yet; adding one to PXXFree under a define would answer this directly and is
   probably the cheapest instrument to build.
2. **Frame-slot aliasing.** ParseUsesUnitBody has an 11216-byte frame and the
   backend allocates scratch through `WasmAddLocal` per SITE — a wasm local, not
   a frame slot, so that is not it — but `WasmStrScratchPush`/`Pop` and the
   shadow-stack spill slots ARE frame memory, and a mis-sized reservation would
   overlap a declared local. This function has more managed locals than anything
   in the test suite.

# What is NOT blocked by this

The lane's own gate: `test/wasm/check_all.sh` is 32/32 green, and every slice
runs its program under WASI and diffs against the native build. This is a bug
that only a program of compiler.pas's size has reached.

Nothing here is a Track U question. It is a measured defect with a repro.
