"""dgmap.py -- the map of Activision Dragster, and the single place it is stated.

Imported by disasm.py, mkbanks.py, check_patch.py and checkrom_filter.py, so
that a region boundary, a symbol or a zero-page name exists exactly once. Combat
could afford to state its regions in mkbanks.py alone because its source of
record was a hand-written disassembly that already carried the labels; this port
GENERATES its source, so the map is upstream of everything and has to be shared.

Addresses are the cartridge's own: $F000-$F7FF, 2K flat, mirrored into $F800.
"""

ROM_BASE = 0xF000
ROM_END  = 0xF800           # exclusive
BANK_BASE = 0x1000          # every bank is entered here; $F000 -> $1000

# ---------------------------------------------------------------------------
# REGIONS -- (first, last+1, banks, kind, why)
#
# `banks` is a SET, which is the one structural difference from Combat's table.
# Dragster has one code region and three data regions that BOTH halves read, and
# they are emitted into every bank that declares them, byte-identical. Combat
# had a single EXPORT and no shared code at all.
#
# The rule that makes this safe: a bank that does not own a region has no labels
# for it, so an accidental cross-bank reference is an assembler error rather
# than a silently wrong address.
GAME = "GAME"
KERN = "KERN"

REGIONS = [
    (0xF000, 0xF016, {GAME},       "code", "cold boot, the clear loop, JSR StageRace"),
    (0xF016, 0xF051, {KERN},       "code", "colour setup, kernel fine-timing prep, the VBLANK wait"),
    (0xF051, 0xF209, {KERN},       "code", "the lane kernel, run twice"),
    (0xF209, 0xF226, {KERN},       "code", "lane advance, ACTIVISION band, arm overscan"),
    (0xF226, 0xF285, {GAME},       "code", "the audio engine"),
    (0xF285, 0xF28A, {GAME},       "code", "the overscan wait -- THE NETWORK HOOK"),
    (0xF28A, 0xF2C8, {GAME},       "code", "VSYNC, frame counter, attract colours, arm VBLANK"),
    (0xF2C8, 0xF31E, {GAME},       "code", "input, restart detect, SELECT / new game"),
    (0xF31E, 0xF4E5, {GAME},       "code", "the game logic, the LFSR, the tach bar"),
    (0xF4E5, 0xF52D, {KERN, GAME}, "code", "PositionSprites -- SHARED, see note below"),
    (0xF52D, 0xF53B, {KERN},       "code", "CalcSpritePtrs part A"),
    (0xF53B, 0xF56A, {KERN},       "code", "DrawMessage"),
    (0xF56A, 0xF6C8, {KERN},       "data", "ball table, six car sprite layers, road-dash PF"),
    (0xF6C8, 0xF6CA, {KERN, GAME}, "data", "scroll-rate masks -- SHARED, read at $F37C"),
    (0xF6CA, 0xF6D3, {KERN},       "data", "colour table, lane-top PF"),
    (0xF6D3, 0xF6F6, {GAME},       "code", "StageRace"),
    (0xF6F6, 0xF700, {KERN, GAME}, "data", "the two gear tables -- SHARED"),
    (0xF700, 0xF7C4, {KERN},       "data", "the 14-glyph font and four message strips"),
    (0xF7C4, 0xF7D0, {KERN},       "data", "the six sprite-pointer bases"),
    (0xF7D0, 0xF7FA, {KERN},       "code", "CalcSpritePtrs part B"),
    (0xF7FA, 0xF800, set(),        "data", "the 1977 vectors; not emitted into any bank"),
]

# PositionSprites is duplicated into both banks rather than switched to, and the
# reason is structural: the kernel JSRs it three times ($F055, $F164, $F219) and
# StageRace -- which lives in the GAME bank -- JMPs into its MIDDLE at $F4E9,
# returning through its RTS to StageRace's own caller. A bank switch is a jump;
# nothing returns through one, so a pending return address cannot survive it.

# ---------------------------------------------------------------------------
# SYMBOLS -- code labels. Everything else gets L_Fxxx.
SYMBOLS = {
    0xF000: "Reset",           0xF004: "ClearEntry",     0xF006: "ClearLoop",
    0xF013: "ColdStage",       0xF016: "FrameTop",       0xF046: "WaitVBlank",
    0xF04B: "DisplayStart",    0xF051: "LaneKernel",     0xF0A7: "CarKernel",
    0xF12C: "TachBar",         0xF209: "LaneNext",       0xF217: "LogoBand",
    0xF221: "ArmOverscan",     0xF226: "Audio",          0xF242: "BeepTest",
    0xF285: "WaitOverscan",    0xF28A: "SyncBlock",          0xF29A: "FrameCount",
    0xF2A7: "ReadBW",          0xF2C1: "ArmVBlank",      0xF2C8: "ReadJoy",
    0xF2D7: "RestartDetect",   0xF2E3: "ReadSwitches",   0xF2E9: "Restage",
    0xF2EE: "ChkSelect",       0xF2FD: "NewGame",        0xF31E: "Logic",
    0xF322: "TickCountdown",       0xF338: "RaceOver",       0xF344: "TimeChain",
    0xF398: "FinishTest",      0xF3B1: "ReadTrigger",    0xF3E9: "RevLimit",
    0xF450: "FoulTest",        0xF466: "LaneDrift",      0xF4A4: "StepLfsr",
    0xF4B4: "BuildTach",       0xF4E5: "PositionSprites", 0xF4E9: "PositionBall",
    0xF52D: "CalcPtrsA",       0xF53B: "DrawMessage",    0xF6D3: "StageRace",
    0xF7D0: "CalcPtrsB",
}

# ---------------------------------------------------------------------------
# DATALBL -- labels for the data tables, so the code that reads them says what
# it is reading. Anything referenced but unnamed gets D_Fxxx.
DATALBL = {
    0xF56A: "BallTbl",     0xF56E: "CarL0",       0xF5B3: "CarL1",
    0xF600: "CarL2",       0xF62E: "CarL3",       0xF65C: "CarL4",
    0xF68A: "CarL5",       0xF6C0: "RoadDashA",   0xF6C4: "RoadDashB",
    0xF6C8: "ScrollMask",  0xF6CA: "ColourTbl",   0xF6D0: "LaneTopPF",
    0xF6F6: "GearRate",    0xF6FB: "GearAccel",   0xF700: "Font",
    0xF76E: "MsgA",        0xF775: "MsgB",        0xF77C: "MsgC",
    0xF783: "MsgD",        0xF7C4: "SprBase",
}

# ---------------------------------------------------------------------------
# BIAS -- operands that point OUTSIDE the table they actually read.
#
# `ADC GearRate-4,Y` with Y in {4,6} touches $F6F6 and $F6F8. The operand $F6F2
# is not the address of anything and must not be given a label of its own; it is
# the gear table biased by the index it is always used with. The disassembler
# emits the expression and then asserts it still evaluates to $F6F2 -- which is
# the whole point of writing it this way rather than as a bare number.
#
#   addr of the INSTRUCTION -> (label, signed offset)
BIAS = {
    0xF7E9: ("GearRate", -4),
}

# ---------------------------------------------------------------------------
# ZP -- the zero page, by what it means.
#
# Per-player values are adjacent pairs indexed by X in {0,1}: `addr` is the top
# lane (player 0) and `addr+1` the bottom. The highest cell ANY addressing mode
# in the game touches is $D9; $DA-$FF is the netcode's, and $83 and $AF are left
# free deliberately.
ZP = {
    0x80: "GameVar",    0x81: "FrameCnt",   0x82: "Lfsr",       0x84: "AttrEor",
    0x85: "AttrAnd",    0x86: "ColDigit",   0x88: "ColPF",      0x89: "ColBK",
    0x8A: "ColP0",      0x8B: "ColP1",      0x8C: "ColRoad",    0x8D: "Countdown",
    0x8E: "KernLine",   0x8F: "CurPlayer",  0x90: "SprPtr0",    0x92: "SprPtr1",
    0x94: "SprPtr2",    0x96: "SprPtr3",    0x98: "SprPtr4",    0x9A: "SprPtr5",
    0x9C: "TachPF0",    0x9E: "TachPF1",    0xA0: "TachPF2",    0xA2: "TachPF3",
    0xA4: "TachPF4",    0xA6: "TachPF5",    0xA8: "Rpm",        0xAA: "LaneIdx",
    0xAB: "LanePos",    0xAD: "Joy0",       0xAE: "Joy1",       0xB0: "SelDelay",
    0xB1: "EngVol",     0xB3: "TimeSec",    0xB5: "TimeHun",    0xB7: "TimeSub",
    0xB9: "Attract",    0xBA: "TrackPos",   0xBC: "KernCoarse", 0xBE: "KernFine",
    0xC0: "Speed",      0xC2: "SubPos",     0xC4: "ScrollPh",   0xC6: "WheelPh",
    0xC8: "BodyOff",    0xCA: "Scrape",     0xCC: "Gear",       0xCE: "Blown",
    0xD0: "BoomTimer",  0xD2: "RaceDone",   0xD4: "MsgIdx",     0xD6: "PrevGear",
    0xD8: "Tmp0",       0xD9: "Tmp1",
}

ZP_FREE = (0x83, 0xAF)
ZP_NETCODE_LO = 0xDA        # the netcode owns $DA upward; the clears stop here
ZP_STACK_LO = 0xFA


def region_of(addr):
    for lo, hi, banks, kind, why in REGIONS:
        if lo <= addr < hi:
            return (lo, hi, banks, kind, why)
    raise KeyError(f"${addr:04X} is outside the cartridge")


def is_code(addr):
    return region_of(addr)[3] == "code"


def banks_of(addr):
    return region_of(addr)[2]


def check_totals():
    """The regions must tile $F000-$F800 exactly, with no gap and no overlap."""
    want = ROM_BASE
    for lo, hi, banks, kind, why in REGIONS:
        if lo != want:
            raise AssertionError(f"region gap/overlap at ${lo:04X}, expected ${want:04X}")
        want = hi
    if want != ROM_END:
        raise AssertionError(f"regions end at ${want:04X}, not ${ROM_END:04X}")
    return sum(hi - lo for lo, hi, _, _, _ in REGIONS)


if __name__ == "__main__":
    total = check_totals()
    print(f"regions tile ${ROM_BASE:04X}-${ROM_END:04X}: {total} bytes")
    for lo, hi, banks, kind, why in REGIONS:
        b = "+".join(sorted(banks)) if banks else "-"
        print(f"  ${lo:04X}-${hi-1:04X} {hi-lo:5d}  {b:9s} {kind}  {why}")
