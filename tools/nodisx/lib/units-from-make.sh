#!/bin/sh
# units-from-make.sh TOP LOG PROG... : turn a `make V=1` log of an autotools
# (automake + libtool) build into the two files an onsite.sh replays, on
# stdout, separated by a line `%%`:
#
#   unit lines:  <obj> <dir> <src> <flag>...
#       obj and dir relative to TOP; src relative to dir; flags are the -D,
#       -U, -I, -isystem (as -I) and -include words of the compiler command, as written (they
#       are relative to dir too, and keep configure's shell quoting; a
#       double-quoted word with spaces stays one word, quotes included)
#   link lines:  <prog> <obj>...
#       every object the program's link line names, archives (`ar cr`)
#       expanded to their members, all relative to TOP
#
# HOST SIDE (record.sh): needs awk. Each compile is taken from the line the
# compiler actually ran -- a bare `gcc ... -c` (automake) or `libtool:
# compile:` (libtool's own echo) -- never from libtool's wrapper line, which
# would count it twice. The directory comes from make's `Entering directory`.
set -eu
TOP=$(cd "${1:?usage: units-from-make.sh TOP LOG PROG...}" && pwd)
LOG=${2:?usage: units-from-make.sh TOP LOG PROG...}
shift 2
awk -v top="$TOP" -v progs="$*" '
function rel(d, p,   parts, n, i, out, k, stack) {
  # normalise d/p and make it relative to top
  if (substr(p, 1, 1) == "/") s = p; else s = d "/" p
  n = split(s, parts, "/"); k = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") { if (k > 0) k--; continue }
    stack[++k] = parts[i]
  }
  out = ""
  for (i = 1; i <= k; i++) out = out "/" stack[i]
  if (out == "") out = "/"
  if (index(out, top "/") == 1) return substr(out, length(top) + 2)
  if (out == top) return "."
  return out
}
function byname(a,   b, k, hit, n) {
  # an archive linked by a path it was not BUILT at: e2fsprogs builds
  # lib/ext2fs/libext2fs.a and links ../lib/libext2fs.a, a link make makes
  # after `ar`. Take the one built archive with that file name; an
  # ambiguous name stays missing.
  if (a in members) return a
  b = a; sub(/.*\//, "", b); n = 0
  for (k in members) { hit2 = k; sub(/.*\//, "", hit2); if (hit2 == b) { hit = k; n++ } }
  return n == 1 ? hit : a
}
BEGIN { np = split(progs, P, " "); for (i = 1; i <= np; i++) want[P[i]] = 1; dir = top; nu = 0; sp = 0 }
# a stack: after `Leaving directory` the commands belong to the parent make again
# (dropbear links its programs at the top after the libtomcrypt and
# libtommath sub-makes; without the pop they resolved inside libtommath/)
/Entering directory/ {
  s = $0; sub(/.*Entering directory ./, "", s); sub(/.$/, "", s); stk[++sp] = dir; dir = s; next
}
/Leaving directory/ { if (sp > 0) dir = stk[sp--]; else dir = top; next }
{
  line = $0
  # a command make echoes over several lines (a trailing backslash, as
  # the e2fsprogs misc/Makefile writes the debugfs sources) is ONE command.
  # (no apostrophes in these comments: the program is single-quoted)
  while (line ~ /\\$/ && (getline more) > 0) { sub(/\\$/, " ", line); line = line more }
  if (line ~ /^libtool: compile: +/) sub(/^libtool: compile: +/, "", line)
  else if (line ~ /^libtool: link: +/) sub(/^libtool: link: +/, "", line)
  else if (line !~ /^(gcc|cc|ar) /) next
  n = split(line, raw, /[ \t]+/)
  # rejoin a double-quoted word that held spaces (the dhcpcd rbtree unit:
  # "-D__predict_false(exp)=__builtin_expect((exp) ? 1 : 0, 0)"), quotes kept
  # for the eval in onsite.sh; split alone dropped it with no error
  m = 0
  for (i = 1; i <= n; i++) {
    t = raw[i]
    if (substr(t, 1, 1) == "\"" && (length(t) == 1 || substr(t, length(t)) != "\""))
      while (i < n) { i++; t = t " " raw[i]; if (substr(raw[i], length(raw[i])) == "\"") break }
    w[++m] = t
  }
  n = m
  if (w[1] == "ar") {
    # ar cr ARCHIVE member...
    a = rel(dir, w[3]); members[a] = ""
    for (i = 4; i <= n; i++) if (w[i] ~ /\.o$/) members[a] = members[a] " " rel(dir, w[i])
    next
  }
  isc = 0; out = ""; src = ""; flags = ""
  for (i = 2; i <= n; i++) {
    if (w[i] == "-c") isc = 1
    else if (w[i] == "-o") { out = w[++i] }
    else if (w[i] ~ /^-[DUI]./ || w[i] ~ /^"-[DUI]./) flags = flags " " w[i]
    else if (w[i] == "-include") { flags = flags " -include " w[i + 1]; i++ }
    # -isystem DIR: curl names its dependencies (mbedTLS) so; dropped, the
    # unit compiled against whatever headers pxx found instead. Written as
    # -IDIR: pxx has no -isystem, and the only difference (gcc searches it
    # after the -I directories) matters only if a -I directory holds a
    # header of the same name
    else if (w[i] == "-isystem") { flags = flags " -I" w[i + 1]; i++ }
    else if (w[i] ~ /^-isystem./) { t = w[i]; sub(/^-isystem/, "-I", t); flags = flags " " t }
    else if (w[i] ~ /\.c$/) { src = w[i]; sub(/.*`/, "", src) }   # automake: `test -f x.c || echo ./`x.c
  }
  if (isc && src != "" && out != "") {
    if (out ~ /\.lo$/) sub(/\.lo$/, ".o", out)
    o = rel(dir, out)
    if (!(o in seen)) { seen[o] = 1; unit[++nu] = o " " rel(top, dir) " " src flags }
    next
  }
  if (!isc && out != "") {
    p = out; sub(/.*\//, "", p)
    if (!(p in want)) next
    objs = ""
    for (i = 2; i <= n; i++) {
      if (w[i] ~ /\.o$/) objs = objs " " rel(dir, w[i])
      else if (w[i] ~ /\.a$/) { a = byname(rel(dir, w[i])); if (a in members) objs = objs members[a]; else objs = objs " MISSING-ARCHIVE:" a }
    }
    # an archive named twice (ld resolves a cycle between libraries that
    # way; e2fsprogs links libext2fs.a again after libblkid.a) is ONE set
    # of objects: keep each object at its first place
    m = split(objs, ow, " "); objs = ""; delete once
    for (i = 1; i <= m; i++) if (!(ow[i] in once)) { once[ow[i]] = 1; objs = objs " " ow[i] }
    link[p] = objs
  }
}
END {
  for (i = 1; i <= nu; i++) print unit[i]
  print "%%"
  for (i = 1; i <= np; i++) {
    if (!(P[i] in link)) { print "units-from-make: no link line for " P[i] > "/dev/stderr"; exit 1 }
    print P[i] link[P[i]]
  }
}' "$LOG"
