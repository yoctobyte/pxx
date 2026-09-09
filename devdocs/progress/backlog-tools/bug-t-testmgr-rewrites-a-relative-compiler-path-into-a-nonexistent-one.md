---
slug: bug-t-testmgr-rewrites-a-relative-compiler-path-into-a-nonexistent-one
track: T
prio: 55
type: bug
status: backlog
owner: ""
created: 2026-09-09
found-by: frank-seven
tags: [testmgr, harness, snapshot, false-red]
blocked-by: []
summary: "testmgr rewrites recipe invocations onto its per-run compiler snapshot with COMPILER_PATH_RE = /\\./compiler/pascal26(?![-\\w])/ (testmgr.py:2029), which is UNANCHORED on the left. `../../compiler/pascal26` contains `./compiler/pascal26` at offset 4, so the leading `..` survives the substitution and the row is rewritten to `.././tmp/testmgr-<id>/compiler/pascal26` -- a path that does not exist. 5720 recipe rows spell it `./$(COMPILER)` and are fine; test/libmanifest's rows are the only ones spelling it `../../$(COMPILER)` after a `cd`, and they are the ones that break. THE FAILURE IS SILENT IN BOTH DIRECTIONS: the row carries a leading `!`, so the missing binary makes the compile step EXIT 0 and PASS while writing a log whose only content is `No such file or directory`; the next row is a bare `grep -q` for a note that is therefore absent, which prints nothing when it fails. Net effect: test_libmanifest is RED under testmgr and GREEN under gate.sh quick and bare make, and the job log is 0 bytes. Not a compiler defect and not frankZ's 102d95440, whose paired test is behaving exactly as designed."
---

# The mangling, measured

```
IN : cd test/libmanifest && ! ../../compiler/pascal26 unitalias_no_row.pas out
OUT: cd test/libmanifest && ! .././tmp/testmgr-abc123/compiler/pascal26 ...
```

`RUN_COMPILER` is absolute (`os.path.join(RUN_TMP, "compiler", "pascal26")`), so
the surviving `..` prefix turns an absolute replacement into a relative path that
resolves, from `test/libmanifest`, to `test/tmp/...`. Nothing is there.

# The fix, and the one thing to check before landing it

Consume the whole relative prefix rather than a suffix of it:

```python
COMPILER_PATH_RE = re.compile(r"(?<![\w.-])(?:\.{1,2}/)+compiler/pascal26(?![-\w])")
```

`./compiler/pascal26` matches with one repetition, `../../compiler/pascal26` with
two, and the left-hand guard stops it matching inside a longer path. Because
`RUN_COMPILER` is absolute, substituting the entire prefix is correct from any
CWD, which is what makes this a one-line fix rather than a CWD calculation.

**But the same constant is load-bearing elsewhere and this widens it.**
`testmgr.py:2155` uses `not COMPILER_PATH_RE.search(body)` to decide
`Job.pin_built`. Today a `../../compiler/pascal26` row does NOT match, so it is
classified as pinned; after the fix it matches and is classified HEAD-built.
That is almost certainly the correct classification — the row does invoke the
HEAD compiler — but it is a behaviour change to a field the pin path reads, and
it must be stated in the commit rather than discovered later. Check whether any
`pin_built` count moves, and say so either way.

Do not "fix" this by respelling the libmanifest rows as `./$(COMPILER)`. The
`cd` is the point of that test — it exists to compile a unit from inside its own
directory — and rewriting the test to suit the harness is the compiler-appeasement
shape applied to tooling.

# Why it was invisible

Green under `gate.sh quick`, green under bare `make`, red only under testmgr, and
the red carries an empty failure-detail block. So the one instrument that sees it
is the one that cannot say what it saw. See the sibling ticket
`bug-t-a-failing-grep-q-step-leaves-the-archive-unable-to-say-what-broke`.

# Provenance

frank-seven, on seven at `2d3e5fb9dfd6`, running the mangled command verbatim to
confirm the exit-0 behaviour. Reached only after establishing that frankZ's
paired test passes by hand in both arms — control silent, bare-filename arm
fires the note, exactly one of two, which is the property the pair asserts.
