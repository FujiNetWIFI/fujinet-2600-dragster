-- inputs.lua -- where does this ROM read the console?
--
-- Dragster's whole input surface is four reads: SWCHA at $F2C8, INPT4,X at
-- $F3B1, and SWCHB at $F2A7 and $F2E3. After the patch every one of them must
-- come from inside the shim -- because in lockstep BOTH players' inputs are
-- applied at the same tick on both consoles, so a site still reading a live
-- port is a desync the moment somebody touches something.
--
-- This turns "four sites, all patched" into a measurement rather than a claim.
-- The mirrors matter: the TIA and RIOT are decoded on very few address lines,
-- so INPT4 answers at $0C, $1C, $2C... and a tap on $000C alone would report a
-- clean run while the ROM read a mirror all day.
local mem
local hits = {}
-- WHICH BANK a read came from, tracked from the bank hotspot rather than read
-- out of the cartridge window inside a tap. The boot bank reads SWCHB on
-- purpose -- CSLEFT spins on the RESET switch locally, because there is no peer
-- left to agree with -- and it lives at the same addresses as the game bank.
local curbank = 0
local reads = 0
local fields = {}
for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end

-- The ADDRESS READ is reported alongside the PC, because the PC read from
-- inside a tap is the CPU's, not the instruction's: the core has already moved
-- on by the time the callback runs, so it points a byte or two past the load
-- that caused it. Chasing $13B9 as an unpatched site cost an hour; it is the
-- PC left over from the patched LDA DGTRIG,X two instructions earlier.
local function watch(lo, hi, name)
    return mem:install_read_tap(lo, hi, name, function(offset, data, mask)
        local pc = manager.machine.devices[":maincpu"].state["PC"].value
        local k = string.format("%d/%04X/%04X", curbank, pc, offset)
        hits[k] = (hits[k] or 0) + 1
        reads = reads + 1
        return data
    end)
end

_G._in_frame = emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
        _G._bk = mem:install_write_tap(0x1D80, 0x1D8F, "in_bank",
            function(offset, data, mask)
                curbank = offset - 0x1D80
                return data
            end)
        _G._t1 = watch(0x0280, 0x0283, "in_swch")     -- SWCHA/SWCHB and their DDRs
        _G._t2 = watch(0x000C, 0x000D, "in_inpt")     -- INPT4/INPT5
        _G._t3 = watch(0x003C, 0x003D, "in_inptm")    -- and their mirror
    end
    -- A GATE THAT PRESSES NOTHING PROVES NOTHING: drive everything, so any
    -- site that still reads a port has something to read.
    local f = manager.machine.time.seconds
    for _, n in ipairs({"P1 Right", "P1 Left", "P1 Up", "P1 Down", "P1 Button 1",
                        "P2 Right", "P2 Left", "P2 Button 1"}) do
        if fields[n] then fields[n]:set_value((math.floor(f * 7) % 3 == 0) and 1 or 0) end
    end
    if fields["Select Game"] then
        fields["Select Game"]:set_value((math.floor(f * 2) % 5 == 0) and 1 or 0)
    end
end)

_G._in_stop = emu.add_machine_stop_notifier(function()
    local ks = {}
    for k in pairs(hits) do ks[#ks + 1] = k end
    table.sort(ks)
    print(string.format("INPUTS %d console-port reads from %d distinct sites",
                        reads, #ks))
    for _, k in ipairs(ks) do
        local bk, pc, ad = k:match("(%d+)/(%x+)/(%x+)")
        print(string.format("  bank %s PC $%s reading $%s  %d times", bk, pc, ad, hits[k]))
    end
end)
