---
slug: bug-n-a-module-level-regex-call-recompiles-and-leaks-its-pattern
title: a module-level regex call recompiles and leaks its pattern
summary: >
  FIXED. Every module-level `re` convenience wrapper -- findall, split, match,
  search, sub, subn, finditer, fullmatch -- called MakePattern on EVERY call and
  nothing ever freed the TPattern, because the TMatch/TPyList handed back may
  reference p.compiled. 3000 iterations of `re.findall("a","banana")` left 8349
  objects live (~2.78 each); precompiling once left 8. Fixed by giving
  MakePattern a cache, which is what CPython does and is also where all 19 call
  sites already funnel, so it is one function. NO EVICTION, deliberately:
  CPython clears past _MAXCACHE and can because it is refcounted, we would leave
  a TMatch holding a dangling p.compiled -- so the residue is bounded by the
  DISTINCT patterns a program's source mentions instead of by how often it
  loops. Also a speed fix; ReCompile ran on every call.
track: N
type: bug
prio: 55
owner: frankS
status: resolved
---

## Measured 2026-09-13 (frankS), 3000 iterations, -dPXX_ALLOC_CENSUS

    re.findall("a", "banana")            live=8349    ~2.78 per iteration
    re.findall("z", "banana")            live=8335    0 matches, SAME leak
    re.findall("z[0-9]+q", "banana")     live=8335    longer pattern, same
    re.match("b", "banana")              live=10975   ~3.66, returns no list
    p = re.compile("a"); p.findall(...)  live=8       ZERO

## The controls are what identified it, and one of them nearly misled me

The first reading was "a container return leaks", because this was found while
auditing a container-returning callable value. Three rows kill that:

    "b,a,n".split(",")  x3000     live=1     a fresh TPyList per iteration, CLEAN
    ["a","a","a"]       x3000     live=3     CLEAN
    struct.calcsize     x3000     live=3     CLEAN

`str.split` is the sharp one -- same shape, same loop, fresh list every time,
and no leak at all. The 0-match and longer-pattern rows then rule out the match
results and the pattern's size, and `re.match` -- which returns no container --
leaking MORE than findall rules out the return value entirely. What is left is
the only thing every wrapper does and the precompiled spelling does not:
`MakePattern` per call.

## The fix, and why not the obvious one

Freeing the TPattern in each wrapper is the obvious fix and is wrong: the TMatch
and TPyList handed back may reference `p.compiled`, so freeing it trades a leak
for a use-after-free. Caching avoids the question -- nothing is ever freed early
because nothing is freed at all.

No eviction. CPython clears `re._cache` past `_MAXCACHE` and is safe doing so
because a pattern still in use survives on its refcount; we have no such
guarantee, and a clear would leave any live TMatch dangling. So the residue is
O(distinct patterns in the source) rather than O(calls) -- which is the actual
defect, since the first is a property of the program text and cannot grow at
run time.

The cache is keyed on the PAIR held in two parallel arrays, not on a
concatenated string: a pattern may contain any byte, including any separator, so
no flattened key is injective. (This unit also has no IntToStr -- it uses only
`regex` and `pylib` -- which is how the first attempt failed, and it failed at
FIXTURE time and not at build time, because `compiler.pas` never imports `re`.
That is the fixedpoint's second scope limit doing exactly what CLAUDE.md says it
does.)

## Identity now matches CPython, and that is not incidental

`re.compile("a") is re.compile("a")` answers True here and in CPython; before
the cache it was False. It is asserted in the fixture because it catches a
regression by OUTPUT, independently of the census -- unfixed, the fixture fails
on that line AND on the leak bound.

## Verified

`test_nilpy_a_module_level_regex_call_caches_its_pattern.npy`, built
`-dPXX_ALLOC_CENSUS` and wired with both an expect_same and an
`assert_no_leak.sh ... 400`. Negative control, measured by reverting re.pas with
`git checkout HEAD --` and recompiling: **live=24029 unfixed against 75 fixed**,
and the output differs at the identity line. 3000 iterations is the point -- a
handful of calls cannot separate a per-iteration leak from a fixed residue.

`test_nilpy_re`, `test_nilpy_re_split_subn_finditer`, `test_nilpy_raw_string_set`,
`test_nilpy_dotted_package_import`, `test_nilpy_import_py_from_library_path`
(with its `-Futest/nilpylib`) and the Pascal-side `lib_regex.pas` all pass.
Sharing is safe to introduce: the only writes to `.pattern`/`.compiled` in the
unit are MakePattern's own, and nothing frees a TPattern anywhere.

## What this did NOT fix

The fixture's residue did not go to zero, and the remainder is a different bug:
a call result DISCARDED in a boolean context is never released, which is not an
`re` bug at all (`if "b,a".split(","):` leaks the same way, while a discarded
list LITERAL is clean). Filed as
[[bug-n-a-call-result-discarded-in-a-boolean-context-is-never-released]]. The
fixture binds its `re.match` result to a local specifically so that this
fixture's bound stays about the pattern cache.
