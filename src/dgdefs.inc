; dgdefs.inc -- zero page, banks and constants for networked Dragster.
;
; EQUATES ONLY. Included BEFORE the ORG, like fujinet.inc. The code half is
; dgcore.inc and goes inside it.

; ---------------------------------------------------------------------------
; ZERO PAGE
;
; This console has 128 bytes of RAM. Scanning every addressing mode in
; $F000-$F7F9 -- and bounding each index by hand, which is the only way to do
; it -- the highest cell Dragster touches is $D9. That leaves $DA-$FF, and $83
; and $AF in the middle of the game's own map.
;
; Thirty-four cells against Combat's twenty-six. The union below is therefore a
; convenience rather than a forced move, and it is kept anyway: the session's
; cells and the lockstep rings are never live at the same time, and spending
; real bytes to prove a point nobody asked about is how a port runs out of room
; at the end.
;
; $83 and $AF are left free ON PURPOSE. Something will want them.

; ---------------- the netcode, $DA-$E8, always live ----------------
DGENT   EQU     $DA             ; entry mode, role, phase, and the flags below
DGSEQ   EQU     $DB             ; the sequence we are waiting for
DGERR   EQU     $DC             ; low nibble last transport error, high nibble
                                ;   consecutive stalled ticks -- the watchdog
                                ;   needs no cell of its own
DGTICK  EQU     $DD             ; sim tick, low 8 bits
DGNST   EQU     $DE             ; the network machine's state
DGCRCV  EQU     $DF             ; the sim checksum, SAMPLED AT A TICK BOUNDARY
                                ;   and always of the state ENTERING DGTICK.
                                ;   It cannot be sampled where it is sent: the
                                ;   transport free-runs and Dragster's logic
                                ;   runs every frame, so "the state" changes
                                ;   four times a tick and two consoles reading
                                ;   it whenever their transport got round to it
                                ;   disagree for no reason at all.
DGADV   EQU     $E0             ; nonzero: the sim advances this frame. Read by
                                ;   the stall gate at $F2C8, written by DGSHIM
                                ;   at $F285 -- earlier in the same frame.
DGTMP   EQU     $E1             ; scratch, dead between routines
DGLEAD  EQU     $E2             ; THE DISPLAY LEAD, in simulated frames: 0 when
                                ;   this console is not in a match, DGLEADV in
                                ;   one. A cell and not a constant, because a
                                ;   cartridge with no server has to be Dragster.
DGCLRX  EQU     $E3             ; the restage clear's seed: $B9 not networked,
                                ;   DGRSYX in a match. See the note below.
DGSWB   EQU     $E4             ; the synthetic SWCHB -- patches at $F2A7, $F2E3
DGTRIG  EQU     $E5             ; 2: triggers by player, DGTRIG,X -- patch at
                                ;   $F3B1. Zero page in the RIOT where INPT4 is
                                ;   zero page in the TIA, so that patch is the
                                ;   same opcode and the same four cycles.
DGW0    EQU     $E7             ; player 0's wire byte, during the shim
DGW1    EQU     $E8             ; player 1's

; ---------------- the union, $E9-$F9 ----------------
; The rings belong to a match; the transport's setup cells and the input
; scanner belong to the boot bank, which finishes before a match can start. The
; only thing that could make them overlap in time is a cold start from inside a
; match, which empties everything anyway.
;
; Game side:
DGRWAT  EQU     $E9             ; highest remote tick received
DGRING  EQU     $EA             ; 8: remote input ring, index = tick AND 7
DGLOC   EQU     $F2             ; 4: local input ring, index = tick AND 3
DGRDN   EQU     $F6             ; records left to consume; also the window
                                ;   cursor, as (DGRDN-1)*IR_LEN
                                ; $F7-$F9 spare
; Session side:
FNDEV   EQU     $E9             ; transaction setup, read by FNBEG
FNCMD   EQU     $EA
FNNPR   EQU     $EB
FNTMO   EQU     $EC             ; timeout in ~0.6s quanta
FNCNT   EQU     $ED             ; timeout quanta remaining
FNPTRL  EQU     $EE             ; reply-window cursor
FNPTRH  EQU     $EF
FNPCNT  EQU     $F0             ; bytes written into the current path payload
INCUR   EQU     $F1             ; input scan, both halves
INPREV  EQU     $F2
CSDLY   EQU     $F3             ; a frame counter for the session's wait loops.
                                ;   IN MEMORY, NOT IN A REGISTER: the text
                                ;   kernel counts scanlines in X and Y and
                                ;   clobbers both, and a caller that counted its
                                ;   own repeats in one of them ran its wait 256
                                ;   times over.
; Shared by both, because it means the same thing to both:
FNSEQ   EQU     DGSEQ

; THE REMOTE RING IS EIGHT, AND THE EIGHT IS LOAD-BEARING. Console B can only
; advance to tick T_B with A's input for T_B, which A sent at its own tick
; T_B - d. So T_B <= T_A + d, and A has sent up to T_A + d <= T_B + 2d: B can
; be holding records for T_B .. T_B + 2d, which is 2d+1 slots. At d = 2 that is
; five, and eight is the next power of two, for a free AND #7 instead of a
; modulo. A four-slot ring silently overwrites a tick that has not been used
; yet, and the symptom is the peer's car occasionally repeating a move.

; ---------------- the bound on both clears ----------------
; Dragster has TWO paths into one clear loop, and the second is the one that
; would have killed this port. $F2E9 does `LDX #$B9 / JMP ClearEntry`, entering
; the boot path's loop MID-ROUTINE with X preloaded, and the loop runs to $FF --
; so a restage wipes $B9-$FF, which is every cell above. A restage happens on
; every RESET and every SELECT.
;
; So the loop is bounded here instead, and both entries share the bound.
; Everything below $DA is the game's and is cleared exactly as stock cleared it;
; everything from $DA up is this port's and survives.
DGZPLO  EQU     $DA             ; the first cell the clears may not touch
DGSTKLO EQU     $FA             ; the stack. Deepest: DGWAIT -> DGSHIM -> DGCRC

; The seed the restage clear uses in a match, and why it is not $B9.
;
; $A8 makes the desync repair TOTAL. The clear then covers RPM, lane position,
; the input shadows, the select-repeat timer, engine volume, the time
; accumulators -- including the sub-hundredths at $B7/$B8, which are never
; displayed and would otherwise carry a difference across a repair -- track
; position, speed, gear, blown, the explosion timer, race-over and the message
; index. StageRace then rewrites the countdown, the LFSR seed, the blanked
; times, the lane and gear defaults, VDELP0/1, and re-positions the ball.
;
; What is left uncovered is GameVar ($80), FrameCnt ($81) and $83, and all three
; agree by construction: the variation moves only on SELECT presses that are
; ANDed on the wire, the sim clock counts simulated frames, and $83 is unused.
;
; Combat could not do this. Its tank X positions live in the TIA's HMP0/HMP1 and
; are applied incrementally by HMOVE, so nothing in RAM could carry them and its
; repair wiped the scores -- "correct rather than a wart". Dragster's car X is
; recomputed from TrackPos by PositionSprites on every frame of every lane, so
; it IS in RAM, and the repair restores every checksummed cell.
DGRSYX  EQU     $A8             ; the clear seed in a match
DGSTKX  EQU     $B9             ; the clear seed when not networked: stock

; ---------------------------------------------------------------------------
; THE TICK
;
; K = 4 video frames a tick, 15 ticks a second. Four and not the three the
; latency probe would allow, because a power of two makes the ring index a free
; AND. The probe measured a full WRITE/STATUS/READ cycle at three frames, so the
; transport keeps up with a four-frame tick with a frame to spare.
;
; The phase is two bits of DGENT and NOT a count in a cell the game can reach.
; Dragster clears $B9-$FF on every restage and $00-$D9 on every new game, and a
; sim clock the game resets on a frame of its own choosing re-phases the tick
; underneath the transport.
DGK     EQU     4               ; frames per tick
DGKM    EQU     DGK-1           ; ...as a mask, which is why it is a power of two

; d, the input delay, in ticks. Hardcoded rather than taken from START's delay
; byte: it sizes the local ring at assembly time, and a console that honoured a
; delay its ring could not hold would overwrite a tick it had not used yet.
; The server is asked for this value and START is checked against it.
DGD     EQU     2               ; 2 ticks = 8 frames = ~133 ms, symmetric
DGLM    EQU     3               ; local ring mask; the ring is 4, and 4 > d

; THE DISPLAY LEAD -- the one thing in this port that Combat has no analogue for.
;
; Dragster is a drag race and its entire identity is an elapsed time to two
; decimal places. Delay-based lockstep applies a press d ticks after it is made,
; so a player who launches perfectly has the simulation see it eight frames
; late, and every time in the game inflates by about thirteen hundredths.
;
; So the TREE is drawn from Countdown - DGLEAD rather than Countdown. The player
; reacts to a green that is eight simulated frames early, the press is captured
; on the next boundary and applied d ticks later, and it lands at sim-green. The
; simulation is untouched; only the picture and the beep move.
;
; EIGHT IS THE MINIMUM LATENCY, NOT THE MEAN, and that is the right choice: a
; press made on a boundary frame lands 8 frames later, one made 1-3 frames into
; a tick is sampled at the next boundary and lands 9-11 later. A lead of 8 makes
; a perfect launch achievable and never lets a player beat the tree. A lead of
; 10 would let them.
DGLEADV EQU     DGK*DGD         ; 8 simulated frames

; DGENT is SEVERAL INDEPENDENT BITS, and keeping them independent matters.
;
;   bit 0  WARM. Set once the game bank's cold path has run. The game bank is
;          entered at $1000 by the trampoline at the end of every frame, so its
;          first act is to ask whether this is a frame boundary or a cold start.
;   bit 1  NETWORKED. Set by the boot bank when a match has started.
;
; They were one value in the sibling port -- 0 cold, 1 local, 2 playing -- and
; the boot bank handing over with 2 meant the game bank read "not cold" and
; jumped straight into the frame loop, so the game's own initialisation never
; ran and both consoles came up identically wrong. Identically, which is why the
; transport looked perfect.
DGE_WARM EQU    $01
DGE_NET EQU     $02
DGE_ROLE EQU    $04             ; set = guest, and it drives the BOTTOM lane
DGE_RAN EQU     $08             ; set = the last boundary ran its tick, so the
                                ;   next one must advance DGTICK before it
                                ;   samples anything
DGE_LEFT EQU    $10             ; the peer left: the boot bank says so in words
DGE_RSY EQU     $20             ; a checksum mismatch was seen: press RESET
DGE_PH  EQU     $C0             ; 2 bits: which frame of the tick this is

; ---------------------------------------------------------------------------
; THE WIRE
;
; One byte carries a player's whole console, which is what lets the ring be a
; ring. The senses are the hardware's, straight through, so the mixer is masks
; and shifts and never an inversion -- which matters more than it sounds,
; because an inversion applied on one console and not the other is a desync that
; only shows when somebody presses something.
IW_TRIG EQU     $80             ; 1 = released      (INPT4's sense)
IW_DIFF EQU     $40             ; 1 = A / Pro       (SWCHB's sense)
IW_SEL  EQU     $20             ; 1 = not pressed
IW_RST  EQU     $10             ; 1 = not pressed
IW_STICK EQU    $0F             ; 1 = not pushed    (SWCHA's sense)

; IW_DIFF IS INERT ON THIS CONSOLE and is carried anyway. Dragster never reads
; SWCHB bits 6 or 7 -- there is no difficulty setting in the game at all. The
; bit stays in the byte, and stays SET, so that IW_IDLE is $FF and the idle
; pattern is the same one every other client in the family uses. Repurposing it
; would save nothing and would cost the next port the bit it wanted.
IW_IDLE EQU     IW_TRIG|IW_DIFF|IW_SEL|IW_RST|IW_STICK

; Both rings are SEEDED with IW_IDLE rather than with zero, and the difference
; is not cosmetic: zero reads as EVERY switch pressed and the stick shoved in
; all four directions, because the wire keeps the hardware's active-low sense.
;
; The seeding is what makes the first d ticks honest. A record is stamped
; DGTICK+d, so the first one anybody sends is for tick d and the slots for ticks
; 0..d-1 are never sent by anyone. Both consoles filling them with the same
; constant is the only way the two agree about a tick neither has heard anything
; about; filling them with a LOCAL capture would be asymmetric.

; A record is six bytes of payload, eight on the wire with len and type.
IR_TICK EQU     0               ; the tick the window ENDS at
IR_IN   EQU     1               ; 3 bytes: that tick and the two before it
IR_CRC  EQU     4               ; the boundary-sampled checksum
IR_CHK  EQU     5               ; the XOR check byte
IR_LEN  EQU     8               ; ON THE WIRE, and a power of two on purpose
IR_MASK EQU     $F8
IR_SEED EQU     $A5             ; the check byte's salt

DGWIN   EQU     3               ; ticks of input in every record, newest first.
                                ; THE TRANSPORT IS NOT LOCKED TO THE TICK: a
                                ; WRITE/STATUS/READ cycle that runs long means a
                                ; tick's record is never sent at all, and the
                                ; peer's watermark tracks only the newest tick
                                ; received, so the hole leaves the PREVIOUS
                                ; LAP's byte in that ring slot and the gate uses
                                ; it. Three covers any gap the local ring can
                                ; still supply, which is one less than its four.

; ---------------------------------------------------------------------------
; THE NETWORK MICRO-STEP MACHINE
;
; Stepped from inside the wait for the OVERSCAN timer to run out. Dragster has
; two timed waits and they are not comparable:
;
;   $F285  overscan  TIM64T=$21 = 2112 cycles, and the audio engine in front of
;                    it spends about a hundred. ~2000 cycles of slack.
;   $F046  VBLANK    TIM64T=$19 = 1600 cycles, and the worst path in front of it
;                    -- the tach-bar loop at $F4D1 is 19 iterations of 31 cycles
;                    on its own -- spends about 1293. ~307 cycles, which is
;                    TIGHTER THAN COMBAT'S ONLY WINDOW, and it has to absorb a
;                    bank switch as well.
;
; So the hook is the overscan, and the VBLANK is the reserve. emu/slack.lua
; reports both and `make slack` asserts a floor on each, because the second
; number is the early warning for anything a later change puts in the logic.
;
; The loop re-reads INTIM before every step and stops when the slack is gone, so
; THE HOOK CANNOT OVERRUN THE KERNEL BY CONSTRUCTION -- there is no budget to
; get wrong. TIM64T decrements every 64 cycles, so a gate of 8 guarantees at
; least 7 x 64 = 448 cycles remain, against a worst step of about 310.
DGGATE  EQU     8

NS_IDLE EQU     0               ; no socket, or no match: do nothing
NS_WISS EQU     2               ; issue the WRITE and launch it
NS_WACK EQU     4               ; wait for the cartridge to acknowledge
NS_SISS EQU     6               ; issue the STATUS
NS_SACK EQU     8               ; ...and read how many bytes are waiting
NS_RISS EQU     10              ; issue the READ
NS_RACK EQU     12              ; ...and turn its length into a record count
NS_CONS EQU     14              ; consume one record from the reply window
NS_FAIL EQU     16              ; count it and start the cycle again
NS_LAST EQU     NS_FAIL         ; the dispatch table's last entry

; ---------------------------------------------------------------------------
; BANKS
;
; An image is (N+1) x 2048 -- N banks then the fixed half -- and MAME's cart
; slot accepts only N in {1,3,7,15}. Three banks, and the fourth slot is the
; fixed half.
BANKBOOT EQU    0               ; cold start, the session, the WAITING screen
BANKGAME EQU    1               ; the frame logic, the audio, and the transport
BANKKERN EQU    2               ; the lane kernel and all the sprite data
NBANKS   EQU    3

; The trampoline, at a fixed address in the fixed tail because the banks are
; assembled separately. A bank switch is a JUMP, never a call: the store that
; switches is the last instruction fetched from the old bank, so there is no
; return address to come back to. "Where to carry on" is DATA, in DGENT.
DGGOTO  EQU     FNTAIL

; THE TWO SEAMS, AND WHY THEY COST NO PATCHED BYTES.
;
; Every byte keeps its cartridge address, so the bank that does NOT own a seam
; address has a hole there, and the trampoline goes in the hole:
;
;   A: logic -> display.  $F4E2 JMP FrameTop, unpatched. In the game bank
;      $1016 is a hole, and FrameTop is defined there as the trampoline.
;   B: display -> logic.  $F225 falls through into $F226, unpatched. In the
;      kernel bank $1226 is a hole, and the trampoline sits in it.
;
; Seam B lands immediately after $F221 has armed the overscan timer, so the
; switch is paid for out of a budget that is already running.
;
; It is worth recording that ONE cross-bank reference exists in the whole of
; Dragster, and it is seam A. tools/dgmap.py's shared regions are what make that
; true; without them there would be four more.
DGSEAMA EQU     $1016           ; the game bank's trampoline to the kernel
DGSEAMB EQU     $1226           ; the kernel bank's trampoline to the game

; ---------------------------------------------------------------------------
; THE WIRE PROTOCOL
;
; frame := len(1) type(1) payload(len-1). `len` counts type and payload, so a
; frame is never zero-length and the reader can reject a bad one on sight.
WT_HELO EQU     $01
WT_LOBBY EQU    $03
WT_JOIN EQU     $04
WT_START EQU    $05
WT_INPUT EQU    $06
WT_CRC  EQU     $07
WT_STATE EQU    $08
WT_RESYN EQU    $09
WT_BYE  EQU     $0A
WT_LEFT EQU     $0B
WT_PING EQU     $0C
WT_PONG EQU     $0D

WPROTO  EQU     2               ; HELLO's version byte, carrying the television
                                ; standard between the version and the name.

TVNTSC  EQU     0
TVPAL   EQU     1

; ---------------------------------------------------------------------------
; APPKEYS
;
; Two of them, both under the family's shared creator and app:
;
;   key 0            the FujiNet USERNAME, which every game in the family reads
;   key DGAPPKEY     the room's own URL, which the Lobby writes there on the way
;                    out and the booted game reads on the way in. There is no
;                    HTTP "join a room" call anywhere in this family; joining is
;                    a local write and a reboot.
;
; Both are read into a CARTRIDGE PATH BUFFER and never into console RAM. That is
; not thrift, it is necessity: a name is eight bytes and a URL is sixty-four.
DGAPPKEY EQU    25              ; Dragster's room; Combat's is 24
AKNAMEK EQU     0
PB_NAME EQU     FP_SEL0         ; path buffer 0: the username
PB_URL  EQU     FP_SEL1         ; path buffer 1: the server URL
NAMEMIN EQU     2
NAMEMAX EQU     8
