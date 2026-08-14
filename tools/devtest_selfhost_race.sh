#!/usr/bin/env bash
# Track T devtest: tools/selfhost_fixedpoint.sh under a concurrent build.
#
# The Gate of bug-t-gate-sh-fixedpoint-reads-the-live-mutable-compiler asks that
# replacing compiler/pascal26 mid-check must not produce a self-host FAIL. Doing
# that against the REAL script would cost ~40s per case, need a real compiler,
# and mutate the live binary while the watcher may be building — so this builds
# a fake tree instead and drives the same script.
#
# The script takes ROOT from its own location and PINNED from $PXX_STABLE, so a
# copy in a scratch tree with stub "compilers" exercises every branch in
# milliseconds. The stubs `compile` by copying THEMSELVES, so they converge in
# round 1 and the interesting variable is the BUILT binary alone.
set -u
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/selfhost_fixedpoint.sh"
fails=0

# A stub "compiler" must be RUNNABLE and SELF-REPRODUCING, because the script
# runs each stage it produces: `$cur src a` then `$a src b`, and converges when
# a == b. `cp "$0" "$2"` gives exactly that in one round -- the fixedpoint IS
# the stub's own bytes. (A plain payload string with +x is not executable, which
# made every round die at "stage could not compile" on the first attempt.)
mk_tree() {                      # $1=tree  $2=stub delay secs
  local t=$1 delay=${2:-0}
  rm -rf "$t"; mkdir -p "$t/tools" "$t/compiler" "$t/stable_linux_amd64/default"
  cp "$SCRIPT" "$t/tools/"
  echo "program compiler;" > "$t/compiler/compiler.pas"
  cat > "$t/stable_linux_amd64/default/pinned" <<EOF
#!/bin/sh
sleep $delay
cp "\$0" "\$2"
chmod +x "\$2" 2>/dev/null
exit 0
EOF
  chmod +x "$t/stable_linux_amd64/default/pinned"
}

# the bytes the fixedpoint converges to == the seed stub itself
seed_of() { echo "$1/stable_linux_amd64/default/pinned"; }

check() {                        # $1=name $2=got $3=want
  if [ "$2" = "$3" ]; then printf '  ok  %s\n' "$1"
  else printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- 1. agreement: BUILT already equals the fixedpoint -----------------------
mk_tree "$T/ok"
cp "$(seed_of "$T/ok")" "$T/ok/compiler/pascal26"
out=$(bash "$T/ok/tools/selfhost_fixedpoint.sh" 2>&1); rc=$?
check "agreement: rc" "$rc" "0"
case "$out" in *"agrees with compiler/pascal26"*) r=yes;; *) r=no;; esac
check "agreement: says so" "$r" "yes"

# --- 2. a GENUINE disagreement must still FAIL -------------------------------
# The whole point of the check. A stable-but-different binary is the Thompson
# case and must not be softened by the race handling.
mk_tree "$T/bad"
printf '#!/bin/sh\nexit 0\n' > "$T/bad/compiler/pascal26"; chmod +x "$T/bad/compiler/pascal26"
out=$(bash "$T/bad/tools/selfhost_fixedpoint.sh" 2>&1); rc=$?
check "genuine mismatch: rc" "$rc" "1"
case "$out" in *"FAIL: the fixedpoint reached from PINNED differs"*) r=yes;; *) r=no;; esac
check "genuine mismatch: reported as self-host FAIL" "$r" "yes"

# --- 3a. THE REPORTED BUG: replaced mid-check, BUILT was correct -------------
# The snapshot makes the replacement INVISIBLE -- the comparison is against a
# stable copy, so this is simply green, agreement intact. That is the fix
# working; the "changed DURING" path below never fires here and should not.
mk_tree "$T/race" 2                       # stub sleeps, giving us a window
cp "$(seed_of "$T/race")" "$T/race/compiler/pascal26"
( sleep 1; printf '#!/bin/sh\n# rebuilt by a sibling\nexit 0\n' > "$T/race/compiler/pascal26" ) &
racer=$!
out=$(bash "$T/race/tools/selfhost_fixedpoint.sh" 2>&1); rc=$?
wait $racer 2>/dev/null
check "concurrent build: rc is NOT a failure" "$rc" "0"
case "$out" in *"FAIL: the fixedpoint reached from PINNED differs"*) r=yes;; *) r=no;; esac
check "concurrent build: no self-host FAIL emitted" "$r" "no"
case "$out" in *"agrees with compiler/pascal26"*) r=yes;; *) r=no;; esac
check "concurrent build: agreement still asserted from the snapshot" "$r" "yes"

# --- 3b. the FALLBACK: BUILT already disagreed AND changed under us ----------
# Here the snapshot genuinely differs from the fixedpoint, so the mismatch
# branch is entered -- and must still not cry self-host, because the binary is
# no longer the one it judged. This is the only path that prints the race note.
mk_tree "$T/race2" 2
printf '#!/bin/sh\n# stale\nexit 0\n' > "$T/race2/compiler/pascal26"; chmod +x "$T/race2/compiler/pascal26"
( sleep 1; printf '#!/bin/sh\n# rebuilt again\nexit 0\n' > "$T/race2/compiler/pascal26" ) &
racer=$!
out=$(bash "$T/race2/tools/selfhost_fixedpoint.sh" 2>&1); rc=$?
wait $racer 2>/dev/null
check "stale+changed: rc is NOT a failure" "$rc" "0"
case "$out" in *"changed DURING this check"*) r=yes;; *) r=no;; esac
check "stale+changed: named as the race" "$r" "yes"
case "$out" in *"FAIL: the fixedpoint reached from PINNED differs"*) r=yes;; *) r=no;; esac
check "stale+changed: not reported as self-host" "$r" "no"

# --- 4. convergence is still the real gate ----------------------------------
# A seed that cannot reproduce itself must fail regardless of BUILT.
mk_tree "$T/noconv"
cat > "$T/noconv/stable_linux_amd64/default/pinned" <<'EOF'
#!/bin/sh
# reproduces a RUNNABLE but always-different generation -> never converges
{ printf '#!/bin/sh\n# gen %s\n' "$$$RANDOM"; sed -n '3,$p' "$0"; } > "$2"
chmod +x "$2" 2>/dev/null; exit 0
EOF
chmod +x "$T/noconv/stable_linux_amd64/default/pinned"
printf '%s' 'anything' > "$T/noconv/compiler/pascal26"; chmod +x "$T/noconv/compiler/pascal26"
out=$(bash "$T/noconv/tools/selfhost_fixedpoint.sh" 2>&1); rc=$?
check "no convergence: rc" "$rc" "1"
case "$out" in *"no fixedpoint after"*) r=yes;; *) r=no;; esac
check "no convergence: reported as a self-host regression" "$r" "yes"

# --- 5. no BUILT at all: convergence alone, no agreement claim ---------------
mk_tree "$T/nobuilt"
out=$(bash "$T/nobuilt/tools/selfhost_fixedpoint.sh" 2>&1); rc=$?
check "missing compiler/pascal26: rc" "$rc" "0"
case "$out" in *"agrees with compiler/pascal26"*) r=yes;; *) r=no;; esac
check "missing compiler/pascal26: claims no agreement it did not check" "$r" "no"

echo
if [ "$fails" -ne 0 ]; then echo "devtest_selfhost_race: $fails FAILED"; exit 1; fi
echo "devtest_selfhost_race: all checks pass"
