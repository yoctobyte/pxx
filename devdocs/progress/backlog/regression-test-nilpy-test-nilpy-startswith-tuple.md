---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_startswith_tuple.npy red at b898d0543fc8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T20:46:31Z
- **Test source:** test/test_nilpy_startswith_tuple.npy test/test_nilpy_startswith_tuple.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_startswith_tuple.npy'` at b898d0543fc8499facc66706257ff08d39195520

## Range
> **The named sha `b898d0543fc8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b898d0543fc8`, last good `8b2cc332791e`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-25046/test_nilpy_swtuple26  [code=1277065B  data=55459B  bss=42588B  procs=1804]
Segmentation fault (core dumped)
--- test/test_nilpy_startswith_tuple.expected	2026-08-09 01:14:26.952809883 +0200
+++ -	2026-08-27 22:41:21.249287413 +0200
@@ -4,5 +4,3 @@
 plain      True True
 window     True True
 winmiss    False
-param      True False
-platform   False True

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Track T triage, 2026-08-27 — this IS a real NEW-RED, and here is a usable range

**It is not a first-report.** The concern is legitimate in general —
`diff_jobs()` asks the was-it-passing question with
`prev_jobs.get(name, "pass")`, so a job never seen before arrives as a NEW-RED
against a green history it never had. That is **not** what happened here.
Walking the committed history of `tstate/plexus.json`, this job's recorded
status was:

| tstate commit | run date | status |
|---|---|---|
| `854c315fe` | 2026-08-27T20:26:39Z | **pass** |
| `c0840ac21` | 2026-08-27T20:53:44Z | **fail** |

A real recorded green immediately prior. The regression is genuine.

**Ignore the `bad=` in the stub.** `b898d0543fc8` is docs-only
(`devdocs/dev/session-roster.md`); nothing in it can break a NilPy test. It is
the sha that was TESTED, not a cause — with buildable commits swept only
incidentally, a bisect has no fine-grained ladder to land on.

**The honest range, and it is short.** `test-nilpy` runs in the
**limited/full** tiers only, so a `native` run does not refresh these job
entries — the map carries them forward. The last-good is therefore the last
*deep* run, not the last run of any tier:

- last full run with **0** nilpy new-reds: `8b2cc332791e` @ 20:09:39Z
- first full run reporting this red: `b898d0543fc8` @ 20:46:26Z

Seventeen commits sit between them and **only two touch a buildable file**:

| sha | commit | lane |
|---|---|---|
| `218ce1eaf` | fix(rtl): AnsiQuotedStr, and TryStr* zeroes its value on failure | B |
| `19dc5586e` | fix(nilpy): type a method call by the METHOD, not a same-named intrinsic | N |

**`19dc5586e` is the prime suspect** — it changes how a method call is typed
when an intrinsic shares the name, which is the exact shape of both failing
tests (a parent method call; `startswith`, which is both a string method and an
intrinsic). Start there, and confirm by building at `8b2cc332791e` vs
`19dc5586e` rather than by reading the diff.

*Triaged by Track T (face 2) from tstate; the fix belongs to the owning lane.*

---

## Diagnosis, 2026-08-30 (frankwasm) — root-caused, NOT fixed: the file is held

**Track N confirmed** (the defect is in `compiler/pyparser.inc`, frontend
return-type inference). **Not claimed and not fixed** — frankA holds
`pyparser.inc` for slice 7 of the speculative-parse work. Handing the diagnosis
over rather than colliding.

### The name of this ticket is misleading — the tuple is irrelevant

`startswith` is not special and neither is the tuple. Minimal repro, no tuple,
no `startswith`:

```python
def f():
    y = "abc"
    return y.find("b")
print(f())
```

→ **SEGV**. The boundary, measured shape by shape:

| shape | result |
| --- | --- |
| `def f(): return "abc".find("b")` — **literal** receiver | OK |
| `def f(): y = "abc"; return y.find("b")` — **local** receiver | **SEGV** |
| `def f(x): return x.find("b")` — **parameter** receiver | **SEGV** |
| `def f(x): return x.upper()` / `.lower()` / `.replace()` — str→**str** | OK |
| `def f(x): return x.find(...)` / `.count(...)` — str→**int** | **SEGV** |
| `def f(x): return x.startswith(...)` — str→**bool** | **SEGV** |
| `def f(x): return len(x)` — intrinsic, not a method | OK |
| result computed but **not returned** | OK |
| `if x.startswith("a"): return 1` — returns an int literal | OK |

So: **a str method whose return type is not a string, called on a receiver that
is a variable, and whose value is returned from a def.** The str→str methods
survive because the wrong answer happens to equal the right one.

### Cause — measured, not read off the diff

`PXXDBG=a.ir:f` on the crashing and working programs. Both emit the same
`call a=1048` and store to `$pyresult`; the difference is the first op:

```
CRASH:  0: zero_sym a=473 ...            [sym=$pyresult]   <- managed init
OK:     0: const_int a=-1 ...
        1: store_sym a=473 ...           [sym=$pyresult]
```

`zero_sym` on `$pyresult` means the def's **result symbol is typed
`tyAnsiString`** while the call returns an Integer/Boolean. The caller then
reads the returned small integer as a string handle and dies.

The inference is in `PyInferDefRetTypeScanInner`'s `recv.mth(...)` arm:

```pascal
        t2 := PyRetMethodType(bodyScanStart, j, GetTokenStr(j + 1),
                              GetTokenStr(j + 3), rec2, recvCi2);
        if t2 <> tyUnknown then
        begin
          cur := t2;
          ...
        end
        else if recvCi2 >= 0 then
        begin
          cur := tyVariant;
          PyInferLastCi := -1;
        end;
```

`PyRetMethodType` resolves **user-class methods only** — `PyRetRecvClass` then
`FindUMeth`. For a *string* receiver it returns `tyUnknown` **and** leaves
`recvCi2 = -1`, so **neither** branch fires and `cur` keeps whatever the
expression chase produced: the receiver's own `tyAnsiString`.

That is precisely the failure `PyRetMethodType`'s own header comment warns
about, one type-family over:

```pascal
{ ... The second case must
  NOT be left to fall through: the expression chase then types the return as
  the receiver's class, which is the defect. tyVariant is the honest answer and
  the one the equivalent two-statement spelling already produces. }
```

The correct answer is already tabulated and simply never asked for —
`PyStrMethodInfo` has `find` → `tyInteger`, `startswith`/`endswith` →
`tyBoolean`, with `tyAnsiString` as the str→str default.

### Which commit, confirmed by building both sides

Track T's triage named `19dc5586e` as the prime suspect and asked for a build
rather than a diff read. Done — two compilers, each seeded then rebuilt to its
own verified fixedpoint:

| commit | fixedpoint | repro |
| --- | --- | --- |
| `9c8e20c58` (parent) | `100300ef2b3a` | **OK → 1** |
| `19dc5586e` | `ecf52e008b11` | **SEGV** |

**Track T's suspicion was right.** `19dc5586e` added `PyDottedRootIsLocal` so
that a dotted call whose root is bound in this def skips the flat lookup and
falls through — correctly stopping `f.hi()` from resolving onto Pascal's `Hi`
intrinsic. Its commit message says the fallthrough yields "the scan's
tyVariant"; for a **string** receiver it does not, because the str arm was
never wired into `PyRetMethodType`, so the chase claims the receiver's type
instead.

Its control list is the tell, and this is worth recording as a test-design
point rather than as a criticism: the 13 probes included *"a str method on a
**literal**"* — which is the one str-receiver shape that still works, because a
literal receiver never reaches this arm. A str method on a **local or
parameter** was not among them. The control that was present could not have
failed for this bug.

### Suggested direction (for whoever holds the file)

In the arm quoted above, when `PyRetMethodType` returns `tyUnknown` and
`recvCi2 < 0`, ask `PyStrMethodInfo` for the method name before falling
through, and use its `retTk`. Gate it on the receiver being known-string so
`math.sqrt(2.0)` and other module-qualified calls keep their route — the same
distinction `PyDottedRootIsLocal` already draws.

Do **not** fix it by keying on `startswith`, and do not add a test that only
covers the tuple form: the tuple is not part of this defect, and a fix validated
against `test_nilpy_startswith_tuple.npy` alone would leave `.find` and
`.count` broken. Any regression test should carry a str→int row, a str→bool
row, a str→str control, and a literal-receiver control.
