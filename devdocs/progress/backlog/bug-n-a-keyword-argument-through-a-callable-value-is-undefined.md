---
track: N
prio: 65
type: bug
blocked-by: []
summary: "`d = obj.meth; d('x', flag=True)` fails with `undefined variable (flag)` — a callable value carries no parameter NAMES, so a keyword argument has nothing to match against. No name collision anywhere; the sibling of the already-known defaults gap on the same carrier. Distinct from the shadowing bug that produces the corpus's `decode has no parameter named 'final'`."
---

# A keyword argument through a callable value is `undefined variable`

Filed 2026-08-19 by frank3-etree (Track B) out of the corpus-ladder
investigation. **Track N** owns the fix; this is a report, not a claim on the
lane.

## Repro — measured on pinned v357 (`ebcf15ccb1046b29353b3b85091a8cdc`)

```python
class D:
    def decode(self, a, final=False):
        return "d:" + str(a) + ":" + str(final)
d = D()
f = d.decode
print(d.decode("x", final=True))   # direct call: fine, prints d:x:True
print(f("y", final=True))          # through a callable value: FAILS
```

```
pascal26:7: error: undefined variable (final)
  near:  f  y  final >>>
```

CPython prints `d:x:True` / `d:y:True`.

**Not name-specific.** The same file with `decode`->`mymeth` and `final`->`flag`
fails identically (`undefined variable (flag)`), so nothing about builtin method
names is involved.

**No collision required.** There is no module-level `def decode` anywhere in the
repro — which is what separates this from the shadowing bug below.

## What it is NOT — and this distinction is the point of the ticket

It is **not** the 12-file corpus wall. That one produces
`decode has no parameter named 'final'` and is
[[bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name]]
(frank2, `unfinished/`): a local `decode = decoder.decode` loses to a
module-level `def decode`, the call binds to the **module** function, and that
function genuinely has no `final`. The diagnostic there is *correct about the
wrong callee*, which is exactly why it reads as a signature bug and is not one.

The two were conflated for most of a day. What separated them was refusing to
treat a near-miss repro as the bug: **the minimal case produced a different
diagnostic from the corpus, and different diagnostics mean a neighbour, not the
thing.** Two bugs, not one confused one.

## Likely mechanism, and the request that goes with it

Sibling of [[bug-n-a-call-through-a-callable-value-drops-the-callees-defaults]],
whose summary already names the shared carrier: *"the box carries a code address
and no signature."* Defaults are one missing field; parameter **names** are
another, and a keyword argument needs the names.

frank2's request, recorded here so it reaches whoever picks this up: **extend the
PySig record rather than start a fifth mechanism.** Per
`normalise-dont-special-case.md`, a second path for "call through a value" is the
one that stays broken.

**Not merged with the defaults ticket** — frank2's call, on the grounds that it
is the same carrier but a different missing field and that ticket is nearly
closed. Cross-referenced instead.
