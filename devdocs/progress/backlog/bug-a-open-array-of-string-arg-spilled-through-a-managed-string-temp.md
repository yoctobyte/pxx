---
slug: bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp
title: "An open-array-of-string argument is spilled through a hidden temp declared tyAnsiString that actually holds an array data pointer"
track: A
prio: 30
type: bug
status: done
owner: frankwasm
created: 2026-08-29
resolved: PENDING-COMMIT
summary: "`JoinOpen(['x','yy','zzz'])` for `procedure JoinOpen(const a: array of string)` spills the argument through a hidden temp that ir.inc declares tyAnsiString. An open-array parameter records its ELEMENT kind in TypeKind, and six sites in ir.inc read that field without also testing IsArray, so the temp holds an array data pointer while claiming to be a managed string. Register backends absorb it; wasm32 type-checks the store and refuses the body. Fixed by consolidating the decision into one predicate, ParamWantsManagedStrTemp, and calling it from all six."
---

# Symptom

```pascal
program jc;
procedure JoinOpen(const a: array of string);
var i: Integer; r: string;
begin
  r := '';
  for i := 0 to High(a) do r := r + a[i] + '.';
  writeln('n=', Length(a), ' r=', r);
end;
begin
  JoinOpen(['x', 'yy', 'zzz']);
end.
```

Native (x86-64) prints `n=3 r=x.yy.zzz.` and is correct. On `--target=wasm32`:

```
wasm32: 123 of 124 bodies lowered; 1 emitted as `unreachable`:
    main$0 — value of type Pointer assigned to a managed string
```

# Root cause

`ParseArrayCtorAST` (pasparser_lval.inc:3354) documents the convention this
trips over: an open-array parameter's `TypeKind` **is the element type**. For
`const a: array of string` that is `tyAnsiString`, with `IsArray` carrying the
"it is an array" half.

Six sites in `ir.inc` decide "does this argument need an owning managed-string
temp?" by reading `Params[pathIdx].TypeKind = tyAnsiString` without also
testing `IsArray`. The argument — an `IR_LEA` of the constructor's dyn-array
temp, i.e. a Pointer — is then stored into a hidden `AllocVar('', tyAnsiString)`:

```
22: lea       a=92 tk=17         { tyPointer: the array temp's data pointer }
23: store_sym a=93 b=22 tk=23    { sym 93 is tyAnsiString, IsArray=FALSE }
24: load_sym  a=93 tk=23
25: arg       a=24 tk=23
26: call      a=129 b=25         { JoinOpen }
```

(Measured with a probe on the wasm backend's `IR_STORE_SYM` arm:
`sym=93 IsArray=FALSE ArrLen=0 Kind=1 TypeKind=23 IsRef=FALSE valkind=17`.)

So a slot the compiler believes is a managed string holds an array data pointer.

# Two claims in the first draft of this ticket were wrong. Both were corrected by measurement

They are left in rather than quietly edited out, because the shape of the error
is the reusable part.

**1. "The same file already gets this right one site over (`ir.inc:11329`)."**
Not true, and never was. Verified at the exact commit this ticket was filed
against (`f018f4c86`), that line reads

```pascal
(Procs[cpi].Params[pathIdx].TypeKind = tyVariant) and (not ...IsArray)
```

— a **tyVariant default-parameter** branch. It is a correct guard on a
different question. The line had not moved; the citation was wrong when
written. This is the guard on face 42 (*"the fix already exists one site over"
is the most dispatch-accelerating sentence a ticket can contain*) working
exactly as intended: **cite a correct sibling by CONTENT, not by line number**,
because a line number is checkable only against a tree and a claim about
content is checkable against the sentence. Had this ticket been dispatched to
another agent, they would have opened `:11329`, found a variant guard, and had
to redo the whole diagnosis to find out whether the ticket or the tree was
lying.

**2. "Only the CONSTRUCTOR spelling is affected" and "only the first site is
confirmed to fire."** Both false. A seven-shape measurement program — one call
shape per procedure body, so that first-refusal counting does not hide the tail
behind the head — gives **six of seven shapes firing**:

| shape | call | before | after |
| --- | --- | --- | --- |
| S1DirectCtor | `Direct(['x','yy','zzz'])` | refuses | ok |
| S2VirtCtor | `b.Virt(['q','ww','eee'])` | refuses | ok |
| S3DirectFn | `Direct(MakeArr())` | refuses | ok |
| S4IndirectFn | `pv(MakeArr())` — procedure variable | refuses | ok |
| S5VirtFn | `b.Virt(MakeArr())` | refuses | ok |
| S7IntfFn | `j.Take(MakeArr())` — interface method | refuses | ok |
| S6DirectVar | `Direct(av)` — a named array variable | ok | ok |

Note *which* shape is the survivor, because it is not the one the claim named.
Both the constructor spelling `[...]` **and** a function returning the array
fire; the only shape that is fine is a plain named variable — and it is fine
for an unrelated reason, the `<> AN_IDENT` exclusion each guard already
carries. So "only the constructor spelling" was wrong twice over: wrong about
which call kinds reach the site, and wrong about which argument spellings do.

The scope claim was inferred from one repro rather than measured, which is the
whole reason the coordinator made "establish which sites can actually fire
before editing" a condition of the grant rather than a suggestion. The count of
unguarded sites is what justified consolidating instead of patching.

# Why no register backend has noticed

On the register backends the mistyped store retains the "string" (bumping a
word below the array data) and the scope-exit release decrements it again. The
two cancel, so the program is correct and nothing crashes — verified with a
2000-iteration loop and with `-dPXX_HEAP_DEBUG`, both clean, and confirmed
again here by an A/B arena-advance probe (below) that is flat on both builds.

wasm32 is the only backend that type-checks the store rather than emitting a
machine word, so it is the only one that can see it. **This is the third
instance of that pattern from the wasm lane: a shared-frontend mistyping that
every register backend absorbs by arithmetic coincidence.** The value is the
diagnosis; the wasm refusal is only what made it visible.

# Fix

One predicate, inserted before `IRLowerCallArg`, and six callers:

```pascal
function ParamWantsManagedStrTemp(cpi, pathIdx: Integer): Boolean;
begin
  ParamWantsManagedStrTemp :=
    (cpi >= 0) and (cpi < ProcCount) and (pathIdx >= 0)
    and (pathIdx < Procs[cpi].ParamCount)
    and (not Procs[cpi].Params[pathIdx].IsArray)
    and (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString);
end;
```

Consolidating rather than adding `and (not ...IsArray)` six times is the
`root-cause-over-microfix` call, and the grant was widened to permit it
(`50bf88683`): granting the line number would have forced the microfix that
document exists to prevent, and left five sites for someone to rediscover. The
predicate is now the single place the question is asked, so the next person who
learns something new about it has one edit to make.

Two further sites read the same field and are **deliberately not** routed
through the predicate, because they are asking a different question:

* the isNilPy char-to-pystr wrap — keyed on the *argument* being `tyChar`,
  which an open-array parameter cannot receive;
* the default-parameter frozen-literal arm — keyed on the parameter *having a
  default*. Guarding it would turn one wrong lowering into a different wrong
  lowering, because the real defect there is upstream: the parser accepts
  `procedure P(const a: array of string = 'x')` by reading `TypeKind` without
  `IsArray` — the same discriminator confusion, one level up — and the call
  then prints a pointer as a length. Filed separately as
  `bug-p-a-default-value-is-accepted-on-an-open-array-parameter`.

# Verification

Built in a clean worktree at `origin/master` (`7aba316be`), seeded from
`stable_linux_amd64/default/pinned`, sources touched after the copy so the
fixedpoint rule could not no-op.

* self-host fixedpoint: **converged after 2 round(s)**, `6988eff2aac0`.
* all seven shapes lower on `--target=wasm32` (`136 of 136 bodies`), and the
  wasm output matches native byte for byte.
* `compiler.pas --target=wasm32`: **3699 of 3735, 36 refusals** — unchanged
  (the 35 builtins + `IR_SYSCALL`, all blocked on
  `decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`).
  Body count rose by one because `ir.inc` gained a function.
* x86-64 A/B against a baseline built **in the same worktree from the same
  base** (`43be165be817`), which is the control the first attempt got wrong:
  emitted binaries are **smaller** with the fix (oas3 −4514 bytes) — the hidden
  temps and their ARC sequences disappearing, which confirms the arm was firing
  on x86-64 too and not only on wasm — and program output is unchanged.
* arena advance for an open-array-of-string call at 1000 vs 9000 iterations is
  identical on both builds, so the mistyped temp was leaking nothing and this
  change frees nothing: it removes dead work and a latent type violation.

# Gate

Track A's: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
plus the repro on both `--target=wasm32` and native, plus `tools/gate.sh quick`.
