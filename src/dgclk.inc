; dgclk.inc -- the sim clock, the countdown beep, and the frame-in-tick phase.
;
; Three small routines that share a hole: the 250 bytes between the font's start
; and the vectors, which belong to the kernel bank and are therefore empty here.

; ---------------------------------------------------------------------------
; DGCLK -- Dragster's frame counter, moved.
;
; FrameCnt ($81) IS THE SIM CLOCK. It selects which car the logic updates, and
; paces the engine tone, the road scroll, the gear timer, the scrape and the
; lane drift -- so it has to count frames the SIMULATION took, not frames the
; television drew. Stock increments it at $F29A, unconditionally.
;
; It could not be gated where it stood. $F298-$F2C3 is untimed -- between the
; last VSYNC WSYNC and the WSYNC at $F2C3 -- and the stock path already spends
; 54 of a scanline's 76 cycles. A JSR gate costs twenty of the twenty-two left.
;
; So it runs here instead, inside the two thousand cycles of overscan, called
; only on a frame whose logic will run. Behaviour is identical because of an
; ordering fact that was checked rather than assumed: the audio engine reads
; FrameCnt at $F226, BEFORE the hook at $F285, so it still sees the previous
; frame's value exactly as stock does, and nothing between the hook and $F2A5
; reads either cell.
DGCLK:  inc     FrameCnt
        bne     DGCLK9
        inc     Attract
        bne     DGCLK9
        sec
        ror     Attract
DGCLK9: rts

; ---------------------------------------------------------------------------
; DGBEEP -- the countdown beep, on the display lead.
;
; Returns with Z SET for silence, which is the sense both stock branches already
; had, so the patch at $F242 is `JSR DGBEEP / BEQ` where stock was `LDA / BEQ`.
;
; The ear has to agree with the eye or the lead is worse than none: a player who
; launches on the sound would be eight frames behind one who launches on the
; light, and the two cues are a third of a car length apart at the stripe.
DGBEEP: lda     Countdown
        sec
        sbc     DGLEAD
        bcc     DGBN            ; already inside the lead: green, no beep
        beq     DGBN
        and     #$0F
        bne     DGBN
        lda     #$01            ; Z clear -> beep
        rts
DGBN:   lda     #$00            ; Z set   -> silence
        rts

; ---------------------------------------------------------------------------
; DGPHI -- advance the frame-in-tick phase.
;
; FOUR BYTES OF WORK. The phase is the top two bits of DGENT, so adding $40
; increments it and the carry out of bit 7 is simply discarded -- the low bits,
; which are the entry, role and flag bits, cannot be disturbed because nothing
; carries into them. Masking would be three instructions of ceremony.
;
; Called on every frame whose logic will run, and on NO stalled frame: a stall
; leaves the phase at 0 so the next frame is the same boundary again, which is
; exactly what retrying a tick means.
DGPHI:  lda     DGENT
        clc
        adc     #$40
        sta     DGENT
        rts
