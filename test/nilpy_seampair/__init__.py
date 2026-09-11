# THE SEAM SHAPE, with the two halves that only fail TOGETHER.
#
# lekkerzeilen/platform/__init__.py selects a backend with a guarded import and
# binds the SAME alias in both arms, then probes it with getattr. That makes the
# alias a DOUBLE REGISTRATION, and FindUnitOrAlias is first-wins: the dead arm's
# row is appended first and, without dead-arm suppression, is the one every
# later lookup reaches.
#
# The guard is a module absent under BOTH CPython and pxx, deliberately. Using
# `ctypes` -- which is what the corpus writes -- would make CPython take the try
# arm and pxx the except arm, so the oracle and the subject would be running
# different code and the differential could not fail.
try:
    import a_module_that_does_not_exist_anywhere  # noqa: F401
    from . import ctypes_arm as backend
except ImportError:
    from . import pxx_arm as backend


# NOTE: this file deliberately does NOT read `backend.NAME` or any other member
# directly. A direct member read on a mis-bound alias fails LOUDLY
# (`no member NAME came of the qualifier backend`) and stops the compile before
# any getattr runs -- which is what the first draft of this fixture did, so it
# went red for a reason that had nothing to do with the fold. The sibling
# fixture test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias
# covers the direct-read face. This one covers the FOLD face, which is silent.


def probe_live():
    # getattr folded against the LIVE arm: present, so it must answer.
    f = getattr(backend, "only_in_pxx", None)
    return f() if f else "absent"


def probe_dead():
    # THE ROW THAT CATCHES THE PAIR. This name exists ONLY in the dead arm, so
    # the honest answer is "absent" -- and it is absent for a reason a single
    # half cannot produce. If dead-arm suppression regresses, the fold resolves
    # it against ctypes_arm and answers DEAD-ARM-WRONG instead.
    f = getattr(backend, "only_in_ctypes", None)
    return f() if f else "absent"
