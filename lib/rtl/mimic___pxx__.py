# SPDX-License-Identifier: 0BSD
"""mimic___pxx__ -- the marker module: `import __pxx__` succeeds only under pxx.

A program that runs on both CPython and pxx picks its backend with

    try:
        import __pxx__
        BACKEND = "pxx"
    except ImportError:
        BACKEND = "cpython"

CPython has no such module, so the import raises there; here the resolver maps
it to this file. `compiler` names the implementation for a program that wants
to print it. (TSP selects its backend this way.)
"""

compiler = "pxx"
