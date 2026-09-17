; dgcap.inc -- this console's own half of the stick, the stall, and the
; non-networked path.

; ---------------------------------------------------------------------------
; DGCAP -- this console's own console, packed into one wire byte.
;
; THE LEFT PORT, ON BOTH CONSOLES, WHATEVER THE ROLE.
;
; The role decides which CAR this byte drives, and that is settled by the swap
; in the gate, where it belongs. Here there is no role at all: each player sits
; at their own console with one joystick in port 1, and a guest who had to plug
; into port 2 to drive their own car would be right about nothing except the bit
; numbering. It is the kind of mistake that is invisible in a rig, where
; nobody's hands are on anything, and obvious the moment two people play.
DGCAP:
        lda     SWCHA           ; bits 7-4: the LEFT port, joystick 1
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     DGTMP
        lda     INPT4           ; and its trigger
        and     #IW_TRIG        ; bit 7, straight through
        ora     DGTMP
        sta     DGTMP

; RESET and SELECT, SHIFTED UP FROM BITS 0 AND 1 TO BITS 4 AND 5.
;
; That shift is the whole of a bug worth remembering. SWCHB puts RESET at bit 0
; and SELECT at bit 1; the wire byte puts them at 4 and 5, because 0-3 are the
; stick. Masking SWCHB with #$30 and calling it done reads the console's UNUSED
; bits 4 and 5 instead -- which read high on real hardware and in MAME, so the
; wire says "not pressed" for ever and NEITHER SWITCH EVER REACHES THE OTHER
; CONSOLE. The mixer at the far end shifts them back down correctly, so both
; halves look right in isolation and the pair is silently broken.
;
; It survives every gate that only checks agreement: two consoles that both
; ignore SELECT agree perfectly.
        lda     SWCHB
        and     #$03            ; bit 0 RESET, bit 1 SELECT, both active low
        asl     a
        asl     a
        asl     a
        asl     a               ; -> IW_RST and IW_SEL
        ora     DGTMP

; IW_DIFF is forced SET rather than read. Dragster never reads SWCHB bits 6 or
; 7 -- it has no difficulty setting at all -- and forcing the bit is what keeps
; the idle byte $FF, which is what both rings are seeded with. Reading the
; switch instead would make a console whose difficulty happens to sit on B send
; a byte that differs from the seed in a bit nothing looks at, which is a
; difference waiting to be mistaken for a real one.
        ora     #IW_DIFF

; The desync repair is a synthetic RESET pressed into this byte.
        jmp     DGRSY

; ---------------------------------------------------------------------------
; DGSTALL -- the peer's input for this tick has not arrived.
;
; Nothing else happens. The frame still runs: VSYNC still goes out, the overscan
; and VBLANK timers still run, and the kernel still draws. What does not happen
; is the game logic, so the picture freezes coherently and the display never
; shudders.
;
; That is FREE on this console, more cheaply than it was on Combat's. Dragster's
; kernel rebuilds every TIA register it uses from RAM on every frame, and the
; game never reads a collision latch -- it never strobes CXCLR at all, and never
; touches a CX register. N frozen frames leave exactly what one would, so two
; consoles that stalled for different lengths resume in agreement.
;
; The phase is NOT bumped here. A stall leaves it at 0 so the next frame is the
; same boundary again, which is exactly what retrying a tick means. The sim
; clock is not ticked either, which is what keeps FrameCnt a count of simulated
; frames on both consoles however differently they stalled.
;
; The stall count lives in DGERR's high nibble, saturating. A stall is normal;
; fifteen in a row at four frames each is a second, and that is a peer that has
; gone. Saturation is the ONE "the peer is gone" condition: a clean leave
; arrives as a PEER_LEFT frame and the transport saturates this on the spot, and
; a console that was unplugged saturates it by simply not arriving.
DGSTALL:
        lda     #0
        sta     DGADV
        lda     DGERR
        cmp     #$F0            ; the low nibble is an error code below $10, so
        bcc     DGSTA1          ;   this is exactly "high nibble is already $F"
        jmp     DGGONE
DGSTA1: clc
        adc     #$10            ; +1 in the high nibble, low nibble untouched
        sta     DGERR
        rts

; ---------------------------------------------------------------------------
; DGLOC0 -- not in a match: the console drives both cars, exactly as it always
; did.
;
; This path is byte-for-byte the behaviour `make det` compares against stock,
; and it is why the shim went in before the network did: a build that plays
; differently here would make every later difference ambiguous.
;
; It reproduces the split the patch at $F2C8 deleted, in the same order and with
; the same result -- SWCHA's high nibble to the top lane, its low nibble to the
; bottom -- and it stores the triggers RAW, because $F3B1 tests bit 7 with BMI
; and stock handed it the untouched port value.
DGLOC0:
        lda     SWCHA
        tay
        and     #$0F
        sta     Joy1
        tya
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     Joy0
        lda     INPT4
        sta     DGTRIG
        lda     INPT5
        sta     DGTRIG+1
        lda     SWCHB
        sta     DGSWB
        rts
