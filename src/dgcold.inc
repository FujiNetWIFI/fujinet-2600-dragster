; dgcold.inc -- the game bank's cold path and the bounded clear.
;
; In the SECOND hole, not the first: the first is 528 bytes and the transport
; wants 510 of them. The dispatcher at $1000 reaches this with a JMP rather than
; a branch for exactly that reason.

; ---------------------------------------------------------------------------
; The cold path. Reached from $1000 when DGE_WARM is clear: either the boot
; bank has just handed over, or the cartridge came up cold.
DGBOOT: sei
        cld
        ldx     #$00

; ---------------------------------------------------------------------------
; THE CLEAR, BOUNDED.
;
; Two paths enter this loop and the second is the one that would have killed the
; port. $F2E9 restages a race with `LDX <seed> / JMP DGCLRE`, entering here with
; X preloaded -- and stock ran to $FF, so a restage wiped $B9-$FF, straight
; through every cell the netcode owns, on every RESET and every SELECT.
;
; The bound costs nothing per iteration. Stock was `STA VSYNC,X / TXS / INX /
; BNE`; this is `STA VSYNC,X / INX / CPX / BNE`, and CPX immediate is the two
; cycles TXS was -- eleven either way. What it does change is where TXS happens:
; stock relied on the last iteration leaving X = $FF, and this loop never
; reaches $FF, so the stack pointer is set explicitly below.
;
; The TIA sweep is untouched. X still counts from $00 through $7F on a cold
; start, so every write register is strobed exactly as stock strobed it; the
; bound only removes iterations $DA-$FF, which are RAM the game never reads.
DGCLRE: lda     #$00
DGCLR:  sta     VSYNC,x
        inx
        cpx     #DGZPLO
        bne     DGCLR
        ldx     #$FF
        txs

; AND THE SHADOWS BACK TO IDLE, WHICH IS NOT OPTIONAL.
;
; The restage clear reaches $A8 in a match, and $AD/$AE are the joystick
; shadows. Zero in a joystick nibble is not "nothing pressed" -- the wire and
; the port are both active low, so zero is ALL FOUR DIRECTIONS pressed at once,
; including bit 2, which is Dragster's gear lever.
;
; Stock never sees this: its clear starts at $B9 and stops short of the
; shadows, and in any case $F2C8 re-read the port before anything looked at it.
; This port deleted that read -- DGMIX writes the cells directly -- and DGMIX
; runs only on a TICK boundary, so in a match the fabricated press stands for up
; to three frames. Long enough for $F43B to see the lever go down and come back
; up, which arms a shift and then releases it, and a release while the tree is
; counting is a jump start: every single race began with EARLY on the screen.
;
; Nothing desynchronised, because both consoles fabricated the same press at the
; same tick. `rig`, `rig-play` and `tree` all passed while the game was
; unplayable, which is the whole argument for having a gate that measures the
; RACE and not just the agreement.
;
; Harmless on the local path, and provably: DGLOC0 rewrites both cells from the
; hardware on every frame, before anything reads them.
; ONLY IN A MATCH. Not networked, DGCLRX is $B9 and the clear never reaches the
; shadows at all, so stock's behaviour is stock's behaviour -- and `make det`
; compares this path byte for byte against the 1980 ROM, which leaves $AD/$AE
; at zero on a cold start and re-reads the port before anything looks at them.
; Writing $0F here unconditionally is a two-cell difference on frame three, and
; the gate found it.
        lda     DGENT
        and     #DGE_NET
        beq     DGCLR9
        lda     #IW_STICK       ; $0F -- nothing pushed
        sta     Joy0
        sta     Joy1
DGCLR9:

; ORA, NEVER LDA. The boot bank has already set DGE_NET and the role in here,
; and a match that lost its role on the first frame would have both consoles
; driving the top lane.
        lda     DGENT
        ora     #DGE_WARM
        sta     DGENT

; Stock's own cold test, unchanged: a zero LFSR means the RAM really was just
; cleared, so go and pick a game variation; anything else is a restage.
        lda     Lfsr
        bne     DGST1
        jmp     NewGame
DGST1:  jsr     StageRace
        jmp     FrameTop
