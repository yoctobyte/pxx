---
track: N
prio: 30
type: feature
---

# argparse: add_mutually_exclusive_group

Vloot's entry point uses one (--console | --gui). The shim
(lib/rtl/mimic_argparse.py) now has `add_mutually_exclusive_group(required=)`
with CPython's rules: a member given a non-default value conflicts with another
("argument --gui: not allowed with argument --console"), a required group with
no member set errors ("one of the arguments --json --text is required"), and
usage shows `[a | b]` / `(a | b)`. Messages, usage and help match python3 byte
for byte (test_nilpy_argparse_mutually_exclusive_group, 9 command lines).
