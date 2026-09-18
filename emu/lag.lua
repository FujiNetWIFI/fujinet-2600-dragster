-- lag.lua -- the interception proof.
--
-- `make inputs` shows that every console-port READ comes from inside the shim.
-- It does not show that the game is actually USING what the shim wrote: a build
-- that read the port in the right place and then let the original code read the
-- hardware somewhere the tap did not cover would pass it.
--
-- So this is the dynamic half. Built with DGLAG=1 the shim refreshes its
-- shadows once every DGLAGM+1 frames instead of every frame, and Dragster
-- should then answer the stick in visible steps about a second apart. If it
-- answers smoothly, something is still reading a live port.
local mem
local changes, frames = 0, 0
local last = nil
local fields = {}
for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end

_G._lg_frame = emu.add_machine_frame_notifier(function()
    if not mem then mem = manager.machine.devices[":maincpu"].spaces["program"] end
    frames = frames + 1
    -- wiggle the stick every few frames, far faster than the shadows can follow
    local on = (frames % 6) < 3
    for _, n in ipairs({"P1 Right", "P1 Left", "P1 Button 1"}) do
        if fields[n] then fields[n]:set_value(on and 1 or 0) end
    end
    local now = string.format("%02X%02X%02X%02X",
        mem:read_u8(0x00AD), mem:read_u8(0x00AE),
        mem:read_u8(0x00E5), mem:read_u8(0x00E6))
    if last ~= nil and now ~= last then changes = changes + 1 end
    last = now
end)

_G._lg_stop = emu.add_machine_stop_notifier(function()
    local per_sec = frames > 0 and (changes * 59.92 / frames) or 0
    print(string.format("LAG %d frames, shadows changed %d times (%.2f a second)",
                        frames, changes, per_sec))
    -- DGLAGM is $3F, so a refresh is one frame in 64: about 0.94 a second, and
    -- the stick is being wiggled ten times a second. Anything near the wiggle
    -- rate means a live port is still being read somewhere.
    print((per_sec < 6) and "LAG PASS" or "LAG FAIL")
end)
