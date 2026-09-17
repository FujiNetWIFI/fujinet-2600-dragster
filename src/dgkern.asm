; dgkern.asm -- bank 2: Dragster's lane kernel and all of its sprite data.
;
; The kernel runs TWICE a frame, once per lane, and each dragster is a single
; 48-pixel sprite multiplexed across P0 and P1 with NUSIZ=$03 and VDELP0/1 set.
; The kernel and its data are 1282 of this bank's 2048 bytes -- far more than
; Combat's 388 -- which is why the transport lives in the other bank and not
; this one.
;
; What is here besides Dragster is one routine: DGTREE, because the countdown
; tree is drawn by the kernel and the display lead has to be applied where the
; glyph is chosen.

        CPU     6502
        INCLUDE "vcs.inc"
        INCLUDE "fujinet.inc"
        INCLUDE "cfg.inc"
        INCLUDE "dgdefs.inc"
        INCLUDE "tail.inc"

DGBANK  EQU     BANKKERN

; ---------------------------------------------------------------------------
; The entry. The trampoline enters every bank at $1000, and this bank's first
; stock byte is FrameTop at $1016, so these are the 22 bytes in front of it.
;
; CLD is insurance, not ceremony: Dragster runs SED at $F348 for the BCD time
; chain. It closes it at $F35C and no branch leaves the block between them, so
; decimal mode is provably clear -- but this bank is entered by a jump from
; another bank, and a jump is exactly the thing that could one day arrive with
; the flag set.
        ORG     $1000
DGKENT: cld
        jmp     FrameTop

        INCLUDE "dragster.inc"

; ---------------------------------------------------------------------------
; SEAM B: the kernel bank has finished drawing and the game bank runs.
;
; This must be AT $1226, because $F225 -- the store that arms the overscan
; timer -- falls through into $F226, unpatched. DGRE3 is the end of the region
; the generator just emitted, which is that store.
;
; The switch is paid for out of a budget that is already running: TIM64T was
; armed two instructions ago with $21, so the thirty-odd cycles this costs come
; out of 2112 that the audio engine and the network machine were going to share
; anyway.
        ORG     DGRE3

        IF      * <> DGSEAMB
        ERROR   "the arm-overscan region does not end at seam B"
        ENDIF

        lda     #BANKGAME
        jmp     DGGOTO

; The rest of the 703-byte hole where the game logic used to be.
        INCLUDE "dgtree.inc"

        IF      * > $14E5
        ERROR   "the seam and the tree have overrun PositionSprites"
        ENDIF

        END
