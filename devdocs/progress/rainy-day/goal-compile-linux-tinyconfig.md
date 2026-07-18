# 🗼 Lighthouse — boot a Linux tinyconfig kernel built with PXX's C frontend

- **Type:** goal (lighthouse / end-goal — NOT a sprint ticket)
- **Track:** C (C frontend) + A (backend/ELF/codegen where noted)
- **Status:** rainy-day
- **Opened:** 2026-07-18
- **Nature:** a fixed point on the horizon to steer by, not a task to schedule.
  Attempting it will avalanche into many concrete tickets; those are the work,
  this is the bearing. Do not "start" this ticket — sub-tickets get crafted
  when we get there.

## The goal

PXX (as `CC=pxx` in the standard kernel make toolchain) compiles an x86-64
**tinyconfig** Linux kernel — mitigations off, frame-pointer unwinder, GNU
`as`+`ld` doing assemble/link — and the resulting `vmlinux`/`bzImage` **boots
to init in qemu**. The kernel is the hairiest GNU-C corpus in existence; the
point is the same as the FPC lighthouse
(`goal-compile-fpc-compiler.md`): conformance proven at industrial scale, this
time on the C/GNU side.

## Strategic decisions (settled in the 2026-07-18 gap analysis)

These shape everything below; they are why the scope is bounded:

1. **Be a `.o` producer in the standard toolchain, not a whole-program
   compiler.** The kernel is thousands of separately-compiled TUs linked by
   GNU `ld` against `vmlinux.lds`. We do NOT reimplement that: emit object
   files (`--emit-obj` already exists), let the kernel's own Makefile, `as`,
   and `ld -T` do their jobs. Bonus: per-TU bisection — mix gcc-built and
   pxx-built `.o`s to isolate miscompiles.
2. **Emit `.s` text and let GNU `as` assemble (at least for this target).**
   Kernel inline-asm strings are full of assembler directives
   (`.pushsection .altinstructions`, `.popsection`, `.long`, macros). With a
   text-asm emission path, inline asm reduces to string paste + operand
   substitution + constraint-driven register choice — the directives are
   `as`'s problem, we never parse AT&T ourselves.
3. **Config the hardening away.** objtool/ORC, retpoline, kCFI, SLS, stack
   protector are all off-able (`CONFIG_UNWINDER_FRAME_POINTER=y`,
   `CONFIG_MITIGATIONS=n`, `CONFIG_STACKPROTECTOR=n`; kCFI is clang-only).
   A boot goal owes none of them.

## Where the C frontend stands (2026-07-18)

Strong ISO-C + light-GNU base, proven on userspace corpora:

- zlib 1.3.1 compiles, program OUTPUT byte-identical to the gcc-built oracle
  (`done/feature-c-corpus-zlib.md`); SQLite and Lua compile and run; csmith
  differential fuzzing live (Track T); c-conformance 195/0 across x86-64,
  i386, aarch64, arm32, riscv32.
- Working: designated initializers, compound literals, `_Generic` (full
  structural type descriptors), bitfields incl. packed layout, VLAs, alloca,
  varargs, function-pointer declarator zoo, GNU statement expressions
  `({...})`, `packed`/`aligned` attributes, `#pragma pack`,
  `__builtin_expect/clz/ctz/popcount/va_*`.
- Preprocessor: variadic macros, `__VA_ARGS__`, `##` paste with rescan,
  include search paths, LP64 predefines.

## The gap — everything the kernel needs that we lack

Ordered roughly easy → hard. Most items are legwork; one is a real subsystem.

### Preprocessor (each ~an afternoon)
- `__COUNTER__` — kernel headers won't preprocess without it
  (`BUILD_BUG_ON`, `__UNIQUE_ID`, lockdep).
- `#include_next` — kernel/compiler header wrapping.
- `_Pragma(...)` operator; `#pragma once`.
- `__VA_OPT__` — used in newer trees.

### Builtins (mostly trivial)
- `__builtin_offsetof`, `__builtin_unreachable`, `__builtin_choose_expr`,
  `__builtin_types_compatible_p`, `__builtin_memcpy/memset` intrinsics.
- `__builtin_constant_p` — subtle one: kernel relies on it folding to 1 for
  constants to pick immediate-operand asm variants. Conservative always-0
  compiles fine but takes slow paths — acceptable for boot.

### Language / semantics (legwork, days each)
- `typeof` / `__typeof__` — pervasive (`container_of`, `min/max`,
  `READ_ONCE`). Machinery mostly exists via `_Generic`'s type descriptors.
- Flexible array members (`type name[];` trailing member).
- Computed goto / labels-as-values (`&&label`, `goto *p`) — BPF interpreter,
  some fast paths; tinyconfig may dodge most of it.
- `_Atomic` — kernel uses its own asm-based atomics, so likely NOT needed
  for boot; noted for completeness.
- Full pointer-depth ≥ 2 element typing (`not-implemented.md` C-interop gap).
- **Forced inliner for `__attribute__((always_inline))`** — no heuristics,
  no cost model, mechanical call-site substitution. Required for
  *correctness*, not perf: asm-bearing inline helpers need their `"i"`
  immediate constraints const-propagated. (There is currently NO inliner —
  IR pipeline does zero optimization.)

### Attributes (mechanical once named sections exist)
- `__attribute__((section("...")))` — the kernel image IS section attributes
  (`__init`, initcalls, `__ksymtab`, `__ex_table`). Currently only
  `packed`/`aligned` are honored; everything else silently dropped
  (`cparser.inc` attribute skip).
- `weak`, `alias`, `used`, `noinline`, `cold`, `constructor`.

### Object emission / toolchain (Track A; legwork given decision #1)
- More relocation types in the ELF `.o` writer — currently only 4
  (`R_X86_64_PLT32/GLOB_DAT/RELATIVE`, `R_386_GLOB_DAT`); need
  `R_X86_64_64/PC32/32/32S` at minimum.
- Arbitrary named sections — `elfwriter.inc` hardcodes `.text/.data/.bss`.
- Weak/alias/local symbol binding in the symbol table.
- **`.s` text emission path** next to the binary emitter (decision #2) —
  mechanical but real work; also independently useful (debugging, other
  targets).

### THE wall — GNU inline asm constraint engine (weeks, the one subsystem)
`asm`/`__asm__` is currently in the parser's statement *skip list* — zero
support. The kernel is saturated with it. With decision #2 the AT&T/directive
part vanishes; what remains is the genuinely hard core:
- Constraint letters and modifiers: `"r"`, `"m"` (real address modes), `"i"`
  (needs const-prop / forced inlining), `"=&r"` early-clobber, matching
  constraints (`"0"`), `"+m"` read-write.
- Clobber lists incl. `"memory"` (a codegen barrier) and `"cc"`.
- Operand modifiers (`%b0`, `%w1`, `%z2`) and symbolic operand names.
- Integration with register assignment — the one place the kernel meets our
  codegen intimately.
- **`asm goto`** (jump labels / static keys / `__get_user`) — asm with
  branch targets into C labels, incl. the output-operands variant. Moderate
  once the constraint engine exists.

### Kernel codegen gates (bounded, Track A)
- `-mcmodel=kernel` — kernel lives at the top of the address space;
  sign-extended 32-bit addressing (`R_X86_64_32S`). Small if codegen is
  already RIP-relative.
- **Never emit SSE/x87 in kernel code** (`-mno-sse` equivalent) — kernel has
  no FP context. pxx does FP via SSE2; any helper/memcpy-style codegen
  touching XMM must be gated off.
- No red zone (`-mno-red-zone` equivalent) — interrupts trash it.
- `-ffreestanding` mindset: no libc/crtl assumptions, no magic startup.

### Explicitly out of scope (config'd away, per decision #3)
- objtool validation, ORC unwind tables, retpoline, kCFI, SLS, stack
  protector, kernel modules (`=y` everything), non-x86-64 arches, non-tiny
  configs, unpatched-mainline purity (patching the kernel a little is fine —
  tccboot patched 2.4 heavily and still counted).

## Acceptance ladder

1. **Preprocess**: one kernel TU survives `pxx -E` (preprocessor items).
2. **Compile one TU**: an allnoconfig/tinyconfig TU compiles to `.o`
   (typeof, builtins, attributes, sections, relocs).
3. **Link**: full tinyconfig build where pxx compiles a growing subset of
   TUs, gcc the rest — per-TU mix is the bisection tool, not a compromise.
4. **All TUs**: `CC=pxx` for every C file; `as`/`ld` untouched.
5. **Boot**: qemu + `earlyprintk=serial,ttyS0` reaches init. THE bar.

## Risk notes

- The listed features are not the tail — the tail is the thousand small
  divergences the kernel's macro soup will surface, same shape as the
  SQLite/csmith campaigns. The differential-fuzzing + agent-fleet loop that
  crushed those is the mitigation; it is proven.
- Debugging silent miscompiles pre-console is the nasty part: no stdout,
  triple faults. Tooling answer: qemu early serial, plus gcc/pxx per-TU
  bisection from ladder step 3.
- Velocity calibration: clang→kernel took ~a decade, but they insisted on
  zero kernel patches, all configs, all arches. tccboot booted a (patched)
  2.4 kernel in 2004 with far less compiler than we have. At our measured
  pace the honest estimate is **order 1–3 months of focused campaign**, not
  years.

## Relationship to other lighthouses

Sibling of `goal-compile-fpc-compiler.md` — same "conformance at industrial
scale" motive, C-side instead of Pascal-side. Several sub-goals here are
independently valuable regardless of the kernel: `.s` emission, more reloc
types, named sections, `typeof`, the preprocessor items, the forced inliner.
