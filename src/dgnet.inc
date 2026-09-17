; dgnet.inc -- the non-blocking network machine, in the game bank.
;
; Battleship's NPGO blocks a whole transaction and spends each wait redrawing a
; frame. That is right for a turn-based game polling every ninety frames and
; fatal here: the sim has to keep running while the transport works.
;
; So the transport is a state machine of bounded micro-steps, run from a loop
; inside the wait for Dragster's OVERSCAN timer to expire, which re-reads INTIM
; before every step. The machine free-runs: every cycle it sends this console's
; record for tick+d and consumes whatever has arrived. It is never TOLD that a
; tick has passed and never has to be -- a duplicate record is idempotent,
; because the ring is indexed by tick, and a machine running slower than the
; tick rate simply causes a stall, which is exactly the right behaviour.
;
; It lives in the GAME bank, which is where both the room and the hook are.
; Dragster's split leaves the game bank 1204 free bytes against the kernel
; bank's 766, and the hook at $F285 is in the game bank too -- so unlike
; Combat, where the machine and the loop that steps it lived in the kernel bank
; and the shim lived in the other, everything here is one bank and DGWAIT can
; simply JSR the shim.
;
; The mailbox at $1D00-$1FFF is fixed and visible from every bank, so the
; netcode would work from either; it should run where the room is.

; ---------------------------------------------------------------------------
; DGNSTEP -- one bounded step.
;
; Dispatched through the RTS trick, which is 26 cycles flat. A chain of CMP/BEQ
; would be sixty at worst and, worse, VARIABLE -- and the gate's arithmetic
; above is stated in terms of a worst case, so a constant one is worth having.
DGNSTEP:
        ldx     DGNST
        lda     DGJT+1,x
        pha
        lda     DGJT,x
        pha
        rts

; The table holds addr-1, because RTS increments what it pulls.
DGJT:
        DW      DGSIDLE-1
        DW      DGSWISS-1
        DW      DGSWACK-1
        DW      DGSSISS-1
        DW      DGSSACK-1
        DW      DGSRISS-1
        DW      DGSRACK-1
        DW      DGSCONS-1
        DW      DGSFAIL-1

DGSIDLE:
        rts

; ---------------------------------------------------------------------------
; DGLNCH -- commit a transaction and go to state A.
;
; THE NEXT SEQUENCE NUMBER COMES FROM THE CARTRIDGE'S OWN PERSISTED ACKSEQ + 1,
; never a counter in RAM. This connector has no reset line: the RESET switch
; restarts the 6507 and leaves the cartridge running, so a program-local counter
; would restart at 1, collide with a sequence already answered, and the
; transaction would be dropped in silence.
DGLNCH:
        sta     DGNST
        lda     FNACKS
        clc
        adc     #1
        bne     DGLN1
        lda     #1              ; 0 is reserved as "never used"
DGLN1:  sta     DGSEQ
        ldx     #FR_SEQ
        jmp     FNRW            ; the single commit that launches it

; DGACK -- has the cartridge answered? Returns with Z set if it has.
;
; ACKSEQ is published LAST, after the reply, its length and the error code are
; all in place, so a match means everything behind it is already readable.
DGACK:
        lda     FNACKS
        cmp     DGSEQ
        rts

; ---------------------------------------------------------------------------
; WRITE -- our record for tick + d.
DGSWISS:
        lda     #NETDEV
        ldx     #FR_DEV
        jsr     FNRW
        lda     #NCWRITE
        ldx     #FR_CMD
        jsr     FNRW
        lda     #1
        ldx     #FR_NPAR
        jsr     FNRW
        lda     #0
        ldx     #FR_DRST
        jsr     FNRW
; ONE parameter of TWO bytes -- the length -- and not two of one. The stream is
; NPARAM x { size byte, then that many little-endian value bytes }, so a length
; sent as two one-byte parameters is a different request entirely.
        lda     #2
        sta     FNTX
        lda     #IR_LEN
        sta     FNTX
        lda     #0
        sta     FNTX
; The frame: len, type, then six bytes of payload. Eight on the wire, and eight
; is a power of two on purpose -- see the note on DGSSACK.
        lda     #IR_LEN-1
        sta     FNTX
        lda     #WT_INPUT
        sta     FNTX
; b0, the tick the window ENDS at: d ticks ahead of the one being simulated.
        lda     DGTICK
        clc
        adc     #DGD
        sta     FNTX
        sta     DGW0            ; TEMP1, borrowed within this step only
        eor     #IR_SEED
        sta     DGW1            ; the check byte, accumulated as the frame goes
;
; b1, b2, b3 -- A WINDOW OF THREE TICKS, NEWEST FIRST, NOT ONE BYTE.
;
; THE TRANSPORT IS NOT LOCKED TO THE TICK AND CANNOT BE. It free-runs a
; WRITE/STATUS/READ cycle and sends whatever tick the sim is on when the WRITE
; comes round; a cycle that happens to take longer than one tick -- a burst of
; records to consume is enough, at one record a step -- means the sim advances
; twice between two WRITEs and A TICK'S RECORD IS NEVER SENT AT ALL. You cannot
; send N ticks in fewer than N writes, so the answer is not to try: batch.
;
; The hole this left was invisible for as long as nobody touched anything. The
; peer's ring is indexed by tick and its watermark tracks only the NEWEST tick
; received, so a missing tick in the middle left the previous lap's byte in that
; slot and the gate happily used it. In attract mode every byte on the wire is
; IDLE, so a stale IDLE and a fresh one are the same byte -- sixty thousand
; checksums agreed. The instant somebody pressed RESET the two consoles ran
; different code on the same frame: one restarted the game and the other did
; not, and they were a frame of simulation apart for ever after.
;
; Three is enough and is not arbitrary. The local ring is four slots, so ticks
; t, t-1 and t-2 are all still live. A gap wider than that would need the peer
; to be more than three ticks ahead of our transport, and lockstep prevents it:
; if our records stop, the peer stalls, which stops the peer's records, which
; stalls US -- and a stalled sim does not advance DGTICK while the transport
; keeps running, so the transport catches up. It is self-correcting in exactly
; the direction that matters.
        ldx     #DGWIN
DGWW:   lda     DGW0
        and     #DGLM
        tay
        lda     DGLOC,y
        sta     FNTX
        eor     DGW1
        sta     DGW1
        dec     DGW0            ; RMW on zero-page RAM, which is allowed; the
        dex                     ;   ban is on the cartridge's write-only pages
        bne     DGWW
; b4, the checksum SAMPLED AT THE LAST TICK BOUNDARY -- not computed here.
; See the note on DGCRCV: the transport free-runs and the sim moves every
; frame, so a checksum taken at this instant is a different quantity on the two
; consoles and disagrees for no reason.
        lda     DGCRCV
        sta     FNTX
        eor     DGW1
        sta     FNTX            ; b5, the check byte, over the whole frame
        lda     #NS_WACK
        jmp     DGLNCH

DGSWACK:
        jsr     DGACK
        beq     DGWA1
        rts
DGWA1:  lda     FNERR
        bne     DGFJ1
        lda     #NS_SISS
        sta     DGNST
        rts

; A trampoline per state, because DGSFAIL is further than a branch reaches from
; most of them. Each one sits immediately after an rts, so the straight line
; through the state above cannot run into it -- which is the mistake that made
; the latency probe report a failure carrying the step id of the step that had
; just succeeded.
DGFJ1:  jmp     DGSFAIL

; ---------------------------------------------------------------------------
; STATUS -- how many bytes are waiting.
;
; STATUS BEFORE READ IS NOT OPTIONAL, and the reason is worse than the family
; states it: NParser::read resizes its buffer to the length asked for and then
; copies that many bytes out of a receive buffer that may be shorter. That is
; not an error path, it is undefined behaviour returning plausible garbage.
; Never ask for more than the last STATUS reported.
DGSSISS:
        lda     #NETDEV
        ldx     #FR_DEV
        jsr     FNRW
        lda     #NCSTAT
        ldx     #FR_CMD
        jsr     FNRW
        lda     #2
        ldx     #FR_NPAR
        jsr     FNRW
        lda     #0
        ldx     #FR_DRST
        jsr     FNRW
        lda     #1
        sta     FNTX
        lda     #0
        sta     FNTX
        lda     #1
        sta     FNTX
        lda     #0
        sta     FNTX
        lda     #NS_SACK
        jmp     DGLNCH

DGSSACK:
        jsr     DGACK
        beq     DGSA1
        rts
DGSA1:  lda     FNERR
        bne     DGFJ2
; The fourth status byte is nDevStatus_t and SUCCESS is 1, not 0. It is the
; only place a transport error is visible: a dead socket reports a perfectly
; plausible zero bytes waiting.
        lda     FNRPLY+NSDEVST
        cmp     #1
        bne     DGFJ2
; THE SETTLE RULE, AND WHY IT IS NOT THE FAMILY'S. Battleship polls until two
; consecutive readings agree, because an HTTP body arrives in pieces and its
; length is not known in advance. Here every frame is exactly eight bytes, so
; reading `avail AND $F8` reads only WHOLE frames and a partial one is simply
; left for next time. The misframing the two-readings rule guards against is
; structurally unreachable, and the second STATUS round trip it would cost is a
; third of a tick. This is a deliberate departure and not an oversight.
        lda     FNRPLY+NSAVHI
        bne     DGSA2           ; 256 or more waiting: take a capped bite
        lda     FNRPLY+NSAVLO
        and     #IR_MASK
        beq     DGSA3           ; nothing whole yet
        sta     DGRDN
        lda     #NS_RISS
        sta     DGNST
        rts
DGSA2:  lda     #$F8            ; 248 bytes, 31 records, well inside the window
        sta     DGRDN
        lda     #NS_RISS
        sta     DGNST
        rts
DGSA3:  lda     #NS_WISS        ; nothing to read: send the next record
        sta     DGNST
        rts

DGFJ2:  jmp     DGSFAIL

; ---------------------------------------------------------------------------
; READ -- exactly the whole frames STATUS reported.
DGSRISS:
        lda     #NETDEV
        ldx     #FR_DEV
        jsr     FNRW
        lda     #NCREAD
        ldx     #FR_CMD
        jsr     FNRW
        lda     #1
        ldx     #FR_NPAR
        jsr     FNRW
        lda     #0
        ldx     #FR_DRST
        jsr     FNRW
        lda     #2
        sta     FNTX
        lda     DGRDN
        sta     FNTX
        lda     #0
        sta     FNTX
        lda     #NS_RACK
        jmp     DGLNCH

DGSRACK:
        jsr     DGACK
        beq     DGRA1
        rts
DGRA1:  lda     FNERR
        bne     DGFJ3
; CAPTURE THE LENGTH NOW. FNRXLO belongs to the most recent transaction and the
; next one replaces it -- and the next one is always zero, because a WRITE
; returns nothing.
        lda     FNRXLO
        lsr     a
        lsr     a
        lsr     a               ; bytes to records; the frame size is 8
        sta     DGRDN
        lda     #NS_CONS
        sta     DGNST
        rts

DGFJ3:  jmp     DGSFAIL

; ---------------------------------------------------------------------------
; CONSUME -- one record a step, backwards.
;
; Backwards so that DGRDN is both the counter and the cursor: the record at
; index n starts at n*8. Order does not matter, because every record carries its
; own tick and writes its own ring slot.
;
; The records are read IN PLACE out of the cartridge's reply window. Nothing is
; copied to console RAM but the one byte that goes in the ring, because there is
; no RAM to copy into: the 128 bytes are Dragster's.
DGSCONS:
        lda     DGRDN
        bne     DGCO1
        lda     #NS_WISS
        sta     DGNST
        rts
DGCO1:  dec     DGRDN
        lda     DGRDN
        asl     a
        asl     a
        asl     a
        tay
        lda     FNRPLY+1,y      ; the type
        cmp     #WT_INPUT
        beq     DGCO2
        cmp     #WT_LEFT
        bne     DGCO9
; The peer left. Saturate the stall watchdog as well as recording the reason:
; the gate switches to the peer-left screen when that counter tops out, and
; setting it here is what makes a CLEAN leave instant instead of making the
; player wait out the same second an unplugged console would cost.
        lda     #$F0|FNEPEER
        sta     DGERR
        rts
DGCO2:
; The check byte, over every byte of the frame that carries anything. With
; whole-frame reads a misframe cannot happen, so this can only ever catch a
; genuinely corrupt record -- which is the point: it is the difference between
; "the peer's tank moved oddly" and a counter that says so.
        lda     FNRPLY+2,y
        eor     FNRPLY+3,y
        eor     FNRPLY+4,y
        eor     FNRPLY+5,y
        eor     FNRPLY+6,y
        eor     #IR_SEED
        cmp     FNRPLY+7,y
        bne     DGCO9           ; a bad record is dropped, never acted on
;
; THE WHOLE WINDOW GOES IN, not just its newest byte -- that is the entire point
; of sending one. Each of the three bytes is written to the slot for ITS OWN
; tick, so a record that never arrived is filled in by the next one or the one
; after that, and the hole never reaches the gate.
;
; Re-writing a slot is safe and is not a violation of "a record, once sent, is
; immutable": the value being written is the peer's capture for that tick, which
; is fixed the moment it is captured, so a second write puts the same byte back.
        lda     FNRPLY+2,y      ; the tick this window ends at
        and     #7
        tax
        lda     FNRPLY+3,y
        sta     DGRING,x
        lda     FNRPLY+2,y
        sec
        sbc     #1
        and     #7
        tax
        lda     FNRPLY+4,y
        sta     DGRING,x
        lda     FNRPLY+2,y
        sec
        sbc     #2
        and     #7
        tax
        lda     FNRPLY+5,y
        sta     DGRING,x
; ---------------------------------------------------------------------------
; DESYNC DETECTION, ON THE CONSOLE ITSELF.
;
; The relay has always reported mismatches, but a log on another machine cannot
; repair anything. The record carries the sender's checksum, sampled at ITS last
; tick boundary -- which is the boundary of tick (b2 - d), because the record is
; stamped d ticks ahead. So when that tick is the one WE are on, the peer's
; checksum and our DGCRCV are samples of the same instant and must be equal.
;
; Only then. DGCRCV is a single cell holding the current tick's sample and there
; is no room for a history of them, so a record whose tick does not line up is
; simply not compared. That costs nothing: a desync is persistent, and the ticks
; line up within a few of them.
;
; A false positive is impossible -- a difference here IS a difference in the
; simulation -- and a corrupt record was already dropped by the check byte.
        lda     FNRPLY+2,y
        sec
        sbc     #DGD
        cmp     DGTICK
        bne     DGCO8           ; not comparable this time; there will be more
        lda     DGENT
        and     #DGE_RSY
        bne     DGCO8           ; already armed. Records from before the repair
                                ;   are still in flight and must not arm it
                                ;   again on their way past.
        lda     FNRPLY+6,y
        cmp     DGCRCV
        beq     DGCO8
        lda     DGENT
        ora     #DGE_RSY        ; DGCAP presses RESET on the wire; see cbcap.inc
        sta     DGENT
DGCO8:
; Advance the watermark only if this record is NEWER. Records can arrive in any
; order after a catch-up burst, and a stale one must not pull the watermark
; back. Signed, like the gate's compare, and for the same reason: the tick is
; eight bits and wraps.
        lda     FNRPLY+2,y
        sec
        sbc     DGRWAT
        bmi     DGCO9
        lda     FNRPLY+2,y
        sta     DGRWAT
DGCO9:  rts

; ---------------------------------------------------------------------------
DGSFAIL:
        lda     DGERR
        and     #$F0
        ora     #FNEBAD
        sta     DGERR
        lda     #NS_WISS
        sta     DGNST
        rts
