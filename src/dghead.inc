; dghead.inc -- the seam-A trampoline.
;
; FIVE BYTES, and they have to be the first five of the game bank's big hole:
; $14E2 -- which is stock, unpatched -- jumps to $1016, and in this bank $1016
; is a hole rather than the top of the frame.
;
; Everything else that was here has moved to dgcold.inc in the second hole. The
; transport is 510 bytes and this hole is 528, so it gets the rest to itself.

; ---------------------------------------------------------------------------
; SEAM A: the game bank has finished its logic and the kernel bank draws.
;
; Stock's `JMP FrameTop` at $F4E2 needs no patch at all. It is the only
; cross-bank reference in the whole of Dragster -- tools/dgmap.py's shared
; regions are what make that true -- and it lands here.
FrameTop:
        lda     #BANKKERN
        jmp     DGGOTO

