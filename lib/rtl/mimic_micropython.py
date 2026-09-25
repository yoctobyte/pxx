# SPDX-License-Identifier: 0BSD
"""mimic_micropython -- MicroPython's `micropython` module, the part device
drivers use: `from micropython import const`.

Reached as `import micropython`, which the NilPy import resolver maps to this
file. In MicroPython, const() marks a module-level integer as a compile-time
constant so the bytecode compiler can fold it; the VALUE is the argument,
unchanged. NilPy compiles ahead of time and folds what it can anyway, so the
function is the identity, and a driver written as

    _SET_CONTRAST = const(0x81)

means here exactly what it means there. Nothing else from the module is
provided: its other members (mem_info, opt_level, schedule, alloc_emergency_
exception_buf, ...) describe MicroPython's own interpreter and have no
counterpart in a compiled program.
"""


def const(value):
    return value
