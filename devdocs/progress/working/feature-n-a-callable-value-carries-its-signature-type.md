---
track: A
prio: 88
type: feature
owner: frankonpiler-an
blocked-by: []
summary: "DECIDED 2026-08-19. A boxed callable's VT_CALLABLE_TAG payload becomes ONE pointer to a static signature record {code address, ReqN, TotN, per-param default descriptor}. Static, so the slot still owns nothing and no refcount behaviour changes. One call-site helper reads it: check arity, fill defaults, call. Unblocks three tickets whose symptoms are SIGSEGV and silent wrong values."
status: working
---

# A callable value carries its signature type

**Implements [[decide-how-a-compiled-def-carries-its-signature-when-boxed]] (decided by
the user, 2026-08-19).** Filed as work because a decided ticket that is never re-filed is
invisible to `ready`/`next` and gets rediscovered later, sometimes with a fix the decision
already rejected.

**Track A, not N:** it changes the variant payload contract in `defs.inc` and the call
lowering — shared compiler internals. Whoever holds A owns it.

## What to build

`VT_CALLABLE_TAG`'s payload becomes **one pointer to a static signature record**:

```
{ code address; ReqN; TotN; per-parameter default descriptor[] }
```

- **One payload word only.** A variant is 16 bytes: 8-byte tag + 8-byte payload. So the
  code address lives *inside* the record; there is no room for address + ID side by side.
- **The record is static** — emitted at compile time, never allocated, never freed. The
  slot therefore still owns nothing, and the deliberate non-owning lifetime recorded in
  `defs.inc` ("that is the lifetime these values already had while they wore VT_INT64")
  is preserved **by construction**. **No retain/release change anywhere.** This is the
  property the decision turns on — do not trade it away for convenience.
- **Per-parameter default descriptor** holds *either* the constant-folded value *or* the
  address of the hidden global that `ProcParamDefaultSym` already maintains for a
  non-constant default. Python evaluates defaults once at `def` time, and that mechanism
  already exists — **do not rebuild the value at the call site**, or the shared-mutable-
  default idiom (`def f(a=[])`) stops being observable.
- **One call-site helper, written once:** read `ReqN`/`TotN`, check the actual argument
  count, fill missing defaults from the record, call the code address.

## Do this too, or the win is half-taken

Give `TPyClosure` **the same signature type**. Then the two callable shapes differ only in
**ownership**, never in what a signature *is*, and the helper is written once against the
type rather than once per shape. That is what recovers the goal of the rejected
"route everything through the owned path" option without touching lifetimes.

## Context that prevents two wrong turns

- **`VT_CALLABLE_TAG` already carries two payload kinds** — "usually a static code
  address; it may also be a BORROWED heap callable" — and run-time dispatch already tells
  callable shapes apart by the object's magic, never by this tag. So this adds a payload
  kind to a tag that has them; it is not a third convention.
- **Do not "resolve the target statically where possible" and diagnose the rest.** That
  was explicitly considered and rejected: it fixes the one row that does not crash and
  leaves every row that does — dispatch table, handler list, callback parameter, bound
  method — still segfaulting. A passing test certifying a hole.

## What it unblocks

- [[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]] (currently
  `unfinished/`) — the measured evidence lives there.
- [[bug-n-a-call-through-a-callable-value-drops-the-callees-defaults]]
- [[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]] (`blocked/`)

Symptoms today: `handlers[0](1)`, `d["x"](1)`, `def call(fn): fn(1)` and a bound method
`cb = k.m` all **SIGSEGV**; `zz(1,2,3)` against a 2-parameter def returns a **wrong value
with exit 0**.

## Accepted limitation

Signatures are fixed at compile time; a callable synthesized at run time the way CPython
can is not covered. Not a new constraint — NilPy is a compiler, and the `pyeval` library
is where genuinely dynamic Python is expected to be served.

## Gate

Track A: `make compiler/pascal26` (the byte-identical self-host fixedpoint) + repro +
`tools/gate.sh quick`. Land green.


## Reconnaissance 2026-08-19 (frankonpiler-an) — before cutting

### The p70 IS this ticket, confirmed by measurement not by reading

`bug-n-a-call-through-a-callable-value-drops-the-callees-defaults` (Track N, p70)
is the same gap. Measured at HEAD:

| shape | pxx | CPython |
| --- | --- | --- |
| `al = g; al(1)` (a default must be filled) | **empty**, rc 0 — silent wrong value | `7` |
| `g(1)` direct | `7` | `7` |
| `g` passed as an argument, called with fewer args | **rc 139 (SIGSEGV)** | `7` |
| `al(1, 9)` — every argument supplied | `9` | `9` |

The last row is what makes it causal rather than plausible: through the **same
value**, a fully-supplied call is correct and only a call that needs something
filled in fails. There is nothing to fill from. So p70 needs no separate work —
its table becomes this ticket's regression test, and N's queue should be ranked
with p70 removed rather than sitting behind it.

### CORRECTION: there are FOUR callable-bearing tags, not two (and not three)

My first pass said TWO. That was wrong — I collapsed the owned shapes together.
A standing note in the repo says THREE (9 / 10 / 12). That is closer but also
incomplete. Read off `defs.inc` directly:

| tag | payload | built by |
| --- | --- | --- |
| `VT_BOUNDMETHOD` = **8** | `{code, recv}` pair pointer | `pybound_new` (pylib.pas:13626, stamps `VType := 8`) |
| `VT_PYCLOSURE_TAG` = 9 | pyeval closure object (`PClosureObj`, RAW2 block) | pyeval |
| `VT_BOUNDFN_TAG` = 10 | lifted bound-fn object (RAW2 block) | `pyboundfn_new` |
| `VT_CALLABLE_TAG` = 12 | a callable the slot does NOT own — static code address, or a borrowed heap callable | backend variant-boxing, keyed on `IRSrcIsCallable` |

Nothing was retired. 9 and 10 are deliberately distinct and `defs.inc` says why:
*"A SEPARATE tag from 9 rather than a reuse of it: the tag-9 consumers read
`PClosureObj(payload)^.Cidx`, which is a different record, so a bound-fn riding
as a 9 would be interpreted at the wrong offsets."* The count that was missing
from every version is **8**.

(`VT_CLASSREF_TAG` = 11 is also invoked — `cls = A; cls(3)` — but its callee is a
constructor, so it is a different signature question and is deliberately out of
scope here. Worth naming so the next reader does not have to re-derive that it
was considered.)

**Why 8 is the one that matters:** `PyMakeFuncValueFor` — the ASSIGNMENT path,
and the path this ticket's own headline repro `al = g` takes — calls
`pybound_new`, which stamps tag **8**. So a design that changes only tag 12's
payload, and adds the record to `TPyClosure` (tag 9), would still leave `al = g;
al(1)` broken. The plan needs to name tag 8 explicitly.

### The original two-way note, kept because it is still the operative split

This is the thing to settle before writing code, because it changes the size.

1. **`VT_CALLABLE_TAG` (defs.inc:747)** — payload is a static code address, the
   slot owns nothing. This is the one the plan describes.
2. **`TPyBound`, built by `pybound_new(code, recv, isFunc)`** (pylib.pas:13626),
   a refcounted heap object wearing `VT_BOUNDFN_TAG` / `VT_PYCLOSURE_TAG`.

`PyMakeFuncValueFor` — the function the ASSIGNMENT path uses, i.e. the one my
`al = g` repro goes through — builds **the second**. So changing only
`VT_CALLABLE_TAG`'s payload would leave the ticket's own headline repro
untouched. The instruction "give TPyClosure the same signature type" is
therefore not a nice-to-have that recovers half a win; **it is load-bearing for
the primary repro**, and should be read as such rather than as a follow-up.

**Encouraging precedent, and it validates the shape:** `pybound_new_star` already
carries `starIdx` — a piece of *signature* — beside the code pointer, and
`TPyBound` already has a `StarIdx` field. So adding a signature-record pointer to
this object is an established move in this file, not a new convention. `starIdx`
should fold INTO the signature record rather than sitting beside it, or the
"one concept, two mechanisms" smell the repo's own guidance warns about is baked
in from the start.

### Pin boundary

`compiler/builtin/pylib.pas` will change, so nothing here reaches another lane
until `make stabilize-fast && make pin`. That holds the repo-wide lock and is the
coordinator's to schedule, not mine to take.


## Implementation plan (frankonpiler-an, 2026-08-19) — researched, not yet cut

Recorded at this level of detail because the research below is most of the risk,
and re-deriving it costs more than the cutting does.

### Nothing needs inventing: the static-emission API already exists

`compiler/rtti_emit.inc` has the whole mechanism, used today for class RTTI:

| need | existing call |
| --- | --- |
| reserve N bytes of static data | `DataPutZeros(n)` |
| write a word | `PatchDataU64(off, v)` |
| data -> data pointer relocation | `AddDataPtrFix(off, targetOff)` |
| **patch a CODE address into DATA** | `QueueMethCodeFixup(off, procIdx)` |

That last one is exactly the signature record's `code` field, already solved.
The classref payload proves the whole shape works: `VT_CLASSREF_TAG`'s payload is
a static blob address reached by `DataOff = -(CLASSREF_DATAREF_BASE + ci)`
patched to `UClsRTTIOff[ci]`. **The signature record should follow that pattern
exactly**, with its own DATAREF base, rather than a new convention.

### A signature record ALREADY half-exists — do not build a second one

`RTTI_METH_SIZE = 48` is `{name, code, arity, retKind, paramKindsPtr, flags}`,
its param block carries per-parameter **names** as well as kinds, and **flags
bits 8..15 already hold the NilPy `*args` index plus one**. So per-CLASS-METHOD
signatures largely exist. What does not exist is any per-PROC record for a plain
module-level `def` — and that is what a boxed def needs.

Two consequences:
1. `starIdx` must fold INTO the new record, not sit beside it in `TPyBound` as it
   does today, or one concept keeps two mechanisms from day one.
2. Whoever cuts this should check whether the new record can *replace* the
   `RTTI_METH` signature fields rather than duplicate them. I did not settle
   that; it is the difference between deleting a case and adding one.

### The defaults design — one mechanism, not two

Today a default is stored TWO ways in the header arrays: a constant-folded value
(`PyHdrDefVal` plus `PyHdrDefIsStr/IsNone/IsFloat/IsBool` and `SOff/SLen`), or a
hidden global symbol for a non-constant one (`PyHdrDefSym` ->
`ProcParamDefaultSym`, pyparser.inc:27152-27166).

**Recommendation: give EVERY defaulted parameter a hidden global Variant**, and
make the descriptor one word — that global's address, or 0 for no default.

- It deletes a case rather than adding one: no constant-vs-indirect split in the
  record, and the call-site helper is a plain variant assignment.
- It gets refcounting right for free. A packed immediate would have to carry a
  static string/list pointer into a managed slot, which is where this would
  otherwise go wrong quietly.
- **It is what Python actually specifies** — a default is evaluated ONCE, where
  the `def` stands. `ProcParamDefaultSym`'s own comment already says this is why
  the mechanism exists. Extending it to constants makes `def f(a=[])` observable
  through a callable value by construction rather than by care.

### Proposed record

```
+0   code address           (QueueMethCodeFixup)
+8   ReqN                   user-space params with no default (Self excluded)
+16  TotN                   user-space params total
+24  StarIdx + 1            0 = no *args   (folded in from TPyBound.StarIdx)
+32  defaults array pointer TotN words, each a hidden-global address or 0
```

### Order of work, each increment green on its own

1. Emit the record per NilPy def; nothing reads it yet.
2. Point **tag 8** (`pybound_new`) at it and route the call helper through
   `ReqN`/`TotN`/defaults. **This is the increment that fixes the headline
   repro** and the SIGSEGV row — do it before tag 12, not after.
3. Tag 12 (`VT_CALLABLE_TAG`) payload becomes the record pointer.
4. Tags 9/10 carry the same record; delete `TPyBound.StarIdx`.

### Gate and blast radius

`make compiler/pascal26` + the p70 table diffed against CPython + `gate.sh
quick`. Touches `defs.inc` and `compiler/builtin/pylib.pas`, so it needs a PIN
before any other lane sees it. Land nothing half-applied: a Track A ticket in
`unfinished/` fails `progress.sh check` for good reason.
