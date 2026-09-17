#!/usr/bin/env python3
"""check_zp.py -- prove no RAM clear in the built image can reach the netcode.

Dragster has two paths into one clear loop and the second is a JMP into the
middle of the first with X preloaded, so a restage wiped $B9-$FF -- every cell
this port owns -- on every RESET and every SELECT. The loop is bounded now, and
this is the gate that keeps it bounded.

A regression here is silent and slow: the netcode survives until the first time
somebody presses RESET, and then the tick, the ring and the role are zero on one
console and not the other. Twenty lines to make that impossible.

Three assertions:
  1. every netcode cell is at or above DGZPLO
  2. the clear loop really compares against DGZPLO and not a literal
  3. both restage seeds are below DGZPLO, so the loop terminates where it should

Usage: check_zp.py build/dggame.lst
"""
import re
import sys

# The cells the netcode owns. Session-side cells share the same range by union.
NETCODE = ["DGENT", "DGSEQ", "DGERR", "DGTICK", "DGNST", "DGCRCV", "DGADV",
           "DGTMP", "DGLEAD", "DGCLRX", "DGSWB", "DGTRIG", "DGW0", "DGW1",
           "DGRWAT", "DGRING", "DGLOC", "DGRDN",
           "FNDEV", "FNCMD", "FNNPR", "FNTMO", "FNCNT", "FNPTRL", "FNPTRH",
           "FNPCNT", "INCUR", "INPREV", "CSDLY"]

SYM = re.compile(r"^\*?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([0-9A-F]{1,8})\b")
# `(1)  312/1027 : E0 DA        CPX  #DGZPLO`
CPX = re.compile(r"^\s*(?:\(\d+\)\s*)?\d+/([0-9A-F]{4})\s*:\s*"
                 r"((?:[0-9A-Fa-f]{2} )+)\s*(\S+)\s+(\S+)")


def symbols(path):
    out, in_tab = {}, False
    for line in open(path, errors="replace"):
        if "Symbol Table" in line:
            in_tab = True
            continue
        if not in_tab:
            continue
        for part in line.split("|"):
            m = SYM.match(part.strip())
            if m:
                try:
                    out[m.group(1).upper()] = int(m.group(2), 16)
                except ValueError:
                    pass
    return out


def main():
    lst = sys.argv[1]
    syms = symbols(lst)
    problems = []

    need = ["DGZPLO", "DGRSYX", "DGSTKX", "DGSTKLO"]
    for n in need:
        if n not in syms:
            problems.append("%s is not in the listing's symbol table" % n)
    if problems:
        for p in problems:
            print("check_zp: " + p, file=sys.stderr)
        return 1

    lo = syms["DGZPLO"]

    # 1. every netcode cell is at or above the bound.
    for n in NETCODE:
        a = syms.get(n.upper())
        if a is None:
            problems.append("%s is not in the listing's symbol table" % n)
        elif a < lo:
            problems.append("%s is $%02X, BELOW the clear bound $%02X -- a "
                            "restage would wipe it" % (n, a, lo))

    # 2. the clear loop compares against the bound, and does so as a symbol.
    #    A literal here would drift the moment the map moved.
    found = []
    for line in open(lst, errors="replace"):
        m = CPX.match(line)
        if not m:
            continue
        if m.group(3).upper() != "CPX":
            continue
        by = m.group(2).split()
        if len(by) == 2 and by[0].upper() == "E0":      # CPX immediate
            found.append((int(m.group(1), 16), int(by[1], 16), m.group(4)))
    bounded = [f for f in found if f[1] == lo]
    if not bounded:
        problems.append("no `CPX #$%02X` anywhere in the bank: the clear loop "
                        "is not bounded" % lo)
    elif not any("DGZPLO" in f[2].upper() for f in bounded):
        problems.append("the clear loop's bound is a literal, not DGZPLO")

    # 3. both seeds terminate below the bound.
    for n in ("DGRSYX", "DGSTKX"):
        if syms[n] >= lo:
            problems.append("%s is $%02X, at or above the bound $%02X -- the "
                            "clear would run away" % (n, syms[n], lo))

    # and the stack stays clear of the netcode's top cell
    if syms["DGSTKLO"] < lo:
        problems.append("DGSTKLO $%02X is below the bound" % syms["DGSTKLO"])

    for p in problems:
        print("check_zp: " + p, file=sys.stderr)
    if problems:
        return 1
    print("check_zp: %d netcode cells, all at or above $%02X; the clear is "
          "bounded by DGZPLO and both seeds terminate" % (len(NETCODE), lo))
    return 0


if __name__ == "__main__":
    sys.exit(main())
