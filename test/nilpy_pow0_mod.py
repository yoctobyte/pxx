# Imported by test_nilpy_pow_zero_base_in_an_imported_module.npy, and the
# IMPORT is the whole point: `**` in a module installs PyPowHook, and a module
# that is imported does not — the scan runs before the import pass, and a unit's
# initialisation section runs before the main body where the assignment sits.
# So these rows, and only these rows, reach pypow_cx's hookless fallback, which
# used to compute exp(e * ln(0.0)) and raise ValueError: math domain error.
# Measured against CPython 2026-09-12; this is what lekkerzeilen's hull tables
# do at module level (math.sin(0.0) ** fine) and what stopped the program.
import math

ZERO = 0.0
HALF = 0.5


def zpow(b, e):
    return b ** e


# module level, at import time — the position that raised
AT_IMPORT = ZERO ** HALF
AT_IMPORT_CALL = zpow(0.0, 4.5)
AT_IMPORT_SIN = math.sin(0.0) ** 2.5

# the zero exponent takes the OTHER arm of the same row: 1.0, not 0.0
AT_IMPORT_E0 = ZERO ** (HALF - HALF)

# and a nonzero base through the same hookless path, so the row that answers
# 0.0 is not the only thing this fixture can observe. Read as a TOLERANCE, never
# as digits: this path is exp(e * ln(b)) and is a last-ulp away from the RTL's
# Power — measured, sqrt(2) comes back 1.414213562373095 against CPython's
# ...0951. That difference is the hookless fallback's accuracy and is a separate
# (F-lane) question; pinning it here would redden this row for no defect.
AT_IMPORT_NZ = 4.0 ** HALF
AT_IMPORT_NZ_OK = abs(AT_IMPORT_NZ - 2.0) < 1e-12
