---
track: N
prio: 72
type: bug
blocked-by: []
summary: "`d = obj.meth; d('x', flag=True)` fails with `undefined variable (flag)` — a callable value carries no parameter NAMES, so a keyword argument has nothing to match against. No name collision anywhere; the sibling of the already-known defaults gap on the same carrier. Distinct from the shadowing bug that produces the corpus's `decode has no parameter named 'final'`."
commit: PENDING-COMMIT
claimed-by: frankonpiler-an
status: done
---

# A keyword argument through a callable value is `undefined variable`

> **RE-RANKED 65 -> 72 on 2026-08-19 (coordinator). This is now the sole remaining wall on
> the 12-file corpus group, and it inherited that position by measurement, not by argument.**
>
> frank2 fixed the shadowing bug (`5fc7dc358`) that produced the corpus's
> `decode has no parameter named 'final'`. `webencodings/__init__.py` now reports
> **`undefined variable (final)`** — i.e. exactly this ticket. The 12 files moved one wall
> further along and **still do not compile**.
>
> **Read that as the expected result, not a failed fix.** A ladder run whose `decode` row is
> replaced by a `final` row rather than shrinking is what success looks like at this stage;
> conflating "moved past a wall" with "cleared" misreads the campaign in both directions.
>
> **Scope note from frank2, who built the PySig record and went looking:** this is a design
> increment on p88, not a fifth caller to teach the same trick. It needs something the record
> does not carry **at all** — parameter NAMES — plus a call-site lowering that can hand a
> keyword name to the runtime. Today `final=True` is parsed as an expression and dies on the
> bare name. Recommended order: (1) extend PySig with parameter names, (2) lower a keyword
> argument at a callable-value call site into a name/value pair the dispatcher can match.
> Step (3), consolidating the carriers, is deliberately split out as
> [[refactor-a-one-signature-record-for-every-callable-carrier]] and must not be done inside
> this ticket — that kind of absorption is what grew p88 to four increments.

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

---

## FIXED. The signature record was extended, not duplicated.

Three pieces, in the order frank2 recommended when it declined to merge this
with the defaults ticket.

**1. PYSIG grows a NAMES field** (`PYSIG_OFF_NAMES = 40`, `PYSIG_SIZE` 40 → 48).
`EmitPySignatures` emits `TotN` pointers followed by the NUL-terminated names
themselves, in the SAME record as the defaults rather than beside it — one
carrier answers every signature question. A proc with no user parameters leaves
the field nil, which the dispatcher reads as "no names known" and treats exactly
as it did before names existed.

**2. The call site sends the name to run time.** There is no callee to resolve
`final` against at compile time — that is the entire difficulty, and it is why
this failed as `undefined variable (final)`: the name was parsed as an ordinary
expression because nothing had told the parser it was a parameter. `PyMakeDynCall`
now recognises `ident =` in a dynamic call's argument list and appends the name
(as a string) and its value to two parallel `TPyList`s, exactly the way the
existing `*args` arm builds its list.

**3. The dispatcher matches them.** `pyvar_callv_kw` → `pybound_pair_call_kw`,
which reads `Names` and binds each keyword to a position, THEN fills the
remaining holes from the defaults — that order is what makes a supplied keyword
win over a default, which is the only reason a caller writes one. `PySigNameEq`
compares in place rather than converting to an AnsiString: putting the names in
`.data` was pointless if answering a question about one allocated.

Errors are Python's, not silence: unknown keyword, multiple values for one
argument, and missing required arguments each raise `TypeError`, and the
required-argument count is recomputed after keyword binding rather than trusting
the positional count — a keyword can supply a required parameter.

**A shape that does NOT carry names gets a named refusal**, not a wrong answer.
Only the tag-8 pair has a signature today; a keyword through any other callable
carrier raises rather than silently dropping the keyword and binding the
default, which would return something plausible. That is the failure mode most
worth avoiding, and the refusal names why.

### Verified

`test/test_nilpy_keyword_arg_through_a_callable_value.npy`, wired into
`test-nilpy`, expectation generated from CPython, byte-identical. Covers the
ticket's own repro, keywords out of declaration order, all-defaulted callees,
a keyword supplying a REQUIRED parameter, and all three TypeError cases.

### The corpus

**`webencodings/__init__.py` COMPILES** — the file behind all 12. Sampled
dependents move past the `decode` wall too: `tinycss2/__init__.py` and
`tinycss2/parser.py` both go from `decode has no parameter named 'final'` to
`undefined variable (MULTILINE)` (`re.MULTILINE`), a new and unrelated wall.

So the `decode` row is **cleared** from the ladder. Whether the 12 files now
COMPILE is per-file and is the ladder's to report — the ones sampled advance
rather than finish, which is the ordinary shape of corpus progress and should
be read as such.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
