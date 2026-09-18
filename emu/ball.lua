-- ball.lua -- the decimal point, which looks like a hazard and is not.
--
-- Dragster never writes RESBL by name. The ball is positioned as a SIDE EFFECT:
-- StageRace ends `TAX` with A = $04 and enters PositionSprites at $F4E9, which
-- skips its `LDX #$00` -- so `STA $20,X` and `STA $10,X` land on HMBL and RESBL
-- instead of HMP0 and RESP0, anchored by the STA WSYNC at $F511, and the
-- `CPX #$02 / BCC` then falls straight out with X = 5.
--
-- That makes it deterministic, and every path into a race goes through
-- StageRace -- so it is not a design constraint. It is still worth a cheap
-- guard, because the mechanism is invisible in the source and the first person
-- to relay a hole could break it without noticing.
--
-- What is measured is the SHAPE of the strobe: how many WSYNCs stand between
-- the countdown being armed and RESBL being hit, and how many cycles' worth of
-- the DEY/BPL delay loop ran. Both are fixed by the code path, and both change
-- if the path changes. MAME binds neither screen:hpos() nor the CPU's cycle
-- count to Lua, so the raster column itself cannot be read directly.
local mem
local wsyncs, staged = 0, 0
local shots = {}
local last9f = nil
local fields = {}
for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end

_G._bl_frame = emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
        _G._bl_ws = mem:install_write_tap(0x0002, 0x0002, "bl_wsync",
            function(offset, data, mask) wsyncs = wsyncs + 1; return data end)
        _G._bl_cd = mem:install_write_tap(0x008D, 0x008D, "bl_cd",
            function(offset, data, mask)
                if (data & 0xFF) == 0x9F then last9f = wsyncs; staged = staged + 1 end
                return data
            end)
        _G._bl_bl = mem:install_write_tap(0x0014, 0x0014, "bl_resbl",
            function(offset, data, mask)
                if last9f ~= nil then
                    shots[#shots + 1] = wsyncs - last9f
                    last9f = nil
                end
                return data
            end)
    end
    local f = manager.machine.time.seconds
    if fields["P1 Right"] then
        fields["P1 Right"]:set_value((math.floor(f * 3) % 4 == 0) and 1 or 0)
    end
end)

_G._bl_stop = emu.add_machine_stop_notifier(function()
    local seen, vals = {}, {}
    for _, v in ipairs(shots) do
        if not seen[v] then seen[v] = 0; vals[#vals + 1] = v end
        seen[v] = seen[v] + 1
    end
    table.sort(vals)
    local o = {}
    for _, v in ipairs(vals) do o[#o + 1] = string.format("%d:%d", v, seen[v]) end
    print(string.format("BALL %d races staged, %d RESBL strobes, WSYNCs from "..
                        "the stage to the strobe: %s",
                        staged, #shots, table.concat(o, " ")))
end)
