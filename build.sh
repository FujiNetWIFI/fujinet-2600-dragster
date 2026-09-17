#!/usr/bin/env bash
# build.sh -- assemble the Atari 2600 networked Dragster client.
#
#   ./build.sh verify-org   the anti-drift gate: rom/dragster.asm regenerated,
#                           its annotations proved inert, assembled, and
#                           required to be rom/dragster.bin byte for byte
#
# The client is (N+1) x 2048 bytes: N 2K banks then the 2K fixed half. MAME's
# vcs_cart_slot_device::call_load() accepts only 4096/8192/16384/32768, so N is
# 1, 3, 7 or 15 and nothing between. Dragster needs three banks.
#
# The "FUJI" claim is stamped into the fixed half. Without it the cartridge
# treats the image as an ordinary game and the mailbox goes dead the moment it
# boots.
#
# Env:
#   FUJI_FIRMWARE=...  firmware tree (default ~/Workspace/fn-2600)
#   TVSTD=ntsc|pal     the television standard, baked in (default ntsc)

set -euo pipefail
cd "$(dirname "$0")"

FUJI_FIRMWARE="${FUJI_FIRMWARE:-$HOME/Workspace/fn-2600}"
VCS="$FUJI_FIRMWARE/pico/atari-2600"

# ---------------------------------------------------------------------------
# THE TELEVISION STANDARD, AND THE ONE IMAGE THIS WILL NOT BUILD.
#
# A 2600 cannot measure which television it is plugged into. The ROM generates
# the video timing itself; there is no register, no interrupt and no external
# reference to read. That is why every 2600 game shipped as separate NTSC, PAL
# and SECAM images rather than detecting the standard at runtime, and it is why
# the refusal has to live HERE, at the only moment anyone knows.
#
# Combat refused SECAM because its two tanks are the same shape and are told
# apart only by colour. THAT REASON DOES NOT APPLY TO DRAGSTER -- its two cars
# are told apart by which lane they are in, and a SECAM set would show that
# perfectly well. The refusal stands anyway, for a duller reason: this port has
# no SECAM colour table. Dragster's ColourTbl at $F6CA is seven bytes of
# hue-luminance, and on a SECAM TIA the luminance nibble is ignored entirely.
# Building one would mean authoring those seven bytes and having somebody with
# a SECAM console look at them, and neither has happened.
case "${TVSTD:-ntsc}" in
    ntsc) tvstd=0 ;;
    pal)  tvstd=1 ;;
    secam)
        cat >&2 <<'SECAM'
build.sh: refusing to build a SECAM image.

  Not for Combat's reason -- Dragster's two cars are told apart by lane, not by
  colour, so a SECAM set would show the race perfectly well. The reason is that
  this port has no SECAM colour table: ColourTbl at $F6CA is hue-luminance, and
  a SECAM TIA renders eight colours from the hue nibble and ignores luminance
  entirely. Somebody has to author those seven bytes and look at the result on
  a real set first.

  This is refused at build time because a 2600 cannot detect its own television
  standard at runtime: the ROM generates the video timing and there is nothing
  to read. The relay refuses a console that declares SECAM as well.

  TVSTD=ntsc (the default) or TVSTD=pal.
SECAM
        exit 1 ;;
    *)
        echo "build.sh: TVSTD must be ntsc, pal or secam (got '${TVSTD}')" >&2
        exit 1 ;;
esac

# ---------------- the toolchain ----------------
if command -v asl >/dev/null 2>&1; then
    AS=asl P2BIN=p2bin
elif [ -x "$HOME/asl/asl" ]; then
    AS="$HOME/asl/asl" P2BIN="$HOME/asl/p2bin"
else
    echo "build.sh: no Macroassembler AS found (tried PATH and ~/asl)" >&2
    exit 1
fi

mkdir -p build
HERE=$(pwd)

# AS writes its .p and .lst next to the source, so assemble from the source's
# own directory and collect the artefacts into build/. The include path carries
# src/ as well, because a generated source in build/ still includes vcs.inc.
assemble() {  # assemble <basename> <srcdir>
    local b=$1 d=${2:-src}
    ( cd "$d" && "$AS" -q -L -i . -i "$HERE/src" -i "$HERE/build" "$b.asm" )
    if [ "$d" != "build" ]; then
        mv "$d/$b.p" "build/$b.p"
        mv -f "$d/$b.lst" "build/$b.lst" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# THE ANTI-DRIFT GATE
#
# Combat could lean on a disassembly somebody else wrote and had checked: its
# rom/combat.asm is the 2002 DASM source, and `verify-org` only had to prove
# the DASM-to-AS conversion lossless. No Dragster disassembly exists, so this
# port GENERATES its source -- which moves the thing that has to be trusted from
# a document to a program, and means the gate has to prove two claims, not one.
verify_org() {
    # (1) the generator's own proofs: every instruction re-encodes to the bytes
    #     it came from, the reached-code set matches the declared regions, and
    #     the one biased operand still evaluates to the address it names.
    python3 tools/disasm.py --check rom/dragster.bin

    # (2) the annotations are inert. rom/dragster.asm is the generated source
    #     plus comments and nothing else: regenerate, strip both, compare.
    python3 tools/disasm.py rom/dragster.bin | python3 tools/strip.py > build/regen.txt
    python3 tools/strip.py rom/dragster.asm > build/committed.txt
    if ! cmp -s build/regen.txt build/committed.txt; then
        echo "build.sh: rom/dragster.asm is not tools/disasm.py's output plus comments." >&2
        diff -u build/committed.txt build/regen.txt | head -40 >&2
        exit 1
    fi

    # (3) and it is the cartridge.
    assemble dragster rom
    "$P2BIN" build/dragster.p build/dragster_org.bin -r '$F000-$F7FF' -l 255 -q
    mv -f build/dragster.lst build/dragster_org.lst 2>/dev/null || true
    mv -f build/dragster.p   build/dragster_org.p   2>/dev/null || true
    if ! cmp build/dragster_org.bin rom/dragster.bin; then
        echo "build.sh: the rebuilt image is not the cartridge." >&2
        exit 1
    fi
    echo "verify-org: rom/dragster.asm -> $(stat -c%s build/dragster_org.bin) bytes, identical to rom/dragster.bin"
}

# ---------------------------------------------------------------------------
# THE CLIENT
build_client() {
    verify_org

    # Build-time configuration, as EQUates and NOT as IFDEFs: AS resolves IF in
    # its FIRST PASS, and a condition naming a symbol defined further down the
    # file is not a build error -- it quietly takes the branch it should not.
    cat > build/cfg.inc <<CFG
; generated by build.sh -- do not edit.
DGLAG   EQU     ${DGLAG:-0}     ; 1: refresh the input shadows once a second, so
                                ;    \`make lag\` can prove nothing reads a live
                                ;    port any more
DGLAGM  EQU     \$3F
DGTVSTD EQU     $tvstd          ; 0 NTSC, 1 PAL. Declared, never detected: a
                                ;    2600 generates its own video timing and has
                                ;    nothing to read.
CFG

    # The room's URL, baked in as the fallback for a console whose appkey the
    # Lobby has not written. The Lobby is how a room is normally joined: it
    # writes the URL into appkey 25 and reboots this ROM, so there is no HTTP
    # "join" call anywhere in this family.
    {
        ep="${ENDPOINT:-TCP://127.0.0.1:9601/}"
        echo "; generated by build.sh -- do not edit"
        printf 'UENDPT: DB      "%s",0\n' "$ep"
    } > build/endpoint.inc
    {
        name="${PLAYER:-PLAYER1}"
        echo "; generated by build.sh -- do not edit"
        printf 'CSHNLEN EQU     %d\n' $(( ${#name} ))
        printf '        DB      "%s"\n' "$name"
    } > build/playername.inc

    # The banked, patched Dragster, generated from the listing verify-org has
    # just proved reproduces the cartridge.
    python3 tools/mkbanks.py build/dragster_org.lst rom/dragster.asm build/dragster.inc

    # THE TAIL IS ASSEMBLED FIRST, and its addresses exported, because every
    # bank calls into it and none of them can know where it landed otherwise.
    assemble dgtail
    python3 tools/mktail.py build/dgtail.lst \
        FNRW,FNARM,FNCHK,FNBEG,FNPB,FNPW,FNGO,FNACK,FNROWA,FNCHR,FNENDR \
        > build/tail.inc

    for b in dgboot dggame dgkern; do
        assemble "$b"
        python3 tools/checkbanks.py "build/$b.lst" $((0x1800)) "$b"
        "$P2BIN" "build/$b.p" "build/$b.bin" -r '$1000-$17FF' -l 255 -q
    done
    "$P2BIN" build/dgtail.p build/tail.bin -r '$1800-$1FFF' -l 255 -q

    cat build/dgboot.bin build/dggame.bin build/dgkern.bin build/tail.bin \
        > build/dragster.bin
    stamp_claim build/dragster.bin

    python3 tools/checkrom_filter.py "$VCS/tools/checkrom.py" build/dragster.bin
    python3 tools/check_zp.py build/dggame.lst
    # The audit baseline is the same never-edited source assembled where a bank
    # is actually mapped. Comparing against the $F000 image would report every
    # rebased high byte as an undeclared change.
    sed 's/ORG\t\$F000/ORG\t$1000/' rom/dragster.asm > build/dragster_win.asm
    assemble dragster_win build
    "$P2BIN" build/dragster_win.p build/dragster_win.bin -r '$1000-$17FF' -l 255 -q
    python3 tools/check_patch.py build/dragster_win.bin build/dragster.bin
}

# The "FUJI" claim. Without it the cartridge treats the image as an ordinary
# game and the mailbox goes dead the moment it boots.
stamp_claim() {
    local f=$1 size
    size=$(stat -c%s "$f")
    printf 'FUJI' | dd of="$f" bs=1 \
        seek=$((size - 0x800 + 0x0710)) conv=notrunc status=none
    echo "$f: $size bytes"
}

case "${1:-}" in
    verify-org) verify_org ;;
    dragster)   build_client ;;
    "")         build_client ;;
    *)
        echo "build.sh: unknown mode '$1'" >&2
        exit 1 ;;
esac
