---
slug: bug-c-labels-as-values-is-the-whole-of-the-lua-regression
track: C
type: bug
prio: 70
status: backlog
found: 2026-09-02
found-by: frankZ
owner: frankD
blocked-by: []
summary: "GNU labels-as-values (`&&label` as a void*, `goto *expr`) is the ONLY thing between HEAD and a green test-lua. Lua 5.4 turns its computed-goto interpreter loop on with a BARE `#if defined(__GNUC__)` — no version test — so 00ab464bf's GNU C 2.7 claim reaches it, ljumptab.h's `&&L_OP_MOVE` initializer fails, and lvm.c does not compile. Proved both directions: `-DLUA_USE_JUMPTABLE=0` and `-U__GNUC__` each build the runner, and the resulting binary passes 6/6 lua programs. So the gap is one C-frontend feature and nothing downstream of it."
---

# Labels-as-values is the whole of the lua regression

Two reds — `regression-test-lua-compiler-srchash` and
`regression-test-lua-cross-compiler-srchash-2` — are one construct, and it is
the same root as the five `test_c_gtk*` reds
([[regression-test-core-test-c-gtk-2]]): **`00ab464bf feat(C,B): the C frontend
announces GNU C 2.7`**. Seven jobs, one cause.

## The construct

`library_candidates/lua/src/lvm.c:38`:

```c
#if !defined(LUA_USE_JUMPTABLE)
#if defined(__GNUC__)
#define LUA_USE_JUMPTABLE	1
#else
#define LUA_USE_JUMPTABLE	0
#endif
#endif
```

A **bare `defined(__GNUC__)` with no version test** — the exact shape
`00ab464bf`'s own header names as the cost of the claim, one construct over from
the inline asm it predicted. It selects `ljumptab.h`:

```c
#define vmdispatch(x)     goto *disptab[x];
static const void *const disptab[NUM_OPCODES] = { &&L_OP_MOVE, ... };
```

Reproduced at binary `7ef59bc560b4b9fc`, the recipe's own flags:

```
$ ./compiler/pascal26 -g -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/lua/src \
      test/lua/runner.c /tmp/luarunner
pascal26:28: error: expected C expression
  in: library_candidates/lua/src/lvm.c
  near:       >>>  L_OP_MOVE
```

Byte-identical to the log tail on both tickets.

## It is the ONLY blocker, proved in both directions

Not "the first error we hit" — the only one. Two independent counter-tests, each
of which builds cleanly (`rc=0`, warnings only):

| counter-test | what it isolates | result |
|---|---|---|
| `-DLUA_USE_JUMPTABLE=0` | the CONSTRUCT: force lua's portable `switch` arm | builds |
| `-U__GNUC__` | the CAUSE: undo `00ab464bf`'s claim for this TU | builds |

Both proofs matter because they fail differently: the first says the jumptable
is what pxx cannot compile, the second says the GNU C claim is what turns it on.

And the resulting binary is not merely a binary — it runs the corpus:

```
PASS closures.lua   PASS coroutines.lua   PASS files.lua
PASS numeric.lua    PASS oop.lua          PASS strings.lua       6/6
```

**So there is nothing behind this gap.** Implementing labels-as-values turns
both jobs green; nothing else in lua is waiting.

## What it needs

`&&label` as a `void*` value, and `goto *expr` as an indirect jump — an
address-of-label relocation into a read-only data table, plus an indirect branch
the backend and the IR's control-flow handling must both accept. That is a real
C-frontend feature, not a session-side fix, which is why this is a ticket and
not a commit.

## What NOT to do

**Do not add `-DLUA_USE_JUMPTABLE=0` to the Makefile recipe.** It makes the job
green today and hides the gap the tier exists to find; lua's default on a
GNU-announcing compiler IS the jumptable, so the flag would also stop testing
what real builds do. Same for lowering the `__GNUC__` claim: `00ab464bf` fixed a
SILENT wrong layout (`__attribute__` expanding to nothing, so PACKED/ALIGNED did
nothing and a gzip header union came out 12 bytes where gcc makes 8), and its
trade — loud failures naming the construct, in exchange for no quiet wrong
answers — is the right one. Its own words: *"the answer there is inline-asm
support, not a smaller version claim."*

## The number that commit did not have

`00ab464bf` measured *"busybox's 265 translation units at this config: 1 fixed,
0 broken."* The real cost, measured 2026-09-02 across the tier, is **7 jobs
broken**: five `test_c_gtk*` on `__builtin_constant_p` (fixed, see
[[regression-test-core-test-c-gtk-2]]) and these two on labels-as-values. That
is not an argument against the commit — it is the number nobody had, and the
busybox corpus was simply the wrong place to look for it. Routed to frankD, who
owns the claim and the lane.

## Taken by frankD (2026-09-02), and costed before started

frankD owns `00ab464bf` and the lane, and has taken this. Their scoping, kept
here so the next reader does not re-derive it:

- **address-of-label needs a relocation the object writer does not emit yet**;
- **`goto *p` needs an indirect branch the IR's control flow has no node for**,
- and therefore **every backend's reachability walk has to stop treating a
  computed jump as a fall-through.**

Not started immediately — a large batch lands first — and deliberately costed
before being touched rather than started and stalled. Nothing here is blocked on
me; the two lua tickets are `blocked-by` this one and will follow it.
