#!/usr/bin/env python3
"""disasm.py -- turn rom/dragster.bin into Macroassembler AS source, mechanically.

Combat reused the public 2002 DASM disassembly as its source of record and
converted it with dasm2as.py on every build. No Dragster disassembly exists, so
this port generates one instead -- which means the generator, not a human, is
the thing that has to be trusted, and it carries its own proofs:

  1. ROUND TRIP. Every instruction decoded is re-encoded from its mnemonic and
     addressing mode and compared against the bytes it came from. A mis-sized
     opcode table cannot survive contact with this.

  2. REGION AGREEMENT. Recursive descent from $F000 reaches a set of bytes; that
     set is compared against the code regions declared in dgmap.py. A future
     edit to the map that reclassifies a code byte as data is a build failure
     rather than a silently truncated bank.

  3. OPERAND BIAS. `ADC $F6F2,Y` at $F7E9 reads OUTSIDE the table it appears to
     name: Y is 4 or 6 there, so the bytes actually touched are $F6F6 and $F6F8,
     ten bytes into the gear table -- and $F6F2 itself is the immediate operand
     of `LDA #$23` inside StageRace, so a label cannot go there. dgmap.BIAS
     declares the expression and this asserts it still evaluates to $F6F2.

Usage:
    disasm.py rom/dragster.bin            emit the source on stdout
    disasm.py --check rom/dragster.bin    run the three proofs, print a summary
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dgmap

# ---------------------------------------------------------------------------
# Addressing modes: (length, format). {0} is the rendered operand.
MODES = {
    "imp": (1, "{m}"),
    "acc": (1, "{m}\tA"),
    "imm": (2, "{m}\t#{0}"),
    "zp":  (2, "{m}\t{0}"),
    "zpx": (2, "{m}\t{0},X"),
    "zpy": (2, "{m}\t{0},Y"),
    "izx": (2, "{m}\t({0},X)"),
    "izy": (2, "{m}\t({0}),Y"),
    "rel": (2, "{m}\t{0}"),
    "abs": (3, "{m}\t{0}"),
    "abx": (3, "{m}\t{0},X"),
    "aby": (3, "{m}\t{0},Y"),
    "ind": (3, "{m}\t({0})"),
}

# The 151 official opcodes. Anything not here stops a trace.
OPS = {
    0x00: ("BRK", "imp"), 0x01: ("ORA", "izx"), 0x05: ("ORA", "zp"),  0x06: ("ASL", "zp"),
    0x08: ("PHP", "imp"), 0x09: ("ORA", "imm"), 0x0A: ("ASL", "acc"), 0x0D: ("ORA", "abs"),
    0x0E: ("ASL", "abs"), 0x10: ("BPL", "rel"), 0x11: ("ORA", "izy"), 0x15: ("ORA", "zpx"),
    0x16: ("ASL", "zpx"), 0x18: ("CLC", "imp"), 0x19: ("ORA", "aby"), 0x1D: ("ORA", "abx"),
    0x1E: ("ASL", "abx"), 0x20: ("JSR", "abs"), 0x21: ("AND", "izx"), 0x24: ("BIT", "zp"),
    0x25: ("AND", "zp"),  0x26: ("ROL", "zp"),  0x28: ("PLP", "imp"), 0x29: ("AND", "imm"),
    0x2A: ("ROL", "acc"), 0x2C: ("BIT", "abs"), 0x2D: ("AND", "abs"), 0x2E: ("ROL", "abs"),
    0x30: ("BMI", "rel"), 0x31: ("AND", "izy"), 0x35: ("AND", "zpx"), 0x36: ("ROL", "zpx"),
    0x38: ("SEC", "imp"), 0x39: ("AND", "aby"), 0x3D: ("AND", "abx"), 0x3E: ("ROL", "abx"),
    0x40: ("RTI", "imp"), 0x41: ("EOR", "izx"), 0x45: ("EOR", "zp"),  0x46: ("LSR", "zp"),
    0x48: ("PHA", "imp"), 0x49: ("EOR", "imm"), 0x4A: ("LSR", "acc"), 0x4C: ("JMP", "abs"),
    0x4D: ("EOR", "abs"), 0x4E: ("LSR", "abs"), 0x50: ("BVC", "rel"), 0x51: ("EOR", "izy"),
    0x55: ("EOR", "zpx"), 0x56: ("LSR", "zpx"), 0x58: ("CLI", "imp"), 0x59: ("EOR", "aby"),
    0x5D: ("EOR", "abx"), 0x5E: ("LSR", "abx"), 0x60: ("RTS", "imp"), 0x61: ("ADC", "izx"),
    0x65: ("ADC", "zp"),  0x66: ("ROR", "zp"),  0x68: ("PLA", "imp"), 0x69: ("ADC", "imm"),
    0x6A: ("ROR", "acc"), 0x6C: ("JMP", "ind"), 0x6D: ("ADC", "abs"), 0x6E: ("ROR", "abs"),
    0x70: ("BVS", "rel"), 0x71: ("ADC", "izy"), 0x75: ("ADC", "zpx"), 0x76: ("ROR", "zpx"),
    0x78: ("SEI", "imp"), 0x79: ("ADC", "aby"), 0x7D: ("ADC", "abx"), 0x7E: ("ROR", "abx"),
    0x81: ("STA", "izx"), 0x84: ("STY", "zp"),  0x85: ("STA", "zp"),  0x86: ("STX", "zp"),
    0x88: ("DEY", "imp"), 0x8A: ("TXA", "imp"), 0x8C: ("STY", "abs"), 0x8D: ("STA", "abs"),
    0x8E: ("STX", "abs"), 0x90: ("BCC", "rel"), 0x91: ("STA", "izy"), 0x94: ("STY", "zpx"),
    0x95: ("STA", "zpx"), 0x96: ("STX", "zpy"), 0x98: ("TYA", "imp"), 0x99: ("STA", "aby"),
    0x9A: ("TXS", "imp"), 0x9D: ("STA", "abx"), 0xA0: ("LDY", "imm"), 0xA1: ("LDA", "izx"),
    0xA2: ("LDX", "imm"), 0xA4: ("LDY", "zp"),  0xA5: ("LDA", "zp"),  0xA6: ("LDX", "zp"),
    0xA8: ("TAY", "imp"), 0xA9: ("LDA", "imm"), 0xAA: ("TAX", "imp"), 0xAC: ("LDY", "abs"),
    0xAD: ("LDA", "abs"), 0xAE: ("LDX", "abs"), 0xB0: ("BCS", "rel"), 0xB1: ("LDA", "izy"),
    0xB4: ("LDY", "zpx"), 0xB5: ("LDA", "zpx"), 0xB6: ("LDX", "zpy"), 0xB8: ("CLV", "imp"),
    0xB9: ("LDA", "aby"), 0xBA: ("TSX", "imp"), 0xBC: ("LDY", "abx"), 0xBD: ("LDA", "abx"),
    0xBE: ("LDX", "aby"), 0xC0: ("CPY", "imm"), 0xC1: ("CMP", "izx"), 0xC4: ("CPY", "zp"),
    0xC5: ("CMP", "zp"),  0xC6: ("DEC", "zp"),  0xC8: ("INY", "imp"), 0xC9: ("CMP", "imm"),
    0xCA: ("DEX", "imp"), 0xCC: ("CPY", "abs"), 0xCD: ("CMP", "abs"), 0xCE: ("DEC", "abs"),
    0xD0: ("BNE", "rel"), 0xD1: ("CMP", "izy"), 0xD5: ("CMP", "zpx"), 0xD6: ("DEC", "zpx"),
    0xD8: ("CLD", "imp"), 0xD9: ("CMP", "aby"), 0xDD: ("CMP", "abx"), 0xDE: ("DEC", "abx"),
    0xE0: ("CPX", "imm"), 0xE1: ("SBC", "izx"), 0xE4: ("CPX", "zp"),  0xE5: ("SBC", "zp"),
    0xE6: ("INC", "zp"),  0xE8: ("INX", "imp"), 0xE9: ("SBC", "imm"), 0xEA: ("NOP", "imp"),
    0xEC: ("CPX", "abs"), 0xED: ("SBC", "abs"), 0xEE: ("INC", "abs"), 0xF0: ("BEQ", "rel"),
    0xF1: ("SBC", "izy"), 0xF5: ("SBC", "zpx"), 0xF6: ("INC", "zpx"), 0xF8: ("SED", "imp"),
    0xF9: ("SBC", "aby"), 0xFD: ("SBC", "abx"), 0xFE: ("INC", "abx"),
}

ENC = {}
for _op, (_m, _md) in OPS.items():
    ENC[(_m, _md)] = _op

TERMINAL = {0x60, 0x40, 0x00, 0x4C, 0x6C}      # RTS RTI BRK JMP JMP()
BRANCHES = {0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0}

# ---------------------------------------------------------------------------
# The console, by name. The SAME address is a different register depending on
# whether it is read or written, so the side matters: $0C is INPT4 read and
# REFP0 written, and Dragster reads it ($F3B1) -- which is exactly the site the
# netcode patches, so getting this backwards would rename the patch target.
TIA_W = ["VSYNC","VBLANK","WSYNC","RSYNC","NUSIZ0","NUSIZ1","COLUP0","COLUP1",
         "COLUPF","COLUBK","CTRLPF","REFP0","REFP1","PF0","PF1","PF2",
         "RESP0","RESP1","RESM0","RESM1","RESBL","AUDC0","AUDC1","AUDF0",
         "AUDF1","AUDV0","AUDV1","GRP0","GRP1","ENAM0","ENAM1","ENABL",
         "HMP0","HMP1","HMM0","HMM1","HMBL","VDELP0","VDELP1","VDELBL",
         "RESMP0","RESMP1","HMOVE","HMCLR","CXCLR"]
TIA_R = ["CXM0P","CXM1P","CXP0FB","CXP1FB","CXM0FB","CXM1FB","CXBLPF","CXPPMM",
         "INPT0","INPT1","INPT2","INPT3","INPT4","INPT5"]
RIOT = {0x0280:"SWCHA", 0x0281:"SWACNT", 0x0282:"SWCHB", 0x0283:"SWBCNT",
        0x0284:"INTIM", 0x0294:"TIM1T", 0x0295:"TIM8T", 0x0296:"TIM64T",
        0x0297:"T1024T"}
STORES = {"STA", "STX", "STY"}

VCS_NAMES = set(TIA_W) | set(TIA_R) | set(RIOT.values())


def _based(addr, table):
    """Render addr as NAME or NAME+n against a {addr: name} table."""
    keys = sorted(table)
    base = None
    for k in keys:
        if k <= addr:
            base = k
        else:
            break
    if base is None:
        return None
    nxt = next((k for k in keys if k > base), None)
    if addr == base:
        return table[base]
    if nxt is not None and addr >= nxt:
        return None
    if addr - base > 16:
        return None
    return f"{table[base]}+{addr - base}"


class Disassembler:
    def __init__(self, img):
        if len(img) != 2048:
            raise SystemExit(f"disasm: expected 2048 bytes, got {len(img)}")
        self.img = img
        self.starts = set()      # addresses that begin an instruction
        self.covered = set()     # every byte belonging to an instruction
        self.refs = set()        # ROM addresses named by an operand
        self.targets = set()     # ROM addresses that need a code label
        self.labels = {}
        self.problems = []

    def byte(self, a):
        return self.img[a - dgmap.ROM_BASE]

    def word(self, a):
        return self.byte(a) | (self.byte(a + 1) << 8)

    # -- pass 1: recursive descent ------------------------------------------
    def walk(self, entry):
        pending = [entry]
        while pending:
            pc = pending.pop()
            while True:
                if not (dgmap.ROM_BASE <= pc < dgmap.ROM_END) or pc in self.starts:
                    break
                op = self.byte(pc)
                ent = OPS.get(op)
                if ent is None:
                    self.problems.append(f"${pc:04X}: undefined opcode ${op:02X}")
                    break
                mnem, mode = ent
                n = MODES[mode][0]
                if pc + n > dgmap.ROM_END:
                    self.problems.append(f"${pc:04X}: {mnem} runs off the end")
                    break
                self.starts.add(pc)
                for i in range(n):
                    self.covered.add(pc + i)
                nxt = pc + n

                if mode == "rel":
                    off = self.byte(pc + 1)
                    tgt = nxt + (off - 256 if off > 127 else off)
                    self.targets.add(tgt)
                    pending.append(tgt)
                    pc = nxt
                    continue
                if mode in ("abs", "abx", "aby", "ind"):
                    self.refs.add(self.word(pc + 1))
                if op == 0x20:                       # JSR
                    t = self.word(pc + 1)
                    self.targets.add(t)
                    pending.append(t)
                    pc = nxt
                    continue
                if op == 0x4C:                       # JMP abs
                    t = self.word(pc + 1)
                    self.targets.add(t)
                    pc = t
                    continue
                if op in TERMINAL:
                    break
                pc = nxt

    # -- pass 2: labels ------------------------------------------------------
    def build_labels(self):
        for a, name in dgmap.SYMBOLS.items():
            self.labels[a] = name
        for a, name in dgmap.DATALBL.items():
            self.labels[a] = name
        for a in sorted(self.targets):
            if a not in self.labels:
                self.labels[a] = f"L_{a:04X}"
        for a in sorted(self.refs):
            if not (dgmap.ROM_BASE <= a < dgmap.ROM_END):
                continue
            if a in self.labels:
                continue
            if a in self.covered and a not in self.starts:
                continue          # mid-instruction: must be declared in BIAS
            if dgmap.is_code(a) and a not in self.starts:
                continue
            self.labels[a] = ("L_" if dgmap.is_code(a) else "D_") + f"{a:04X}"
        # AS is case-insensitive, so every name in the file shares one
        # namespace: the ROM labels, the zero-page cells and vcs.inc's
        # registers. Combat got away with not checking this by luck.
        seen = {}
        for a, name in list(self.labels.items()) + list(dgmap.ZP.items()):
            key = name.upper()
            if key in {n.upper() for n in VCS_NAMES}:
                self.problems.append(
                    f"'{name}' collides with a vcs.inc register "
                    f"(AS is case-insensitive)")
            if key in seen and seen[key] != a:
                self.problems.append(
                    f"'{name}' is used for both ${seen[key]:04X} and ${a:04X}")
            seen[key] = a

    # -- operand rendering ---------------------------------------------------
    def operand(self, pc, mnem, mode):
        n = MODES[mode][0]
        if mode == "imm":
            return f"${self.byte(pc + 1):02X}"
        if mode == "rel":
            off = self.byte(pc + 1)
            tgt = pc + 2 + (off - 256 if off > 127 else off)
            return self.labels.get(tgt, f"${tgt:04X}")
        if n == 2:
            v = self.byte(pc + 1)
            return self.zpname(v, mnem)
        v = self.word(pc + 1)
        return self.absname(pc, v, mnem)

    def zpname(self, v, mnem):
        if v <= 0x2C and mnem in STORES:
            return TIA_W[v]
        if v <= 0x0D and mnem not in STORES:
            return TIA_R[v]
        if v >= 0x80:
            nm = _based(v, dgmap.ZP)
            if nm:
                return nm
        return f"${v:02X}"

    def absname(self, pc, v, mnem):
        if pc in dgmap.BIAS:
            base, delta = dgmap.BIAS[pc]
            site = next(a for a, nm in dgmap.DATALBL.items() if nm == base)
            if site + delta != v:
                self.problems.append(
                    f"${pc:04X}: BIAS says {base}{delta:+d} = ${site + delta:04X}, "
                    f"but the operand is ${v:04X}")
            return f"{base}{delta:+d}"
        if v in RIOT:
            return RIOT[v]
        if v in self.labels:
            return self.labels[v]
        if dgmap.ROM_BASE <= v < dgmap.ROM_END:
            nm = _based(v, {a: n for a, n in self.labels.items()
                            if dgmap.ROM_BASE <= a < dgmap.ROM_END})
            if nm:
                return nm
        if v < 0x0100:
            # An absolute instruction naming a zero-page address. AS would fold
            # it to the short form and shift every byte after it; '>' is what
            # stops that, and the round-trip check is what proves it did.
            return ">" + (self.zpname(v, mnem) if v >= 0x80 else f"${v:02X}")
        return f"${v:04X}"

    # -- proof 1: round trip -------------------------------------------------
    def roundtrip(self):
        for pc in sorted(self.starts):
            op = self.byte(pc)
            mnem, mode = OPS[op]
            if ENC.get((mnem, mode)) != op:
                self.problems.append(
                    f"${pc:04X}: {mnem}/{mode} re-encodes to "
                    f"${ENC.get((mnem, mode), -1):02X}, not ${op:02X}")

    # -- proof 2: region agreement -------------------------------------------
    def regions_agree(self):
        declared = set()
        for lo, hi, banks, kind, why in dgmap.REGIONS:
            if kind == "code":
                declared.update(range(lo, hi))
        extra = self.covered - declared
        missing = declared - self.covered
        for a in sorted(extra):
            self.problems.append(f"${a:04X}: reached as code, declared as data")
        for a in sorted(missing):
            self.problems.append(f"${a:04X}: declared as code, never reached")
        return len(declared)

    # -- emission ------------------------------------------------------------
    def emit(self):
        out = []
        w = out.append
        w("; dragster.asm -- Activision Dragster (1980), disassembled.")
        w(";")
        w("; GENERATED by tools/disasm.py and then annotated BY HAND, comments")
        w("; only. Never a token of code: `make verify-org` regenerates this file,")
        w("; strips the comments from both, and requires them to be identical --")
        w("; and then assembles it and requires the result to be rom/dragster.bin")
        w("; byte for byte. Every change to the program is declared in")
        w("; tools/patches.py and applied at build time.")
        w("")
        w("\tCPU\t6502")
        w("\tINCLUDE\t\"vcs.inc\"")
        w("")
        w("; The zero page, by what it means. These MUST be declared before")
        w("; first use: AS resolves a forward reference as 16-bit, and `STY")
        w("; abs,X` is not a 6502 instruction -- while `LDA abs` where `LDA zp`")
        w("; was meant assembles quietly and shifts every byte after it.")
        w(";")
        w("; Per-player cells are adjacent pairs indexed by X in {0,1}: the")
        w("; name is the top lane (player 0) and name+1 the bottom.")
        for a in sorted(dgmap.ZP):
            w(f"{dgmap.ZP[a]}\tEQU\t${a:02X}")
        w("")
        w(f"\tORG\t${dgmap.ROM_BASE:04X}")
        w("")
        for lo, hi, banks, kind, why in dgmap.REGIONS:
            b = "+".join(sorted(banks)) if banks else "(neither bank)"
            w(f"; --- ${lo:04X}-${hi-1:04X}  {b}  {why}")
            if kind == "code":
                self.emit_code(w, lo, hi)
            else:
                self.emit_data(w, lo, hi)
            w("")
        return "\n".join(out) + "\n"

    def emit_code(self, w, lo, hi):
        pc = lo
        while pc < hi:
            if pc in self.labels:
                w(f"{self.labels[pc]}:")
            if pc not in self.starts:
                w(f"\tDB\t${self.byte(pc):02X}")
                pc += 1
                continue
            op = self.byte(pc)
            mnem, mode = OPS[op]
            n, fmt = MODES[mode]
            txt = fmt.format(self.operand(pc, mnem, mode), m=mnem)
            w("\t" + txt)
            pc += n

    def emit_data(self, w, lo, hi):
        pc = lo
        row = []
        while pc < hi:
            if pc in self.labels and row:
                w("\tDB\t" + ",".join(row))
                row = []
            if pc in self.labels:
                w(f"{self.labels[pc]}:")
            if hi - lo == 6 and lo == 0xF7FA:
                # the vectors, as words, so the reset vector reads as a name
                w(f"\tDW\t${self.word(pc):04X}" if self.word(pc) not in self.labels
                  else f"\tDW\t{self.labels[self.word(pc)]}")
                pc += 2
                continue
            row.append(f"${self.byte(pc):02X}")
            pc += 1
            if len(row) == 8:
                w("\tDB\t" + ",".join(row))
                row = []
        if row:
            w("\tDB\t" + ",".join(row))


def main(argv):
    check = False
    args = []
    for a in argv[1:]:
        if a == "--check":
            check = True
        else:
            args.append(a)
    if not args:
        raise SystemExit("usage: disasm.py [--check] rom/dragster.bin")
    img = open(args[0], "rb").read()

    dgmap.check_totals()
    d = Disassembler(img)
    d.walk(dgmap.ROM_BASE)
    d.build_labels()
    d.roundtrip()
    declared = d.regions_agree()
    text = d.emit()          # rendering is where BIAS is checked

    if d.problems:
        for p in d.problems:
            print(f"disasm: {p}", file=sys.stderr)
        raise SystemExit(f"disasm: {len(d.problems)} problem(s)")

    if check:
        print(f"disasm: {len(d.starts)} instructions, {len(d.covered)} code bytes")
        print(f"disasm: round trip OK, regions agree ({declared} code bytes declared)")
        print(f"disasm: {len(d.labels)} labels, {len(dgmap.BIAS)} biased operand(s) verified")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main(sys.argv)
