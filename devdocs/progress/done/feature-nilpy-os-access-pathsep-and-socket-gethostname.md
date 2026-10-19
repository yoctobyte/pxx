---
track: N
prio: 55
type: feature
---

# os.pathsep, os.access + F_OK/R_OK/W_OK/X_OK, socket.gethostname()

Found missing 2026-10-19 in sysdash's backend.py. Its PATH search is
`any(os.access(os.path.join(d, "nvidia-smi"), os.X_OK) for d in
os.environ.get("PATH", "").split(os.pathsep))`, and it labels each sample with
the host name. All three were `undefined variable (os)` / missing.

**Fix:**
- `os.pathsep` is `':'`, next to `os.sep`.
- The `*_OK` constants use the POSIX values.
- `os.access` → `pyos_access` → `PyPalAccessMode`. ESP has no access() and FAT
  has no permission bits, so there it only checks that the path exists.
- `socket.gethostname()` returns uname's nodename (mimic_socket.pas). It raises
  OSError on an ESP, which has no uname.

**Test:** test/test_nilpy_os_access_pathsep_gethostname.npy.
