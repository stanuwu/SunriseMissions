-- Run from the repository root with a stock Lua 5.4; NOKRIS_HEALTH_CSV names run 11's
-- nokris-health-timeline.csv (t_ms,health_q10,...), the boss's replicated health over one fight.
package.path = "./?.lua;" .. package.path
local new_provider = require("strike_nokris.native_phase_provider")
local path = assert(os.getenv("NOKRIS_HEALTH_CSV"), "NOKRIS_HEALTH_CSV required")

local SOURCE, BOSS = "5", 7
local function damage(q, fields)
    local event = {registry_key=0xC55749AB, slot_type=1, slot_index=0, source_generation=SOURCE, health=q/1023}
    for key, value in pairs(fields or {}) do event[key] = value end
    return event
end
local sequence = 0
local function reaction(phase)
    sequence = sequence + 1
    return {source_generation=SOURCE, spawn_generation=BOSS, capture_sequence=tostring(sequence),
        native_admission="reaction", health_phase=phase}
end
-- A stand-in for the encounter model: an onset moves it into the shield stage; release() returns it.
local function fight()
    local provider = new_provider()
    local model = {source=SOURCE, epoch=1, boss=BOSS, phase=0, stage="opening_damage"}
    local status = {model=model, boss_population_available=true}
    local onsets = {}
    local function feed(event, callback)
        local inputs, reason = provider.read(event, status, callback)
        assert(not reason, reason)
        for _, input in ipairs(inputs or {}) do
            if input.kind == "phase_onset" then
                model.phase = model.phase + 1; model.stage = "shield"
                onsets[#onsets+1] = {phase=model.phase, event=event}
            end
        end
    end
    return {provider=provider, model=model, status=status, onsets=onsets, feed=feed,
        release=function() model.stage = model.phase == 3 and "final_damage" or "damage" end}
end
local function check(name, ok) assert(ok, name); print("ok  " .. name) end

-- 1. The recorded fight, server only: three onsets at the clamp levels, each exactly once.
do
    local run, expected = fight(), {879, 614, 338}
    for line in io.lines(path) do
        local q = tonumber((line:match("^%d+,(%d+),")))
        if q then
            run.feed(damage(q), "on_event_damage_state")
            if run.model.stage == "shield" then run.release() end
        end
    end
    check("recorded fight gives three server onsets", #run.onsets == 3)
    for index, onset in ipairs(run.onsets) do
        check("phase " .. index .. " at level " .. expected[index],
            onset.phase == index and math.floor(onset.event.health*1023+0.5) == expected[index])
    end
end

-- 2. The hook's gate reaction starts nothing, before or after the server's onset, and is no fault.
do
    local run = fight()
    run.feed(reaction(1), "on_event_native_reaction")
    check("native reaction alone starts nothing", #run.onsets == 0)
    run.feed(damage(879), "on_event_damage_state")
    run.feed(reaction(2), "on_event_native_reaction")
    check("server onset stands; later native reaction is ignored", #run.onsets == 1)
end

-- 3. Traffic that is not a gate.
do
    local run = fight()
    run.feed(damage(-1023), "on_event_damage_state")
    run.feed(damage(100, {registry_key=1}), "on_event_damage_state")
    run.feed(damage(100, {slot_index=20}), "on_event_damage_state")
    run.feed(damage(100, {source_generation="6"}), "on_event_damage_state")
    run.feed(damage(900), "on_event_damage_state")
    check("unobserved, foreign and above-floor levels start nothing", #run.onsets == 0)
end

-- 4. A gate crossed while the previous release is still in flight is held, then started.
do
    local run = fight()
    run.feed(damage(879), "on_event_damage_state")
    run.model.stage = "releasing"; run.status.attachment = {active=false}
    run.feed(damage(614), "on_event_damage_state")
    check("crossing during release is held", #run.onsets == 1)
    run.model.stage = "damage"
    run.feed({}, "settle")
    check("held crossing starts on the next settle", #run.onsets == 2 and run.onsets[2].phase == 2)
end
print("ok")
