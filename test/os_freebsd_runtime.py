# NilPy runtime under --os=freebsd: dict, sort, sys.argv, os.environ.
# Run by `make test-freebsd` on both kernels; output must match.
# feature-port-freebsd-native
import os
import sys
d = {"b": 2, "a": 1}
print("nilpy", len(sys.argv), sorted(d.keys()), sum(d.values()))
print("probe=" + os.environ.get("PXX_TEST_PROBE", "(unset)"))
