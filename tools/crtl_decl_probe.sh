#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Which crtl declarations have no implementation?
#
# WHY. A function DECLARED in lib/crtl/include/** but implemented nowhere does
# not fail to build -- the call becomes a glibc dynamic import, the program runs
# fine on the dev box, and the only symptom is that the binary is no longer
# statically linked. It then cannot run on a cross target without a sysroot, or
# on ESP, or anywhere libc-free. That shape has now bitten three times
# (bug-cfront-spurious-dt-needed-libc-with-no-imports,
# bug-b-crtl-wchar-wctype-declared-not-implemented,
# bug-b-crtl-basic-posix-io-not-implemented -- the last of which was read,
# write, close and lseek).
#
# HOW. For each prototype, build a program that includes only its header and
# takes the function's ADDRESS. Taking the address forces a reference without
# needing valid arguments or a runnable call, so an unimplemented function shows
# up as a dynamic import. Verified against a known case before being trusted:
# CALLING write() produced the same import that taking its address did.
#
# Usage: tools/crtl_decl_probe.sh          (no rebuild; uses the pinned stable)
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
PX="${PXX_STABLE:-./stable_linux_amd64/default/pinned}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

python3 - > "$W/decls.txt" <<'PYEOF'
import os, re
root = 'lib/crtl/include'
proto = re.compile(r'^\s*(?!typedef|#|\})(?:[A-Za-z_][\w \t\*]*?)\b([A-Za-z_]\w*)\s*\([^;{]*\)\s*;\s*$')
for dirpath, _, files in os.walk(root):
    for fn in sorted(files):
        if not fn.endswith('.h'): continue
        p = os.path.join(dirpath, fn)
        hdr = os.path.relpath(p, root)
        for line in open(p, errors='replace'):
            m = proto.match(line.rstrip('\n'))
            if m and m.group(1) not in ('if','while','for','switch','return','sizeof'):
                print(f"{hdr}\t{m.group(1)}")
PYEOF
sort -u "$W/decls.txt" -o "$W/decls.txt"

ok=0; miss=0; fail=0
while IFS=$'\t' read -r hdr name; do
  printf '#include <%s>\nvoid *volatile p;\nint main(void){ p = (void*)&%s; return p != 0; }\n' \
    "$hdr" "$name" > "$W/d.c"
  if ! $PX "$W/d.c" "$W/d_bin" >/dev/null 2>&1; then
    printf 'BUILDFAIL  %-16s %s\n' "$hdr" "$name"; fail=$((fail+1)); continue
  fi
  if objdump -T "$W/d_bin" 2>/dev/null | grep -q "UND.*\b$name\$"; then
    printf 'UNIMPL     %-16s %s\n' "$hdr" "$name"; miss=$((miss+1))
  else ok=$((ok+1)); fi
done < "$W/decls.txt"

echo "---"
echo "declared: $((ok+miss+fail))   implemented: $ok   unimplemented: $miss   build-fail: $fail"
[ "$miss" -gt 0 ] && echo "(each UNIMPL is a silent glibc dependency for anyone who calls it)"
exit 0
