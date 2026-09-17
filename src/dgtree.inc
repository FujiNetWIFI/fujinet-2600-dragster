; dgtree.inc -- the countdown tree, shown DGLEAD simulated frames early.
;
; Lives in the kernel bank, because the christmas tree is drawn by the kernel:
; $F1AA is inside the message band, between the WSYNC at $F195 and the one at
; $F1DC.
;
; THE DIRECTION IS DOWN. Countdown runs $9F to 0 and 0 IS green, so showing the
; player the state the simulation will be in eight frames from now means
; SUBTRACTING the lead, not adding it. Getting that backwards shows the tree
; late, which looks exactly like network lag and passes every synchronisation
; gate in the ladder -- `make rig-launch` is the one that fails.
;
; TIMING. Stock's path through $F1AA-$F1BC is 81 cycles at its shortest and 91
; at its longest, so the band is always two scanlines and never three. This adds
; a JSR and an RTS (12) and the subtract and its two branches (~10), for 103 to
; 113 -- still two scanlines, with about 39 cycles of headroom to the third.
; Nothing else in the stretch is raster-sensitive: PositionSprites finished at
; $F164. `make frames` is the gate.
;
; X is LaneIdx, set at $F185 and still live; JSR preserves it, and the digit
; path below needs it.
DGTREE: lda     Countdown
        sec
        sbc     DGLEAD
        bcc     DGTRD           ; inside the lead: the player sees green
        beq     DGTRD
; Stock's own arithmetic, on the led value. AND #$F0 leaves bit 0 clear, so the
; LSR that follows clears the carry and the ADC is exact -- which is why stock
; could write it this way and why this can too.
        and     #$F0
        lsr     a
        adc     #$08
        rts
; The digit path: the hundredths, which is what the slot shows once the race is
; running. Reached both when the tree is green and when a race is under way.
DGTRD:  lda     TimeHun,x
        and     #$0F
        asl     a
        asl     a
        asl     a
        rts
