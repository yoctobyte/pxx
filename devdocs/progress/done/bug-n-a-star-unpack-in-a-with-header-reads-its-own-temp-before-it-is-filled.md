---
slug: bug-n-a-star-unpack-in-a-with-header-reads-its-own-temp-before-it-is-filled
title: a star-unpack in a `with` header reads its own temp before it is filled
summary: >
  FIXED 2026-09-13. `with f(a, *rest) as x:` died with `Runtime error 216 (nil
  reference)` BEFORE `f` was entered. A star expansion lowers to an arity dispatch
  over a hidden tyClass temp, and the setup that FILLS that temp is hoisted to
  statement level -- but `with` builds its own statement SEQUENCE and puts the
  manager's evaluation inside it, so the flush landed AFTER the `cm := <manager>`
  assignment that reads the temp. Fixed by folding the header's own hoisted setup
  into the expression with `PyHoistTail` / `PyFoldHoistSince`, the idiom short-circuit
  operands already use. `with` was the ONLY statement header with this shape --
  `if`, `while`, `for`, `try` and a plain expression statement were all measured
  correct. This was the live wall on lekkerzeilen's `--shot` capture path
  (app.py:4236).
track: N
type: bug
prio: 0
owner: unassigned
status: done
---

## What was measured

2026-09-13. lekkerzeilen `--open-water --shot x.png --for 2` died with

    Runtime error 216 (nil reference)

printing nothing of its own first. The CPython twin of the same command writes a
505 KB PNG. Reduced to four lines, no lekkerzeilen module named:

    size = (3, 4)
    with Box("b", *size) as w:      # dies here
        print("body")

`Box.__init__` never ran -- the nil reference is raised while evaluating the
header, before the manager call. The sibling spellings all work:

    t = mk("a", *size)              # plain statement  -- OK
    if truthy(*size): ...           # if header        -- OK
    while ...(*size): ...           # while header     -- OK
    for x in lst(*size): ...        # for header       -- OK
    tmp = Box("b", *size)
    with tmp as w: ...              # hoisted out      -- OK

So the defect is `with` alone, and it is the HEADER, not the manager protocol.

## The mechanism

`PXXDBG=a.ast:go` showed the temp assignments present and **three statements too
late**. A star expansion cannot know the callee's arity at compile time, so it
lowers to a dispatch on `len(tmp)` over a hidden `tyClass` temp, and the code that
builds and fills that temp is pushed onto the statement-level hoist list --
correct for every other construct, because the flush happens before the statement
that reads it.

`with` is the exception because **it builds its own sequence**: `PyParseWithTail`
allocates an `AN_SEQ`, emits `cm := <manager expression>`, then `__enter__`, the
body, and `__exit__` into it. The statement-level flush lands after that whole
sequence, so the `cm := <manager>` assignment -- which is INSIDE it -- reads a temp
that is still nil.

## The fix

`compiler/pyparser.inc`, `PyParseWithTail`:

    hSave := PyHoistTail;
    PyParseBoolExpr;
    exprNode := PyFoldHoistSince(hSave, CurASTNode);

`PyFoldHoistSince` folds everything hoisted while parsing the header back INTO the
expression as a right-nested `AN_COMMA` chain, so the setup travels with the
manager expression into `with`'s own sequence and is evaluated before it. It is the
same idiom short-circuit operands already use, and it returns the node unchanged
when nothing was hoisted -- so the no-star path is untouched.

Folded BEFORE the type questions further down that function on purpose: `AN_COMMA`
carries the `ASTTk` of its Right, and `ResolveNodeRec` has an `AN_COMMA` arm that
follows Right, so both the context-manager-protocol test and the lowering see
through it.

## Verification

`test/test_nilpy_a_star_unpack_in_a_with_header.npy`, 8 rows, wired as
`test_nilpy_withstar26`:

- **A** a plain call in the header (control -- no star, must keep working)
- **B** the star hoisted out to its own statement (control -- the shape that worked)
- **C** the star IN the header (the row)
- **D** a list rather than a tuple
- **E** no `as` clause
- **F** two managers, the SECOND starred
- **G** two managers, the FIRST starred
- **H** an `if` header with a star (proves the sibling constructs are unaffected)

`Box` prints from `__init__`, `__enter__` and `__exit__`, so the 54 lines of
expected output assert the **order** of the effects, not just their values -- a
value comparison cannot see a sequencing bug.

**The `.expected` was verified against CPython, which agrees on every row.** It was
first captured from our own binary, which pins the implementation rather than the
oracle; that capture was discarded.

Pin v408 control: dies at row C with `Runtime error 216 (nil reference)` after 14
of the 54 lines.

Gate quick GREEN; full NilPy tier GREEN.

## Residual

`--shot` now reaches a **different** wall, which is the same one the interactive
`--open-water` path hits: `TypeError: expected a number, got NoneType`. Separately
owned; this ticket's symptom is gone.
