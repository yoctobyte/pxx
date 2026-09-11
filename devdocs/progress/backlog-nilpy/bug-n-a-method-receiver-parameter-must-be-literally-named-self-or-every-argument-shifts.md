---
track: N
prio: 70
type: bug
owner: unassigned
blocked-by: []
summary: "A NilPy method's receiver parameter must be literally named `self`. TWO distinct failures, isolated by varying one method at a time: a non-`self` receiver in `__init__` never creates the attribute (`AttributeError: 'K' object has no attribute 'x'`, rc 217), and a non-`self` receiver in a plain method SEGFAULTS when the receiver is a local (rc 139) while working when it is an inline construction. Eight names swept per axis; only `self` passes either. The `@classmethod` path binds by POSITION and is correct for ANY spelling, including `zz_whatever` — so the machinery a fix needs is a few lines away. In the pin. CPython requires nothing of the name."
---

# A method's receiver parameter must be literally named `self`

```python
class K:
    def __init__(self, v):
        self.x = v
    def get(zz):
        return zz.x

k = K(5)
print(k.get())        # CPython: 5.   pxx: SIGSEGV
```

## TWO defects, not one. THE MATRIX IS THE TICKET

Three axes, because a probe that fixes any of them names the wrong mechanism:
which receiver is renamed (`__init__`, the plain method, or both) and how the
receiver is spelled at the call site. CPython gives **5** for all eight cells.
Reproduced independently by two seats, two compilers, all eight cells agreeing.

| `__init__` recv | `get` recv | call | pxx |
| --- | --- | --- | --- |
| `self` | `self` | `k.get()` | **5** |
| `self` | `zz` | `k.get()` | **SIGSEGV** (139) |
| `zz` | `self` | `k.get()` | `AttributeError: 'K' object has no attribute 'x'` (217) |
| `zz` | `zz` | `k.get()` | `AttributeError: 'int' object has no attribute 'x'` (217) |
| `self` | `self` | `K(5).get()` | **5** |
| `self` | `zz` | `K(5).get()` | **5** |
| `zz` | `self` | `K(5).get()` | `AttributeError: 'K' object ...` |
| `zz` | `zz` | `K(5).get()` | `AttributeError: 'K' object ...` |

**AXIS A — `__init__`.** A non-`self` receiver there never creates the attribute.
Row 3 is the one that settles it and it needs no other row: `get` is spelled
correctly, the receiver IS a `K`, and `x` simply does not exist. So this is not
an argument shift.

**AXIS B — a plain method.** A non-`self` receiver there SEGFAULTS when the
receiver is a LOCAL and is CORRECT when it is an inline construction. Rows 2 and
6 differ in nothing else. The receiver-expression axis again, which is this
subsystem's recurring discriminator.

**AND THE DIAGNOSTIC TEXT IS ITSELF A FUNCTION OF THE CALL SHAPE.**
`'int' object` appears in exactly ONE of the eight cells, row 4. Rows 4 and 8
have the SAME two defects live and differ only in how the receiver is spelled at
the call site, and they print DIFFERENT messages. So a one-cell probe here cannot
name a mechanism even in principle — not merely because it might pick an
unrepresentative cell, but because the message it reads is partly a property of
the probe. An argument-shift reading drawn from row 4 alone is the worked example;
row 3 refutes it.

## Swept per axis, eight names each, 2026-09-11 at compiler 76626c789ede

`self`, `this`, `obj`, `cls`, `s`, `_self`, `me`, `zz_whatever`.

- Axis A (only `__init__` varies, `get` stays `self`): `self` → 5. Every other
  name → rc 217, `AttributeError: 'K' object has no attribute 'x'`.
- Axis B (only `get` varies, `__init__` stays `self`): `self` → 5. Every other
  name → rc 139, SIGSEGV.

One name passes per axis and seven fail, identically. That is the point of
sweeping: a single probe with `s` reads as "unusual spelling", where eight rows
say the rule is a string comparison against one literal.

`cls` is on the list because the sweep put it there, not because anyone writes it
as an instance receiver — it belongs in a `@classmethod`, and there it works.
The realistic alternatives are `this`, `s`, `me`, `obj` (C++/Java habit, or a
one-liner).

## THE DECORATED PATH ALREADY BINDS BY POSITION — that is the fix direction

| form | receiver spelled | result |
| --- | --- | --- |
| `@classmethod def make(cls, v)` | `cls` | **42** |
| `@classmethod def make(kls, v)` | `kls` | **42** |
| `@classmethod def make(zz_whatever, v)` | `zz_whatever` | **42** |
| `@staticmethod def twice(v)` | n/a | **6** |
| plain `def get(self)` | `self` | **5** |
| plain `def get(zz_whatever)` | `zz_whatever` | SIGSEGV |

`zz_whatever` is the row that closes the last reading: `kls` could still be a
short table of two or three accepted spellings, and a name nobody would type
cannot be. The classmethod path
does not look at the name AT ALL — it takes the first parameter as the receiver
by POSITION and is right for every spelling. Same compiler, a few lines apart.
So the fix is to make the undecorated path do what the decorated one already
does, and a longer accepted-names table would leave the eighth name broken while
still being a string comparison.

A probe here must USE the receiver (`return cls(v * 2)`, not `return v * 2`) or
it proves only that the decorator dispatches and says nothing about what the
name is bound to.

## Second face: a CALLABLE FIELD assigned through a non-`self` receiver

Axis A again, with a worse ending. Assignment never creates the attribute, so a
class that wires a callable field in `__init__` loses it entirely — and THIS is
the shape the pin behaves differently on. It is a SEPARATE claim from the matrix
above; see the warning under "Not a regression".

Two probes, deliberately both kept, because they fail DIFFERENTLY under the same
widening and rounding them both to "it breaks" loses the discriminator:

```python
def helper():                       # A — no __slots__
    return 7
class K:
    def __init__(zz):
        zz.g = helper
    def run(zz):
        return zz.g()
print(K().run())
```

```python
def f(a, b):                        # B — __slots__
    return (a, b)
class K:
    __slots__ = ("g",)
    def __init__(s, v):
        s.g = v
ks = [K(f)]
print(ks[0].g(1, 2))
```

| probe | receiver | pinned 095ef4811a5bf6c9 | HEAD 76626c789ede |
| --- | --- | --- | --- |
| A, no `__slots__` | `zz` | **COMPILE ERROR** rc=1 | rc 217, `AttributeError: 'int' object has no attribute 'g'` |
| B, `__slots__` | `s` | **COMPILE ERROR** rc=1 | **rc 139, SIGSEGV** |
| A, no `__slots__` | `self` | 7 | 7 |
| B, `__slots__` | `self` | 7 | 7 |

**IT IS THE INTERACTION, NOT `__slots__`.** The last two rows are the control and
they matter: `__slots__` with a `self` receiver is correct under both compilers,
so nothing here is a `__slots__` defect. What `__slots__` changes is the FAILURE
MODE of the non-`self` case — adding it to probe A, changing nothing else, turns
217 into 139.

Isolated rather than guessed, one ingredient at a time. Giving probe A a
list-element receiver instead does NOT move it: it stays 217. So the receiver
expression — which discriminates the keyword door, the traffic.py wall and cell 2
of the matrix above — is not what separates these two. Both seats who looked at
this guessed wrong and neither guess was `__slots__`.

Both HEAD rows are a reportability regression: the pin REFUSES both at compile
time with `no class declares a method or callable field .g()`, and HEAD compiles
them with that same sentence as a WARNING and lets the program run into a
failure. The warning is TRUE, and it is true *because* the assignment was not
understood — the nastiest kind of honest diagnostic. **The run-time-dispatch
widening that replaced the refusal is CORRECT** and must not be read as the
cause; it simply has no arm for a class whose fields were never registered.

## Not a regression — and the pin claim SPLITS, so do not join the two halves

**The plain-attribute matrix has not moved.** Pinned 095ef4811a5bf6c9 and HEAD
give IDENTICAL results in all eight cells — same rc, same messages, including the
139 on `self`/`zz`/local. So the "a widening turned a loud stop into a run-time
failure" sentence in the second-face section **does not apply to the matrix**:
under the pin, that cell already segfaulted. A reader meeting the matrix and the
widening in one document will join them; this paragraph exists to stop that.

**The callable-field shape HAS moved**, and only it: the pin refuses both probes
at compile time and HEAD runs them. Table in that section.

Either way this is a long-standing gap and not something 2026-09-11's keyword
work at this door moved.

Attestations, kept separate because neither seat can vouch for the other's
binary: I ran the eight cells and both callable-field probes at compiler
**76626c789ede**, and the pin rows at **095ef4811a5bf6c9**. frankuser
independently reproduced all eight cells at **6d860abd8568bd03** (HEAD) and
**095ef4811a5bf6c9** (pin), and probe A at both.

## THE p90 DEMO DOES NOT HIT THIS — do not rank it up on demo proximity

Censused on lekkerzeilen's runtime modules, 2026-09-11, by two seats using
instruments that fail differently. frankuser counted instance methods from the
AST: 666, all `self`. I grepped first parameters at method indentation across 30
modules: 644 `self`, 3 `cls`, and EIGHT other names — `tile`, `t`, `ring`, `p`,
`width`, `verts`, `v`, `u`. The looser grep is the better instrument here
BECAUSE it had exceptions to explain: each was opened and is either a
`@staticmethod`, which has no receiver (app.py:3177, world.py:1087, gfx.py:495,
math3d.py:242), or a NESTED function inside a method, which is not a method
(lines.py:674, scenery.py:68, geometry.py:312). The three `cls` are the three
`@classmethod`s and none of them calls `cls`. Zero real instances.

So this is NOT wired to umbrella-lekkerzeilen and must not be re-ranked on demo
proximity. It is at 70 for the class of failure.

## Why prio 70

A silent wrong program — or a segfault — from a legal, ordinary Python spelling,
with no diagnostic at all on axis B and only a warning in the callable-field
case. Real code compiling and running wrong is what this project ranks highest,
and the failure lands far from the cause: nothing in either message names the
parameter that caused it.

## The assertion class

**A fixture asserting the plain-method defect MUST use a LOCAL receiver**, because
`K(5).get()` is green on the segfaulting case. That sentence is worth more than
the rest of this ticket to whoever writes the rows.

Beyond it: use a non-`self` name, read the attribute back — a constructor that
silently stores nothing still constructs — and vary ONE method at a time, since
varying both hides the axis-A defect behind the axis-B one and vice versa. Keep
all three axes; the matrix above is the fixture's shape.

**A fixture for the CALLABLE-FIELD face must assert the RUN, not the compile.**
Under the pin the same source is a COMPILE ERROR, so a row written against the
pin would assert a refusal that HEAD no longer produces — the pre-pin-cliff shape
arriving inside this ticket's own subject. Assert the value the program prints.

The instinct to assert the refusal is REASONABLE and that is why this warning is
here: the pin is what most people run, a refusal is the cheapest thing in the
world to pin, and `! $(COMPILER) ... && grep -q` is a row anyone can write in one
line. It is right about the pinned compiler and wrong about the tree.
And carry BOTH probes: `__slots__` is what separates 139 from 217, so a fixture
with only one of them pins one message and will read as a flake if the other
shape is ever fixed independently.
