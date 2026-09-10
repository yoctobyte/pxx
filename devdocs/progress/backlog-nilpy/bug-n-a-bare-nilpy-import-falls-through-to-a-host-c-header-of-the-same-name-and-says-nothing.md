---
slug: bug-n-a-bare-nilpy-import-falls-through-to-a-host-c-header-of-the-same-name-and-says-nothing
type: bug
track: N
prio: 35
status: open
owner: frankuser
---

## summary

A bare NilPy `import X` has **three** routes, and only one of them is silent.
`mimic_X.pas` in scope -> substitution, which prints `note: X -> mimic_X (shim,
subset)`. `X` in `PyRtlUnitServesPython` -> `lib/rtl/X.pas`. Neither -> the HOST's
`/usr/include/X.h`, bound with **no note and no refusal**. The program then fails with a
diagnostic about a C signature it never mentioned — or, when the arities happen
to agree, **compiles and returns a wrong value.**

## the three routes, measured

At compiler `b092b705aacb`, one `-Fu` dir holding `mimic_dflt.pas` (frankB's
probe, reproduced here):

```
import mimic_dflt  -> REFUSED: "mimic_dflt is the Pascal unit ... not a Python
                      module ... name it with its extension"
import dflt        -> COMPILED, reached the shim, and printed
                      note: dflt -> mimic_dflt (shim, subset)
import zlib (pre-fix) -> bound /usr/include/zlib.h, silently
```

**This ticket originally said "a bare NilPy import resolves to Python only".** That
was a quotation from the first diagnostic above, over-generalised: that message is
about the unit's OWN name, and the shimmed name reaches the same Pascal unit
correctly and announces it. Corrected here because the wrong version hides the
actual mechanism, which is that **the NAME decides the route and only one route is
quiet.**

## measured, and the arity-agreement case is real

`import zlib` before `zlib` was added to the curated list (fixed in `80d71d782`,
so reproduce at `09976a4e8`):

```
zlib.crc32(b"hello")        -> error: no overload of crc32 matches these arguments
zlib.crc32(b"hello", 0)     -> same
zlib.crc32(0, b"hello", 5)  -> COMPILES, links system libz, prints 1577690842
                               CPython's answer is 907060870
```

C's is `crc32(uLong, const Bytef*, uInt)` — three arguments — so the two CPython
spellings cannot match and the three-argument spelling does. The bytes object's
pointer is passed where a `const Bytef*` is wanted, and the result is a plausible
wrong number with no diagnostic.

## the population on this box: 16

CPython stdlib names with a matching `/usr/include/<name>.h`, NOT in
`PyRtlUnitServesPython` (17 entries) and with no `mimic_` shim (18):

```
curses  errno  fcntl  fnmatch  getopt  glob  grp  locale
lzma    pty    pwd    sched    signal  syslog termios time
```

`time`, `signal`, `errno`, `locale` and `glob` are ordinary imports in real
Python. **And the population is HOST-DEPENDENT, which is the nastier half**: it is
a function of what is installed, so the same program fails differently on two
boxes and a census compared across machines sees two walls for one cause. Without
zlib-dev the same `import zlib` gives `no member crc32 came of the qualifier zlib`
instead.

## RE-PRIORITISED 60 -> 35 on 2026-09-11, and the measurement is why

frankB named the question that sizes this: how many of the 16 have a
`lib/rtl/<name>.pas` today the way `zlib` did? Those are the rows where the
silence hides a WORKING IMPLEMENTATION rather than merely producing a confusing
error, and frankB's read was that they would justify prio 60 on their own.

**Measured: ZERO of 16.**

```
costs a working unit (the zlib shape) : 0
costs only a confusing error          : 16
  curses errno fcntl fnmatch getopt glob grp locale
  lzma pty pwd sched signal syslog termios time
```

So `zlib` was the only instance of the expensive shape and it is fixed. What
remains is a diagnostic-quality defect on 16 ordinary module names, which is real
and is not prio 60.

**The name-equality test is the RIGHT test here, which is not obvious and was
checked rather than assumed** — testing a name instead of a capability is this
project's house error. Route 2 is name-based: all **17 of 17** listed names have a
`lib/<name>.pas` of exactly that name. So a capability living under a different
filename is not reachable as `import <name>` by any route, and therefore cannot be
something the silence is hiding.

## THE FORWARD-LOOKING REASON TO FIX IT ANYWAY, which the count does not capture

The population is zero TODAY because I closed the only member an hour ago. The
trap is not a list of names, it is a RECURRING step: add a Python surface to a
`lib/rtl/<name>.pas`, forget the `PyRtlUnitServesPython` entry, and you get
exactly the zlib failure -- a working unit in the tree, a host header answering
instead, and a plausible wrong number if the arities happen to agree. I walked
into it while holding both halves and spent five experiments on the wrong file.
Anyone adding the next `lib/rtl` Python surface walks into the same one.

## NOT "close the C route" — the C route is deliberate

`pxx-crash-course.md` and the comment at `pasparser_proc.inc:6330` both say a bare
NilPy import reaching a C header is designed behaviour, and imports resolving OURS
FIRST is for PREDICTABILITY. So the defect is not the route, it is that the route
is taken **silently** when the name is a stdlib module name.

## recommendation, narrow on purpose — and it is now "make one arm match its siblings"

frankB's framing, which is better than the one this ticket was filed with: **the
frontend already owns a good diagnostic for two of the three routes, and the
header arm is the only decision of the three that neither refuses nor announces.**
`import mimic_dflt` is refused with the fix in the message; `import dflt` succeeds
and prints a `note:`. So this is not new machinery, it is the third arm saying
what its siblings already say.

Say it. When a bare NilPy import binds a C header AND the name is a CPython
stdlib module name, emit a note naming the header path — `import time bound
/usr/include/time.h, not a Python module`. That is a one-line fact the reader
cannot otherwise get, it leaves the designed route open, and it scopes the noise
to the 16 names above rather than to every C-header import.

The alternative — refusing when the name is a stdlib module — is a behaviour
change that would break any program deliberately importing a C header whose name
collides, so it should not be taken without someone wanting it.

## how it wasted a session, which is the argument for the warning

I added a declaration to `lib/rtl/zlib.pas` and then ran **five** experiments on
it — changed the arity, the parameter types, the return type, removed the default
— and every one changed nothing, because none of them were ever consulted. I had
a positive control (`base64.b64encode`, the identical `(const data: Variant)`
shape) and it PASSED, which confirmed the shape was fine and sent me to the wrong
unit. The thing that broke it open was a probe whose correct answer only the
header could produce: a three-argument call.

**When every edit to a declaration changes nothing, stop editing the declaration
and ask what else answers to that name.**
