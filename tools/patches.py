#!/usr/bin/env python3
"""patches.py -- every change made to Activision Dragster, declared in one place.

rom/dragster.asm is never edited. Everything this port does to the 1980 program
is here, anchored on the ADDRESS the assembler gave the line rather than on a
line number -- which Combat could not do, because its source of record was a
hand-written document whose line numbering was the only stable thing about it.
A generated source has an address for every line, so the anchor can be the thing
the patch is actually about.

Each entry also carries the source text it expects to replace. An anchor that
still resolves but no longer points at what the author was looking at is the
failure mode this exists to prevent.

tools/check_patch.py reads REWRITTEN and SPANS and audits the built image
against the same source assembled at $1000: a change that is not declared here
is a build failure, and so is a declaration that changed nothing.
"""

# ---------------------------------------------------------------------------
# REWRITTEN -- ranges where wholesale change is expected and byte-level auditing
# would be noise. Exactly one: the 22 bytes of cold-boot head.
REWRITTEN = [
    (0xF000, 0xF016, "the bank entry, the bounded clear and the warm mark"),
]

# ---------------------------------------------------------------------------
# SPANS -- every other changed byte, as (address, length, why). check_patch.py
# allows a difference here and NOWHERE else, and fails if any of these spans
# turns out to be unchanged.
SPANS = [
    (0xF1AA, 19, "the countdown glyph, displayed DGLEAD frames ahead of the sim"),
    (0xF242,  8, "the countdown beep, on the same lead"),
    (0xF285,  5, "the overscan wait becomes the network machine's step loop"),
    (0xF29A, 11, "the frame counter moves into DGSHIM, behind the lockstep gate"),
    (0xF2A7,  3, "SWCHB -> the shadow (Color/B&W)"),
    (0xF2C8, 15, "the SWCHA read is deleted; the stall gate takes its place"),
    (0xF2E3,  3, "SWCHB -> the shadow (RESET/SELECT)"),
    (0xF2E9,  5, "the restage clear's seed becomes a cell"),
    (0xF3B1,  2, "INPT4,X -> the trigger shadows"),
]

# ---------------------------------------------------------------------------
# PATCHES -- the text. `addr`/`span` locate the block; `old` asserts what is
# there; `new` replaces it. Blank and comment-only lines at the head of a block
# belong to the region banner, not to the patch, and are kept.
#
# There is no line-count rule. Combat needed one because it bucketed patched
# lines into banks using the UNPATCHED listing's line->address map, so a patch
# that changed the line count silently misfiled everything after it. Here the
# bucketing happens FIRST and patches are applied to a bucket, so a patch is
# free to be any length it likes -- it cannot reach outside its own region,
# which is asserted rather than assumed.
PATCHES = [

dict(
    name="the bank entry, the bounded clear and the warm mark",
    addr=0xF000, span=0x16,
    old="""Reset:
	SEI
	CLD
	LDX	#$00
ClearEntry:
	LDA	#$00
ClearLoop:
	STA	VSYNC,X
	TXS
	INX
	BNE	ClearLoop
	LDA	Lfsr
	BNE	ColdStage
	JMP	NewGame
ColdStage:
	JSR	StageRace""",
    new="""; The trampoline enters every bank at $1000, so the game bank's first act is
; to ask whether this is a frame boundary or a cold start. TWO INDEPENDENT
; BITS, not one value: Combat's boot bank once handed over with "playing" and
; the game bank read that as "not cold", so Dragster's own initialisation never
; ran and both consoles came up identically wrong.
DGGENT:
; BNE over a JMP rather than BEQ to the cold path, because the cold path is not
; within branch range: the transport is 510 bytes and the hole at $1016 is 528,
; so DGBOOT lives in the second hole, thirteen hundred bytes away.
	LDA	DGENT
	AND	#DGE_WARM
	BNE	DGGWARM
	JMP	DGBOOT
; Warm: the kernel bank has just finished a frame and switched here. Carry on
; at the audio engine, which is where stock falls through to.
;
; CLD is insurance, not ceremony. Dragster runs SED at $F348 for the BCD time
; chain and closes it with CLD at $F35C, and no branch leaves the block between
; them -- so decimal mode is provably clear today. It costs one byte to keep it
; that way, and an ADC in the checksum running in decimal mode would be a desync
; that only appeared after somebody finished a race.
DGGWARM:
	CLD
	JMP	Audio
; The rest of the cold path -- DGBOOT, the bounded clear and the seam-A
; trampoline -- is in the hole at $1016, because it does not fit in 22 bytes.
; These bytes are unreachable; p2bin fills them.
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP"""),

dict(
    name="the countdown glyph, displayed DGLEAD frames ahead of the sim",
    addr=0xF1AA, span=19,
    old="""	LDA	Countdown
	BEQ	L_F1B6
	AND	#$F0
	LSR	A
	ADC	#$08
	JMP	L_F1BD
L_F1B6:
	LDA	TimeHun,X
	AND	#$0F
	ASL	A
	ASL	A
	ASL	A""",
    new="""; THE TREE IS SHOWN DGLEAD SIMULATED FRAMES AHEAD OF THE SIM.
;
; Both stock paths converge on the STA at $F1BD, which is what makes nineteen
; bytes replaceable by three. DGTREE returns the same glyph index stock would
; have, computed from Countdown-DGLEAD instead of Countdown: the player reacts
; to a green that is eight frames early, the press is captured on the next tick
; boundary and applied d ticks later, and it lands at sim-green.
;
; DGLEAD is a cell and not a constant: it is zero when this console is not in a
; match, which is what keeps `make det` byte-identical against the 1980 ROM.
	JSR	DGTREE
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP"""),

dict(
    name="the countdown beep, on the same lead",
    addr=0xF242, span=8,
    old="""BeepTest:
	LDA	Countdown
	BEQ	L_F257
	AND	#$0F
	BNE	L_F257""",
    new="""; The ear has to agree with the eye, or the lead is worse than none: a player
; who launches on the beep would be eight frames behind one who launches on the
; light. DGBEEP returns with Z SET for silence, which is the sense both stock
; branches already had.
BeepTest:
	JSR	DGBEEP
	BEQ	L_F257
	NOP
	NOP
	NOP"""),

dict(
    name="the overscan wait becomes the network machine's step loop",
    addr=0xF285, span=5,
    old="""WaitOverscan:
	LDA	INTIM
	BNE	WaitOverscan""",
    new="""; THE HOOK. Five bytes for five, in the only window this frame has any real
; slack in: TIM64T was armed with $21 at $F221, the audio engine spends about a
; hundred cycles of it, and what is left is around two thousand.
;
; DGWAIT re-reads INTIM before every micro-step and stops when the slack is
; gone, so it cannot overrun the kernel by construction -- there is no budget to
; get wrong. It returns with A = 0 on every path, because $F298 clears VSYNC
; with the accumulator the stock spin left at zero.
WaitOverscan:
	JSR	DGWAIT
	NOP
	NOP"""),

dict(
    name="the frame counter moves into DGSHIM, behind the lockstep gate",
    addr=0xF29A, span=11,
    old="""FrameCount:
	INC	FrameCnt
	BNE	L_F2A5
	INC	Attract
	BNE	L_F2A5
	SEC
	ROR	Attract""",
    new="""; FrameCnt ($81) IS THE SIM CLOCK, so it must count simulated frames and not
; frames the television drew: it selects which car the logic updates ($F226),
; paces the engine tone, the road scroll, the gear timer, the scrape and the
; lane drift. Stock increments it here, unconditionally.
;
; It cannot be gated in place. $F298-$F2C3 is untimed -- between the last VSYNC
; WSYNC and the WSYNC at $F2C3 -- and the stock path already spends 54 of the 76
; cycles a scanline has. A JSR gate costs twenty of the twenty-two that are
; left. So the whole block moves into DGSHIM, which runs in the two thousand
; cycles of overscan, and this becomes a jump.
;
; Behaviour-identical, and the three things that could have made it otherwise
; were checked: the audio engine reads FrameCnt at $F226, BEFORE the hook at
; $F285, so it still sees the previous frame's value exactly as stock does;
; nothing between $F285 and here reads FrameCnt or Attract; and the BIT at
; $F2B2 reads Attract after the wrap in both. `make det` is the gate.
FrameCount:
	JMP	L_F2A5
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP"""),

dict(
    name="SWCHB -> the shadow (Color/B&W)",
    addr=0xF2A7, span=3,
    old="""ReadBW:
	LDA	SWCHB""",
    new="""; The '>' is load-bearing: without it AS folds a zero-page operand into the
; two-byte form, every byte after this shifts, and check_patch.py has nothing
; left to audit.
ReadBW:
	LDA	>DGSWB"""),

dict(
    name="the SWCHA read is deleted; the stall gate takes its place",
    addr=0xF2C8, span=15,
    old="""ReadJoy:
	LDA	SWCHA
	TAY
	AND	#$0F
	STA	Joy1
	TYA
	LSR	A
	LSR	A
	LSR	A
	LSR	A
	STA	Joy0""",
    new="""; THE STALL GATE, in the fifteen bytes the joystick read vacated.
;
; Dragster stores the two stick nibbles in RAM at $AD and $AE and reads them
; back from there ($F2DD, $F43B, $F479), so the shim can simply WRITE those two
; cells and the read here is not shadowed but deleted. That is one fewer shadow
; cell than Combat needed, and it leaves the gate sitting at exactly the address
; the gate wants to be: everything above this line has to run on every frame --
; VSYNC, the frame counter, the attract colours, arming the VBLANK timer -- and
; everything below it is the simulation.
;
; A stall therefore runs the frame normally and skips the logic. The picture
; does not shudder: Dragster's kernel rebuilds every TIA register it uses from
; RAM on every frame, and the game never reads a collision latch -- it never
; strobes CXCLR at all -- so a frozen frame is simply the same frame again.
ReadJoy:
	LDA	DGADV
	BNE	RestartDetect
	JMP	L_F4E2
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP"""),

dict(
    name="SWCHB -> the shadow (RESET/SELECT)",
    addr=0xF2E3, span=3,
    old="""ReadSwitches:
	LDA	SWCHB""",
    new="""ReadSwitches:
	LDA	>DGSWB"""),

dict(
    name="the restage clear's seed becomes a cell",
    addr=0xF2E9, span=5,
    old="""Restage:
	LDX	#$B9
	JMP	ClearEntry""",
    new="""; THE RESTAGE CLEAR, WHICH IS WHERE THE NETCODE WOULD HAVE DIED.
;
; Stock enters the boot path's clear loop with X preloaded, so a restage wipes
; $B9-$FF -- straight through every cell this port owns, on every RESET and
; every SELECT. The loop is now bounded at $DA (see the cold head), and the seed
; is a cell rather than a constant:
;
;   not networked   $B9, which is stock, so `make det` is honest
;   in a match      $A8, set by the boot bank at handover so BOTH consoles
;                   always use the same value
;
; Widening it to $A8 is what makes the desync repair total. The clear then
; covers RPM, lane, the input shadows, the select-repeat timer, engine volume,
; the time accumulators including the sub-hundredths at $B7/$B8 that are never
; displayed, track position, speed, gear, blown, the explosion timer, race-over
; and the message index; StageRace rewrites the countdown, the LFSR seed, the
; blanked times, the lane and gear defaults, VDELP0/1 and the ball. What is left
; uncovered is GameVar, FrameCnt and $83, and all three agree by construction.
;
; Combat's repair could not do this -- its tank X positions live in the TIA, not
; in RAM -- so it wiped the scores and called that correct rather than a wart.
; Dragster's restores every checksummed cell.
Restage:
	LDX	DGCLRX
	JMP	DGCLRE"""),

dict(
    name="INPT4,X -> the trigger shadows",
    addr=0xF3B1, span=2,
    old="""ReadTrigger:
	LDA	INPT4,X""",
    new="""; The neatest patch in the port. INPT4 is zero page $0C -- the TIA, not RAM --
; and DGTRIG is zero page in the RIOT, so this is the same opcode, the same two
; bytes and the same four cycles, indexed by the same player number.
ReadTrigger:
	LDA	DGTRIG,X"""),
]


def _strip(text):
    """The comparable form of a block: code lines only, whitespace normalised."""
    out = []
    for line in text.split("\n"):
        s = line.split(";")[0]
        if not s.strip():
            continue
        indented = s[:1].isspace()
        out.append(("\t" if indented else "") + "\t".join(s.split()))
    return out


def apply_region(entries, lo, hi):
    """Apply every patch that falls in [lo, hi) to a region's (addr, text) list.

    `entries` is a list of (address, source-line) in order. Returns a new list.
    A patch that does not fit entirely inside the region is an error: a patch
    that reached across a bank boundary would be applied to one bank and not the
    other, and the two images would differ in a way check_patch cannot describe.
    """
    out = list(entries)
    for p in PATCHES:
        if not (lo <= p["addr"] < hi):
            continue
        end = p["addr"] + p["span"]
        if end > hi:
            raise SystemExit(
                "patches: '%s' at $%04X spans $%04X, past the region end $%04X"
                % (p["name"], p["addr"], end, hi))

        idx = [i for i, (a, _t) in enumerate(out) if p["addr"] <= a < end]
        if not idx:
            raise SystemExit("patches: '%s' found no lines at $%04X"
                             % (p["name"], p["addr"]))
        # Blank and comment-only lines at the head carry the address of the next
        # byte, so a region banner sits at the same address as the first
        # instruction under it. Those belong to the banner, not to the patch.
        while idx and not _strip(out[idx[0]][1]):
            idx.pop(0)
        if not idx:
            raise SystemExit("patches: '%s' matched only comments at $%04X"
                             % (p["name"], p["addr"]))

        got = _strip("\n".join(out[i][1] for i in idx))
        want = _strip(p["old"])
        if got != want:
            raise SystemExit(
                "patches: '%s' at $%04X does not match the source.\n"
                "  expected: %r\n  found:    %r" % (p["name"], p["addr"], want, got))

        first, last = idx[0], idx[-1]
        out[first:last + 1] = [(p["addr"], line) for line in p["new"].split("\n")]
    return out


def selftest():
    """Every declared span must be covered by exactly one patch, and vice versa."""
    problems = []
    declared = {(lo, hi - lo) for lo, hi, _w in REWRITTEN}
    declared |= {(a, n) for a, n, _w in SPANS}
    have = {(p["addr"], p["span"]) for p in PATCHES}
    for d in sorted(declared - have):
        problems.append("declared $%04X+%d has no patch" % d)
    for h in sorted(have - declared):
        problems.append("patch at $%04X+%d is not declared in SPANS/REWRITTEN" % h)
    # and no two patches may overlap
    ranges = sorted((p["addr"], p["addr"] + p["span"], p["name"]) for p in PATCHES)
    for (a1, e1, n1), (a2, _e2, n2) in zip(ranges, ranges[1:]):
        if e1 > a2:
            problems.append("'%s' and '%s' overlap at $%04X" % (n1, n2, a2))
    return problems


if __name__ == "__main__":
    probs = selftest()
    for p in probs:
        print("patches: " + p)
    if probs:
        raise SystemExit(1)
    total = sum(p["span"] for p in PATCHES)
    print("patches: %d patches, %d bytes of Dragster declared changed"
          % (len(PATCHES), total))
    for p in PATCHES:
        print("  $%04X +%-3d %s" % (p["addr"], p["span"], p["name"]))
