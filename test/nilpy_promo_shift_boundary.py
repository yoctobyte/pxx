# A promotable shift now has an INLINE arm (promocore.pas PXXPromoShl/Shr) as
# well as the bignum one. The danger is not slowness, it is the two arms
# DISAGREEING: a value that takes the inline path and one that takes the bignum
# path must give the same answer, and the interesting rows are exactly the ones
# that straddle the guard.
#
# The guard is |av| < 2^(62-k) for `<<`, and av >= 0 for `>>`. So for each shift
# count the rows below step ACROSS that bound rather than sampling near it --
# a value just inside and just outside take different arms and must agree.
#
# Oracle is CPython: run this file under both and diff. Every line prints, so a
# divergence names its own row instead of collapsing to a pass/fail.

SHIFTS = [0, 1, 5, 13, 17, 31, 32, 33, 34, 61, 62, 63, 64, 100]

# READOUT NOTE: these print with commas rather than `"%d" %`. Not style --
# `"%d" % -9223372036854775808` prints a bare "-" under pxx today, at exactly
# Low(Int64) and at no neighbouring value, so a %d readout manufactures a
# disagreement out of a value that is correct. print() and %s are both fine.
# bug-a-low-int64-renders-as-a-bare-minus-under-percent-d-and-abs-of-it-stays-negative
def probe(label, v):
    for k in SHIFTS:
        print(label, "v=", v, "k=", k, "shl=", v << k, "shr=", v >> k)

# Values that are machine words and stay machine words.
probe("small", 0)
probe("small", 1)
probe("small", 7)
probe("small", 12345)

# The audio RNG's actual population: a 32-bit xorshift state.
probe("rng", 0xFFFFFFFF)
probe("rng", 0x9E3779B9)

# STRADDLE THE GUARD. For each k the inline arm admits |av| < 2^(62-k); these
# walk a value from well inside to well outside, so consecutive rows take
# different arms and must agree.
for k in SHIFTS:
    if k > 62:
        continue
    lim = 1 << (62 - k)
    for v in (lim - 1, lim, lim + 1, 2 * lim):
        print("straddle k=", k, "v=", v, "shl=", v << k)

# Already past a machine word on the way in: the bignum arm on both sides.
probe("big", 1 << 63)
probe("big", 1 << 200)
probe("big", (1 << 64) + 12345)

# NEGATIVES. `>>` deliberately refuses the inline arm for these because Pascal
# `shr` is logical and Python `>>` floors; `<<` admits them within the bound.
# A wrong answer here is silent, so these rows matter more than the fast ones.
probe("neg", -1)
probe("neg", -7)
probe("neg", -12345)
probe("neg", -(1 << 40))
probe("neg", -(1 << 63))

# Floor semantics for `>>` on negatives, where truncation and flooring differ:
# every one of these has a nonzero remainder, which is the only case where the
# two disagree.
for v in (-1, -3, -5, -7, -9, -1023, -1025):
    for k in (1, 2, 3, 10):
        print("floor v=", v, "k=", k, "shr=", v >> k)

print("DONE")
