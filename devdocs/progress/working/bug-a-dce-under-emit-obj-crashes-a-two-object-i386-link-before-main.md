---
slug: bug-a-dce-under-emit-obj-crashes-a-two-object-i386-link-before-main
track: A
prio: 55
type: bug
status: working
found: 2026-09-19
found-by: frankS
owner: frankb-8e
blocked-by: []
summary: "`--dce --emit-obj --target=i386` produces objects that LINK cleanly and then die before main: two i386 objects (test/c_obj_fnptr_a.c + _b.c, the callback-table pair) link with `gcc -m32 -no-pie` and the program exits rc=138 having printed nothing, where `--no-dce` prints `20 11`. x86-64 is correct both ways, so it is i386-specific and not the pass in general. Reachable TODAY with an explicit `--dce` -- this is not a regression, it is an existing shipping path nobody had run on i386. Found while measuring whether `--emit-obj` should enable the pass by default (bug-a-emit-obj-retains-pxxassert-...): the answer is NOT YET, and this is why. The single-object rows pass on i386, so only a TWO-OBJECT link exposes it."
---

# `--dce` under `--emit-obj` crashes a two-object i386 link before main

## Measured

At `1e9990bdb070`, `converged after 1 round(s)`:

| build | i386 | x86-64 |
| --- | --- | --- |
| `--no-dce --emit-obj` | rc=0, `20 11` | rc=0, `20 11` |
| `--dce --emit-obj` | **rc=138, no output** | rc=0, `20 11` |

    ./compiler/pascal26 --emit-obj --dce --target=i386 test/c_obj_fnptr_a.c a.o
    ./compiler/pascal26 --emit-obj --dce --target=i386 test/c_obj_fnptr_b.c b.o
    gcc -m32 -no-pie a.o b.o -o f386     # links cleanly
    ./f386                               # rc=138, prints nothing

`make test-emit-obj` reports it as `expect_same: MISMATCH [fnp_386]`, expected
`20 11`, actual empty, with `User defined signal 1` on the line above.

## Why it was not found before

The pass has been allowed under `-c` since 2026-09-02 and the emit-obj rows
assert plenty about it — **on x86-64, and on a single object.** This fixture is
the only two-object i386 link in the tier, and it runs without `--dce` today, so
nothing exercised the combination. The link SUCCEEDS, which is the expensive
shape: no undefined reference, no diagnostic, a crash before `main`.

## What it is not

Not a regression and not caused by any default. `--dce` is opt-in on this path
today and reproduces with the flag spelled explicitly. It was found by turning
the default on experimentally; that default was **reverted**, and this ticket is
the reason.

## The lead

`dce.inc`'s own note is the place to start: the two tables it did not originally
compact are the **init/fini thunk offsets**, stated raw in `.rela.init_array` /
`.rela.fini_array`, and *"turning the refusal off without them SEGFAULTS BEFORE
main"* — which is exactly the observed symptom, one target over. The x86-64 arm
handles them; the question is whether the i386 object writer states those
offsets somewhere the pass does not re-patch. Two objects matter because each
carries its own init/fini array, so the second object's thunks are the ones that
have to survive a compaction they did not participate in.

Not measured: whether one object alone with a non-empty `.init_array` reproduces
it, which would separate "i386 thunk offsets" from "two objects".
