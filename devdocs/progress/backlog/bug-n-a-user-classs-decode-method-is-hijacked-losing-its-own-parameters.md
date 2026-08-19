---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`decode has no parameter named 'final'` is the LARGEST wall on the third-party ladder — 12 of 38 non-compiling files, bigger than the Mapping row. The corpus declares `def decode(self, input, final=False)` on its OWN class; pxx binds the call to a builtin/pylib `decode` instead, so the user's parameter list is not the one consulted. Strongly suspected sibling arm of the already-fixed keys/items/values dict-view hijack."
---

# A user class's `decode` method is hijacked, losing its own parameters

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
