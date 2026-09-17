; dgboot.asm -- bank 0: the cold start and the session.
;
; This bank is entirely ours -- Dragster is not in it at all -- so it is the one
; place in the cartridge with room to spare. It runs once: the appkeys, the
; socket, HELLO, the wait for an opponent, and then the handover to bank 1.
;
; A cartridge with no server is still a Dragster cartridge. Every failure path
; in here ends at DGLOCAL, which says so on the screen and hands over cold and
; not networked -- because a console that silently fell back to playing alone
; looks exactly like a console that never got a turn.

        CPU     6502
        INCLUDE "vcs.inc"
        INCLUDE "fujinet.inc"
        INCLUDE "cfg.inc"
        INCLUDE "dgdefs.inc"
        INCLUDE "tail.inc"

DGBANK  EQU     BANKBOOT

        ORG     $1000
        jmp     DGBENT

        INCLUDE "dgsess.inc"

        IF      * > $1800
        ERROR   "the session has overrun the bank"
        ENDIF

        END
