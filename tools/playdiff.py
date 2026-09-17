#!/usr/bin/env python3
"""playdiff.py -- which cell went first, and at which tick.

Two per-tick dumps from emu/play.lua, one per console. Lines up the ticks,
finds the first one at which the authoritative sim state differs, and NAMES THE
CELLS -- because "the two consoles desynced" is what the relay already says and
is not actionable, while "$A4 TankY0 is one lower on the guest from tick 63" is.

    tools/playdiff.py build/rig/c1.out build/rig/c2.out
"""
import os
import re
import sys

BASE = 0x80
# How many ticks at the end of the run must agree for a repair to count as one.
# 120 is eight seconds at fifteen ticks a second -- long enough that a pair that
# merely happened to coincide for a moment cannot pass.
RECOVER_TAIL = 120
# Combat's own names, from rom/combat.asm. Only the cells the dump covers.
# The names come from tools/dgmap.py, which is where the zero page is stated
# once. A hand-kept copy here would drift the first time a cell was renamed, and
# the symptom would be a diff that named the wrong byte -- which is worse than
# naming none, because it is believed.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dgmap

# Per-player cells are adjacent pairs indexed by X in {0,1}; the rest are
# singletons, and calling $83 "Lfsr+1" would be exactly the wrong name for a
# cell the game never touches.
PAIRED_FROM = 0x90          # $90-$A7 are pairs, and everything from $A8 up is
NAMES = {}
_zp = sorted(dgmap.ZP)
for _i, _a in enumerate(_zp):
    _nxt = _zp[_i + 1] if _i + 1 < len(_zp) else 0x100
    NAMES[_a] = dgmap.ZP[_a]
    if _a >= PAIRED_FROM and _a + 1 < _nxt:
        NAMES[_a + 1] = dgmap.ZP[_a] + "+1"

def load(path):
    """Index by the harness's boundary COUNT, and check the ROM's raw tick.

    The count is authoritative: the tap fires once per completed boundary, so
    counting them is the tick exactly. The raw DGTICK rides along only so a
    disagreement between the two numbering schemes is visible instead of being
    silently absorbed into the diff.
    """
    out, raw = {}, {}
    for line in open(path, errors="replace"):
        m = re.match(r"^S (\d+) (\d+) ([0-9A-F]+)$", line.strip())
        if m:
            n = int(m.group(1))
            out[n] = m.group(3)
            raw[n] = int(m.group(2))
    return out, raw


def addr_of(i):
    # The dump is $80-$D7 contiguous; there is no special case.
    return BASE + i


def main():
    (a, ra), (b, rb) = (load(p) for p in sys.argv[1:3] if not p.startswith("--"))
    if not a or not b:
        print("playdiff: one of the consoles printed no state at all")
        return 1
    common = sorted(set(a) & set(b))
    print("%d ticks from console 1, %d from console 2, %d in common"
          % (len(a), len(b), len(common)))
    # The two consoles number their boundaries from their own first one. If the
    # ROM's raw tick disagrees by a constant, the dumps are simply offset and
    # every "divergence" below is that offset; if it disagrees by a VARYING
    # amount, the two consoles really are running different numbers of ticks.
    off = {((ra[t] - rb[t]) & 0xFF) for t in common}
    if off != {0}:
        print("raw-tick offsets seen between the two dumps: %s"
              % " ".join("%+d" % (o - 256 if o > 127 else o)
                         for o in sorted(off)))
    first = None
    counts = {}
    for t in common:
        x, y = a[t], b[t]
        if x == y:
            continue
        bad = [i for i in range(len(x) // 2)
               if x[2 * i:2 * i + 2] != y[2 * i:2 * i + 2]]
        for i in bad:
            counts[addr_of(i)] = counts.get(addr_of(i), 0) + 1
        if first is None:
            first = t
            print("\nFIRST DIVERGENCE at tick %d" % t)
            for i in bad:
                ad = addr_of(i)
                u, v = int(x[2 * i:2 * i + 2], 16), int(y[2 * i:2 * i + 2], 16)
                print("  $%02X %-10s  c1=$%02X  c2=$%02X  (%+d)"
                      % (ad, NAMES.get(ad, ""), u, v, v - u))
            # The three ticks either side, so the run-up is visible.
            for u in [t2 for t2 in common if t - 3 <= t2 <= t + 3]:
                print("    t%-5d %s" % (u, "SAME" if a[u] == b[u] else "DIFF"))
    # --repair inverts the question. A correct pair NEVER diverges, so recovery
    # cannot be tested by waiting for a bug: the harness breaks one console on
    # purpose (PLAY_INJECT) and the assertion is that they come back together.
    if "--repair" in sys.argv:
        bad = [t for t in common if a[t] != b[t]]
        tail = common[-RECOVER_TAIL:]
        healed = all(a[t] == b[t] for t in tail)
        print()
        if not bad:
            print("NO DIVERGENCE AT ALL -- the injection never landed, so this "
                  "run proves nothing about the repair")
            return 1
        print("diverged at tick %d, %d divergent ticks in all, last at %d"
              % (bad[0], len(bad), bad[-1]))
        print("recovered after %d ticks (%.1f seconds at 15 a second)"
              % (bad[-1] - bad[0] + 1, (bad[-1] - bad[0] + 1) / 15.0))
        if healed:
            print("the last %d ticks agree byte for byte" % len(tail))
        else:
            print("THE LAST %d TICKS DO NOT AGREE -- no repair happened"
                  % len(tail))
        return 0 if healed else 1

    if first is None:
        print("\nNO DIVERGENCE -- the two consoles agree at every common tick")
        return 0
    print("\nevery cell that ever differed, by how many ticks:")
    for ad in sorted(counts, key=lambda k: -counts[k]):
        print("  $%02X %-10s %d" % (ad, NAMES.get(ad, ""), counts[ad]))
    return 1


if __name__ == "__main__":
    sys.exit(main())
