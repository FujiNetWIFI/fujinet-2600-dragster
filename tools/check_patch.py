#!/usr/bin/env python3
"""check_patch.py -- audit the built image against the cartridge.

The family's rule: a change that was not declared is a build failure, and so is
a declaration that changed nothing. This is the gate that makes "Dragster, moved
into banks" a claim rather than a hope.

It works because of a deliberate layout choice: every byte of Dragster keeps the
OFFSET it has in the dump, and each bank simply leaves the other's regions
empty. So the audit is a byte compare of each region against the same offsets of
the baseline, and the only bytes allowed to differ are the ones patches.py
declares.

The baseline is NOT rom/dragster.bin. It is the same never-edited source
assembled at $1000, where a cartridge bank is actually mapped -- because every
absolute address inside Dragster has a high byte, and $F4 really does become
$14. Comparing against the $F000 image would report a hundred and more
"undeclared changes" that are the rebase and nothing else, and a gate that cries
wolf that loudly is not a gate. Both images come from the same source through
the same generator, and `make verify-org` proves that path reproduces the dump
byte for byte, so the baseline cannot drift.

ONE DIFFERENCE FROM COMBAT: a region's bank is a set, and a SHARED region is
compared in EVERY bank that owns it. PositionSprites, the scroll masks and the
gear tables exist twice in the image, and a build that got one copy right and
the other wrong would play correctly until the frame a lane happened to be
drawn from the wrong one.

Usage: check_patch.py baseline.bin built.bin
"""

import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import dgmap
import patches as patchmap

SLOT = {"BOOT": 0, "GAME": 1, "KERN": 2}
BANKSZ = 0x800


def main():
    stock = open(sys.argv[1], "rb").read()
    built = open(sys.argv[2], "rb").read()
    if len(stock) != BANKSZ:
        sys.exit("check_patch: %s is %d bytes, expected 2048"
                 % (sys.argv[1], len(stock)))

    allowed = set()
    for lo, hi, _why in patchmap.REWRITTEN:
        allowed.update(range(lo, hi))
    for a, span, _why in patchmap.SPANS:
        allowed.update(range(a, a + span))

    problems, changed, seen, shared = [], set(), 0, 0
    for lo, hi, banks, kind, why in dgmap.REGIONS:
        for bank in sorted(banks):
            base = SLOT[bank] * BANKSZ
            if len(banks) > 1:
                shared += hi - lo
            for a in range(lo, hi):
                off = a - dgmap.ROM_BASE
                seen += 1
                if stock[off] == built[base + off]:
                    continue
                changed.add(a)
                if a not in allowed:
                    problems.append(
                        "UNDECLARED DIFF at $%04X (%s bank, %s): $%02X -> $%02X"
                        % (a, bank.lower(), why, stock[off], built[base + off]))

    # A declaration that changed nothing is as much a bug as an undeclared
    # change: it means the patch did not land where it was aimed.
    for a, span, why in patchmap.SPANS:
        if not any(x in changed for x in range(a, a + span)):
            problems.append("DECLARED PATCH at $%04X changed nothing: %s" % (a, why))
    for lo, hi, why in patchmap.REWRITTEN:
        if not any(x in changed for x in range(lo, hi)):
            problems.append("DECLARED REWRITE $%04X-$%04X changed nothing: %s"
                            % (lo, hi - 1, why))

    for p in problems:
        print("check_patch: " + p, file=sys.stderr)
    if problems:
        return 1
    print("check_patch: %d bytes of Dragster compared (%d of them a shared "
          "region's second copy), %d changed, all declared"
          % (seen, shared, len(changed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
