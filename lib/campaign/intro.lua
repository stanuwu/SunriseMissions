-- Opening cutscenes: each runs in its own state, in list order, before the first leg.
local lib = require("lib.mission_lib")

local intro = {name = "intro"}

local PLAYING, ENDED = 1, 2

function intro.check(content)
    for index, cut in ipairs(content.intro or {}) do
        lib.one(cut.state, "intro " .. index .. " state")
        lib.one(cut.cinematic, "intro " .. index .. " cinematic")
    end
end

function intro.declare(content, builder)
    local cuts = content.intro or {}
    local function key(index)
        return content.key .. ".intro." .. index
    end
    local function done(state)
        return #cuts == 0 or state:variable(key(#cuts)) == ENDED
    end
    builder:provide("intro", {count = #cuts, done = done, key = key})
end

function intro.build(content, builder)
    local cuts = content.intro or {}
    local first = content.legs[1]
    local service = builder:need("intro")
    local key, done = service.key, service.done
    if #cuts > 0 then builder.initial.region_index = cuts[1].state.region_index end

    -- The client holds the cutscene's region, so only the start is owed.
    local function start(context, state, region)
        for index, cut in ipairs(cuts) do
            if cut.state.region_index == region and state:variable(key(index)) == nil then
                context:set_variable(key(index), PLAYING)
                context:slot(cut.cinematic):set_cinematic_active{active = true}
            end
        end
    end
    -- The client places a spawn at the body's last position, so a body built in a cutscene region
    -- lands inside the first leg's geometry. Holding the spawn until the last cutscene ends means
    -- there is no body to place, and the arrival picks its own point as a launch does.
    local function select_after(context, index)
        if index < #cuts then
            context:select_state(cuts[index + 1].state)
        else
            context:select_state(first.state, builder:need("core").omit)
            context:hold_spawn{active = false}
        end
    end
    local function finish(context, state, index)
        if state:variable(key(index)) == ENDED then return end
        context:set_variable(key(index), ENDED)
        -- Stop before the state change, or the rebuilt component plays the cutscene again.
        context:slot(cuts[index].cinematic):set_cinematic_active{active = false}
        select_after(context, index)
    end
    -- Ends the playing cutscene the reported slot names.
    local function finish_reported(context, state, event)
        for index, cut in ipairs(cuts) do
            if state:variable(key(index)) == PLAYING
                and lib.is_slot(context, event, cut.cinematic) then
                finish(context, state, index)
            end
        end
    end

    builder:on_start(function(context)
        if #cuts > 0 then context:hold_spawn{active = true} end
    end)
    -- A reattach lands in the world, so a cutscene still marked playing is ended, not replayed.
    builder:on_load(function(context, state)
        for index in ipairs(cuts) do
            if state:variable(key(index)) == PLAYING then finish(context, state, index) end
        end
        local core = builder:need("core")
        if #cuts > 0 and done(state) and not core.graph():fact(context, state, "arrival") then
            context:select_state(first.state, core.omit)
        end
    end)
    builder:on("on_event_region_changed", function(context, state, event)
        start(context, state, event.region_index)
    end)
    builder:on("on_event_client_state_changed", function(context, state, event)
        if event.entered == true then start(context, state, event.held_region_index) end
    end)
    -- End and a refused start arrive here; a skip request has its own event kind. Both end the
    -- cutscene, or a skipped intro never releases the held spawn.
    builder:on("on_event_cinematic_terminated", finish_reported)
    builder:on("on_event_cinematic_skip_requested", finish_reported)
end

return intro
