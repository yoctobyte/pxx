# C: `invalid symbol in lea` lowering sqlite amalgamation

- **Type:** bug (C frontend → IR lowering) — Track C (+ A if the fault is in
  shared symtab/IR)
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]).

## Symptom

Compiling the sqlite 3.46.0 amalgamation (`library_candidates/sqlite/sqlite3.c`,
fetch via `tools/install_lib_candidates.sh sqlite`) fails the IR validation pass:

```text
pascal26:22272: error: invalid symbol in lea ()
```

Raised at `ir.inc:296` (the `IR_LEA` arm of the IR verifier):

```pascal
IR_LEA:
  if (IRA[i] < 0) or (IRA[i] >= SymCount) then
    Error('invalid symbol in lea');
```

So some C construct lowers to an `IR_LEA` whose `IRA` (symbol index) is out of
`[0, SymCount)` — almost certainly negative / an unresolved-or-placeholder sym.

## Ruled out

- **Not capacity (`SymCount` overflow).** Sym allocation is guarded
  (`symtab.inc` `SymCount >= MAX_SYMS -> Error('too many symbols')`); we'd see
  that message, not this one. (Reached only after the `MAX_TOKENS` 512K→2M bump,
  see [[chore-sqlite-static-capacity-bumps]].)
- **Not the obvious string-pointer-array path.** `static const char * const
  opts[] = { #ifdef… "A", "B" };` with `opts[0][0]` compiles and runs fine — so
  it is not the plain `PendingInitKind=1` global init.

## Position is unreliable

The reported `22272` lands inside a dead `#ifdef` block (`azCompileOpt[]`). The
verifier runs **after** lowering, so the printed line is just the last-set
counter, not the offending construct. Do not trust it.

## Next step (diagnosis plan)

1. Instrument `ir.inc:296` to print `i`, `IRA[i]`, `SymCount`, and the current
   proc/node context instead of bailing — recompile sqlite, capture the bad sym
   value (negative? a sentinel like -1? a specific large index?).
2. From the value, find the emit site: grep the C→IR lowering for `IR_LEA`
   emission where the sym can be unresolved (extern not yet bound? address-of a
   not-yet-allocated global? a function/label sym used as a data sym?).
3. Reduce to a minimal C repro once the construct is known; add to `test/`.

## Acceptance

- The offending construct identified, fixed at the lowering (or symtab) site.
- A minimal C repro in `test/` (exit-code oracle) compiles + runs.
- sqlite advances past this wall (next wall filed separately).
- self-host byte-identical + cross unaffected (or, if shared IR/symtab touched,
  full gate green).

## Log

- 2026-06-27 - Found during M5 sqlite first-compile (after the MAX_TOKENS bump
  cleared the token-overflow wall). Characterized as a genuine bad-sym IR_LEA,
  not capacity; simple string-array repro negative; position stale. Needs
  instrumentation — parked for a focused debug session.

## Diagnosis (2026-06-27, session 2)

Instrumented the IR_LEA verifier and `IRLowerAddress` (reverted after). Chain:

- `IRLowerAddress` (`ir.inc:587`) is called on an **`AN_INT_LIT` (value 0,
  ASTTk=tyInteger)** node → no lvalue case matches → falls through to
  `IR_UNSUPPORTED` (`ir.inc:878`). The caller wraps that result in `IR_LEA` with
  sym = **-1** (0xffffffff) → `IRVerify` (`ir.inc:296`) rejects it.
- Verifier dump at failure: `IRA=-1`, `SymCount=0x24c (588)`, `iridx=0x2f`; IR
  context shows `IR_UNSUPPORTED(a=AN_INT_LIT)` then `IR_ARG` then the bad
  `IR_LEA`. So it is a function/init body taking the address of an integer
  literal.
- The offending node's `ASTLine = 22225`, inside the **`sqlite3azCompileOpt[]`**
  `const char * const []` global array initializer (def line 21934). That array
  is densely `#ifdef`-guarded; with no `-D` defines most entries vanish and the
  survivors use `CTIMEOPT_VAL(...)` stringify + adjacent string-literal
  concatenation (e.g. `"COMPILER=gcc-" __VERSION__`, `"THREADSAFE=" CTIMEOPT_VAL
  (THREADSAFE)`). One surviving element is being lowered as an **integer literal
  0** instead of a `char*`, and the global array-pointer-init path then takes its
  address.

### Not yet reduced

Isolated repros that did NOT trigger it: plain string-concat element
(`{"A=" "B"}`), stringify of a numeric macro, a `0`/null element in a `char*[]`,
`&global[const]`. So the trigger is specific to pxx's expansion of a surviving
azCompileOpt entry. **Next probe:** dump pxx's preprocessed view of that array
(no `-E`/preprocess-dump flag exists — add one, or instrument `cpreproc`), or log
`IRLowerAddress`'s caller to capture the parent expression that wraps an int
literal in an address-of.

## Log

- 2026-06-27 (s2) - Traced to `IRLowerAddress(AN_INT_LIT 0)` -> IR_UNSUPPORTED ->
  IR_LEA(-1), node at azCompileOpt[] init (~line 22225). Minimal repro still
  elusive (macro-expansion-specific). Separate offset bug found:
  [[bug-c-addr-of-global-array-element-const-index-wrong-offset]].
