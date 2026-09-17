-- drive.lua -- find the input sequence that actually drives a Dragster.
local mem
local fields = {}
local frames = 0
local log = {}
for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end
local function set(n, v) if fields[n] then fields[n]:set_value(v and 1 or 0) end end

_G._d_frame = emu.add_machine_frame_notifier(function()
    if not mem then mem = manager.machine.devices[":maincpu"].spaces["program"] end
    frames = frames + 1
    local f = frames
    -- stage at 60-90, green at ~250, then: shift up once, then throttle
    -- THE GEAR LEVER IS THE STICK PULLED LEFT, and it is pull-AND-RELEASE:
    -- pulling left sets bit 7 of Gear (the shift in progress), releasing it
    -- increments the gear. Releasing while the tree is still counting is the
    -- jump start that puts EARLY on the screen.
    set("P1 Right", f >= 60 and f < 90)
    local function lever(a) return f >= a and f < a + 8 end
    set("P1 Left", lever(252) or lever(300) or lever(360) or lever(430))
    set("P1 Button 1", f >= 250)
    if f % 30 == 0 and f > 200 then
        log[#log+1] = string.format(
            "f%-4d cd=%02X gear=%02X rpm=%02X spd=%02X pos=%02X sub=%02X blown=%02X sec=%02X hun=%02X done=%02X",
            f, mem:read_u8(0x8D), mem:read_u8(0xCC), mem:read_u8(0xA8),
            mem:read_u8(0xC0), mem:read_u8(0xBA), mem:read_u8(0xC2),
            mem:read_u8(0xCE), mem:read_u8(0xB3), mem:read_u8(0xB5), mem:read_u8(0xD2))
    end
end)
_G._d_stop = emu.add_machine_stop_notifier(function()
    for _, l in ipairs(log) do print(l) end
end)
