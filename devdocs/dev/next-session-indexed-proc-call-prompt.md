# Handoff: implement `feature-indexed-proc-value-call` (Track A)

You are Track A (compiler, `compiler/**`). Implement indexed/element proc-value
indirect calls: `arr[i](args)`. This is the **chess demo** blocker
(`EvalTerms[i](pos)`); the scalar/const-record half is already done.

Ticket: `devdocs/progress/backlog/feature-indexed-proc-value-call.md` (read it).
Move it to `working/` while active, `done/` when finished; regen BOARD.md.

## The bug, exactly

```pascal
type TFn = function(x: Integer): Integer;
function Dbl(x: Integer): Integer; begin Dbl := x*2; end;
var arr: array[0..0] of TFn;
begin arr[0] := @Dbl; writeln(arr[0](21)); end.   { -> error: unexpected token () }
```

`arr[i](args)` is NOT parsed as a call (fails even with an int arg — no const
record involved). Scalar `fn(args)` and record-field `rec.fn(args)` both work.

## Why it's missing (already investigated)

- Scalar var call: `ParseProcVarCallAST` (parser.inc ~2726), invoked from ~4192
  and ~7537 when an **ident** with `SymProcSig[idx] >= 0` is immediately followed
  by `(`. Only handles a simple-ident callee (builds `AN_IDENT`).
- Record-FIELD proc call: parser.inc ~1870-1906 — builds `AN_CALL_IND` using
  `UFldProcSig[fIdx]` (the field's signature). **Mirror this for array elements.**
- `AN_CALL_IND` lowering: ir.inc ~3195. `ASTLeft`=arg chain (AN_ARG), `ASTRight`=
  callee expression node, `ASTIVal`=signature Procs[] index, `ASTTk`=return type,
  `ASTSLen[node]=1` flags a method pointer (`of object`, a 16-byte {Code,Data}).
- Signatures: `SymProcSig` (defs.inc:762) for a var, `UFldProcSig` for a field —
  **there is NO element equivalent**, so an `AN_INDEX` of a proc-typed array has
  no signature to marshal/return-type with. That is the core gap.

## Fix plan

1. **Add `SymElemProcSig: array[0..MAX_SYMS-1] of Integer`** in defs.inc next to
   `SymProcSig`. Semantics: signature Procs[] index of an array's ELEMENT proc
   type, -1 if not. **LANDMINE (`project_symtab_alloc_parallel_array_landmine`):
   every `Alloc*` in symtab.inc must reset it to -1** — the same sites that set
   `SymProcSig[SymCount] := -1` (symtab.inc ~1515, 1606, 1684, 1739). Missing one
   gives stale "callable" garbage on a recycled slot.

2. **Capture it at array declaration.** Where an array var's element type is
   parsed and `ElemType`/`IsArray` are set, also do
   `if LastTypeProcSig >= 0 then SymElemProcSig[idx] := LastTypeProcSig;`.
   `array of TFn` → `ParseTypeKind('TFn')` sets `LastTypeProcSig` (= the alias's
   sig). Find the array-decl sites in `ParseVarSection` and `ParseTypeSection`
   (search `ElemType :=` / where dyn/fixed array element type is recorded). At
   least the dynamic-array (`array of T`) and fixed-array (`array[lo..hi] of T`)
   var forms — chess uses one of these.

3. **Splice the call in the ParseFactor postfix loop** (parser.inc ~1275-1450,
   where `AN_INDEX` is built). After an `AN_INDEX` whose base is an `AN_IDENT`
   with `SymElemProcSig[ASTIVal[base]] >= 0` and `CurTok.Kind = tkLParen`, build
   an `AN_CALL_IND` exactly like the field path (~1882-1906): parse the arg list
   into an AN_ARG chain, set `ASTRight`=the index node, `ASTIVal`=elem sig,
   `ASTTk`=`Procs[sig].RetType`. Method-pointer elements (`array of TFoo` where
   `TFoo = procedure(...) of object`) need `ASTSLen=1`; detect via the element
   being a method-ptr type (its `ElemType`/rec is `tyRecord`). **Plain proc-type
   elements first** (chess's `TEvalFn` is almost certainly plain); guard or defer
   the method-ptr-element case if it complicates things, and note it.

## Already done (do NOT redo)

- `const record`/variant params in proc-TYPE signatures are now forced by-ref
  (parser.inc ~10474, commit 67c5536), matching `ParseSubroutine` ~11403. So once
  the indexed call is built, a `const record` arg through it marshals correctly.

## Verify

- `/tmp` repro int arg: `arr[0](21)` -> 42.
- const record array form (from the closed ticket's repro): `arr[0](r)` -> 42.
- Compile + RUN the chess demo (`feature-demo-chess`) — eval must stop saturating
  to `±INF` (startpos score sane, not 30000).
- Add `test/test_indexed_proc_call.pas` + a Makefile line (near `test_proctype` /
  `test_proc_const_record`, ~line 417-420).

## Gate

Front-end change, BUT it adds a symtab parallel array → **expect a one-generation
reseed** (`feedback_codegen_reseed_not_nondeterminism`): `make bootstrap` will
build/verify-differ once; gen3==gen4; just re-run `make bootstrap` and it settles
byte-identical. Then `make test`. Cross unaffected (parser-only); a quick cross
sanity on the new test is cheap insurance.

## Landmines (this codebase)

- Read a lookahead token's text with `GetTokenStr(TokPos)`, NOT `Tokens[TokPos].SVal`
  (the `Tokens[]` record has no `SVal`; caught only at the FPC build stage).
- `IsNodePChar`/other ir.inc helpers are included AFTER parser.inc — forward-declare
  if you need one in the parser.
- Commit in small units; `git pull --rebase` before push (3 parallel agents).
  Exclude `.claude/` and `compiler/pascal26*` (build artifacts) from commits.

## Pin?

Front-end only; pin (`make stabilize && make pin && commit stable_linux_amd64/`)
only if Track B / the chess demo needs it on the pinned compiler. Otherwise leave.
