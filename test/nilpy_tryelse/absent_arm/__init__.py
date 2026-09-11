"""The arm selected when the guarded import MISSES."""


# `WHO` is read through a unit alias; `ABSENT_WHO` through a symbol import. The
# two arm modules name their SYMBOL members differently on purpose -- see the
# package header.
WHO = "fallback"
ABSENT_WHO = "sym-fallback"
