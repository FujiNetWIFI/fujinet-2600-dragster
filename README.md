# Networked two-player Dragster

Activision's Dragster (1980), for the Atari 2600, with two people racing each
other over the network through a FujiNet cartridge. Both players use joystick 1
on their own console; the host drives the top lane and the guest the bottom.

With no FujiNet, no relay or no opponent, it is simply Dragster. `make det`
proves that: 742 simulated frames byte-identical to the 1980 cartridge.

```
make verify-org   the disassembly is mechanical, inert, and the cartridge
make dragster     the 8K image, every changed byte declared
make ladder       all of it, in order
make play         two windows, paired, playing
```

## How it plays

Stage a race by pushing the stick right while both engines are quiet. The gear
lever is the stick pulled **left** — pull it to arm a shift and let go to take
the gear, which is also how you launch: let go the instant the tree goes green.
The button is the throttle, and holding it past the red line still blows the
engine.

RESET and SELECT work from either console — the two are ANDed on the wire, so
either player may press either and both machines act on it at the same tick.
Black & white stays local, so each player sees their own setting. SELECT walks
the game variation between Dragster's two games: a straight drag race, and the
same race with a lane drift you have to steer against.

## The elapsed time, which is the whole problem

Dragster's identity is a number to two decimal places. Delay-based lockstep
applies a press `d` ticks after it is made, so a perfect launch would reach the
simulation eight frames late and every time in the game would inflate by about
thirteen hundredths — and the 5.51 nobody has beaten since 1980 would stop being
reachable at all.

So the countdown tree, and its beeps, are drawn **eight simulated frames ahead
of the simulation's own countdown**. The player reacts to a green that is early,
the press is captured on the next tick boundary and applied `d` ticks later, and
it lands at sim-green. `make rig-launch` measures it: the same robot driver
launches 5 frames after green on the 1980 cartridge and 7 over the network,
where with no lead it would be 13.

**Gear shifts are not compensated and cannot be.** The countdown is a
deterministic function of the simulation, so it can honestly be shown early;
what the revs will do next depends on what the player does next, and nothing can
show that early. Shifts land `d` ticks late, so a full-race time over the
network is still somewhat higher than the same driver's time on a single
console. That is the honest cost of playing this particular game this way.

## How it works

The cartridge window is 4K: a 2K banked half and a 2K fixed half that holds the
mailbox. Dragster is exactly 2048 bytes, so it fills a bank precisely and leaves
nowhere for netcode. It is split across two banks, plus a third for the session:

| bank | contents | stock bytes |
|---|---|---:|
| 0 boot | the session: appkeys, the socket, HELLO, the screens | 0 |
| 1 game | the frame logic, the audio, and the transport | 844 |
| 2 kern | the lane kernel and all the sprite data | 1282 |

Every byte keeps the address it has in the cartridge dump, rebased
`$F000 → $1000`, and each bank leaves the other's regions empty — so the holes a
bank has are exactly the regions it does not own, and `tools/check_patch.py` can
be a real byte audit rather than a formality.

**The split costs no patched bytes at either seam.** `$F4E2 JMP FrameTop` is
stock and unpatched: in the game bank $1016 is a hole, and the trampoline lives
there. `$F225` falls through into `$F226`, also stock: in the kernel bank $1226
is a hole, and the other trampoline lives there. One cross-bank reference exists
in the whole of Dragster and it is the first of those.

The simulation is delay-based input lockstep: a tick is four video frames, a
record carries a three-tick window of input plus a checksum, and a console whose
peer has not arrived stalls — which is free here, because Dragster's kernel
rebuilds every TIA register it uses from RAM on every frame and the game never
reads a collision latch.

**The repair is a synthetic RESET.** On a checksum mismatch a console presses
RESET into its own wire byte; RESET is ANDed on the wire, so both machines
restage at the same tick. Unlike Combat's, this repair is total — Dragster's car
positions are in RAM, so the clear plus StageRace restore every checksummed
cell. `make rig-repair` injects a difference and measures the recovery: four
ticks, about a third of a second.

## What is in here

| path | |
|---|---|
| `rom/` | the cartridge and its generated disassembly. Neither is redistributed; see `rom/README.md` |
| `src/` | the 6502: the banks, the shim, the transport, the session |
| `tools/` | the disassembler, the bank generator, the patch map, and the build audits |
| `emu/` | MAME harnesses, one per gate |
| `test/` | the rigs: two consoles, two fujinet-pc, one relay |
| `server/` | the relay, TCP 9601 |
| `PORTING.md` | what this cost to learn |

The FujiNet Lobby is how a room is normally joined: it writes the relay's URL
into appkey 25 and boots this ROM. There is no HTTP "join" call anywhere in this
family — joining is a local write and a reboot.

## Not done yet

- Never run on hardware. Every number here is MAME plus a real `fujinet-pc`
  speaking BoIP to a real socket; what is missing is the cartridge bus.
- `make echo` — the transaction-latency probe — is not ported. `K = 4` and
  `d = 2` are inherited from the Combat bring-up, which measured one frame per
  transaction on this same cartridge and firmware. They should be re-measured on
  hardware before anyone trusts them there.
- No SECAM image. Not for Combat's reason — Dragster tells its cars apart by
  lane, not colour — but because nobody has authored a SECAM colour table for
  `$F6CA` or looked at the result on a real set. `build.sh` refuses to build one
  and the relay refuses to pair one, and the two refusals have to agree.
