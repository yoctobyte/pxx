---
slug: bug-n-a-bare-nilpy-import-falls-through-to-a-host-c-header-of-the-same-name-and-says-nothing
type: bug
track: N
prio: 60
status: open
owner: frankuser
---

## summary

A bare NilPy `import X` whose Pascal chain is closed (X not in
`PyRtlUnitServesPython`, no `mimic_X`) falls through to the HOST's
`/usr/include/X.h` and binds it silently. The program then fails with a
diagnostic about a C signature it never mentioned — or, when the arities happen
to agree, **compiles and returns a wrong value.**

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

## NOT "close the C route" — the C route is deliberate

`pxx-crash-course.md` and the comment at `pasparser_proc.inc:6330` both say a bare
NilPy import reaching a C header is designed behaviour, and imports resolving OURS
FIRST is for PREDICTABILITY. So the defect is not the route, it is that the route
is taken **silently** when the name is a stdlib module name.

## recommendation, narrow on purpose

Say it. When a bare NilPy import binds a C header AND the name is a CPython
stdlib module name, emit a warning naming the header path — `import time bound
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
