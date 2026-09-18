-- tree.lua -- is the countdown really shown DGLEAD frames early?
--
-- This is the gate for the one thing in this port that Combat has no analogue
-- for, and it is the ONLY gate that can catch the lead computed in the wrong
-- direction. Countdown runs $9F down to 0 and zero IS green, so "ahead" means
-- SUBTRACTING the lead. Add it instead and the tree shows LATE, which looks
-- exactly like network lag, and every synchronisation gate in the ladder still
-- passes -- the two consoles agree perfectly about a tree that is wrong on both.
--
-- The beep is what it measures, because the beep is unambiguous. $F24E writes
-- $18 to AUDV0,X and nothing else does, so a write tap filtered on that value
-- fires exactly when a tree stage sounds. Stock beeps when Countdown is a
-- multiple of 16; with a lead of L it must beep when Countdown - L is.
local mem
local beeps = {}
local lead, netted = nil, nil
local cds = {}
local frames = 0
local fields = {}
for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end

_G._tr_frame = emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
        _G._tr_beep = mem:install_write_tap(0x0019, 0x001A, "tr_beep",
            function(offset, data, mask)
                if (data & 0xFF) == 0x18 then
                    beeps[#beeps + 1] = mem:read_u8(0x008D)
                end
                return data
            end)
        -- Countdown must still be STOCK's sequence: the lead is a display
        -- offset and nothing in the simulation may move because of it.
        _G._tr_cd = mem:install_write_tap(0x008D, 0x008D, "tr_cd",
            function(offset, data, mask)
                cds[#cds + 1] = data & 0xFF
                return data
            end)
    end
    frames = frames + 1
    -- LATCHED, not sampled at stop. When the rig tears down, one console
    -- exits first and the other's stall watchdog saturates, DGGONE clears
    -- DGE_NET, and a reading taken at the end says the match never happened.
    -- The same applies to the lead, which DGGONE leaves behind.
    if (mem:read_u8(0x00DA) & 0x02) ~= 0 then
        netted = true
        lead = mem:read_u8(0x00E2)
    elseif netted == nil then
        netted = false
        lead = mem:read_u8(0x00E2)
    end
    -- stage a race every few seconds and hold the throttle off, so the tree
    -- runs its whole length undisturbed
    if fields["P1 Right"] then
        fields["P1 Right"]:set_value(((frames // 420) % 2 == 1) and 1 or 0)
    end
end)

_G._tr_stop = emu.add_machine_stop_notifier(function()
    local L = lead or 0
    print(string.format("TREE lead=%d networked=%s beeps=%d",
                        L, tostring(netted), #beeps))
    -- every beep must land where the LED value is a multiple of 16
    local bad, seen = 0, {}
    for _, cd in ipairs(beeps) do
        local led = cd - L
        if led < 0 then led = 0 end
        if (led % 16) ~= 0 then bad = bad + 1 end
        seen[cd] = true
    end
    local vals = {}
    for k in pairs(seen) do vals[#vals + 1] = k end
    table.sort(vals, function(x, y) return x > y end)
    local out = {}
    for _, v in ipairs(vals) do out[#out + 1] = string.format("%02X", v) end
    print("TREE beep Countdown values: " .. table.concat(out, " "))
    print(string.format("TREE beeps off the lead: %d", bad))
    -- and the countdown itself: stock writes $9F then decrements by one
    local steps, jumps = 0, 0
    for i = 2, #cds do
        if cds[i] == cds[i-1] - 1 then steps = steps + 1
        elseif cds[i] ~= 0x9F and cds[i] ~= 0 then jumps = jumps + 1 end
    end
    print(string.format("TREE countdown: %d single steps, %d irregular", steps, jumps))
end)
