---
track: U
prio: 45
type: decide
summary: "`\"\" is None` is True for a statically str-typed value and False for the same string in a variant — the variant path ALREADY models None-vs-empty correctly, so choose: route str Optionals through variants, give None-str a distinguished non-nil handle, or leave the divergence documented"
---

# How should a NilPy `str` represent None?

Requested by [[bug-nilpy-empty-str-and-none-are-the-same-value]], which says in
so many words that this is a model decision and should not be picked in passing.
Two neighbours circle the same model:
[[bug-nilpy-non-ascii-string-surface-measured]] and
[[bug-nilpy-encode-ignores-the-codec]].

## The measurement that shapes the choice (2026-08-09, HEAD)

The bug ticket reports `"" is None` answering True. Measured across shapes, the
failure is **not uniform**, and that is the useful part:

| operand | `"" is None` | correct? |
| --- | --- | --- |
| `x = ""` (local, str-typed) | True | no |
| `"" + ""` | True | no |
| `"ab"[0:0]` | True | no |
| a `-> str` function's result | True | no |
| a class FIELD holding `""` | True | no |
| **`["", "x"][0]` (list element)** | **False** | **yes** |
| **`{"k": ""}["k"]` (dict value)** | **False** | **yes** |
| `None is None` | True | yes |
| `"abc" is None` | False | yes |

So the split is exactly **static `AnsiString` vs `Variant`**. `pystr_is_none`
tests `Pointer(s) = nil` and Pascal's empty AnsiString IS a nil handle, so every
statically str-typed operand conflates them. A string boxed in a variant carries
`VT_STRING` in its TAG, and `is None` tests the tag — so **the variant
representation already gets this right today.**

That reframes the decision. "Give None-str a representation `""` cannot collide
with" is not a design to invent: one already exists in this codebase, works, and
is exercised by the corpus.

## Options

### A — route str-typed Optionals through variants (recommended)

Make a `str` value that can be None a variant, as container elements already are.

- **Working precedent in-tree**, which is the strongest argument available: the
  two correct rows above are this option, already shipped.
- Cost: boxing on the Optional paths, and the promotion boundary has to be
  decided (every `str`? only `Optional[str]`? only where a None can reach?).
  Only-Optional keeps the hot plain-`str` path untouched, which matters because
  `s := s + c` performance work is recent and load-bearing.
- Risk: widening a str to a variant is exactly what broke
  `test_nilpy_none_str_field` when tried from a different direction
  ([[bug-nilpy-name-bound-by-a-method-call-in-a-block-is-undefined-later]]), so
  the promotion boundary is the whole design, not a detail.

### B — a distinguished non-nil sentinel handle for None-str

Keep str as AnsiString; make `pystr_none` return a unique non-nil handle that
`pystr_is_none` recognises.

- Smallest change to the type model; the hot path stays an AnsiString.
- Cost: EVERY consumer of a str must treat that handle as not-a-string —
  `Length`, indexing, concatenation, printing, the C boundary. Miss one and it
  renders as whatever bytes the sentinel points at, which is a silent wrong
  value rather than a crash. That is a large audit surface with no compiler help.

### C — make the empty AnsiString non-nil

Fixes it at the root for str, but changes the RTL's string representation for
**Pascal too**, and the self-host binary depends on it. Disproportionate, and it
would be felt by every track. Listed for completeness; not recommended.

### D — document the divergence and close

`""` and None being one value is a real CPython incompatibility on code that
branches with `if s is None:` versus `if s == "":`. By CLAUDE.md's
upward-compatibility rule this is a defect, not a dialect choice — working
CPython code can observe it — so D is only defensible as an explicit deferral,
not as a resolution.

### E — a CANONICAL NON-NIL EMPTY STRING (user, 2026-08-10)

> "we overlook the option where we allocate a string, just it's length is zero.
> now in pascal, we auto-nil such string, but we don't have to?" — user

Correct, and it is one policy line, not a structural fact. `PXXStrFromLit`
(builtinheap.pas:1062) early-returns nil:

```pascal
{ ...Returns the data pointer (base+16) or nil for an empty string. }
if len <= 0 then begin Result := nil; Exit; end;
```

The layout is `[refcount:8][length:8][data][nul]`. Nothing requires empty to be
nil. Give `""` a **single canonical static zero-length block**, pinned so it is
never released, and nil goes back to meaning exactly one thing: None.

**Why this is better shaped than option B.** B gives NONE a distinguished
non-nil sentinel, so every str consumer must learn to recognise it, and a missed
site renders the sentinel's bytes — a silent wrong value. E inverts that: nil
already means "nothing" everywhere, so the None case needs no new knowledge at
all. And the empty case degrades benignly — a site that checked `s = nil` to
mean "empty" now falls through and reads a header that honestly says length 0,
which is the correct answer anyway.

**And it has no promotion boundary.** That is the decisive advantage over A:
this ticket's own recommendation warns that the boundary — not the
representation — is where the variant route will go wrong. E has none. It fixes
local, concat, slice, field and return in one change, for annotated and
unannotated code alike.

**No per-instance cost:** one shared block, so `s := ''` stays a pointer store.

#### What must be measured before choosing E

1. **The 55 `= nil` comparisons in builtinheap.pas.** Most are "don't deref"
   guards and get *more* correct under E, but they need reading, not assuming.
   This is the real work and the honest counterweight to "one line".
2. **Refcounting the canonical block.** It must never be freed: a pinned
   refcount, or an address check in release. Get this wrong and it is a
   use-after-free in the string runtime, i.e. the worst possible blast radius.
3. **Pascal-side semantics.** Pascal has no None, so nil-vs-empty is harmless
   there today — but any Pascal code testing `Pointer(s) = nil` to mean empty
   changes meaning. Grep it; the RTL and the compiler itself are the corpus.
4. **Self-host + pin.** This is `compiler/builtin/**`, so it needs
   stabilize-fast + pin, and the compiler binary is built with the changed
   representation. Expect a full-gate day, not a quick fix.
5. **Does `s = ''` still compare equal?** The content compare must treat the
   canonical block and (if any survive) nil as equal-length-zero.

#### Relationship to A

Not mutually exclusive: `Optional[str]` could still be a variant for annotation
consistency with `decide-nilpy-optional-int-none-vs-zero`, while E fixes the
unannotated majority. But if E works, A's scope question mostly disappears —
which is an argument for measuring E FIRST.

### F — tag None in the META word (user, 2026-08-10) — CHEAPEST, and it composes with work already queued

> "notice that every ansistring also has a 64-bit META tag with plenty free bits
> to tag as we see fit." — user

Correct, and it is already in the tree. The managed-block header is

```
[kind:8][refcount:8][length:8][data...]      handle = block + PXX_HDR_SIZE (24)
PXX_KIND_MASK = $FF          <- only 8 bits used; 56 free
PXXHdrMeta(p)                <- accessor; returns PXX_KIND_LEGACY for nil
PXX_KIND_BYTESTR = 1 / PXX_KIND_TEXTSTR = 2 / DYNARRAY = 3 / OBJECT = 4
```

It was added recently for unicode tagging — reusing AnsiString for other
stringly types — which is the same kind of purpose. Phase 2 of that work is
already queued as [[feature-nilpy-text-string-kind]] (N, 55).

**The design:** None is a canonical block tagged `PXX_KIND_NONE` (a new kind, or
a flag bit in the free 56). `pystr_is_none` reads the meta word instead of
testing nil.

**Why it beats E:** *empty stays nil, completely unchanged.* `PXXHdrMeta(nil)`
already answers `PXX_KIND_LEGACY`, which is `<> PXX_KIND_NONE`, so `"" is None`
becomes False **for free** — no canonical empty block, no refcount pinning of
one, and **the 55-site `= nil` audit disappears entirely.** Every risk item
1-3 of option E evaporates.

**Why it beats B:** B's fatal flaw was that a bare sentinel handle must be
memorised by every consumer, and a missed site renders its bytes as a silent
wrong value. Here the sentinel is **self-describing** — any consumer can ASK via
`PXXHdrMeta`, and the ones that do not ask see a length-0 block, which is benign.

**Remaining audit surface, and it is small:** only the places that must
distinguish None from `""` — `is None`, `str()`/`print`, and truthiness. Not
every string consumer.

**Still true:** this is `compiler/builtin/**`, so it needs stabilize-fast + pin.

#### The IMMORTAL bit — the same META word also solves "never free this" (user)

> "one of those bits could possibly be used for the refcounting fix ('don't free
> this empty string and nil it')." — user, 2026-08-10

Better than pinning a refcount or special-casing an address: make **immortal a
property of the block**. One free bit in the meta word (56 are unused above
`PXX_KIND_MASK = $FF`), and release skips the free when it is set.

**It costs nothing on the hot path.** The x86-64 release blob
(`EmitAnsiStrReleaseLocked`, ir_codegen.inc) is:

```asm
test rax, rax          ; nil check
dec qword [rax-16]     ; refcount
jnz  done              ; still referenced -> done
<free path>            ; <-- the immortal test goes HERE
```

The check sits *after* `jnz done`, so it runs only when the refcount actually
reached zero — which for an immortal block is rare, and for every ordinary
string is the free it was going to do anyway. A load of `[rax-24]` plus a test;
same cache line as the refcount it just wrote.

**Scope is smaller than it looks:** only `ir_codegen.inc` carries an emitted
AnsiStr release blob; the other backends route through Pascal helpers. So this
is one asm site plus the helper(s), not six backends.

**It generalises**, which is the real argument. The same bit serves the
canonical None block, a canonical empty block (if E is ever revisited), interned
literals, and any other static/constant managed block. "Immortal" stops being a
per-case hack and becomes a header property with one enforcement point.

That removes option F's last remaining risk item, leaving only the
stabilize+pin obligation that any `compiler/builtin/**` change carries.

## Recommendation

**Superseded by option E pending measurement — see the note at the end.** (Original: **A, scoped to `Optional[str]`.**) It is the only option whose correctness is
demonstrated rather than argued, and scoping to Optional keeps the plain-`str`
performance path out of it. Decide the promotion boundary explicitly and write it
down, because that boundary — not the representation — is where this will go
wrong.

## Note

`==` is unaffected: `x == ""` already answers True correctly. It is `is None`
specifically that conflates, so any fix can be validated by the `is`/`==` pair
disagreeing the way CPython makes them disagree.

## RECOMMENDATION UPDATED 2026-08-10 (twice)

**Take option F.** Tag None in the META word. It is strictly cheaper than E —
empty stays nil, so E's `= nil` audit and canonical-empty refcount pinning both
disappear — and strictly safer than B, because the sentinel is self-describing
via `PXXHdrMeta` rather than an address every consumer must recognise. It also
composes with [[feature-nilpy-text-string-kind]], which is already queued and
touches the same word.

Superseded reasoning kept below. (Previous: measure **option E** before
committing to A.)
E has no promotion boundary, fixes annotated and unannotated code alike, and
costs one shared block rather than boxing. Its risk is concentrated in a
readable, finite place — the `= nil` sites in the string runtime and the
refcount pinning — rather than spread across a type-promotion policy.

If E survives items 1-5 above, take E. If the `= nil` audit turns up sites that
genuinely need nil-means-empty, fall back to A scoped to `Optional[str]`.

## CORRECTION 2026-08-10 — the bit guards the COLLAPSE, not the lifetime

The "IMMORTAL bit" framing above is stronger than what is needed, and stronger
than what the user proposed. Corrected by the user:

> "well it could still be freed if it goes out of scope, just not when it's
> zero'd" — user

So the semantics are **not** "never free this block". Lifetime stays completely
ordinary: refcounted, freed at scope exit like any other string. What the bit
prevents is the **empty-collapse** — the rule that a zero-length string becomes
`nil`.

That collapse is the actual source of the whole bug. `PXXStrFromLit`
(builtinheap.pas:1064) is the visible one:

```pascal
if len <= 0 then begin Result := nil; Exit; end;
```

A block tagged with the bit is exempt: it stays a real handle with length 0,
so `is None` (which reads the meta word) and `""` stop sharing a representation
— while `Length`, `=`, printing and every other consumer keep working on an
honest length-0 block.

**This is simpler than what I wrote, and strictly better:**

- **No pinning, no immortality.** The refcount risk item disappears entirely
  rather than being solved — there is no shared canonical block whose premature
  free would be a use-after-free in the string runtime.
- **No special case in release at all.** The change is at the string-PRODUCING
  sites (the `len <= 0` collapse), not in the retain/release blobs. That is a
  smaller and much safer surface than the six-backend refcount path.

### One thing to confirm before implementing

Which blocks carry the bit, and who sets it. Two readings, both coherent:

1. **None only** — `None` is a length-0 block tagged NONE; ordinary empty
   strings keep collapsing to nil, and `"" is None` is False because
   `PXXHdrMeta(nil) = LEGACY <> NONE`. Smallest change; empty-vs-nil stays as
   it is today for Pascal.
2. **Empty too** — zero-length results stop collapsing generally, so `""` is
   also a real block. Fixes more (any place that distinguishes them), but
   re-opens the `= nil` audit that reading 1 avoids.

Reading 1 is the cheaper one and appears to be what is meant. Confirm before
building, because it decides whether the `len <= 0` sites change at all or only
the None constructor gains a tagged allocation.

### Reading 2, expressed better: a third KIND rather than a flag bit (user)

> "only nilpy code would use this construction.. then again, nilpy already has 2
> string types.. so might as well add a type
> 'ansistring_that_can_be_zero_length'." — user

Worth taking seriously rather than as overthinking. The meta word ALREADY
distinguishes `PXX_KIND_BYTESTR = 1` (Pascal AnsiString, Length in bytes) from
`PXX_KIND_TEXTSTR = 2` (NilPy str, positions in characters). A third kind is the
established mechanism, not a new one, and it keeps the property in the same
place as the two distinctions already made there.

It also scopes cleanly: only NilPy-produced strings carry the new kind, so
Pascal's `AnsiString` behaviour — and the self-host binary that depends on it —
is untouched by construction. That is a stronger isolation guarantee than a flag
bit sprinkled across shared producers.

Decide flag-bit vs third-kind together with the reading 1 / reading 2 question
above; they are the same question asked twice.

## STANDING INSTRUCTION (user, 2026-08-10)

If any of this string handling raises further issues, **park them in Track U
again** rather than deciding in passing — "i have the feeling we're not done
with that."
