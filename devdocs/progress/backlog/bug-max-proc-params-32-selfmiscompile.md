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
