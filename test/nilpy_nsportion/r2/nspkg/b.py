# SPDX-License-Identifier: 0BSD
# The other portion: its `from . import a` is found in r1 (umqtt.robust -> simple).
from . import a


def hello():
    return a.hi() + " via b"
