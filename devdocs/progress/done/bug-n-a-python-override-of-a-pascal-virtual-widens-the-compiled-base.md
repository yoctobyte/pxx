---
track: N
prio: 70
type: bug
---

# An unannotated override of a Pascal virtual widens the compiled base

Found building songformatter (2026-10-27, peer session):

    class CP(configparser.ConfigParser):
        def optionxform(self, optionstr):
            return optionstr
    cfg = CP(); cfg.add_section("Render"); print(cfg.has_option("Render","Font"))

segfaulted in has_option (`repz cmpsb`). A plain ConfigParser printed False.

**Cause.** The override block in PyRegisterClassMembers joins a variant override
with an AnsiString base through PyOverrideRetJoinsToVariant, and it does that
by setting the BASE's result to Variant. That is sound for a Python base,
because the pre-pass runs before the base body is compiled. configparser.pas is
compiled Pascal whose has_option calls optionxform through the slot and reads
an AnsiString. test_nilpy_configparser.npy annotates `s: str -> str`, so it
never took the join.

**Fix.** The join (and the widening) applies only when the base class is
Python (a py module, the main program, or a pylib class, which keeps its
long-standing behaviour). A Pascal-unit base keeps its declared signature, and
the override adopts it.

Test: test/test_nilpy_an_unannotated_override_of_a_pascal_virtual.npy (CPython
oracle). Pin v452 fails it.
