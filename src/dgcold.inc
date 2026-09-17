; dgcold.inc -- the game bank's cold path and the bounded clear.
;
; In the SECOND hole, not the first: the first is 528 bytes and the transport
; wants 510 of them. The dispatcher at $1000 reaches this with a JMP rather than
; a branch for exactly that reason.

; ---------------------------------------------------------------------------
; The cold path. Reached from $1000 when DGE_WARM is clear: either the boot
; bank has just handed over, or the cartridge came up cold.
DGBOOT: sei
        cld
        ldx     #$00

; ---------------------------------------------------------------------------
; THE CLEAR, BOUNDED.
;
; Two paths enter this loop and the second is the one that would have killed the
; port. $F2E9 restages a race with `LDX <seed> / JMP DGCLRE`, entering here with
; X preloaded -- and stock ran to $FF, so a restage wiped $B9-$FF, straight
; through every cell the netcode owns, on every RESET and every SELECT.
;
; The bound costs nothing per iteration. Stock was `STA VSYNC,X / TXS / INX /
; BNE`; this is `STA VSYNC,X / INX / CPX / BNE`, and CPX immediate is the two
; cycles TXS was -- eleven either way. What it does change is where TXS happens:
; stock relied on the last iteration leaving X = $FF, and this loop never
; reaches $FF, so the stack pointer is set explicitly below.
;
; The TIA sweep is untouched. X still counts from $00 through $7F on a cold
; start, so every write register is strobed exactly as stock strobed it; the
; bound only removes iterations $DA-$FF, which are RAM the game never reads.
DGCLRE: lda     #$00
DGCLR:  sta     VSYNC,x
        inx
        cpx     #DGZPLO
        bne     DGCLR
        ldx     #$FF
        txs

; ORA, NEVER LDA. The boot bank has already set DGE_NET and the role in here,
; and a match that lost its role on the first frame would have both consoles
; driving the top lane.
        lda     DGENT
        ora     #DGE_WARM
        sta     DGENT

; Stock's own cold test, unchanged: a zero LFSR means the RAM really was just
; cleared, so go and pick a game variation; anything else is a restage.
        lda     Lfsr
        bne     DGST1
        jmp     NewGame
DGST1:  jsr     StageRace
        jmp     FrameTop
