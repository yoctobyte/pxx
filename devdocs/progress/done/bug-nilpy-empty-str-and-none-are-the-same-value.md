---
track: N
prio: 75
type: bug
blocked-by: [decide-nilpy-none-str-sentinel-vs-textstr-kind]   # re-asked 2026-08-15: the decided representation's prerequisite (a stamped block kind) turns out never to have been built
summary: "`\"\" is None` answers TRUE for any NilPy value whose static type is plain `str` — literal, local, parameter, `-> str` return, AND every pylib str-method result (`.replace()`, a slice, `.join()`, `*0`). Container-derived and `Optional[str]` values are correct, because they carry a variant TAG; the rule is tagged-vs-untagged, not literal-vs-computed. A CORRECTION at the bottom retracts the 2026-08-27 down-scoping, which claimed the pylib results were already right and was measured wrong (they answer True on v385, v386 and HEAD alike) — the original ~260-producer sizing, and the basis the decision was taken on, both stand. A constant-fold is unsafe: `def f() -> str: return None` is legal CPython."
status: done
owner: frankA
---

# `""` and `None` are the same value for a NilPy str

```python
class E:
    def empty(self) -> Optional[str]:
        return ""
    def plain(self) -> str:
        return ""

print(E().empty() is None)   # CPython False   pxx True
print(E().plain() is None)   # CPython False   pxx True
print(len(E().empty()))      # both 0
```

## Why it matters

NilPy's whole None-for-str design rests on the two being distinguishable.
`pystr_none` returns a nil handle and `pystr_is_none` tests `Pointer(s) = nil`,
and pylib's comment states the assumption outright:

> a NilPy str that is None has a nil handle, a real string (including "") does
> not

Measured, that is FALSE — an empty AnsiString is nil in this runtime, so every
`is None` test on a str also fires for `""`. Ordinary Python code branches on
exactly that difference (`if s is None:` versus `if s == "":`), and here both
answer the same.

It also bounds what any fix in this family can do: a bridge that boxes "a nil
str handle" as None — which is the obvious way to make a host method's None
survive — would silently convert every returned `""` into None. That approach
was tried and abandoned for this reason while fixing
[[bug-nilpy-return-none-from-a-str-returning-def-yields-the-text-None]].

## PRE-EXISTING

Identical under `stable_linux_amd64/default/pinned`.

## Shape of the fix

The sentinel needs a representation that "" cannot collide with. Options worth
weighing rather than guessing between: a distinguished non-nil handle for None;
a separate variant tag for a None-str; or making str-typed Optionals variants
outright and accepting the cost. This is a model decision — consider a Track U
`decide-` ticket rather than picking one in passing, since
[[bug-nilpy-non-ascii-string-surface-measured]] and
[[bug-nilpy-encode-ignores-the-codec]] are already circling the same model.

## Gate

The three lines above matching CPython, `test_nilpy_none_str_field.npy` extended
with the "" case it currently documents as NOT asserted, plus the per-fix loop.

## Measured 2026-08-09 — the failure is NOT uniform, and that decides the fix

The conflation is exactly **static `AnsiString` vs `Variant`**:

| operand | `"" is None` | correct? |
| --- | --- | --- |
| `x = ""`, `"" + ""`, `"ab"[0:0]`, a `-> str` result, a class FIELD | True | no |
| **`["", "x"][0]`, `{"k": ""}["k"]`** | **False** | **yes** |
| `None is None` / `"abc" is None` | True / False | yes |

A string boxed in a variant carries `VT_STRING` in its TAG and `is None` tests
the tag, so **the variant representation already models None-vs-empty
correctly** — it is only the statically str-typed path, where `pystr_is_none`
tests `Pointer(s) = nil` against an empty AnsiString that IS nil, that
conflates.

That is the useful fact this ticket was missing: "the sentinel needs a
representation `""` cannot collide with" is not a design to invent. One exists
in-tree, works, and is exercised by the corpus. It makes "route str Optionals
through variants" the option with a demonstrated precedent rather than one of
three guesses.

Also measured: `x == ""` answers True correctly, so it is `is None`
specifically that conflates — which gives any fix a ready-made oracle, the
`is`/`==` pair disagreeing the way CPython makes them disagree.

Filed as [[decide-nilpy-none-str-representation]] with the four options and a
recommendation (route `Optional[str]` through variants, and decide the promotion
boundary EXPLICITLY — that boundary, not the representation, is where this will
go wrong; widening a str to a variant from a different direction is what broke
`test_nilpy_none_str_field` earlier the same day).

## UNBLOCKED 2026-08-11 — the representation is decided

[[decide-nilpy-none-str-representation]] is settled (user): **a NilPy string
kind whose blocks may be zero length.** Zero-length NilPy strings stop
collapsing to nil; Pascal's `AnsiString` keeps collapsing exactly as today, so
the RTL and the self-host binary are untouched by construction.

The consequence for this ticket is that **nothing in the `is None` path
changes**: `pystr_none` returning nil and `pystr_is_none` testing
`Pointer(s) = nil` (pylib.pas:834) become correct as written, because nil goes
back to meaning only None. pylib's comment quoted above stops being false.

The work is at the string-PRODUCING sites — `PXXStrFromLit`'s
`if len <= 0 then Result := nil` (builtinheap.pas:1064) and its siblings, plus
the pylib str constructors — which must not collapse for a NilPy-kind string.
Whether the property rides on the existing `PXX_KIND_TEXTSTR` or a new kind is
an implementation call; the decision ticket recommends `TEXTSTR`, and notes
this may be cheapest done alongside [[feature-nilpy-text-string-kind]] (N, 55),
which makes the same kind semantically live.

**Gate:** this is `compiler/builtin/**`, so it is Track A's obligation —
`stabilize-fast` + `make pin`, not the quick loop alone. Oracle stays the
`is` / `==` pair disagreeing the way CPython makes them disagree.

## PARKED 2026-08-15 — the decided representation has an unbuilt prerequisite

Re-measured at HEAD (66d65dbbb, self-hosted fixedpoint): the table above still
holds exactly, statically-str-typed operands conflating and variant-boxed ones
correct. Nothing has drifted.

Then checked whether the decided fix has anything to hang on, before starting it
(the lesson of [[feedback_check_the_design_was_built_before_debugging_it]]):

**It does not.** The decision is "a NilPy string kind whose blocks may be zero
length", resting on the block-kind word from
[[feature-a-managed-block-kind-word]]. That word EXISTS — `PXX_KIND_TEXTSTR = 2`
(builtinheap.pas:174) — but **nothing in the tree ever writes it**. The only
producer, `PXXStrMeta` (builtinheap.pas:382), stamps `PXX_KIND_LEGACY`
unconditionally, on every string, from both string constructors. Grep for
`PXX_KIND_TEXTSTR` outside its own declaration returns nothing.

[[feature-nilpy-text-string-kind]] is marked done, and it is — NilPy `str`
really does count characters — but it got there through three explicit helpers
keyed on the FRONTEND's static type, not by stamping a kind at runtime. So
phase 2's *header* half was never needed and never built. There is no runtime
predicate today that can answer "is this block a NilPy str?", which is precisely
the question the decided fix must ask before deciding whether to collapse at
length 0.

### What the decided fix therefore costs

1. Stamp TEXTSTR for real: a kind-carrying string constructor, and NilPy user
   code emitting its literals through it (`NilPyUserCode`, symtab.inc:25, is
   the existing hook).
2. **Propagate it through every string-PRODUCING routine** — concat, slice,
   join, format, upper/lower, and the pylib str surface — because the bug is
   reported for `"" + ""` and `"ab"[0:0]` as much as for a literal. A fix that
   covers literals only leaves the other producers wrong, which is the failure
   shape this repo keeps meeting
   ([[devdocs/dev/normalise-dont-special-case.md]]).
3. Let a non-nil zero-length handle loose in a runtime with **208 `= nil` tests
   in `compiler/builtin/**` alone**, several of which mean "empty". Each has to
   be read. This is the part that can break the self-host gate, and it is not
   estimable from the ticket.

That is a Track A representation project, not a session's bugfix — so this is
parked with the diagnosis banked rather than half-applied.

### A cheaper alternative the decision did not consider — escalated

Invert it: leave `""` collapsing to nil, and give **None** the distinguished
representation instead — one canonical zero-length sentinel block, allocated
once with a saturated refcount so release can never free it. `pystr_none`
returns it, `pystr_is_none` compares against it.

- `"" is None` answers False without any producer changing, because "" is still
  nil and nil is no longer what None means.
- Pascal `AnsiString` is untouched by construction, same as the decided option.
- No kind word, no propagation, no new invariant for the 208 nil tests: the
  sentinel IS a valid zero-length string, so anything that treats a None-str as
  "" keeps behaving exactly as it does today (where None-str is nil, i.e. "").
- Blast radius is `pystr_none` / `pystr_is_none` plus the frontend sites that
  materialise a None into a str slot.

It is not free — a sentinel is a global singleton, and `s == ""` on a None-str
would still answer True (it does today too, and CPython says False), so it
closes `is None` without closing `== ""`. The decided option closes both.

Filed as [[decide-nilpy-none-str-sentinel-vs-textstr-kind]] rather than taken:
the representation was settled by the user on 2026-08-11 and the new fact — that
its prerequisite is unbuilt, which was not known then — is a reason to re-ask,
not a licence to substitute a different design quietly.

**blocked-by** that decision.

## UNBLOCKED 2026-08-16 — implement the decided design; do NOT re-open the model

[[decide-nilpy-none-str-sentinel-vs-textstr-kind]] re-asked the representation
question and was closed by the user as already-decided. The design is
[[decide-nilpy-none-str-representation]]'s DECIDED section and has not moved:

> a NilPy string **kind** that may be zero length — `PXX_KIND_TEXTSTR` gaining
> "does not auto-nil on empty", ordinary AnsiString refcounting, scoped to
> NilPy-produced strings so Pascal's `AnsiString` keeps collapsing and the
> self-host binary is untouched **by construction**.

Two things follow that were not clear when this was filed.

**`is None` is not the bug and must not be changed.** `pystr_is_none` testing
`Pointer(s) = nil` (`pylib.pas:12066`) is *already correct* under the decided
representation, because a NilPy `""` becomes a real length-0 block and nil goes
back to meaning only None. Every row of this ticket's repro — `""`, `"" + ""`,
`"ab"[0:0]`, `"".join([])` — is a string-PRODUCING site that still collapses to
nil. Fix the producers, leave the consumer alone. (I initially read the
lowering as the defect and proposed routing str through variants; that is
option A of the decided ticket, set aside there because the variant route's
promotion boundary is where it goes wrong and the kind has none.)

**The first step is bigger than the decided ticket assumed:** `PXX_KIND_TEXTSTR`
is declared and never written — `PXXStrMeta` stamps `PXX_KIND_LEGACY`
unconditionally — so the stamping has to be built before the property can hang
off it. Correction recorded on the decided ticket.

Residual this does NOT close, recorded on the closed re-ask and parked in U per
that ticket's standing instruction: a genuine None-str still compares `== ""`
True where CPython says False, because a content compare sees two zero-length
operands either way.

Track N, and it carries Track A's `stabilize-fast` + `make pin` obligation
(`compiler/builtin/**`).

---

## Re-measured 2026-08-27 at HEAD — the surface is ~1 mechanism, not 260 producers

Not resolved. Parked back to the backlog with the sizing corrected, because the
sizing this ticket and [[decide-nilpy-none-str-sentinel-vs-textstr-kind]] both
carry is **wrong by two orders of magnitude in our favour**, and the target is a
different thing than either says. Nothing was changed in the tree.

### Every empty a computation produces is ALREADY correct

The decided design says the fix "lands at the string-PRODUCING sites", and the
closing measurement counted `pylib.pas`'s ~260 `: AnsiString` functions as that
surface. Measured at HEAD, none of them is in it — every one of these answers
`is None` **False**, matching CPython exactly:

| shape | `is None` | CPython |
| --- | --- | --- |
| `"abc".replace("abc", "")` | False | False |
| `"abc"[0:0]` | False | False |
| `"".join([])` | False | False |
| `str("")` | False | False |
| `"  ".strip()` | False | False |
| `"x"[1:]` | False | False |
| `"x" * 0` | False | False |

They are correct because a pylib result reaches NilPy as a **variant**, and a
variant carries its own tag — the tag distinguishes None from `""` without the
handle having to. So the block-level representation was never load-bearing for
any of them.

### What is actually wrong: the statically-plain-`str` slot, and only that

```python
class E:
    def opt(self)   -> Optional[str]: return ""
    def plain(self) -> str:           return ""
```

| row | pxx | CPython |
| --- | --- | --- |
| `E().opt() is None` — **Optional** | False | False |
| `E().plain() is None` — plain `str` | **True** | False |
| `x = E().plain(); x is None` | **True** | False |
| `"" is None` (bare literal) | **True** | False |
| `y = ""; y is None` | **True** | False |
| a value passed through a lambda parameter | False | False |

`Optional[str]` is already right. Only a slot whose static type is plain `str`
is wrong — that is the one place with no tag, where the value IS a bare
AnsiString handle and nil means both things. **That is the whole bug.**

This also explains why the original repro looked broader than it is: the
`Optional` row in it was already passing when it was filed, and the two rows
were read as one symptom.

### The fold is UNSAFE — measured, not assumed

The obvious cheap fix is to constant-fold `x is None` to False when `x` is
statically plain `str`, on the theory that such a slot can never hold None. It
cannot be done, because CPython does not enforce annotations:

```python
def retnone() -> str:
    return None
print(retnone() is None)    # CPython True
```

pxx answers True here too — accidentally, via the same nil that `""` produces.
Folding to False would fix the five rows above and break this one, which is
trading one wrong answer for another and is exactly the microfix
`devdocs/dev/root-cause-over-microfix.md` says not to take as a consolation.

(Two neighbouring rows are the *other* ticket, not this one:
`takes(None)` for `def takes(s: str)` and `z: str = None` both yield the TEXT
`'None'` — [[bug-nilpy-return-none-from-a-str-returning-def-yields-the-text-None]].)

### The decided design handles BOTH rows, so nothing is re-opened

Under `PXX_KIND_TEXTSTR` "may be zero length": `""` becomes a real length-0
block so `is None` is False, and `return None` from `-> str` stays nil so
`is None` is True. Both correct, no fork, no U ticket. The decision stands
exactly as written — this is a sizing correction, not a design question, so the
standing instruction to park string-model *questions* in U is not engaged.

### What the work now looks like

Much smaller than "stamp every producer", and in this order:

1. Lower NilPy's **empty string literal** to a helper that allocates a
   length-0 `PXX_KIND_TEXTSTR` block, instead of emitting an empty AnsiString
   literal. A frontend change plus one runtime helper — `PXXStrFromLit`, the six
   backends' inline literal paths, and Pascal's `''` are all untouched, which is
   the "untouched by construction" the decision asked for.
2. Make `return None` from a `-> str` def produce nil rather than `''`.
3. **The one thing that must be measured before building:** what the rest of the
   runtime does when a NilPy plain-`str` holds a *non-nil zero-length* handle.
   `Length` reads the header and is fine; retain/release are fine; a content
   compare is fine. The risk is any `Pointer(s) = nil` test that means "empty" —
   which is option E's 55-site audit arriving through the back door, scoped now
   to whatever pylib and the NilPy lowering do with a plain-`str` operand. Count
   those sites FIRST; that count, not the producer count, is what sizes this.

Also found while probing and filed separately: `str()` with no arguments is
`expected expression` — [[bug-n-str-with-no-arguments-is-rejected]].

---

## CORRECTION 2026-08-27 (later, sha 28d72544b) — the down-scoping above is WRONG

Re-measured at HEAD **and against the v385 / v386 pinned binaries**, which is
what settles it: the section immediately above claims the surface is "~1
mechanism, not 260 producers" because "every empty a computation produces is
ALREADY correct". **It is not.** Its seven-row table lists shapes that answer
`is None` **True** on the very binaries it was measured against.

Nothing regressed — that was checked first, since this session had touched the
`is` lowering (`IRPyVarEqTry` now routes `PY_BINOP_IDENTITY` to `pyvar_isv`).
The two prior pinned binaries answer identically:

| shape, as a BARE expression | v385 `dcc5945d5048` | v386 `22690b507548` | HEAD | CPython |
| --- | --- | --- | --- | --- |
| `"abc".replace("abc", "") is None` | True | True | True | **False** |
| `"abc"[0:0] is None` | True | True | True | **False** |
| `"".join([]) is None` | True | True | True | **False** |
| `str("") is None` | True | True | True | **False** |
| `"  ".strip() is None` | True | True | True | **False** |
| `"x"[1:] is None` | True | True | True | **False** |
| `"x" * 0 is None` | True | True | True | **False** |

Same through a plain-`str` annotated local (`a: str = "abc".replace("abc","")`),
same through a plain-`str` parameter, same for `-> str` defs returning a slice,
a `.join`, or a `+` of two empties. Ten rows, all True, all should be False.

### Why the earlier measurement read as correct

Its premise is the load-bearing error: *"a pylib result reaches NilPy as a
variant, and a variant carries its own tag"*. A pylib result reaches NilPy as an
**`AnsiString`** — that is what the ~260 `: AnsiString` functions return — and an
empty one is nil. The variant claim IS true for the 2026-08-09 table's rows,
which is where it came from, and those rows are container-derived:

| genuinely correct, re-verified at HEAD (7/7 match CPython) |
| --- |
| `["", "x"][0]` · `{"k": ""}["k"]` · `d.get("k")` · `d.get("nope")` → True · an element bound to a local · `Optional[str]` · a value through a lambda parameter |

So the correct rule is not "literal vs computed" and not "producer vs consumer".
It is **tagged vs untagged**: a value that reaches `is None` as a *runtime
variant* is right, and a value whose static type is plain `str` is wrong —
literal, local, parameter, `-> str` return, **and every pylib str-method result**,
because none of those carries a tag and nil means both things.

### What this restores

The **original sizing**, and therefore the basis the user's 2026-08-16 decision
was actually made on: the fix lands at the string-PRODUCING sites, and the pylib
`: AnsiString` surface is in scope after all. The 2026-08-27 note's "step 1 alone
closes every reported row" is false — it closes the literal rows and leaves every
`.replace()` / slice / `.join()` row wrong, which is the partial-coverage failure
shape `devdocs/dev/normalise-dont-special-case.md` describes.

**The decision is NOT re-opened.** It was taken under the large sizing; this
measurement restores that sizing rather than changing it, so there is nothing new
to ask. `PXX_KIND_TEXTSTR` "may be zero length" remains the design.

### One fear that IS smaller than recorded, measured

The parked note's third cost — *"let a non-nil zero-length handle loose in a
runtime with 208 `= nil` tests in `compiler/builtin/**`, several of which mean
empty"* — counted every nil test, most of them on object and block pointers.
Scoped to **string handles**:

```
grep -rn "Pointer([A-Za-z_][A-Za-z0-9_]*) *\(=\|<>\) *nil" compiler/builtin/*.pas
  -> 1 hit, and it is pystr_is_none itself
```

and the two comparison kernels are length-first by construction, so a non-nil
zero-length handle is already safe in both: `PXXStrEq` returns 0 on `lenA <>
lenB` before touching either pointer, and `PXXStrCmp3`'s own comment states *"a
nil handle arrives here as len 0, which is what makes '' the least element
without a special case"* — which holds equally for a real length-0 block.

So the risk is not "208 sites to audit". It is the ordinary work of making the
producers stop collapsing, and the audit is bounded.

### Parked back to the backlog, unclaimed

Still a Track A string-representation project carrying the `stabilize-fast` +
`make pin` obligation, and still too large to half-apply — but now correctly
sized, with the wrong plan removed. Whoever takes it should start from
`PXXStrFromLit`'s `if len <= 0 then Result := nil` (builtinheap.pas:1260) and the
pylib producers, NOT from the empty literal alone.

---

## RESOLVED 2026-08-29 (frankA) — three collapse sites, not ~260 producers

Implemented as decided: `PXX_KIND_TEXTSTR`'s "may be zero length" property,
scoped so Pascal's `AnsiString` keeps collapsing. Every row of the repro now
matches the CPython oracle. **The model was not re-opened.**

### The sizing, measured — this is what unblocked it

Both prior parks stalled on a sizing neither could measure without building the
thing. Measured directly, by removing the collapse and looking:

**There are exactly THREE sites where an empty string becomes nil**, and the
~260 pylib `: AnsiString` producers are not among them — they funnel through
site 1, because a Pascal `Result := ''` IS the empty-literal path:

| # | site | reaches |
| --- | --- | --- |
| 1 | `PXXStrFromLit` (builtinheap.pas) | every `""` literal, and every pylib `Result := ''` |
| 2 | `PXXStrSetLen` (builtinheap.pas) | `SetLength` through a non-symbol lvalue; **five of six backends** route all `SetLength` here |
| 3 | the **inline** symbol-target resize in `ir_codegen.inc` | x86-64 only — the one backend that does not call `PXXStrSetLen` |

Site 1 alone fixed 5 of the 7 wrong rows. `.replace()` and `.join()` were the
last two standing and they are site 3: both do `SetLength(Result, outLen)` on a
plain symbol, which on x86-64 alone never reaches the helper.

So the CORRECTION's "the pylib surface is in scope" was right about the
*symptom* and wrong about the *shape*: those results are wrong, but they are not
260 places to change. They are one.

### The scoping, and why it is whole-compilation

A new define, `PXX_NILPY_STR`, set in `compiler.pas` when `isNilPy`. Sites 1
and 2 read it via `{$ifdef}`; site 3 reads `isNilPy` at codegen time. **A Pascal
compilation never defines it, so it compiles the collapsing arm** — "untouched
by construction" is literal here, not an audit result, and the self-host
fixedpoint sha does not move.

It is whole-compilation rather than per-callsite because the producers are not
only NilPy user code: pylib is Pascal source whose `Result := ''` must not
collapse. Scoping to "source the NilPy user wrote" would have left every
`.replace()` / slice / `.join()` result wrong — the partial-coverage shape
`normalise-dont-special-case.md` warns about, and precisely the failure the
2026-08-27 down-scoping would have shipped.

### The trap: fixing the producers alone trades one wrong answer for another

`pystr_none` was `Result := ''`. Under the new model that returns a REAL block,
so `def retnone() -> str: return None` flipped from True to **False** — and
CPython says True. That row was correct *by accident* before, via the same
collapse that made `""` wrong. `pystr_none` now leaves `Result` unassigned (the
zero-initialised nil handle) and says why. A fix that stops the collapse and
forgets this line is not a partial fix, it is a lateral move.

`pystr_is_none` is **unchanged** — as the 2026-08-16 note said it would be. Its
own comment ("a real string (including \"\") does not [have a nil handle]") was
measurably FALSE for as long as it stood and is now true; the comment is
corrected in place rather than left as a claim the code finally earned.

### Verified

- 12-row repro: **matches CPython on every row**, tagged and untagged alike.
- 19-row empty-string semantics sweep (truthiness, `==`, `len`, concat,
  ordering, `in`, dict key, list index, `split`, `%`/`format`, methods, `join`,
  `repr`, `str()`): identical to CPython **and byte-identical to `pinned`** — no
  row moved. This is the "what does the runtime do with a non-nil zero-length
  handle" measurement the park demanded, and the answer is: nothing changes.
  The CORRECTION's bound was right — the comparison kernels are length-first and
  the only `Pointer(s) = nil` test on a string handle is `pystr_is_none` itself.
- Identity (`"" is ""`, `"" is "".replace(...)`) matches CPython; a 200k-iteration
  empty-allocation loop stays at 8 MB RSS / 0.12 s, so the extra blocks do not
  accumulate.
- `make compiler/pascal26` fixedpoint: `converged after 1 round(s)`.
- `tools/gate.sh quick`: **GREEN**.
- Ten named NilPy tests run individually: all that carry a `.expected` pass.

### Gate — stated honestly

`gate.sh quick` is green but its tier ran **29 Pascal/C jobs and zero `.npy`
jobs**, so it is NOT breadth for a change to the NilPy string model. NilPy
breadth is Track T's limited/full sweep against the pushed sha. The named-test
sample above is a sample, not a suite.

**This touches `compiler/builtin/**`, so it carries the pin obligation — NOT
done here.** Workers do not pin; flagged to the coordinator.

### Test

`test/test_nilpy_none_str_field.npy` extended with the case its own closing
comment had recorded as "NOT asserted here". The expectation is derived from
**CPython**, and the test **fails on `pinned`** (`867207f2b418`) on exactly the
eight untagged rows while the tagged control rows pass — so it discriminates
rather than merely agreeing with the build that produced it.

### Residual, unchanged and still parked in U

A genuine None-str still compares `== ""` True where CPython says False: a
content compare sees two zero-length operands either way. Recorded on
[[decide-nilpy-none-str-sentinel-vs-textstr-kind]]; not re-opened here.

### Note on `PXX_KIND_TEXTSTR`

Still declared and never stamped. This fix delivers the decided *property*
("a NilPy string may be zero length") through the compilation axis rather than
through the block-kind word, because the collapse decision happens **before a
block exists** — there is no header to read at the moment you are deciding
whether to allocate one. The kind word remains available and unstamped for
[[bug-nilpy-non-ascii-string-surface-measured]] /
[[bug-nilpy-encode-ignores-the-codec]], which ask their question *of an existing
block* and so can use it.

## Log
- 2026-08-29 — resolved, commit 8be3c6d06.
