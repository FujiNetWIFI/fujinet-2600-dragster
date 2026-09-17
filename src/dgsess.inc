; dgsess.inc -- the session. PLACEHOLDER: hands straight over to local play.
; The real session (appkeys, socket, HELLO, WAITING, START) replaces this.
DGBENT:
        sei
        cld
        ldx     #$FF
        txs
        lda     #0
        ldx     #$80
DGBC1:  sta     $00,x
        inx
        bne     DGBC1
        sta     DGENT           ; cold, not networked
        sta     DGLEAD          ; no display lead when not in a match
        lda     #DGSTKX
        sta     DGCLRX          ; the stock restage seed
        lda     #BANKGAME
        jmp     DGGOTO
