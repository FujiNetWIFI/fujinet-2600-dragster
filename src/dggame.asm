; dggame.asm -- bank 1: Dragster's frame logic, its audio, and the transport.
;
; Everything the game does between the overscan timer being armed and the jump
; back to the display: the audio engine, VSYNC, the attract colours, the input,
; the restart and SELECT handling, and the per-player physics. The lane kernel
; and all the sprite data are in bank 2, because Dragster is exactly 2048 bytes
; and a bank is exactly 2048 bytes, so something had to move to make room.
;
; Every byte here keeps the address it has in the cartridge dump, rebased
; $F000 -> $1000. The holes are the regions this bank does not own, and they are
; where the netcode goes:
;
;   $1016-$1225   528 bytes, where the colour setup and the lane kernel were
;   $152D-$16C7   411 bytes, where CalcSpritePtrs, DrawMessage and the car
;                 sprites were
;   $16CA-$16D2     9 bytes, the colour table's -- too small for anything, and
;                 left empty on purpose rather than filled with something that
;                 would have to move the first time it grew
;   $1700-$17F9   250 bytes, where the font and the message strips were

        CPU     6502
        INCLUDE "vcs.inc"
        INCLUDE "fujinet.inc"
        INCLUDE "cfg.inc"
        INCLUDE "dgdefs.inc"
; The shared transport's addresses, generated from the tail's own listing so
; there is no hand-kept list to go stale.
        INCLUDE "tail.inc"

DGBANK  EQU     BANKGAME

        INCLUDE "dragster.inc"

; ---------------------------------------------------------------------------
; The first hole. DGRE0 is the end of the region the generator just emitted --
; the rewritten cold head -- so this cannot go stale if that ever changes
; length. It is $1016, which is where seam A has to land.
        ORG     DGRE0

        IF      * <> DGSEAMA
        ERROR   "the cold head does not end at seam A; $14E2 JMPs into nothing"
        ENDIF

        INCLUDE "dghead.inc"
        INCLUDE "dgnet.inc"

        IF      * > DGSEAMB
        ERROR   "the seam and the transport have overrun the audio engine"
        ENDIF

; ---------------------------------------------------------------------------
; The second hole: the 411 bytes the kernel's sprite data left behind. DGRE9 is
; the end of PositionSprites, which is shared and therefore emitted here too.
        ORG     DGRE9
        INCLUDE "dgcold.inc"
        INCLUDE "dginput.inc"
        INCLUDE "dgcap.inc"
        INCLUDE "dgcrc.inc"

        IF      * > $16C8
        ERROR   "the cold path, the shim and the checksum have overrun ScrollMask"
        ENDIF

; ---------------------------------------------------------------------------
; The fourth hole: the 250 bytes the font and the message strips left. DGRE16 is
; the end of the gear tables, which are shared.
        ORG     DGRE16
        INCLUDE "dgclk.inc"

        IF      * > $17FA
        ERROR   "the clock, the beep and the phase have overrun the vectors"
        ENDIF

        END
