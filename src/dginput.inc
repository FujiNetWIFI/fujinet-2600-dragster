; dginput.inc -- the console capture, the lockstep gate, and the shadows.
;
; Dragster's whole input surface is four reads and emu/inputs.lua proves it
; rather than assuming it: after the patch, every read of a console port in a
; whole run comes from in here.
;
; It runs from DGWAIT, at $F285, inside the overscan timer -- which is where
; this port's slack is. Its other job is to decide whether the sim advances at
; all this frame, which is the lockstep gate.

; ---------------------------------------------------------------------------
; DGWAIT -- the hook, called from $F285 in place of the stock overscan spin.
;
; IT MUST RETURN WITH A = 0. $F298 clears VSYNC with `STA VSYNC` and the
; accumulator the stock spin left at zero when INTIM ran out. Every path out of
; here ends in DGWSPIN, which exits on `BNE` failing -- A = 0. That is the sort
; of thing which works for a thousand frames and then does not.
DGWAIT:
        jsr     DGSHIM

        lda     DGENT
        and     #DGE_NET
        beq     DGWSPIN         ; no match: the stock spin, unchanged

; The step loop. INTIM is re-read before every step and the loop stops when the
; slack is gone, so THE HOOK CANNOT OVERRUN THE KERNEL BY CONSTRUCTION -- there
; is no budget to get wrong. TIM64T decrements every 64 cycles, so DGGATE = 8
; guarantees 7 x 64 = 448 cycles remain against a worst step of about 310.
DGWLOOP:
        lda     INTIM
        cmp     #DGGATE
        bcc     DGWSPIN         ; THROUGH THE CARRY: INTIM is unsigned, and a
                                ;   sign test on an unsigned quantity is how the
                                ;   Channel F port lost a day
        jsr     DGNSTEP
        jmp     DGWLOOP

DGWSPIN:
        lda     INTIM
        bne     DGWSPIN
        rts

; ---------------------------------------------------------------------------
; DGSHIM -- once a frame, from DGWAIT.
;
; Returns with DGADV nonzero if the game logic should run this frame. The gate
; itself is the patch at $F2C8, which reads DGADV and jumps past the logic.
DGSHIM:
        lda     #$FF
        sta     DGADV           ; assume the sim advances

        IF      DGLAG
; The interception proof (`make lag`): refresh the shadows once every DGLAGM+1
; frames. Dragster then answers the stick in visible steps about a second apart
; -- and if it does not, something is still reading a live port.
        lda     FrameCnt
        and     #DGLAGM
        beq     DGSHIM1
        rts
DGSHIM1:
        ENDIF

        lda     DGENT
        and     #DGE_NET
        bne     DGNET

; Not in a match: the console drives both cars, exactly as it always did.
        jsr     DGLOC0
        jmp     DGCLK           ; the sim clock, which always ticks here

; ---------------------------------------------------------------------------
; In a match.
DGNET:
; Only a tick boundary has anything to decide; the other three frames of a tick
; re-use the shadows that are already there.
        lda     DGENT
        and     #DGE_PH
        beq     DGNT1
        jsr     DGPHI           ; mid-tick: bump the phase
        jmp     DGCLK           ; ...and the sim runs, so the clock ticks

DGNT1:
; A RECORD, ONCE SENT, IS IMMUTABLE. Everything below happens ONLY on a boundary
; that actually advanced the tick.
;
; The transport free-runs: it sends the record for DGTICK+d whenever it reaches
; its WRITE step, several times per tick, and a duplicate is harmless only
; because it is IDENTICAL. Re-capturing on a stalled boundary makes it not
; identical -- the peer has already stored and SIMULATED the first version of
; tick X while this console goes on to use the second.
;
; It is invisible while nobody touches anything, because every capture returns
; the same idle byte. The moment somebody presses SELECT during a stall, one
; console counts the press and the other does not.
        lda     DGENT
        and     #DGE_RAN
        beq     DGNT1B          ; the tick has not moved: nothing to re-commit

        inc     DGTICK
        lda     DGENT
        and     #$FF-DGE_RAN
        sta     DGENT

; The checksum, of the state ENTERING the tick just advanced to. The boundary is
; the one instant two consoles can agree on.
        jsr     DGCRC
        sta     DGCRCV

; And this console's own stick, for the tick d ahead. Captured once, here, and
; never revised.
        jsr     DGCAP
        pha
        lda     DGTICK
        clc
        adc     #DGD
        and     #DGLM
        tay
        pla
        sta     DGLOC,y
DGNT1B:

; Has the peer's input for this tick arrived? DGRWAT is the highest remote tick
; received.
;
; THIS IS THE ONE SIGNED COMPARE IN THE NETCODE, and it is signed on purpose:
; the tick is eight bits and wraps, and a window of +-127 either side is what
; makes the wrap invisible.
        lda     DGRWAT
        sec
        sbc     DGTICK
        bpl     DGNT2
        jmp     DGSTALL

DGNT2:
; ---- the tick runs ----
        lda     DGERR           ; a tick that ran clears the stall counter
        and     #$0F
        sta     DGERR

; Our own byte for this tick was captured d ticks ago and has been sitting in
; the local ring ever since. That is the whole of delay-based lockstep: our
; input is delayed exactly as far as the peer's, so both players feel the same
; lag and neither is ahead of the other.
        lda     DGTICK
        and     #DGLM
        tay
        lda     DGLOC,y
        sta     DGW0

; The peer's byte for the same tick, out of the remote ring.
        lda     DGTICK
        and     #7
        tay
        lda     DGRING,y
        sta     DGW1

; The host drives the TOP lane, which is Dragster's player 0. A guest's own byte
; is therefore player 1's and the two have to change places.
        lda     DGENT
        and     #DGE_ROLE
        beq     DGMIX
        lda     DGW0
        ldy     DGW1
        sty     DGW0
        sta     DGW1

; ---------------------------------------------------------------------------
; DGMIX -- two wire bytes into the three cells Dragster reads.
;
; Every bit keeps the hardware's sense on the wire, so this is masks and shifts
; and never an inversion.
DGMIX:
; The sticks. Dragster keeps them as two nibbles in RAM, ALREADY SPLIT -- $AD is
; the top lane's and $AE the bottom's, both in bits 3-0, both active low. The
; patch at $F2C8 deleted the split, so these are written directly and there is
; no synthetic SWCHA anywhere in this port.
        lda     DGW0
        and     #IW_STICK
        sta     Joy0
        lda     DGW1
        and     #IW_STICK
        sta     Joy1

; The triggers: bit 7 of each byte, straight through, in the pair Dragster
; indexes with the player number at $F3B1.
        lda     DGW0
        and     #IW_TRIG
        sta     DGTRIG
        lda     DGW1
        and     #IW_TRIG
        sta     DGTRIG+1

; SWCHB. RESET and SELECT are ANDed: both bits are active low, so the AND means
; EITHER PLAYER MAY PRESS THEM -- which is the couch semantics, preserved. There
; is no host authority here and none is needed: every bit is a pure function of
; the two wire bytes, so both consoles compute the same byte without a protocol
; for it.
        lda     DGW0
        and     DGW1
        lsr     a               ; IW_RST is bit 4 and SWCHB's reset is bit 0,
        lsr     a               ;   IW_SEL is bit 5 and select is bit 1
        lsr     a
        lsr     a
        and     #$03
        sta     DGTMP
; B&W STAYS LOCAL, and it is provably safe: Dragster reads SWCHB bit 3 at $F2A7
; for one purpose, to force AttrAnd to $0F so the attract-mode colour mask keeps
; luminance only. No colour cell reaches physics, and none is checksummed.
        lda     SWCHB
        and     #$08
        ora     DGTMP
        ora     #$F4            ; bits 2, 4, 5 read high on a real console, and
                                ;   6 and 7 are the difficulty switches, which
                                ;   Dragster never reads at all
        sta     DGSWB

; Mark the tick as run -- the next boundary does the increment, immediately
; before it samples -- and bump the phase, because this frame's logic will run.
        lda     DGENT
        ora     #DGE_RAN
        sta     DGENT
        jsr     DGPHI
        jmp     DGCLK
