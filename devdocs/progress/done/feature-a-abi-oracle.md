---
track: A
prio: 60
type: feature
status: done
owner: claude-A
---

# ABI oracle: backends consult it, and stop reading Syms[]

Design: `devdocs/dev/type-identity-as-substrate.md` item 4.
Depends on [[feature-a-typeref-handle]].

## The break being fixed

`IRTk` is a bare kind and identity rides `IRA`/`IRB`/`IRC` positionally per
opcode. That is not enough to emit code, so backends reach around the IR into
frontend data:

```pascal
(Syms[symIdx].Kind = skParam) and (Syms[symIdx].IsRef or ...)
```

The IR claims to be the substrate but a backend cannot be written against the IR
alone.

## Shape

- **portable, carried in the IR:** 16-byte managed variant; class #7.
- **per-target, NOT in the IR:** register vs memory, 4 vs 8 bytes, hidden-dest
  vs `rax`. Freezing these into the IR breaks cross-compilation — this is the
  thing to get right.

A per-target oracle answers `PassBy(t)` / `ReturnVia(t)` / `SlotHoldsPointer(t)`.
**Backends consult the oracle and never touch `Syms[]`** — that clause is the
enforceable invariant, and is greppable in review.

## Cleans up

The "param slot holds a pointer" rule is written 8 times and 3 copies disagree
(see [[bug-a-param-pointer-rule-divergence]]). `AN_CALL` and `AN_VIRTUAL_CALL`
decide returns independently, which is why a `def` returning str works and a
method crashes ([[bug-nilpy-method-returning-str-garbage]]).

CAUTION: `RetViaHiddenDest` does NOT cover `tyAnsiString` — a managed string
returns a heap handle in a register. The oracle must not assume
"aggregate" == "hidden dest".

## Success metric

Adding one new pass-by-pointer / return-via-dest type kind currently needs edits
at **9 independent sites**. After this it must need **one**. If it still takes
six backend edits, this failed regardless of how clean it reads.

## 2026-08-09 — measured before designing, and one bug fell out

Started this ticket by diffing what the five backends actually DO today against
FPC, rather than reading the rule out of the source. That immediately produced
[[bug-a-set-and-shortstring-value-params-alias-the-caller]] (fixed, `7d7bdad29`):
a by-value `set` or `string[N]` parameter aliased the caller's variable on
x86-64 / aarch64 / arm32 and not on riscv32 — i.e. the divergence table in
[[bug-a-param-pointer-rule-divergence]] is **live, not latent**, and that
ticket's "LATENT" conclusion is corrected there. Its probe only READ the set.

**What this tells the oracle's design, and it is not what the ticket assumed.**

The ticket's shape section says the portable/per-target split is the thing to
get right. Measured, the per-target part is bigger than "register vs memory":
the five copies of "param slot holds a pointer" are not five copies of one
portable rule at all. They are the CALLEE half of a per-target calling
convention whose CALLER half lives somewhere else entirely (the argument
lowering), and the two must agree target by target:

- riscv32 omits `tySet` from the deref list AND does not pass a set param's
  address — consistent, and FPC-correct.
- x86-64 / aarch64 / arm32 include `tySet` AND pass the address — also
  internally consistent, and it was the aliasing bug.
- `symtab.inc`'s `ParamSlotIsPointer` (the slot-SIZE authority, already
  unified between `ParamSize` and `AllocParam`) agrees with NEITHER: it lists
  `tyString`/`tyRecord`/`tyClass`/`tyPointer` and omits `tySet` and
  `tyFixedString`.

So there are **three** rules here, not one written eight times: slot SIZE,
caller PASSES-BY, callee SLOT-HOLDS. Unifying them into a single predicate is
wrong; the oracle needs those three queries and each backend's table must be
internally consistent across them. That is what `PassBy(t)` / `ReturnVia(t)` /
`SlotHoldsPointer(t)` should mean, and the success metric ("one edit, not
nine") should be measured against a change to a per-target table, not to a
portable predicate.

**Parked here deliberately, not microfixed.** The remaining work is a design
task of its own size and `working/` must not hold a Track A lock across
sessions. Nothing is half-applied: the aliasing fix is complete and green on its
own, and no oracle code was written.

## 2026-08-09 — BUILT (`compiler/abi.inc`)

`compiler/abi.inc`, included straight after `symtab.inc`, is now the one place
that answers calling-convention questions. Three queries, and the file's header
explains why they are three rather than one:

| query | was | now |
| --- | --- | --- |
| callee SLOT-HOLDS (`ABIParamSlotHoldsValueAddr`) | written out longhand in **5 backends** | one function |
| slot SIZE (`ABIParamSlotIsPointer`) | `symtab.inc`'s `ParamSlotIsPointer` | moved here unchanged |
| ReturnVia (`RetViaHiddenDest` / `AggRetCopySize`) | already one function in `symtab.inc` | moved here |

### The success metric

Adding a pass-by-pointer kind is now **one edit** — to whichever of the three
predicates actually governs it, which is itself the point: the old eight copies
made "which rule am I changing?" unanswerable. The invariant is greppable, and
currently clean:

```
$ grep -n "IsRef or Syms\|IsRef or .*IsArray or" compiler/ir_codegen*.inc
  (no matches)
```

A ninth copy shows up in that grep.

### Two of the ticket's own premises were wrong, and the file says so

- **"the same rule written 8 times".** It is three different rules. `tyClass`
  and `tyPointer` params are pointer-SIZED but must NOT be dereferenced (the
  pointer IS the value); `tySet` is dereferenced on three targets and not on two
  — and both arrangements are internally consistent with their own argument
  lowering, so this is a per-target TABLE, not drift to be unified away. Encoding
  it here makes the divergence deliberate and reviewable.
- **"AN_CALL and AN_VIRTUAL_CALL decide returns independently".** Stale: the
  direct, virtual, indirect and interface paths all reach `RetViaHiddenDest` and
  all four build their destination with the one `IRBuildHiddenDest`.

### Not claimed

"Backends never touch `Syms[]`" is true for the CONVENTION now, not for
everything — they still read offsets, kinds and sizes from it. Making the IR
carry enough that a backend needs no symbol table at all is the TypeRef lane's
job ([[feature-a-typeref-migrate-consumers]]), and this oracle is shaped to
become a query on a TypeRef when it lands: the signature changes, the answers
do not.

### Verified

Behaviour unchanged by construction and measured: the FPC differential that
found [[bug-a-set-and-shortstring-value-params-alias-the-caller]] gives
identical output on x86-64, aarch64 and arm32 (qemu) and riscv32, and
`test_set_shortstring_value_param_copies` passes.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.


## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
