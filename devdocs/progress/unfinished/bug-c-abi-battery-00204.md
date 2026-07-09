---
prio: 55  # auto
---

# c-testsuite 00204: calling-convention battery (structs 1..17 bytes by value, HFAs, varargs)

- **Type:** bug (umbrella — run AFTER the other init/float tickets). Track C/A.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00204 (527 lines): passes/returns structs of every size 1..17, HFA float
  structs, mixed varargs, by value AND through `...`. Output mismatch from the
  first "Arguments:" block (stack-passed args print garbage).
  Known-adjacent: v180 struct-by-value fix covered 8-byte records; this battery
  covers every size class + return-in-registers + varargs-of-struct.

## Approach
Re-run after bug-c-init-designated-and-nested + bug-c-float-single-precision
land (its structs use string/float inits); then diff section by section vs
.expected and file/fix per size class. x86-64 SysV first, then cross targets.

## Gate
Drop 00204.c from test/c-conformance/pxx.skip; runner green.


## Triage 2026-07-07
00204 COMPILES; the first "Arguments:" section prints BLANK where the struct
fields (`struct s1 { char x[1]; } = {"0"}` ... s17) should appear — so passing a
struct BY VALUE drops its data across the size classes. This is the whole
struct-by-value ABI battery (1..17-byte structs, HFA float structs, structs
through `...`), not a single bug. v180 fixed the 8-byte case; this exercises
every class + register-return + varargs-of-struct. Large, deep ABI work per size
class (SysV first, then cross) — focused multi-step session.

## 2026-07-08 (fable-c) — %Lf landed; scope narrowed to HFA float structs
Progress on 00204 after the init/float tickets cleared:
- **%Lf/%Le/%Lg** (long double, printf) — FIXED (crtl vformat now accepts the
  `L` length modifier; long double == double in pxx so it formats as %f).
  Cleared the long-double scalar-varargs block (lines ~27-64).
- **Verified already working**: struct-by-value <= 8 bytes (int/char members),
  struct RETURN <= 8 bytes, char-ARRAY structs (e.g. `struct{char s[9]}` by
  value + return) — the v180 struct-by-value arc covers these.
- **REMAINING core gap = HFA (homogeneous float aggregate) ABI**: a struct of
  floats/doubles (`struct{float x,y;}`) must pass/return in XMM registers per
  SysV (SSE-class eightbytes), but pxx classifies every aggregate as INTEGER
  (GP registers) -> `mkff()`/`useff()` read garbage
  (13743900737.0 instead of 34.1). This is the bulk of the residual 00204
  diff (the `NN.N,NN.N` and `0.0,0.0` blocks). Needs SysV eightbyte
  classification (INTEGER vs SSE per 8-byte chunk), XMM argument-register
  assignment for SSE eightbytes, and struct return in xmm0(:xmm1). Deep
  Track A codegen; the true "hardest slice" this ticket flagged. Left skipped
  under this ticket; the %Lf fix is committed separately.

## Scope sharpened 2026-07-09 (cfront-agent) — gap is VARARGS-only, non-varargs HFA works
Retested at HEAD (217/220 conformance). Confirmed by direct repro vs gcc oracle:
- **Non-varargs HFA float aggregates ALL WORK** — `struct{float x,y}`, 3-float,
  4-float, and `struct{double a,b}` pass/return byte-identical to gcc via direct
  calls (`useff(f)`, `use4(b)`, returned `mkff()`). The 2026-07-08 note that HFA
  reads garbage is STALE — direct-call SSE-class aggregate ABI is correct now.
- **The entire remaining 00204 diff is the VARARGS path.** Every failing section
  (char-array structs at expected line 66, float HFA at line 69+) goes through
  `myprintf(const char *fmt, ...)` and `va_arg(ap, struct T)` (source lines 245-304).
  So the gap is exactly: (1) passing a struct BY VALUE as a VARIADIC argument
  (classify eightbytes → SSE in xmm0..7 / INTEGER in GP, overflow to stack, and
  bump the al vector-count), and (2) `va_arg(ap, struct T)` reading a struct back
  from the register-save-area / overflow per its eightbyte classes. Both
  INTEGER-class (char[9]) and SSE-class (float HFA) variadic structs fail.

This is a focused variadic-ABI + va_arg(struct) feature, NOT a broad struct-ABI
rewrite. Non-varargs struct-by-value (all size classes) + HFA are done.

## Codegen map + minimal repro 2026-07-09 (cfront-agent) — released for a focused session
Minimal repro (fails vs gcc): a variadic fn that `va_arg`s a struct —
```c
struct FF{float x,y;}; struct S9{char s[9];};
void vp(int n,...){ va_list ap; va_start(ap,n);
  struct FF f=va_arg(ap,struct FF); struct S9 c=va_arg(ap,struct S9);
  printf("%.1f,%.1f %s\n",f.x,f.y,c.s); va_end(ap); }
// vp(1,f,c) -> pxx "ff -0.0,0.0 s9 <garbage>"; gcc "3.1,4.4 ABCDEFGH"
```
Root: `va_arg(ap, struct T)` (cparser.inc:506-557) picks `__pxx_va_arg_gp`
(TypeIsFloat(tyRecord)=false), which returns a pointer to ONE 8-byte GP slot;
then AN_DEREF with ASTTk=tyRecord. So a struct is read as a single 8-byte scalar
— wrong for >8-byte structs (S9=9B needs 2 slots) and it doesn't copy RecSize.
The variadic CALLER side (IR_CALL arg marshalling, ir_codegen.inc:3319-3360) also
treats a struct arg as a single 8-byte GP value.

Since 00204 is all-pxx (its `myprintf` is pxx, structs never cross to glibc),
the fix does NOT need true SysV SSE/HFA classification — it needs the variadic
struct CALLER and `va_arg(struct)` to be mutually consistent through the GP save
area: caller places a struct's ceil(RecSize/8) eightbytes into consecutive GP
regs/overflow; `va_arg(struct T)` returns a pointer to the next ceil(RecSize/8)
GP slots and copies RecSize bytes (AN_DEREF tyRecord must memcpy RecSize).
(Non-varargs struct-by-value + HFA already work — see prior note.)

Codegen sites (x86-64): IR_CALL arg classify ir_codegen.inc:3319-3360 (struct→GP
single 8B today); float XMM machinery reusable at 3442/3481; struct return via
hidden dest symtab.inc:5169. va_arg helpers `__pxx_va_arg_gp/_fp/_cross*` +
`__pxx_va_start_impl` (cparser.inc:506-639). Field walk: UClsFBase/UClsFCount/
UFldTk/UFldOff_ (symtab.inc). Bounded to x86-64 first; cross backends untouched.

Released to unfinished (scoped, not landed — NO compiler change this session, so
the self-host gate is untouched). Next picker: a focused variadic-struct session.

## COPY-PASTE KICKOFF PROMPT (fresh session, variadic struct passing)

You are Track A+B+C (compiler core + C frontend), on master, sole-A confirmed
(you may self-resolve shared-internals changes). Task: implement C variadic
struct passing + `va_arg(struct)` and turn c-testsuite 00204 green. Read this
ticket first — scope, repro, root cause, and codegen map are already settled;
do NOT re-derive them.

VERIFIED FACTS (do not re-check):
- Non-varargs struct-by-value (all size classes) AND HFA float aggregates
  (`struct{float x,y}`, 3/4-float, `struct{double a,b}`) already pass/return
  byte-identical to gcc via direct calls. The 2026-07-08 "HFA reads garbage" note
  is STALE. Do NOT touch the direct-call struct ABI.
- The ENTIRE 00204 diff is the VARARGS path: passing a struct BY VALUE through
  `...` and reading it back with `va_arg(ap, struct T)`. Both INTEGER-class
  (char[9]) and "SSE-class" (float HFA) variadic structs fail.
- 00204 is ALL-PXX (its `myprintf` is pxx; structs never cross to glibc). So the
  fix needs the variadic CALLER and `va_arg(struct)` to be MUTUALLY CONSISTENT
  through the GP register-save-area — it does NOT need true SysV SSE/HFA
  eightbyte classification. Keep pxx's "structs travel in GP" convention.

MINIMAL REPRO (fails today; gcc prints "3.1,4.4 ABCDEFGH"):
    #include <stdarg.h>
    extern int printf(const char*,...);
    struct FF{float x,y;}; struct S9{char s[9];};
    void vp(int n,...){ va_list ap; va_start(ap,n);
      struct FF f=va_arg(ap,struct FF); struct S9 c=va_arg(ap,struct S9);
      printf("%.1f,%.1f %s\n",f.x,f.y,c.s); va_end(ap); }
    int main(){ struct FF f={3.1f,4.4f}; struct S9 c={"ABCDEFGH"}; vp(1,f,c); return 0; }
  pxx today: "ff -0.0,0.0 s9 <garbage>".

ROOT CAUSE:
- `va_arg(ap, struct T)` (cparser.inc ~506-557): TypeIsFloat(tyRecord)=false, so
  it picks `__pxx_va_arg_gp` which returns a pointer to ONE 8-byte GP slot, then
  wraps `AN_DEREF` with ASTTk=tyRecord. A struct is thus read as a single 8-byte
  scalar — wrong for >8B structs (S9=9B needs 2 slots) and it never copies
  RecSize bytes.
- Caller side (IR_CALL arg marshalling, ir_codegen.inc ~3319-3360): a struct arg
  is treated as a single 8-byte GP value; a >8B variadic struct arg is not split
  into consecutive GP slots.

APPROACH (x86-64 first; keep GP-consistent, no SSE classification):
1. va_arg(struct T): when vt=tyRecord, return a pointer to the next
   ceil(RecSize/8) GP slots (advance gp_offset / overflow_arg_area by that many
   8-byte slots, honoring the reg-save-area→overflow transition the scalar path
   already implements), and copy RecSize bytes to a result temp. Verify AN_DEREF
   with ASTTk=tyRecord actually memcpy's RecSize (if not, materialize a temp +
   record-copy). May need a size-parametrized helper (mirror
   `__pxx_va_arg_cross32`'s size arg) or a new `__pxx_va_arg_agg(ap, size)`.
2. Variadic CALLER: a struct passed as a variadic arg must place its
   ceil(RecSize/8) eightbytes into consecutive GP arg regs (rdi..r9), overflow to
   the stack, so they land contiguously in the callee's GP save area / overflow.
   Ensure the AL vector-count (ir_codegen.inc ~3481) is unaffected (structs use GP,
   contribute 0 to AL).
3. Confirm caller and va_arg agree on slot count and ordering for 1-slot (FF, 8B)
   and 2-slot (S9, 9B) structs. Test the minimal repro FIRST, then 00204.

CODEGEN SITES (investigator map):
- IR_CALL arg classify: ir_codegen.inc 3319-3360 (struct→single-8B-GP today);
  XMM machinery 3442/3481 (leave for scalars); struct return via hidden dest
  symtab.inc 5169.
- va_arg helpers: `__pxx_va_arg_gp/_fp/_cross/_cross32`, `__pxx_va_start_impl`
  (cparser.inc 506-639). The GP helper's overflow logic is the model to extend.
- Field walk (if needed): UClsFBase/UClsFCount/UFldTk/UFldOff_ (symtab.inc).
- RecSize / RetViaHiddenDest (symtab.inc 1534).

GATE: minimal repro matches gcc; drop 00204 from test/c-conformance/pxx.skip;
`make test-c-conformance` = 218 pass / 0 fail / 2 skip; self-host fixedpoint
BYTE-IDENTICAL; quick tier + lua/core green; cross targets unaffected (this is
x86-64-only — do NOT edit ir_codegen386/arm32/aarch64/riscv32/xtensa). If any
codegen changed the stable binary needs it: `make stabilize` then `make pin`
(watch pin.log; verify VERSION advanced). Commit with a regression test
(test/cvariadic_struct_bNNN.c → exit 42, wire into test-core), update this
ticket, board-md, push.

LANDMINES:
- NO literal `{` or `}` inside `{ }` comments — nested comments are ON, a braced
  char in a comment desyncs the self-host lexer ("unexpected character"). Reword
  to prose. (This caused two bogus "self-host-fragile" reverts before.)
- `ErrOutput` is unavailable in this codebase for debug — use plain `writeln`
  (compile-time output to stdout) and remove before the byte-identical build.
- After any AST/marker change, verify one-step self-host convergence; a 2-step
  converge = a reseed slipped in (usually the comment-brace landmine, not a real
  codegen reseed).
