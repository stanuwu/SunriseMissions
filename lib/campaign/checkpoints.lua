-- Wipes restart the party at the checkpoint of the leg it is in.
-- A leg names the spawn set a wipe in its region restarts at with `spawn_set`. The steps a restart
-- replays are the core's checkpoints; before any checkpoint, a restart replays from the arrival.
-- When the whole party is dead in such a leg, the restart arms at its set. The accepted request
-- opens the new attempt, and its release answers the client's wait. Every graph holds still until
-- the party is up again, so the removals and the replay reach the client apart. A new attempt
-- clears every timer, so beats replay through their graphs.
local checkpoints = {name = "checkpoints"}

function checkpoints.check(content)
    for _, leg in ipairs(content.legs or {}) do
        local set = leg.spawn_set
        assert(set == nil or (math.type(set) == "integer" and set > 0 and set <= 0xFFFFFFFF),
            "leg " .. tostring(leg.id) .. " spawn_set must be a 32-bit hash")
    end
end

-- `restarts` tells the core to keep the arrival as a checkpoint.
function checkpoints.declare(content, builder)
    local restarts = false
    for _, leg in ipairs(content.legs or {}) do restarts = restarts or leg.spawn_set ~= nil end
    builder:provide("checkpoints", {restarts = restarts})
end

function checkpoints.build(content, builder)
    local legs = {}
    for _, leg in ipairs(content.legs) do
        if leg.spawn_set ~= nil then legs[#legs + 1] = leg end
    end
    if #legs == 0 then return end
    local REGION = content.key .. ".cp.region"
    local LEG = content.key .. ".cp.leg"
    local REQUEST = content.key .. ".cp.request"
    local RESPAWNING = content.key .. ".cp.respawning"

    local function restart(context, index, release)
        local leg = legs[index]
        return context:restart_checkpoint{region = leg.state.region_index,
            spawn_set_hash = leg.spawn_set, release_request = release}
    end
    local function respawned(context, state)
        context:clear_variable(RESPAWNING)
        builder:advance(context, state)
    end
    builder:hold(function(_, state) return state:variable(RESPAWNING) == true end)

    -- The restart must name the region the party is in, so the last region it held is kept.
    builder:on("on_event_client_state_changed", function(context, _, event)
        local region = event.held_region_index
        if region ~= nil and region >= 0 then context:set_variable(REGION, region) end
    end)
    builder:on("on_event_region_changed", function(context, _, event)
        if event.region_index ~= nil then context:set_variable(REGION, event.region_index) end
    end)
    -- The restart is the callback's only request, so the wipe starts at once.
    builder:on("on_event_fireteam_state", function(context, state, event)
        if state:variable(RESPAWNING) == true then
            if event.alive_count > 0 then respawned(context, state) end
            return
        end
        local wiped = event.dead_count > 0 and event.alive_count == 0 and event.unknown_count == 0
        if not wiped or state:variable(REQUEST) ~= nil then return end
        local region = state:variable(REGION)
        for index, leg in ipairs(legs) do
            if leg.state.region_index == region then
                context:set_variable(LEG, index)
                context:set_variable(REQUEST, restart(context, index).value)
                return
            end
        end
    end)
    -- The accepted restart opens the new attempt; releasing it lets the client respawn.
    builder:on("on_event_effect_result", function(context, state, event)
        local request = state:variable(REQUEST)
        if request == nil or event.request_key == nil or event.request_key.value ~= request then
            return
        end
        context:clear_variable(REQUEST)
        if event.outcome ~= "transport_staged" then return end
        restart(context, state:variable(LEG), request)
        context:set_variable(RESPAWNING, true)
    end)
    -- A trigger report also means the player is up again.
    builder:on("on_event_player_trigger", function(context, state)
        if state:variable(RESPAWNING) == true then respawned(context, state) end
    end)
end

return checkpoints
