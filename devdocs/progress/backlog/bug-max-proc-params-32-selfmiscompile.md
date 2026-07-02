# Bumping MAX_PROC_PARAMS 16→32 makes the compiler segfault (self-miscompile?)

- **Type:** bug (compiler robustness / capacity) — Track A
- **Status:** backlog
- **Opened:** 2026-07-02, found while fixing
  [[bug-c-vararg-vastart-named-fp-stack]].

## Symptom

Raising `MAX_PROC_PARAMS` from 16 to 32 (defs.inc, plus `TProc.Params:
array[0..31]` and the cparser per-param locals) builds and SELF-VERIFIES
byte-identically — but the resulting compiler segfaults (wild jump to
~0x4000bd, corrupt-looking stack) when compiling a C file with a 17-parameter
function definition. With the cap back at 16 the same source gets the new
clean "too many parameters" error and everything is green.

## Notes / suspicions

- The wild-jump crash smells like a real self-miscompile interaction with the
  GROWN TProc record (16 extra TParam entries, each holding a managed
  AnsiString Name — whole-record copies, managed-field walkers, or a frame
  size crossing some limit are all candidates). Self-host byte-identical does
  NOT clear it: the compiler's own source never exercises >16-param C parsing.
- Also note `Params: array[0..31]` had to be a literal — const-expr bounds
  (`0..MAX_PROC_PARAMS-1`) are not supported in record field declarations
  (parser gap, possibly worth its own small ticket).
- Wanted eventually: sqlite-class C code plausibly exceeds 16 params;
  [[feature-dynamic-compiler-tables]] is the systemic answer, but a working
  32 cap is the cheap interim once this crash is understood.

## Acceptance

MAX_PROC_PARAMS = 32 builds a compiler that compiles a 17..32-param C function
definition correctly (extend test/cvararg_stack_spill.c); root cause of the
wild jump identified and fixed or explained.

## Investigation (2026-07-02, rr session — root-cause narrowed, not yet fixed)

Recorded the crash under rr. It is NOT a wild jump: rip 0x4000bd is inside the
emitted AnsiStrRelease stub (`decq -0x10(%rax)`) with a garbage handle
`rax = 0xffffffff`. Caller chain: the release fires inside **RegisterProc**
(called from ParseCSubroutine registering the 17-param function), i.e. the
release-of-old in `Procs[ProcCount].Params[i].Name := pnames[i]`.

Key evidence: the string slot address is **byte-misaligned** (rdi =
0x31d89e9, ≡1 mod 8), and dumping memory around it shows values shifted by
one byte (a real heap handle stored starting at ...e9 with a stray 00 low
byte at ...e8; repeated `00 ff ff ff ff 00` patterns = int32 -1 writes at
odd offsets). So TParam's field offsets land at odd addresses AND two
access paths appear to disagree about the stride/base by one byte — the
released "handle" 0xffffffff is an int32 `SymIdx := -1` read through a
Name-slot offset computed differently by another path.

Suspicion: the compiler's own layout of an ARRAY-of-record FIELD inside a
record (`Params: array[0..31] of TParam` where TParam has an odd unpadded
size) — stride vs field-offset disagreement between the store path and the
managed-release path, exposed only when i >= 16 is actually reached (the
old silent parameter drop kept every real program at i <= 15, and the
compiler's own source never has >16-param C functions, so self-host
byte-identical proves nothing here). Likely reproducible standalone with a
Pascal record containing `arr: array[0..N] of record s: AnsiString; k:
Integer; b1, b2: Boolean; end` and high-index stores — worth trying BEFORE
touching compiler layout code.

rr trace preserved the session of 2026-07-02 (~/.local/share/rr). Cap
stays 16 with the definition-time error until this is fixed.
