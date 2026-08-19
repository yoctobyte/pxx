---
track: N
prio: 70
type: bug
blocked-by: []
summary: "LARGEST wall on the third-party ladder — 12 of 38 non-compiling files. A KEYWORD ARGUMENT passed through a CALLABLE VALUE held in a variable (`decode = decoder.decode`, then `decode(b'', final=True)`) is not matched against the callee's declared parameters. NOT the method hijack this ticket was filed as — that premise is disconfirmed by measurement, see the banner. Original title kept for grep: 'a user class's decode method is hijacked, losing its own parameters'."
---

# A keyword argument through a callable value is not matched to the callee

> *(Filed as "A user class's `decode` method is hijacked, losing its own
> parameters" — old title kept here so the old spelling still greps.)*

## ⚠ THE ORIGINAL PREMISE IS DISCONFIRMED — read this before working the ticket

Measured by frank3-etree on pinned **v357** (`ebcf15ccb1046b29353b3b85091a8cdc`),
2026-08-19, before anyone had claimed it. The body below is preserved as filed;
where it conflicts with this banner, this banner is the measurement.

**1. It is not a name hijack, and `decode` is not a fourth sibling of
`keys`/`items`/`values`.** Twenty builtin method names — `decode encode keys
items values append count index split join strip upper lower read write close
get pop update copy` — were declared on a user class and called with a keyword
argument, through **both** a direct receiver and an untyped parameter. **All
twenty dispatch correctly.** There is no counter-example supporting the hijack
framing.

**2. The failing construct is different, and so is the line.** `webencodings`
walls at **`__init__.py:230`**, not `:295`:

```python
def _iter_decode_generator(input, decoder):   # decoder: untyped parameter
    decode = decoder.decode                   # :217  bound method -> a variable
    ...
    output = decode(b'', final=True)          # :230  <-- fails here
```

So: **a keyword argument passed through a callable value held in a variable.**
The class's own `def decode(self, input, final=False)` at `:295` is never the
thing being consulted, because the call does not go through a member lookup at
all. Nothing about the *name* `decode` is involved — the same shape with
`mymeth`/`flag` fails identically.

**3. A factual correction to the body.** `lib/rtl/mimic_codecs.pas` **does**
exist (18 KB) and **is** bound — the compile prints `note: codecs ->
mimic_codecs (shim, subset)`. The body's "lib/rtl has no `mimic_codecs.py` at
all" is right about the `.py` and wrong about the shim being absent from play,
so "nothing of ours supplies a competing signature" needs re-checking rather
than assuming.

**4. What was NOT established — do not treat the repro below as the bug.** A
minimal version of the `:230` shape fails with **`undefined variable (final)`**,
while the corpus produces **`decode has no parameter named 'final'`**. Different
diagnostics, so the minimal case is very likely a *neighbour* and not the thing;
there is an ingredient still unfound. Adding a module-level `def decode(input,
fallback, errors=...)` shadowing the method (which is real — `:139`, and it has
no `final`) does **not** produce the corpus message either.

No root cause is written here on purpose. The banner says where to start and,
more usefully, where not to.

## Possible duplicate — a call to make, with this evidence in hand

[[bug-n-a-call-through-a-callable-value-drops-the-callees-defaults]] is the same
sentence with one word changed: *a call through a callable value loses part of
the callee's declared signature* — **defaults** there, **keyword names** here. If
they are one bug, both should say so rather than one being merged away. That call
belongs to whoever holds N (frank2, whose p88 signature-record work is adjacent),
not to Track B.

---

## AS FILED — A user class's `decode` method is hijacked, losing its own parameters

- **Track N** (NilPy frontend — member dispatch / name resolution).
- **Filed by the coordinator 2026-08-19**, the moment it was named, because it had **no
  ticket** while being the biggest single lever on the corpus. That is the
  `measuring a thing is not filing it` failure and it has now happened twice on this
  campaign — the Mapping row was in the same state this morning.

## Why it is the top lever

frank3's ladder re-run on pin v357 (`ebcf15ccb1046b29353b3b85091a8cdc`, captured before and
unchanged after) — **10/48 compiled**, ranked wall table:

| files | wall |
| --- | --- |
| **12** | **`decode has no parameter named 'final'`** |
| 7 | `unknown base class Mapping` (needs [[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]]) |
| 3 | `undefined variable (property)` |
| … | a long tail of ones and twos |

**Those top two rows are 19 of the 38 non-compiling files.** This one is larger than the
Mapping row that was treated as the top lever all day.

## What is actually happening — measured

The parameter is **not** ours to add. `library_candidates/webencodings/webencodings/__init__.py:295`
declares it on the corpus's own class:

```python
    def decode(self, input, final=False):
```

and calls it as `decode(b'', final=True)` (`:230`, `:241`; `encode('', final=True)` at `:267`,
so the encode side is likely the same defect). `lib/rtl` has **no** `mimic_codecs.py` — only
`mimic_codecs.pas`, which declares no `decode` — so nothing of ours is supplying a competing
Python-level signature.

So the diagnostic is not "this parameter is unsupported". It is **the call resolving to a
`decode` that is not the one the class declares.**

## HYPOTHESIS — not verified, and the first thing to test

`decode` is a builtin method name in pylib (see `bug-n-str-encode-and-bytes-decode-ignore-the-encoding`),
which makes this look like a **sibling arm** of the already-resolved
`bug-n-a-user-classs-keys-items-values-is-dispatched-as-a-dict-view` — where a user class's
`keys`/`items`/`values` were dispatched as dict views through an untyped receiver, giving a
segfault or garbage. That fix covered exactly three names. **If the mechanism is "a
builtin-named method on a user class loses to the builtin", then `decode` is the fourth
name and there is no reason to think it is the last.**

**Do not fix `decode` alone.** Per `root-cause-over-microfix.md`: establish whether the
population is *three names plus decode* or *every builtin method name*, and fix the
predicate rather than the list. The keys/items/values ticket's fix is the place to start
reading, and its author noted that every other method dispatched fine — which bounds the
mechanism and should be re-checked now that a fourth name is known.

**Also test the `encode` side** (`:267`) before assuming the fix is symmetric; it may be one
mechanism or two.

## What is NOT yet established

- **Which 12 files.** frank3's run omitted `--files`, so the per-file listing is missing. A
  re-run with it is in flight. The histogram is byte-identical to v353's across all 15
  categories, which makes a swap unlikely but **cannot exclude one** — a file moving off
  `Mapping` while another moved on would look identical. Treat "the same 12" as unconfirmed
  until that lands.
- Whether the receiver is typed or untyped at the failing call sites — the keys/items/values
  defect only bit through an **untyped** receiver, and that distinction is the likeliest
  discriminator here too.

## Gate

Track N's: `test-nilpy` green + self-host byte-identical. Add a `.npy` regression that
declares a class with a `decode(self, input, final=False)` method and calls it with the
keyword, plus whichever sibling names the investigation shows are in the population.
Re-run `tools/nilpy_ladder.py --files` afterwards and report past-a-wall separately from
onto-the-next-wall, naming the pin sha.
