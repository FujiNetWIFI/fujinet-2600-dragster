# The cartridge goes here

One file, which is not in this repository:

| File | What | md5 |
|---|---|---|
| `dragster.bin` | the 2048-byte Dragster cartridge dump | `77057d9d14b99e465ea9e29783af0ae3` |

**Why it is not here.** Dragster is Activision's, published 1980 and written by
David Crane. This repository is a patch and a server. It is not a place to
redistribute the cartridge, so you bring your own.

**The disassembly is not here either, and for a different reason.** Combat's
port could lean on a commented DASM disassembly that had existed publicly since
1997. No Dragster disassembly exists, in this tree or anywhere else, so this one
is *generated*:

```
tools/disasm.py rom/dragster.bin > rom/dragster.asm
```

Recursive descent from `$F000` reaches every code byte and touches no data byte,
so there is nothing to seed by hand. Commit the result, annotate it with
comments — **comments only, never a token of code** — and `make verify-org`
proves all three claims on every build:

1. every instruction re-encodes to the bytes it came from, the reached-code set
   matches the regions declared in `tools/dgmap.py`, and the one biased operand
   (`ADC GearRate-4,Y` at `$F7E9`) still evaluates to the address it names;
2. `rom/dragster.asm` is `disasm.py`'s output plus comments and nothing else —
   both are run through `tools/strip.py` and compared;
3. and it assembles to `rom/dragster.bin` **byte for byte**.

`rom/dragster.asm` is then never edited again. Every change to the program is
declared in `tools/patches.py` and applied at build time, so there is no
hand-maintained copy of Dragster in this tree for a patch to drift away from.

Without the dump, `make verify-org`, `make dragster` and everything downstream
will not run. Nothing else in the repository needs it.
