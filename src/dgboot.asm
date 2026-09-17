; dgboot.asm -- bank 0: the cold start and the session.
;
; This bank is entirely ours -- Dragster is not in it at all -- so it is the one
; place in the cartridge with room to spare. It runs once: the shared username
; out of an appkey, the room's URL out of another, the N:TCP open, HELLO, the
; wait for an opponent, and then the handover to bank 1.
;
; A cartridge with no server is still a Dragster cartridge. Every failure path
; in here ends at CSLOCAL, which says so on the screen and hands over cold and
; not networked -- because a console that silently fell back to playing alone
; looks exactly like a console that never got a turn.

        CPU     6502
        INCLUDE "vcs.inc"
        INCLUDE "fujinet.inc"
        INCLUDE "cfg.inc"
        INCLUDE "dgdefs.inc"
; The shared transport's addresses, generated from the tail's own listing so
; there is no hand-kept list to go stale.
        INCLUDE "tail.inc"

DGBANK  EQU     BANKBOOT
DGHASTXT EQU    1               ; this is the only bank that draws text

        ORG     $1000

; The boot bank is entered twice: once at power-on, and once more if the peer
; leaves -- because this is the only bank with a text kernel in it, and
; "OPPONENT HAS LEFT" is worth saying in words.
DGBOOTE: lda    DGENT
        and     #DGE_LEFT
        beq     DGBENT
        jmp     CSLEFT

        INCLUDE "dgsess.inc"
        INCLUDE "dgappk.inc"
        INCLUDE "dgdisp.inc"

        IF      * > $1800
        ERROR   "the boot bank has overflowed"
        ENDIF

        END
