---
track: A
prio: 88
type: feature
owner: frankonpiler-an
blocked-by: []
summary: "DECIDED 2026-08-19. A boxed callable's VT_CALLABLE_TAG payload becomes ONE pointer to a static signature record {code address, ReqN, TotN, per-param default descriptor}. Static, so the slot still owns nothing and no refcount behaviour changes. One call-site helper reads it: check arity, fill defaults, call. Unblocks three tickets whose symptoms are SIGSEGV and silent wrong values."
status: done
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


## Increment 2 design, settled during the v354 pin window (read-only probing)

The plan above said "descriptor = the address of the hidden global holding the
default". **Probing the fixup path showed that route is far more expensive than
it looks, and that a better one exists.**

### Why "store the global's address" is the wrong route

`Syms[].Offset` for an `skGlobal` is a **BSS** offset (`defs.inc:1246`), and the
existing static-data relocation `AddDataPtrFix` resolves `dataBase + targetOff`
— data to DATA. There is no data-to-BSS fixup. `GlobFix` does resolve
`bssBase + BSSoff`, but it patches a **code** position, 4 bytes, not a data one.

Adding one would mean touching **five** application sites in `elfwriter.inc`
(three `PatchDataU64` at 1614/1753/1918 and two `writeRela32` at 2241/2425), and
the two `writeRela32` ones emit **object-file relocations**, where a BSS target
needs a different section symbol than the `.data` one they pass today. That is a
real ELF-writer change riding on what is supposed to be a NilPy defaults fix.

### The better route: the defaults array is WRITABLE, filled at def time

Keep the defaults array in `.data` as `TotN` **Variants** (16 bytes each), and
have the `def` statement's own execution write each default's value into it.

- **No new fixup kind.** The record's pointer to the array stays an ordinary
  data-to-data `AddDataPtrFix`. Nothing in `elfwriter.inc` changes.
- **It is writable.** Verified: the emitted image has a single `PT_LOAD` with
  flags **7 = RWX** (`elfwriter.inc`, the 64-bit writer), so `.data` is
  writable at run time. This is the assumption the whole approach rests on, so
  it was checked rather than assumed.
- **It puts def-time evaluation where Python says it happens** — at the `def`
  statement, once. The existing non-constant-default machinery already evaluates
  there; this changes *where the value is stored*, not when it is computed.
- **It collapses the two default representations** without needing to mint a
  hidden global for every constant default: the array slot IS the storage, so
  constant and non-constant defaults become one path. That is a stronger version
  of the recommendation above and reaches the same goal with less machinery.
- **`def f(a=[])` stays observable by construction**: one Variant, written once,
  copied (not rebuilt) at each call.

Code needs the array's address to write into it, which is the same data-ref
mechanism `VT_CLASSREF_TAG` already uses — see `CLASSREF_DATAREF_BASE` and its
`-(BASE + ci)` sentinel convention. A `PYSIG_DATAREF_BASE` follows that pattern;
note the comment at `TYPEINFO_REQ_DATAREF_BASE` that the MOST negative base must
be tested FIRST in the fixup branch chain, or a later branch swallows it.


## Increment 2b findings (researched, not cut) — read before writing it

### Trailing-defaults means NO has-default bitmask is needed

Python requires defaults to be trailing, and NilPy matches —
`ProcParamHasDefault`'s own comment says *"Trailing params only."* So `ReqN` and
`TotN` fully determine which parameters have defaults: exactly the slots in
`[ReqN, TotN)`. Do not add a mask field; the two counts already carry it.

### ...which also means you CANNOT stage this by leaving slots empty

There is no `VT_NONE`. None rides `VT_EMPTY` (tag 0), which is also
*"unassigned slot"* (`defs.inc:661`). So an unpopulated array slot is
indistinguishable from a legitimate `def g(x, lo=None)`, and the tempting
staging plan — bake the easy kinds, leave the rest zero, let the dispatcher
fall back — is NOT available. **Every slot in `[ReqN, TotN)` must be correctly
populated before the dispatcher reads the array.** A half-populated array is a
silent wrong-value bug, which is this repo's expensive failure class.

### Consequence: 2b needs BOTH paths, and they are different mechanisms

| default kind | how | where |
| --- | --- | --- |
| int / float / bool / None | **bake at emit time** — the slot is a 16-byte `{VType, Payload}`: `VT_INT64`+value, `VT_DOUBLE`+IEEE bits (`ProcParamDefaultVal` already holds the bits), `VT_BOOL`+0/1, `VT_EMPTY` for None | `EmitPySignatures`, pure `PatchDataU64`, no runtime code |
| string | **def-time store** — `VT_STRING`'s payload is a MANAGED AnsiString ref; baking a static pointer into a managed slot is how refcount corruption starts | the def-init queue |
| non-constant (`lo=[]`) | **def-time store** — must evaluate once, where the `def` stands | the def-init queue |

The def-time half has its mechanism ready: `PyQueueDefInit` (pyparser.inc:688)
already queues `$pdef.<proc>.<param> := <expr>` statements at def time for
non-constant defaults, and `GenMakeVariantAt` (parser.inc) is the ARC-correct
"store a variant at ptr+offset" shape — the generator work used it for exactly
this kind of store. The address to store through comes from the 2a sentinel:
`AN_SET_CONST_REF` with `ASTIVal = -(PYSIG_DATAREF_BASE + procIdx)`, then load
the defaults pointer at `+PYSIG_OFF_DFLTS` and index by `k * 16`.

### Layout note

Keeping the defaults POINTER at +32 rather than inlining the array after the
fixed fields costs one indirection and keeps `PYSIG_SIZE` fixed. Inlining would
remove the field and the `AddDataPtrFix`, at the price of a variable-length
record. Nothing needs an ARRAY of these records (each is reached by address), so
inlining is defensible — but the pointer form is what is emitted and
byte-verified today, so changing it is churn without a reason.


## PARKED 2026-08-19 after increment 2b part 1 (frankonpiler-an)

Parked to let the corpus lever through: the two head-of-N bugs unblock
`feature-b-mimic-collections-abc-mapping-and-mutablemapping`, which has a queue
behind it, while this feature currently unblocks nothing that is moving.

**Landed and green:** increment 1 (`e605d2e96`), 2a (`580e6d1ba`), 2b part 1
(`1aed59155`). All emission-side — `defs.inc`, `rtti_emit.inc`, `compiler.pas`.
Nothing in `pyparser.inc` or `compiler/builtin/**`, so this parks with zero
contention against N frontend work.

**RESUME AT: increment 2b part 2 — the def-time store.** Everything else is
banked above. The one thing that must not be forgotten:

> **Nothing may consume the defaults array until 2b part 2 lands.** Slots for
> string and non-constant defaults currently hold `PYSIG_DFLT_UNSET`. That is a
> loud sentinel by design, but a consumer written before the store exists would
> meet it on every such default.

Order from there: 2b part 2 (def-time store, `pyparser.inc`) -> 2c (`TPyBound`
carries the record, `pylib.pas` + `pyeval.pas`, NEEDS A PIN) -> 2d (dispatcher
reads ReqN/TotN/defaults). Verify the p70 table against the result before
resolving anything — "subsumed" stays a prediction until the fix exists.

## UNPARKED 2026-08-19 — resuming at 2b part 2 (pyparser.inc now uncontended)


## 2b part 2 — infrastructure landed, and what the store still needs

**Landed here:** the defaults ARRAY has its own dataref sentinel
(`PYSIGD_DATAREF_BASE`, `ProcSigDfltOff[]`, resolver branch placed before the
PYSIG one because it is more negative). So the array's address is a plain value
in the AST and the def-time store needs no pointer arithmetic through the
record — the slot is `AN_DEREF(sentinel + k*16)` typed `tyVariant`, which is
exactly `GenMakeVariantAt`'s shape with the sentinel in place of an ident.
Inert: nothing builds one of these yet.

### Measured: there are THREE registration sites, not one

`PyApplyDefSignature(procIdx)` looked like the single hook — procIdx known, every
`ProcParamDefault*` written there, called during def parsing. It is not:
`PXXDBG=n.sig` shows it firing for a plain `def g(x, lo=7)` and **not at all**
for `class K: def m(self, a, b=5)`. Methods register through their own sites
(pyparser.inc ~23267 and ~28080, which assign `ProcParamDefaultSym` directly).

So the store must be queued at all three, and this is the fix-both-arms case
again. For a plain def `hdrNParams = paramCount = 2` and `firstUser = 0`; the
method sites need the `self` offset applied so the slot index stays USER-space,
matching what `EmitPySignatures` computes.

### The remaining work, concretely

1. Queue, at each of the three sites, one `AN_ASSIGN` per unbaked defaulted
   param: LHS `AN_DEREF(PYSIGD sentinel + (i - firstUser)*16)` typed
   `tyVariant`, RHS the value.
2. RHS for a NON-constant default is `PyMakeIdent(PyHdrDefSym[i])` — the hidden
   global already holds the def-time value, so this copies rather than
   re-evaluates and Python's evaluate-once semantics are preserved.
3. RHS for a STRING constant has to be built from `PyHdrDefSOff/SLen`; the
   direct-call path in `parser.inc` (~2962) already does this and is the shape
   to copy.
4. Ordering: the store must be queued AFTER the hidden global's own assignment
   (`PyQueueDefInit` preserves queue order, so queueing later is enough).

### Structural note that governs the whole series

**Nothing in 2b is independently observable.** The array has no consumer until
2d, so 2b/2c/2d form one observable unit; only their *infrastructure* can land
separately, which is what 1, 2a and 2b-part-1 did. When 2d lands it must treat
`PYSIG_DFLT_UNSET` as a hard, explicit error ("this default kind is not
supported through a callable value yet") rather than a value — that keeps every
intermediate state loud instead of silently wrong, and lets the UNSET set shrink
to zero over the remaining increments instead of gating everything on
completeness.


## 2b part 2 — LANDED: the def-time store

The three-hook plan above was wrong, and measuring it is what showed why. Four
sites write `ProcParamDefaultSym`, not three — and that count is the tell
(`root-cause-over-microfix`: two mechanisms is a smell, three is a design flaw).
Hooking each of them would have made it five.

They all converge on one thing: the hidden `$pdef.<cls>.<nest>.<def>.<param>`
global, created in exactly ONE place, `PyEvalParamDefault`. So the store is
queued there, and the four registration sites are irrelevant to it.

**The problem that forced the design:** the store is built while the def's
HEADER is parsed, which is before the Proc exists, so it cannot name a proc or
a slot. **The fix:** `AN_PYSIGDSLOT` carries a PENDING-SLOT index instead. The
pend table is keyed by the hidden global — unique per (def, param) because the
name is fully qualified — and `EmitPySignatures` pairs pending index to data
offset once every registration site has settled. Node → `IR_CONST_DATA` with
the PYSIGD sentinel; the store itself is `AN_DEREF(that) typed tyVariant :=
AN_IDENT(global)`, i.e. `GenMakeVariantAt`'s shape, so it is ARC-correct for
free and needed no new IR op and no backend change.

**String defaults now get a hidden global too.** They are not bakeable —
`VT_STRING`'s payload is a managed AnsiString ref — so they need the def-time
store, and the store needs the global as its key. The direct-call path is
untouched: it still has `sOff`/`sLen` and builds the literal itself.

**Ordering is what makes it a COPY.** The slot store is queued AFTER the
global's own assignment, so it copies the def-time value rather than
re-evaluating the expression. Re-evaluating would get the common case right and
silently break the shared-mutable-default idiom, which is the whole reason the
global exists.

**Orphaned stores go to a bit bucket, not an error.** A rolled-back trial parse
leaves pending entries naming symbols the real parse re-allocates, so an
unresolved sentinel is EXPECTED. It resolves to `PyDfltScratchOff`, 16 bytes of
scratch `.data`; the array slot then stays `PYSIG_DFLT_UNSET` and the complaint
lands at the consumer, which knows the parameter's name.

### Verified

`def q(a, i=7, f=1.5, b=True, n=None, s="hi", L=[])` plus `class K: def m(self,
a, b=5, t="zz")`, with `PXXDBG=n.sig`:

```
n.sig pi=1724 name=K.m paramCount=4 firstUser=1 nUser=3 reqN=1
n.sig pi=1725 name=q   paramCount=7 firstUser=0 nUser=7 reqN=1
n.sig dflt K.m.t pend=2 slot=+32     (k=3, firstUser=1 -> user index 2)
n.sig dflt q.s   pend=0 slot=+80     (user index 5)
n.sig dflt q.L   pend=1 slot=+96     (user index 6)
```

Three unbakeable defaults, three pends, no orphans, and the method's `self` is
excluded from the slot index exactly as `EmitPySignatures` computes it. The
other four are baked statically as before.

**Still no consumer** — 2c/2d. The array is now fully filled for every default
kind, so 2d's `PYSIG_DFLT_UNSET` check should never fire in practice; it stays
as the loud guard for the orphan case above.


## 2c + 2d — LANDED: the value carries the signature, and the bridge uses it

**2c.** `TPyBoundRec` gains `Sig: Pointer` (static `.data`, never refcounted)
and a `pybound_new_sig` constructor; `pybound_new` and `pybound_new_star`
become one-liners onto it. `TPySigRec` in `pylib.pas` mirrors the `PYSIG_OFF_*`
layout in `defs.inc` and has to stay in step with it. `Sig = nil` means "the
producer could not supply one", and every path then behaves exactly as it did
before signatures existed.

Compiler side: `AN_PYSIGREF` (IVal = a proc index, unlike `AN_PYSIGDSLOT`'s
pending index — by the time a def is taken as a VALUE its Proc exists) lowers to
`IR_CONST_DATA` with the PYSIG sentinel. Both producers pass it:
`PyMakeFuncValueFor` for a plain def and `PyMakeBoundMethod` for `obj.method`.

**One trap worth naming:** `PyMakeFuncValueFor` may replace `pi` with
`PyGetOrMakeCallableWrapper(pi)`, a synthesized Proc that adapts the RETURN
side. The signature must name the ORIGINAL — the wrapper has no recorded
defaults, so carrying its index would hand the dispatcher an empty array and
silently undo the whole feature. The overload pick just above it is different:
that one IS the real callee, so it keeps the signature.

**2d.** `pybound_callv0..4` collapse onto ONE dispatcher. It reads `TotN`, fills
`nargs..TotN-1` from the defaults array, and calls at the arity the body was
actually compiled for. Before this, `f(1)` on `def q(a, i=7)` entered a
two-parameter body through a one-parameter pointer and `i` read whatever the
previous call had left there — a plausible wrong value, never a crash, which is
the expensive shape `devdocs/dev/debugging-playbook.md` opens with.

`nargs < ReqN` now raises TypeError instead of calling anyway. A COLLECTING
callee (`*args`) keeps its existing path untouched — it packs its own surplus
and has no omitted parameters to fill.

**The `key=` path had to be fixed too, and pointed at the same code.**
`map`/`filter`/`sorted(key=)` carry the callable as a raw PAIR POINTER, so they
reach `pyeval`'s `PyCallKey1`, which had its own truncated copy of the record
layout (`TPyKeyBoundRec = record Code, Recv: Pointer; end`) and called through a
one-parameter pointer regardless of arity. Rather than duplicate the fill rule
there, the dispatcher was split into a pointer-taking core `pybound_pair_call`
that both entry points call — so the defaults `map` fills are the same ones a
direct call fills, by construction, and the duplicated layout is gone.

### Verified — full CPython parity

`test/test_nilpy_callable_value_defaults.npy` (wired into `make test-nilpy`),
expectation generated from CPython, covers: int/str/None defaults through a
value; the shared-mutable-default accumulator through a value AND through the
name; a bound method with Self excluded; a `*args` callee unchanged; every
arity 0..4; a lambda default; too-few-arguments raising TypeError; `map` and
`sorted(key=)`; and a nested def whose default reads the enclosing scope at def
time. pxx output is byte-identical to CPython's.

This resolves the p70 headline repro. Confirm the rest of that ticket's table
before closing `bug-n-a-call-through-a-callable-value-drops-the-callees-defaults`.

### Found while widening, NOT mine

`sorted(l, key=f)` segfaults when `f` returns a tuple containing a string —
reproduced identically on `PXX_STABLE`, so pre-existing. Filed as
`bug-n-sorted-by-a-key-returning-a-string-bearing-tuple-segfaults` (N, p55) with
the measured boundary.

### Needs a PIN

`compiler/builtin/pylib.pas` and `pyeval.pas` changed, so other lanes see none
of this until `make stabilize-fast && make pin`. Coordinator-scheduled.


## Scope, measured after the fact — this covers the tag-8 pair, and there are FOUR tags

The feature is complete and correct for the **VT_BOUNDMETHOD pair** (tag 8),
which is what `f = some_def`, `obj.method`, and the `map`/`filter`/`sorted(key=)`
path all use. That is verified against CPython by the wired test.

It does NOT cover the other callable-bearing tags. A module-level def reached
through a **subscript** or a **parameter** — `fs = [g]; fs[0](1)`, or
`take(g)` where `take` calls `fn(1)` — is boxed by `PyBoxCallableValue` on the
**boundfn carrier, tag 12**, and `pyvar_callv1` routes only tag 8 into the new
dispatcher. Those shapes still segfault when a defaulted parameter is omitted.

That is pre-existing (identical on `PXX_STABLE`), not a regression, and it is
filed with its full diagnosis as
[[bug-n-a-module-level-def-taken-as-a-value-loses-its-defaults-on-the-boundfn-carrier]]
(N, p65) — including the finding that the boundfn carrier has its OWN defaults
mechanism (`pyboundfn_setdefaults`) which fires for the NESTED def form and not
the module-level one.

**Count the mechanisms before extending this.** There are now four dispatchers
for one concept — `pybound_callv*`, `pycallback_call*`, `PyCallKey1`,
`pyvar_callv*` — and two independent defaults mechanisms. The signature record
this ticket built is the general one; the honest next step is to put `Sig` on
the boundfn carrier too and DELETE `pyboundfn_setdefaults`, rather than teach a
fifth path the same trick.

## Tooling added

`PXXDBG=n.procs` dumps the proc table (index, name, arity, unit). The IR and
AST dumps print a callee as a bare `call a=1508`, and an hour went into the
wrong dispatcher because that number was mapped back by assumption. It is what
finally identified `pyvar_callv1` as the real call site.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
