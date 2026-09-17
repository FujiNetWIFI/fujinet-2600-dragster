-- stage.lua -- stage a race and drive it, to prove the patched input path.
--
-- Dragster's controls: joystick RIGHT alone restages from idle, the button is
-- the throttle, and up/down shift gear. This presses right to stage, waits out
-- the countdown, then holds the throttle and watches the car move.
--
-- Input is driven from a FRAME NOTIFIER and never from a memory tap: a
-- set_value from inside a tap is silently lost, and the fields are looked up
-- ONCE at load time because a field fetched at press time is a fresh wrapper.
local mem
local fields = {}
local frames = 0
local log = {}

for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do
        fields[name] = field
    end
end

local function press(name, on)
    local f = fields[name]
    if f then f:set_value(on and 1 or 0) end
end

emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
    end
    frames = frames + 1

    -- 30..60  joystick right: stage the race
    -- 61..    release, let the tree run down, then hold the throttle
    press("P1 Right", frames >= 30 and frames <= 60)
    press("P1 Button 1", frames > 75)

    if frames % 20 == 0 then
        log[#log+1] = string.format(
            "f%-4d Countdown=%02X Rpm=%02X Gear=%02X Speed=%02X TrackPos=%02X "..
            "TimeSec=%02X TimeHun=%02X Blown=%02X Done=%02X",
            frames,
            mem:read_u8(0x008D), mem:read_u8(0x00A8), mem:read_u8(0x00CC),
            mem:read_u8(0x00C0), mem:read_u8(0x00BA), mem:read_u8(0x00B3),
            mem:read_u8(0x00B5), mem:read_u8(0x00CE), mem:read_u8(0x00D2))
    end
end)

emu.register_stop(function()
    for _, l in ipairs(log) do print(l) end
end)
