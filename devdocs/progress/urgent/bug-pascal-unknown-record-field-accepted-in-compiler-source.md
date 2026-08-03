---
track: P
prio: 80
type: bug
summary: "Writing a field that does NOT exist on a record compiled with no diagnostic in the compiler's own source — `Procs[i].Params[j].ProcSig := -1` where TParam has no ProcSig. It stored to a wrong offset, clobbered a neighbour and segfaulted an unrelated test. FPC rejects it. Four minimal repros do NOT trigger it; the compiler tree does, reliably."
---

# An unknown record field was accepted, silently, and corrupted memory

- **Type:** bug (Pascal frontend, silent memory corruption + missing
  diagnostic) — **Track P** (member resolution, shared `parser.inc`)
- **Found:** 2026-08-03 by claude-P@opus5, while completing
  [[bug-pascal-procvar-value-context-outside-assignment]]. The FPC seed canary
  in `tools/gate.sh quick` is what caught it — every pxx-side check was green.
- **Severity:** it writes to an offset the field does not occupy. Filed to
  `urgent/`.

## What happened

`TParam` (`compiler/defs.inc:953`) is:

```pascal
TParam = record
  Name    : AnsiString;
  TypeKind: TTypeKind;
  SymIdx  : Integer;
  IsRef   : Boolean;
  IsArray : Boolean;
end;
```

There is **no `ProcSig`**. (`TTypeRef`, declared immediately above it, does have
one — that is where the name was borrowed from.) Yet this compiled clean:

```pascal
Procs[ProcCount].Params[i].ProcSig := -1;      { symtab.inc, RegisterProc }
ProcParamProcSig := Procs[cpi].Params[pathIdx].ProcSig >= 0;   { ir.inc }
```

pxx built a working compiler from it. FPC refused the same source:

```
symtab.inc(5389,32) Error: identifier idents no member "ProcSig"
parser.inc(26814,30) Error: identifier idents no member "ProcSig"
ir.inc(2037,52)      Error: identifier idents no member "ProcSig"
```

## It is not just a missing diagnostic — it corrupts

The write landed at some offset inside the record and clobbered a neighbour.
Two visible consequences in one build:

- the READ never saw what the WRITE stored, so the feature being built silently
  did nothing (the value read back never satisfied `>= 0`);
- `test/quick_canary_nilpy.npy` **segfaulted** — an unrelated NilPy test, in the
  `quick` tier. Reverting to a parallel array (`ProcParamProcSig`) restored it
  to `total ok 23 / 23`.

So the failure mode is the worst kind: a wrong store far from the symptom, and
the symptom in someone else's test.

## Reproduction — use the compiler tree, not a minimal case

Reliable, ~40 s:

```sh
cp -r compiler /tmp/ctree/
# in /tmp/ctree/compiler/symtab.inc, RegisterProc's param loop, add:
#     Procs[ProcCount].Params[i].ProcSig := -1;
cd /tmp/ctree && /path/to/compiler/pascal26 compiler/compiler.pas /tmp/out26
# -> "ok: /tmp/out26 ..." with no diagnostic.  FPC rejects the same tree.
```

**Do not start from a minimal case.** Four were tried and every one is
correctly REJECTED by pxx, with the right message
(`"X": no such member on this record/class`):

1. a plain local record, unknown field name;
2. a global `array of record` whose field is an `array of record`, accessed
   `Outers[0].Items[0].Bogus`;
3. two records where the OTHER one declares the field (ruling out "field names
   leak across record types");
4. all of the above combined — a `TTypeRef`-shaped record declaring `ProcSig`
   immediately before a `TParam`-shaped one that does not, inside a
   `TProc`-shaped record, in a global array, assigned in a loop.

So the trigger is something the compiler's own source has and these do not —
scale (`MAX_PROCS`), a `{$ifdef}` region, the `Params` bound being the literal
31 with the `MAX_PROC_PARAMS` const-expr gap noted at `defs.inc:966`, or a
resolution path only some declaration order reaches. Narrowing that is the
work; the tree above is the oracle to narrow against.

## Why it matters beyond this incident

Every `.field` in this compiler is written against a record the author believes
has it. When the belief is wrong, the expected outcome is a compile error — the
cheap case. Instead the store is silently misplaced, which is the
"plausible wrong value far from the cause" class `devdocs/dev/debugging-playbook.md`
is built around, with memory corruption on top. It also means **pxx cannot be
trusted to catch this class in its own source**, so the FPC seed canary is
currently the only thing standing between a typo'd field and a corrupted build
— see [[feedback_fpc_seed_build_not_covered_by_make_or_gate]].

## Gate

The reproduction above errors with `"ProcSig": no such member on this
record/class`, naming the right line; the four minimal cases keep their current
(correct) rejection; self-host fixedpoint byte-identical; the NilPy quick canary
stays green. Worth adding a `{%FAIL}`-style conformance case once the trigger is
understood.
