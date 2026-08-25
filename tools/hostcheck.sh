#!/bin/sh
# hostcheck.sh — is this BOX lying to us right now?
#
# Written 2026-08-25, after two failures that were neither of them code defects
# and both of which reported success-shaped output while broken:
#
#   * Track T went blind for three days. The daemon was alive, `systemctl` said
#     active, `trackt health` said OK -- and every native run was being torn
#     down at the 3600s deadline by one test hanging in GTK's at-spi bridge,
#     publishing a CONTENTLESS RED each time. Liveness was checked; verdicts
#     were not. That is the error this script exists to make impossible.
#   * DNS resolved through a router forwarder dropping ~40% of queries in
#     bursts, for hours, while the NetworkManager profile claimed 8.8.8.8. The
#     profile had been corrected and the live device never reapplied.
#
# Both share a shape: the thing reporting is not the thing doing. So every
# check here compares a CLAIM against the SYSTEM'S OWN RECORD, and every check
# is bounded in time -- a health check that can hang is a second outage.
#
# Cheap and deterministic on purpose: no model, no tokens, safe to run every
# 20 minutes from cron. Prints one line per check; exits 1 if anything FAILed.
#
#   OK    nothing to do
#   WARN  worth a human eye, not urgent
#   FAIL  something is broken or lying; exit 1
set -u

REPO=${REPO:-/home/neo/frank1}
WATCH_CLONE=/home/neo/trackt-watch
rc=0

say()  { printf '%-6s %-12s %s\n' "$1" "$2" "$3"; }
ok()   { say OK   "$1" "$2"; }
warn() { say WARN "$1" "$2"; }
fail() { say FAIL "$1" "$2"; rc=1; }

# ---------------------------------------------------------------- Track T ---
# The verdict check, NOT the liveness check. `wall` at (or just under) the
# 3600s global deadline means the run was TORN DOWN, not completed: the report
# it published carries no usable verdict however green the tree actually is.
#
# Read tstate from ORIGIN, never from the local checkout. The local file is
# only as fresh as the last pull, and reporting your own staleness as the
# watcher's is exactly the trap CLAUDE.md warns about for `twatch --status`.
check_trackt() {
    git -C "$REPO" fetch --no-write-fetch-head -q origin 2>/dev/null

    json=
    for ref in origin/dev origin/master; do
        json=$(git -C "$REPO" show "$ref:devdocs/progress/tstate/plexus.json" \
               2>/dev/null) && [ -n "$json" ] && break
    done
    if [ -z "$json" ]; then
        fail trackt "no tstate/plexus.json on origin/dev or origin/master"
        return
    fi

    printf '%s' "$json" | python3 -c '
import json, sys, time, calendar
d = json.load(sys.stdin)
last = d.get("last") or {}
wall = last.get("wall")
date = last.get("date", "")
sha  = (last.get("sha") or "")[:12]
tier = last.get("tier", "?")
verdict = last.get("verdict", "?")

try:
    age = (time.time() - calendar.timegm(time.strptime(date, "%Y-%m-%dT%H:%M:%SZ"))) / 60.0
except Exception:
    age = None

# 3600s is the global deadline. Anything within 5s of it was killed, not run.
if wall is not None and wall >= 3595:
    print("FAIL|torn down at the %.0fs deadline (%s %s, %s) -- CONTENTLESS, "
          "T is blind" % (wall, tier, sha, verdict))
elif age is None:
    print("WARN|last run has an unparseable date: %r" % date)
elif age > 180:
    print("FAIL|no completed run for %.0f min (%s %s)" % (age, tier, sha))
elif age > 90:
    print("WARN|last completed run is %.0f min old (%s %s)" % (age, tier, sha))
else:
    print("OK|%s %s %s, wall %.0fs, %.0f min ago"
          % (verdict, tier, sha, wall if wall is not None else -1, age))

# The BREADTH record, reported separately and never folded into the line above.
# A native verdict is x86-64 only; reading it as matrix coverage is the mistake
# this line exists to prevent. And a full tier is torn down at the deadline the
# same way a native one is -- the 1d14h-old "full RED" that gating was leaning
# on had wall 3600.3s against a 3600s deadline, i.e. NO VERDICT, published as a
# red. Its still_red list is empty for the same reason, so jobs it never reached
# read as FIXED.
full = d.get("last_full") or {}
fw, fsha = full.get("wall"), (full.get("sha") or "")[:12]
try:
    fage = (time.time() - calendar.timegm(time.strptime(
        full.get("date", ""), "%Y-%m-%dT%H:%M:%SZ"))) / 3600.0
except Exception:
    fage = None
if not full:
    print("WARN|breadth: no full tier on record at all")
elif fw is not None and fw >= 3595:
    # Deliberately a wide net. Deadlines are now scaled by the core throttle,
    # so the ceiling is not always 3600 -- but a completed run landing within a
    # few seconds ABOVE a tuned deadline is vanishingly unlikely, and a false
    # "suspicious" costs a glance while a false "verdict" costs a bad merge.
    print("FAIL|breadth: full %s wall %.0fs is AT the deadline -- torn down, "
          "NO VERDICT (its still_red is empty for the same reason)" % (fsha, fw))
elif fage is not None and fage > 24:
    print("WARN|breadth: newest full tier %s is %.0fh old -- native is x86-64 "
          "only, this is not matrix coverage" % (fsha, fage))
else:
    print("OK|breadth: full %s %s, wall %.0fs, %.0fh old"
          % (fsha, full.get("verdict", "?"), fw if fw is not None else -1, fage or 0))
' 2>/dev/null | while IFS='|' read -r lvl msg; do
        case "$lvl" in
            OK)   ok   trackt "$msg" ;;
            WARN) warn trackt "$msg" ;;
            *)    fail trackt "$msg" ;;
        esac
    done

    # `while` above runs in a subshell, so its rc never reaches us. Re-derive.
    printf '%s' "$json" | python3 -c '
import json,sys
l=(json.load(sys.stdin).get("last") or {})
w=l.get("wall")
sys.exit(1 if (w is not None and w>=3595) else 0)' 2>/dev/null || rc=1
}

# The daemon being ALIVE is a separate, weaker fact. Report it as its own line
# so nobody again mistakes it for "Track T is working".
check_daemon() {
    if systemctl --user is-active --quiet trackt-watcher.service 2>/dev/null; then
        ok daemon "trackt-watcher.service active (liveness only, see trackt line)"
    else
        fail daemon "trackt-watcher.service NOT active"
    fi
}

# ---------------------------------------------------------------- network ---
# Compare the APPLIED device config against the PROFILE. They diverge silently
# whenever someone runs `nmcli connection modify` without `nmcli device
# reapply`, and the box then resolves through whatever DHCP handed it.
check_dns_applied() {
    command -v nmcli >/dev/null 2>&1 || { warn dns "nmcli absent, skipped"; return; }
    for dev in enp7s0 wlp8s4; do
        nmcli -g GENERAL.STATE device show "$dev" 2>/dev/null \
            | grep -q connected || continue
        applied=$(nmcli -g IP4.DNS device show "$dev" 2>/dev/null | paste -sd, -)
        con=$(nmcli -g GENERAL.CONNECTION device show "$dev" 2>/dev/null)
        [ -n "$con" ] || continue
        profile=$(nmcli -g ipv4.dns connection show "$con" 2>/dev/null | tr -d ' ')
        case "$applied" in
            *"$(printf '%s' "$profile" | cut -d, -f1)"*)
                ok dns "$dev applied=$applied matches profile" ;;
            *)
                fail dns "$dev APPLIED=$applied but PROFILE=$profile -- run: nmcli device reapply $dev" ;;
        esac
    done
}

# Prove resolution works AND is not merely slow. Both matter, and the slow case
# is the one that hides: on 2026-08-25 every unqualified lookup on this box took
# exactly 10.02s while succeeding, so nothing failed and everything crawled.
#
# Cause, worth stating precisely because the obvious version of it is wrong:
# a DNS search domain of `local` collides with mDNS. `.local` is reserved for
# multicast DNS, and nsswitch here is `files mdns4_minimal [NOTFOUND=return]
# dns`.
#
# It is NOT that every name is tried as `<name>.local` first. With ndots:1
# glibc tries a dotted name ABSOLUTE first, and consults the search list only
# when the bare name returns no answer FOR THAT ADDRESS FAMILY. So the stall
# lands exclusively on **IPv4-only hosts**: they have no AAAA, the AAAA half
# falls through to `<name>.local`, mDNS has no concept of a negative answer,
# and it can only end in a full timeout. `getent hosts` asks AF_UNSPEC, waits
# for the slow half, and the name looks uniformly broken. Dual-stack hosts
# never stall at all -- which is why this presents as intermittent and random
# rather than as an outage.
#
# CANARY MUST BE IPv4-ONLY. github.com is the headline case (and is why git
# over https and apt ate the tax while browsing mostly did not). If it ever
# gains an AAAA record this check would read green while the box stalls, so
# the canary is asserted rather than assumed.
#
# Comparing the unqualified lookup against the same name with a trailing dot
# isolates it in one measurement: the dot skips the search list and holds
# everything else constant.
CANARY=${CANARY:-github.com}

check_dns_resolve() {
    # If the canary is dual-stack it cannot detect the search-list stall.
    if timeout 5 resolvectl query -t AAAA "$CANARY" 2>/dev/null | grep -q ':'; then
        warn resolve "canary $CANARY now has an AAAA record -- it can no longer detect a search-list stall; pick an IPv4-only name"
    fi
    t0=$(date +%s%N)
    timeout 20 getent hosts "$CANARY" >/dev/null 2>&1; got=$?
    t1=$(date +%s%N)
    unq=$(( (t1 - t0) / 1000000 ))

    t0=$(date +%s%N)
    timeout 20 getent hosts "$CANARY." >/dev/null 2>&1
    t1=$(date +%s%N)
    fqdn=$(( (t1 - t0) / 1000000 ))

    if [ "$got" -ne 0 ]; then
        fail resolve "$CANARY did NOT resolve within 20s"
    elif [ "$unq" -gt 2000 ] && [ "$fqdn" -lt 500 ]; then
        fail resolve "unqualified ${unq}ms vs FQDN ${fqdn}ms -- the search list is stalling; drop \`local\` from ipv4.dns-search (it is mDNS-reserved) and use via.local"
    elif [ "$unq" -gt 2000 ]; then
        fail resolve "resolution is slow: ${unq}ms unqualified, ${fqdn}ms FQDN"
    else
        ok resolve "$CANARY ${unq}ms (FQDN ${fqdn}ms)"
    fi
}

# ------------------------------------------------------------ environment ---
# Every `systemd-run --user` job on this box inherits the graphical session, so
# anything that opportunistically talks to a display or session bus can hang.
# a11y was merely the symptom that hung first; warn while the durable fix (strip
# the environment for test runs) is still an open Track T ticket.
check_session_env() {
    pid=$(systemctl --user show -p MainPID --value trackt-watcher.service 2>/dev/null)
    case "${pid:-0}" in ''|0) warn env "watcher not running, env not checked"; return ;; esac
    env=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null) || {
        warn env "cannot read /proc/$pid/environ"; return; }
    graphical=$(printf '%s\n' "$env" | grep -cE '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS)=')

    # Look for the guard where it actually lives. testmgr sets NO_AT_BRIDGE and
    # GTK_A11Y in the JOB environment, not the daemon's -- deliberately, so it
    # applies however the run was launched, where a unit-level Environment=
    # would silently stop applying the first time someone runs testmgr by hand.
    # Checking the daemon's own /proc environ would therefore WARN forever on a
    # correctly-fixed box, and a check that always warns is a check nobody
    # reads.
    if grep -q 'NO_AT_BRIDGE' "$REPO/tools/testmgr.py" 2>/dev/null; then
        guarded=1
    else
        guarded=0
    fi

    if [ "$graphical" -gt 0 ] && [ "$guarded" -eq 0 ]; then
        fail env "watcher inherits $graphical graphical vars and testmgr sets no a11y guard"
    elif [ "$graphical" -gt 0 ]; then
        ok env "inherits $graphical graphical vars; testmgr guards the job env"
    else
        ok env "clean environment"
    fi
}

# ------------------------------------------------------------------- repo ---
# Unpushed work is work Track T cannot see, and this box has no UPS.
check_repo() {
    branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
    ahead=$(git -C "$REPO" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)
    dirty=$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null | wc -l)
    [ "$ahead" -gt 0 ] && warn repo "$branch has $ahead unpushed commit(s)" \
                       || ok repo "$branch is pushed"
    [ "$dirty" -gt 0 ] && warn repo "$dirty uncommitted file(s) -- no UPS on this box"

    behind=$(git -C "$REPO" rev-list --count origin/master..origin/dev 2>/dev/null || echo 0)
    [ "$behind" -gt 0 ] && ok sync "dev is $behind commit(s) ahead of master (sync-back pending)"
}

check_trackt
check_daemon
check_dns_applied
check_dns_resolve
check_session_env
check_repo

exit $rc
