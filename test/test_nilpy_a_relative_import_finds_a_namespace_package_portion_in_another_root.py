# SPDX-License-Identifier: 0BSD
# A namespace package split across two roots, as micropython-lib ships umqtt:
# robust.py's `from . import simple` lives in another directory. CPython finds
# it in any portion; run with PYTHONPATH=test/nilpy_nsportion/r1:test/nilpy_nsportion/r2.
from nspkg.b import hello

print(hello())
