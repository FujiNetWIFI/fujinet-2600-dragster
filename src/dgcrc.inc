; dgcrc.inc -- the sim checksum, the synthetic RESET, and the way out.

; ---------------------------------------------------------------------------
; DGCRC -- one byte over fifty-two cells of simulation.
;
; A CHECKSUM IS ONLY WORTH WHAT IT COVERS. Combat learned this twice: once when
; two consoles on different game variations agreed on every checksum, and once
; when a quantity sampled only on the ticks that RAN turned out to be a function
; of the local stall pattern -- which is the one thing that differs between two
; consoles by design.
;
; So this covers a contiguous block rather than a hand-picked list: $A8-$D7 is
; everything from RPM to the previous gear-lever state, which is both cars'
; entire physical condition -- rpm, lane, the input shadows, engine volume, all
; three levels of the BCD clock including the sub-hundredths at $B7/$B8 that are
; never displayed, track position, the kernel's derived timing pair, speed, the
; sub-pixel accumulator, the road scroll phase, the wheel and body animation,
; the scrape flag, gear, blown, the explosion timer, race-over and the message
; index.
;
; Four cells outside it are added by name because they decide what all of that
; MEANS: the game variation, the sim clock, the LFSR and the countdown. Combat's
; §4.21 is exactly this -- two consoles agreed perfectly while playing different
; variations, because the variation was not in the sum.
;
; TWO CELLS INSIDE THAT RANGE ARE DELIBERATELY SKIPPED, and finding out why
; cost a rig run.
;
; BoomTimer ($D0/$D1) is the explosion sound's countdown. The logic SETS it, at
; $F3EF, behind the lockstep gate -- but it is read at $F237 and decremented at
; $F23D, and BOTH of those are inside the audio engine, which sits at
; $F226-$F284, in front of the hook at $F285 and therefore in front of the gate.
; The audio runs on every frame the television draws, including stalled ones,
; because a sound that stuttered whenever the transport was late would be worse
; than the stall it was reporting.
;
; So BoomTimer advances once per VIDEO frame while the rest of the simulation
; advances once per SIMULATED frame, and the number of frames the two differ by
; is the local stall pattern -- which is the one thing that differs between two
; consoles by design. Combat's §4.5 in the other direction: there the trap was a
; quantity sampled only on the ticks that ran, here it is one advanced on the
; frames that did not.
;
; It is safe to skip, and provably so: $F237, $F23D and $F3EF are its only three
; references in the whole cartridge, and everything it reaches is AUDV0, AUDF0
; and AUDC0. No audio cell reaches physics. This is Dragster's version of "B&W
; stays local".
;
; The symptom, for the next person: 27 CRC MISMATCH lines in the relay log,
; clustered in a burst of four or five consecutive ticks, arriving only after an
; engine blew -- and two consoles that were byte-identical before it and after.
;
; $D8/$D9 are left out too, for the ordinary reason. They are the kernel's
; scratch, written in the other bank after this is sampled, and a checksum that
; covers a cell whose value depends on where the raster was is a checksum that
; reports differences it cannot explain.
;
; The fold is `asl a / adc`, which is a rotate-and-add: position-sensitive, so a
; pair of cells that swapped values does not cancel.
DGCRC:
        lda     #0
        ldx     #$27            ; $A8 + $27 = $CF, counted down to 0
DGCRC1: asl     a
        adc     Rpm,x
        dex
        bpl     DGCRC1
        ldx     #$05            ; and $D2 + $05 = $D7, skipping BoomTimer
DGCRC2: asl     a
        adc     RaceDone,x
        dex
        bpl     DGCRC2
        asl     a
        adc     GameVar
        asl     a
        adc     FrameCnt
        asl     a
        adc     Lfsr
        asl     a
        adc     Countdown
        rts

; ---------------------------------------------------------------------------
; DGRSY -- the desync repair, pressed into this console's own wire byte.
;
; THE REPAIR IS A SYNTHETIC RESET, AND THAT IS THE WHOLE TRICK. Dragster's RESET
; switch already does everything a repair has to do: $F2E3 reads it, $F2E9
; restages, and the clear plus StageRace rebuild both cars from nothing.
;
; Routing it through the INPUT path is what makes it agree. RESET is ANDed on
; the wire, so ONE console arming it is enough, and both consoles act on it at
; the SAME TICK through machinery that `make rig` already proves. A scheduled
; repair would have needed a tick to be agreed and stored.
;
; It is one-shot: the bit is cleared as it is pressed, so the press lasts
; exactly one tick -- four frames, far more than the one frame $F2E3 needs to
; see it.
;
; Unlike Combat's, this repair is TOTAL. See the note on DGRSYX in dgdefs.inc:
; every cell the checksum covers is either cleared by the restage or rewritten
; by StageRace, so the two consoles come back not merely consistent but equal.
DGRSY:
        sta     DGTMP
        lda     DGENT
        and     #DGE_RSY
        beq     DGRSY9
        lda     DGENT
        and     #$FF-DGE_RSY    ; one-shot: clear it as we press it
        sta     DGENT
        lda     DGTMP
        and     #$FF-IW_RST     ; active low: clearing the bit IS the press
        rts
DGRSY9: lda     DGTMP
        rts

; ---------------------------------------------------------------------------
; DGGONE -- the peer is gone, and the boot bank says so in words.
;
; Reached when the stall watchdog saturates at fifteen consecutive stalled ticks
; -- about a second -- or on the spot when a PEER_LEFT frame arrives. Either way
; the match is over, and the console that is left needs to be told rather than
; left looking at a frozen picture.
DGGONE:
        lda     DGENT
        and     #$FF-DGE_NET-DGE_WARM
        ora     #DGE_LEFT
        sta     DGENT
        lda     #BANKBOOT
        jmp     DGGOTO
