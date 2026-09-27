# `<computed string> * n` must release the computed string. The `str * int` arm
# builds pystr_repeat's call itself and skipped the owning temp every other call
# gives a fresh string argument, so the left operand leaked once per evaluation
# (pin v443: census live=9247 over 10000 for `str(j) * 3`). Found twice on
# 2026-09-27, by the gc test's first run and independently by frankd-90.
# Each row prints how many bytes mem_alloc grew over N evaluations after a
# warm-up: 0 for every spelling. The last three are the controls that were
# always flat -- a literal on the left, a concat, a named temp.
# On pin v443 six of the eight spellings leaked. `"%d" % i * 2` read flat there
# in THIS form (returned through len), though `n + len(("%d" % j) * 3)` leaked
# live=9176/10000 before the fix; the row stays because frankd-90 asked for it.
# `keep` is the positive control: it holds each result, so rows go non-zero.
import gc
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else "check"
N = 2000
kept = []


def run(name, f):
    for i in range(200, 300):
        f(i)
    a0 = gc.mem_alloc()
    for i in range(300, 300 + N):
        r = f(i)
        if mode == "keep":
            kept.append(r)
    print(name, gc.mem_alloc() - a0 == 0)


def s_str(i):
    return len(str(i) * 2)


def s_rstr(i):
    return len(2 * str(i))


def s_pct(i):
    return len("%d" % i * 2)


def s_upper(i):
    return len("ab".upper() * 2)


def s_fstr(i):
    return len(f"{i}" * 2)


def s_concat(i):
    return len((str(i) + "x") * 2)


def s_slice(i):
    s = "abcdef"
    return len(s[1:4] * 2)


def s_bind(i):
    t = str(i) * 3
    return len(t)


def c_lit(i):
    return len("ab" * 2)


def c_concat(i):
    return len(str(i) + "x")


def c_named(i):
    t = str(i)
    s = t * 2
    return len(s)


if mode == "keep":
    run("keep", lambda i: str(i) * 2)
else:
    run("str(i) * 2", s_str)
    run("2 * str(i)", s_rstr)
    run('"%d" % i * 2', s_pct)
    run('"ab".upper() * 2', s_upper)
    run('f"{i}" * 2', s_fstr)
    run('(str(i) + "x") * 2', s_concat)
    run("s[1:4] * 2", s_slice)
    run("t = str(i) * 3", s_bind)
    run('control "ab" * 2', c_lit)
    run('control str(i) + "x"', c_concat)
    run("control t = str(i); t * 2", c_named)
