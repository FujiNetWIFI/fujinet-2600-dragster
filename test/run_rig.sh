#!/usr/bin/env bash
# run_rig.sh -- two consoles, two FujiNets, one relay, one match.
#
#   test/run_rig.sh [seconds]
#
# The shape is the Intellivision family's: isolated copies of fujinet-pc so a
# run cannot disturb a real one, everything this script starts it kills first,
# and an inline verdict block rather than a human reading a log.
#
# Two things about this machine cost an afternoon each and are guarded here:
#
#   * A long-running fujinet-pc has held 127.0.0.1:9995 since September, and
#     the 2600 cartridge model connects there by DEFAULT. A rig on the default
#     port silently measures somebody else's FujiNet; ours logs "bind failed"
#     into a file nobody reads. So the rig uses its own ports and ABORTS if it
#     cannot have them.
#   * `cd "$RIG" && ./fujinet` puts "./fujinet" in the process's command line,
#     and `pkill -f "$RIG/fujinet"` then matches nothing. Every run leaked one,
#     and the next run measured the leak. Launch by absolute path.

. "$(dirname "$0")/serverlib.sh"

set -euo pipefail
cd "$(dirname "$0")/.."
HERE=$(pwd)

SECS=${1:-${SECS:-40}}
RELAY_PORT=${RELAY_PORT:-9601}
BOIP1=${BOIP1:-19995}
BOIP2=${BOIP2:-19996}
FNPC_DIST=${FNPC_DIST:-$HOME/Workspace/fujinet-pc-rs232/build/dist}

cleanup() {
    # Only OUR emulators: a `make play` session may be up on other ports and
    # killing it would be rude as well as wrong.
    for pid in $(pgrep -x mame 2>/dev/null || true); do
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null \
            | grep -q "build/rig/${RIGDIR:-fn}dragster" && kill "$pid" 2>/dev/null
    done
    for n in 1 2; do
        pkill -f "$HERE/build/rig/${RIGDIR:-fn}$n/fujinet" 2>/dev/null || true
    done
    for pid in $(pgrep -x fujinet 2>/dev/null || true); do
        case "$(readlink -f "/proc/$pid/cwd" 2>/dev/null)" in
            "$HERE"/build/rig/"${RIGDIR:-fn}"*) kill "$pid" 2>/dev/null ;;
        esac
    done
    [ -n "${RELAY_PID:-}" ] && kill "$RELAY_PID" 2>/dev/null || true
    return 0
}
trap cleanup EXIT
cleanup
sleep 0.5

mkdir -p build/rig

# Two ROMs, because the two consoles must introduce themselves by different
# names: the relay refuses a duplicate by renaming it, and a rig that relied on
# that would be testing the rename.
for n in 1 2; do
    PLAYER="PLAYER$n" ENDPOINT="TCP://127.0.0.1:$RELAY_PORT/" \
        ./build.sh dragster > "build/rig/build$n.log" 2>&1
    cp build/dragster.bin "build/rig/${RIGDIR:-fn}dragster$n.bin"
done
echo "== built two client ROMs =="

for n in 1 2; do
    port=$([ "$n" = 1 ] && echo "$BOIP1" || echo "$BOIP2")
    rig="$HERE/build/rig/${RIGDIR:-fn}$n"
    rm -rf "$rig"
    mkdir -p "$rig"
    cp -a "$FNPC_DIST"/. "$rig"/
    python3 - "$rig/fnconfig.ini" "$port" <<'PY'
import re, sys
path, port = sys.argv[1], sys.argv[2]
s = open(path).read()
s = re.sub(r"(\[BOIP\][^\[]*?\bport=)\d*", r"\g<1>" + port, s, flags=re.S)
s = re.sub(r"(\[BOIP\][^\[]*?\benabled=)\d*", r"\g<1>1", s, flags=re.S)
open(path, "w").write(s)
PY
    ( cd "$rig" && setsid "$rig/fujinet" < /dev/null > "$HERE/build/rig/fn$n.log" 2>&1 & )
done
sleep 2
for n in 1 2; do
    if grep -q "bind failed" "build/rig/fn$n.log"; then
        echo "run_rig: fujinet-pc $n could not bind its BoIP port -- something" \
             "else holds it. Aborting rather than measuring it." >&2
        grep -m1 "bind failed" "build/rig/fn$n.log" >&2
        exit 1
    fi
done
echo "== two fujinet-pc on :$BOIP1 and :$BOIP2 =="

setsid relay_server --host 127.0.0.1 \
    --port "$RELAY_PORT" --delay 2 --variation 0 \
    < /dev/null > build/rig/relay.log 2>&1 &
RELAY_PID=$!
sleep 1
# THE SAME GUARD THE BoIP PORTS GET, FOR THE SAME REASON. A relay left running
# by `make play` still owns 9601; this one dies with "Address already in use"
# into a log nobody reads, the two consoles pair against the OTHER relay, and
# every verdict below is measured somewhere else. It cost a whole ladder run.
if ! kill -0 "$RELAY_PID" 2>/dev/null; then
    echo "run_rig: the relay could not take 127.0.0.1:$RELAY_PORT." >&2
    tail -3 build/rig/relay.log >&2
    echo "run_rig: something else holds it -- test/stop.sh, or set RELAY_PORT." >&2
    exit 1
fi
echo "== relay on :$RELAY_PORT =="

for n in 1 2; do
    port=$([ "$n" = 1 ] && echo "$BOIP1" || echo "$BOIP2")
    SNAPTICK="${SNAPTICK:-150}" RIG_HOLD="${RIG_HOLD:-}" \
    PLAY_WINDOW="${PLAY_WINDOW:-}" \
    PLAY_INJECT="$([ "$n" = 1 ] && echo "${PLAY_INJECT:-}")" \
    RIG_DRIVE="$([ "$n" = 1 ] && echo 1)" \
    LAUNCH_TRACE="${LAUNCH_TRACE:-}" \
    SECS="$SECS" FUJINET_TCP="127.0.0.1:$port" \
        ./run.sh "rig/${RIGDIR:-fn}dragster$n" "${RIG_LUA:-rig}" \
            < /dev/null > "build/rig/c$n.out" 2>&1 &
    sleep 1
done
wait_secs=$((SECS + 20))
for _ in $(seq "$wait_secs"); do
    pgrep -f "build/rig/${RIGDIR:-fn}dragster" > /dev/null || break
    sleep 1
done
sleep 1

echo
echo "== console 1 =="; tail -7 build/rig/c1.out
echo "== console 2 =="; tail -7 build/rig/c2.out
echo "== relay =="; grep -v "CRC MISMATCH" build/rig/relay.log
echo "   $(grep -c "CRC MISMATCH" build/rig/relay.log || true) CRC MISMATCH lines"

# emu/play.lua's verdict is a different question, so it gets a different block:
# not "did these two agree" -- the relay answers that -- but WHICH CELL WENT
# FIRST. The state dump is megabytes, so only the diagnosis is printed.
if [ "${RIG_LUA:-rig}" = "play" ] && [ -n "${PLAY_INJECT:-}" ]; then
    # The repair gate asks the OPPOSITE question: one console was deliberately
    # corrupted, so mismatches are the point and silence would mean the
    # injection missed. What has to be true is that they STOPPED.
    echo
    echo "== injection =="; grep -h "^INJECT" build/rig/c1.out || true
    python3 tools/playdiff.py build/rig/c1.out build/rig/c2.out --repair
    rc=$?
    echo
    if [ "$rc" = 0 ] && grep -q "CRC MISMATCH" build/rig/relay.log; then
        echo "REPAIR PASS"; exit 0
    fi
    [ "$rc" = 0 ] || echo "  FAIL the two consoles never came back together"
    grep -q "CRC MISMATCH" build/rig/relay.log \
        || echo "  FAIL the relay never saw the injected desync at all"
    echo "REPAIR FAIL"; exit 1
fi

if [ "${RIG_LUA:-rig}" = "inputs" ]; then
    echo
    python3 - build/rig/c1.out build/rig/c2.out build/dggame.lst <<'PY'
import re, sys
fails = []
def want(c, w):
    print(("  ok   " if c else "  FAIL ") + w)
    if not c: fails.append(w)
# DGCAP's extent, from the assembler's own symbol table -- never a hardcoded
# address, which would go stale the first time a hole was relaid.
syms = {}
intab = False
for line in open(sys.argv[3], errors="replace"):
    if "Symbol Table" in line: intab = True; continue
    if not intab: continue
    for part in line.split("|"):
        m = re.match(r"^\*?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([0-9A-F]{1,8})\b", part.strip())
        if m:
            try: syms[m.group(1).upper()] = int(m.group(2), 16)
            except ValueError: pass
cap, stall = syms.get("DGCAP"), syms.get("DGSTALL")
loc0 = syms.get("DGLOC0")
want(cap is not None and stall is not None, "DGCAP's extent is in the listing")
for n, p in ((1, sys.argv[1]), (2, sys.argv[2])):
    t = open(p, errors="replace").read()
    m = re.search(r"INPUTS (\d+) console-port reads from (\d+) distinct sites", t)
    want(m is not None, "console %d reported its reads" % n)
    if not m: continue
    sites = re.findall(r"bank (\d+) PC \$([0-9A-F]{4}) reading \$([0-9A-F]{4})", t)
    # Only the GAME bank is under test. Bank 0 is the session, and CSLEFT reads
    # the RESET switch locally on purpose -- there is no peer left to agree
    # with -- so a console whose partner exited first is SUPPOSED to be there.
    pcs = sorted({int(p, 16) for b, p, _ in sites if b == "1"})
    ports = sorted({int(a, 16) for b, _, a in sites if b == "1"})
    want(len(pcs) > 0 and int(m.group(1)) > 100,
         "console %d actually read the console (%s reads)" % (n, m.group(1)))
    # IN A MATCH, DGLOC0 MUST NOT RUN AT ALL. It is the not-networked path, and
    # a console taking it while paired is reading its own hardware for BOTH
    # cars -- which desyncs on the first thing anybody touches.
    # DGMIX's B&W read is the one deliberate exception and it is named here
    # rather than waved through: SWCHB bit 3 is read LIVE on each console so
    # each player sees their own colour setting, and it is provably safe --
    # Dragster reads it at $F2A7 for one purpose, to force AttrAnd to $0F, and
    # no colour cell reaches physics or the checksum.
    mix = syms.get("DGMIX")
    outside = [pc for pc in pcs
               if not (cap <= pc < stall) and not (mix <= pc < cap)]
    want(not outside,
         "console %d reads the console only inside DGCAP, or DGMIX for B&W; "
         "stray: %s" % (n, ", ".join("$%04X" % x for x in outside) or "none"))
    want(0x0280 in ports or 0x0282 in ports,
         "console %d really did read a console port" % n)
    want(loc0 not in pcs, "console %d never took the local path" % n)
print()
print("INPUTS FAIL" if fails else "INPUTS PASS")
sys.exit(1 if fails else 0)
PY
    exit $?
fi

if [ "${RIG_LUA:-rig}" = "launch" ]; then
    echo
    python3 - build/rig/c1.out build/rig/c2.out "${STOCK_DELTA:-5}" <<'PY'
import re, sys
fails = []
def want(c, w):
    print(("  ok   " if c else "  FAIL ") + w)
    if not c: fails.append(w)
stock = int(sys.argv[3])
rows = []
for n, p in ((1, sys.argv[1]), (2, sys.argv[2])):
    t = open(p, errors="replace").read()
    m = re.search(r"LAUNCH lead=(\d+) networked=(\w+) green=(\S+) moved=(\S+) "
                  r"delta=(\S+) et=(\S+) foul=(\S+)", t)
    want(m is not None, "console %d reported its launch" % n)
    if m: rows.append((n, m))
for n, m in rows:
    lead, net, delta, et, foul = (int(m.group(1)), m.group(2) == "true",
                                  m.group(5), m.group(6), m.group(7))
    want(net, "console %d is in a match" % n)
    want(lead == 8, "console %d has the display lead" % n)
    want(delta != "?" and et != "nil", "console %d actually completed a run" % n)
    # NO JUMP START. The lead is exactly d*K, so a press made at the green the
    # player SEES lands at $8D == 0 and is clean; one frame earlier lands at
    # $8D == 1 and is correctly fouled. Getting the size wrong shows up here.
    want(foul != "1D", "console %d did not jump the start (foul=%s)" % (n, foul))
    if delta != "?":
        d = int(delta)
        want(abs(d - stock) <= 3,
             "console %d launched %d frames after green; stock does %d"
             % (n, d, stock))
if len(rows) == 2:
    a, b = rows[0][1], rows[1][1]
    want(a.group(6) == b.group(6),
         "both consoles recorded the SAME time (%s vs %s)" % (a.group(6), b.group(6)))
    want(a.group(5) == b.group(5),
         "both consoles launched on the same simulated frame")
print()
print("LAUNCH FAIL" if fails else "LAUNCH PASS")
sys.exit(1 if fails else 0)
PY
    exit $?
fi

if [ "${RIG_LUA:-rig}" = "tree" ]; then
    echo
    python3 - build/rig/c1.out build/rig/c2.out <<'PY'
import re, sys
fails = []
def want(c, w):
    print(("  ok   " if c else "  FAIL ") + w)
    if not c: fails.append(w)
for n, p in ((1, sys.argv[1]), (2, sys.argv[2])):
    t = open(p, errors="replace").read()
    m = re.search(r"TREE lead=(\d+) networked=(\w+) beeps=(\d+)", t)
    want(m is not None, "console %d reported the tree" % n)
    if not m:
        continue
    lead, net, beeps = int(m.group(1)), m.group(2) == "true", int(m.group(3))
    want(net, "console %d is in a match" % n)
    # THE SIGN. In a match the lead is DGK*DGD = 8 simulated frames, and it is
    # subtracted, so the beeps move UP the countdown by 8: $98, $88, $78 ...
    want(lead == 8, "console %d has a lead of 8 (got %d)" % (n, lead))
    want(beeps > 4, "console %d heard %d tree stages" % (n, beeps))
    b = re.search(r"TREE beeps off the lead: (\d+)", t)
    want(b is not None and int(b.group(1)) == 0,
         "console %d beeped exactly on the led countdown" % n)
    v = re.search(r"TREE beep Countdown values: (.*)", t)
    want(v is not None and "98" in v.group(1),
         "console %d beeped at Countdown $98, which is $90 plus the lead" % n)
print()
print("TREE FAIL" if fails else "TREE PASS")
sys.exit(1 if fails else 0)
PY
    exit $?
fi

if [ "${RIG_LUA:-rig}" = "play" ]; then
    echo
    python3 tools/playdiff.py build/rig/c1.out build/rig/c2.out
    rc=$?
    echo
    if [ "$rc" = 0 ] && ! grep -q "CRC MISMATCH" build/rig/relay.log; then
        echo "PLAY PASS"; exit 0
    fi
    echo "PLAY FAIL"; exit 1
fi

python3 - build/rig/c1.out build/rig/c2.out build/rig/relay.log <<'PY'
import os, re, sys
c1, c2, relay = (open(p, errors="replace").read() for p in sys.argv[1:4])
fails = []

def want(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)

want("match:" in relay, "the relay paired the two consoles")
want("CRC MISMATCH" not in relay, "the two consoles never disagreed")

# The two snapshots are taken at the SAME simulated tick on both consoles, so
# they have to be identical byte for byte -- including the game variation, which
# is what proves SELECT reached both machines and advanced them together.
#
# SNAP is the SIMULATION only. The raw SWCHB port and the peer's ring slot moved
# to the LOCAL line, which is reported and never compared: with SELECT held on
# one console those two bytes differ BECAUSE the press is working, and comparing
# them asserted that both players had their hands in the same place.
sa = re.search(r"^SNAP .*$", c1, re.M)
sb = re.search(r"^SNAP .*$", c2, re.M)
want(sa is not None and sb is not None, "both consoles snapshotted the same tick")
if sa and sb:
    want(sa.group(0) == sb.group(0),
         "the two consoles agree byte for byte at the snapshot tick")
    # GameVar is the FIRST cell of the snapshot.
    ga = re.search(r":\s+(\w+)", sa.group(0))
    gb = re.search(r":\s+(\w+)", sb.group(0))
    want(ga and gb and ga.group(1) == gb.group(1),
         "the two consoles are on the SAME game variation")

# Dragster has TWO games, not Combat's twenty-seven, so "the variation moved
# away from its default" cannot be a single value: held down, SELECT walks it
# 0,1,0,1 and where it stops is a function of how long the run was. What has to
# be true is that it moved AT ALL and that both consoles walked it identically.
if os.environ.get("RIG_HOLD") == "select":
    wa = re.search(r"^VARWALK (\d+) distinct: (.*)$", c1, re.M)
    wb = re.search(r"^VARWALK (\d+) distinct: (.*)$", c2, re.M)
    want(wa is not None and wb is not None, "both consoles reported the walk")
    if wa and wb:
        want(int(wa.group(1)) > 1, "SELECT actually changed the variation")
        want(wa.group(2) == wb.group(2),
             "both consoles walked the variation identically, tick for tick")
for n, out in ((1, c1), (2, c2)):
    m = re.search(r"RIG ticks=(\d+) tick=\d+ err=\$([0-9A-F]{2}) state=(\d+)", out)
    want(m is not None, "console %d reported its state" % n)
    if m:
        tick, err = int(m.group(1)), int(m.group(2), 16)
        want(tick > 50, "console %d ran %d ticks" % (n, tick))
        mv = re.search(r"MOVED maxpos=(\d+) races=(\d+) states=(\d+)", out)
        want(mv is not None, "console %d reported whether anything happened" % n)
        if mv:
            # A GATE THAT ONLY CHECKS AGREEMENT PASSES TWO MACHINES AGREEING
            # ABOUT NOTHING. Console 2 presses nothing at all, so its car is
            # driven entirely by what arrived over the wire.
            hold = os.environ.get("RIG_HOLD", "")
            if hold == "":
                want(int(mv.group(1)) > 8,
                     "console %d saw a car travel (maxpos=%s)" % (n, mv.group(1)))
            elif hold == "stage":
                # This gate hammers the stage button on purpose, so no car ever
                # gets down the strip; what it proves is that the restage path
                # -- which clears straight through the netcode's cells unless
                # the bound holds -- can be taken over and over without the
                # match noticing.
                want(int(mv.group(2)) > 20,
                     "console %d restaged %s times and stayed in the match"
                     % (n, mv.group(2)))
            if hold != "select":
                # Holding SELECT keeps NewGame zeroing the countdown, so no race
                # can stage while it is down -- which is the correct behaviour
                # and would be a silly thing to assert against.
                want(int(mv.group(2)) > 0,
                     "console %d saw a race staged (%s)" % (n, mv.group(2)))
            if hold != "select":
                want(int(mv.group(3)) > 20,
                     "console %d saw %s distinct simulation states" % (n, mv.group(3)))
            else:
                # With SELECT down the simulation is SUPPOSED to sit still --
                # what is under test is that the variation walks, and that both
                # consoles walk it identically, which the VARWALK lines assert.
                want(int(mv.group(3)) >= 1,
                     "console %d held still while SELECT was down, as it should"
                     % n)
        want(err & 0x0F == 0, "console %d has no transport error ($%02X)" % (n, err))
print()
print("RIG FAIL" if fails else "RIG PASS")
sys.exit(1 if fails else 0)
PY
