# A guarded import NESTED inside another guarded import: three deep.
#
# `try: import X / except ImportError:` is the only conditional-compilation
# mechanism Python has -- C has a preprocessor, Python decides at import time
# and expects ImportError to be caught. NilPy answers it at COMPILE time, which
# is honouring the language's intent rather than bending it. A NESTED guard is
# therefore nested conditional compilation, and resolving an arm the program
# excluded is compiling code the source said not to compile.
#
# THE GUARD IS NEVER `ctypes`, and that is the fixture rather than a detail --
# the same constraint nilpy_tryelse's header records. The construct's real use
# is backend selection, where CPython resolves ctypes and pxx does not, so the
# oracle and the subject would run DIFFERENT arms and the differential could
# never fail. Every guard below is decided identically under both runtimes: two
# modules absent everywhere, one (`math`) present everywhere.
#
# THREE DEEP, NOT TWO, AND THE DEPTH IS THE POINT. The reported reduction was
# two deep; the pre-scan tracked ONE try and keyed its arm test on that try's
# DEPTH, so a fix that only restored the second level would pass a two-deep
# fixture and leave the third broken. The interesting element goes where the
# population does not put it.
#
# WHAT WOULD MAKE THIS FIXTURE LIE, AND IT IS NOT A NESTED-GUARD REGRESSION:
# the innermost guard needs `math` to RESOLVE under both runtimes. If pxx ever
# stops shipping it, this file silently starts testing a different program --
# the innermost guard takes its handler, `deep_miss` becomes the LIVE arm, and
# the row fails reporting a wrong value as though the arm logic had broken.
# A red here should therefore be checked against `import math` compiling AT ALL
# before it is read as a regression in guard nesting. The two
# `definitely_no_such_module_*` guards cannot drift the same way: a name that
# resolves nowhere cannot start resolving.
#
# Left as a NOTE rather than an assertion deliberately. A guard added here
# would fire on a day when `math` is the story and this fixture is not, which
# is how a correct check earns itself deleted.
#
# WHAT A REGRESSION LOOKS LIKE HERE IS A WRONG VALUE, NOT AN ERROR. A unit
# alias is first-wins, so a dead arm that gets resolved registers its alias
# BEFORE the live arm and answers every member read through it. deep_hit -- the
# arm the program selects -- is lexically LAST of the four on purpose, so it
# loses that race if any dead arm survives.
# bug-n-a-nested-import-guard-compiles-the-dead-arm

# Outer guard: MISSES under both runtimes, so the handler runs and the outer
# `else` is dead.
try:
    import definitely_no_such_module_nestguard_outer  # noqa: F401
except ImportError:
    # Middle guard: also MISSES, so its handler runs and its `else` is dead.
    try:
        import definitely_no_such_module_nestguard_mid  # noqa: F401
    except ImportError:
        # Innermost guard: RESOLVES, so the `else` runs and the handler is
        # dead. This is the inversion that matters -- the live arm sits AFTER
        # the dead one.
        try:
            import math
        except ImportError:
            from . import deep_miss as impl
            from .deep_miss import SYM_DEEP_MISS as sym
            WHICH = "deep-handler"
            FLOOR = -1
        else:
            from . import deep_hit as impl
            from .deep_hit import SYM_DEEP_HIT as sym
            WHICH = "deep-else"
            FLOOR = math.floor(2.5)
    else:
        from . import mid_else as impl
        from .mid_else import SYM_MID_ELSE as sym
        WHICH = "mid-else"
        FLOOR = -2
else:
    from . import outer_else as impl
    from .outer_else import SYM_OUTER_ELSE as sym
    WHICH = "outer-else"
    FLOOR = -3


def selected():
    return WHICH, impl.WHO, sym, FLOOR
