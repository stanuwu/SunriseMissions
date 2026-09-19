-- Cutscenes a step, an encounter or a sequence item plays during the mission:
--   cutscene = {state = mission.states.<cutscene state>, cinematic = Slot.<type-6 slot>,
--               after = mission.states.<state to land in>}
-- A cinematic plays only while the client holds the state that owns it, so the cutscene selects
-- that state first and starts on the held report. Its end or a skip request stops it, then the
-- client moves to `after` and lands on that state's default spawn. The cutscene has ended once the
-- client holds `after`, since a goal sent before then names a target the client cannot reach.
-- A step can end once its cutscene has ended: `ends = {cutscene = true}`. Opening cutscenes stay
-- in `intro`.
local lib = require("lib.mission_lib")
local common = require("lib.campaign.common")

local cutscenes = {name = "cutscenes"}

local SELECTING, PLAYING, LANDING, ENDED = 1, 2, 3, 4

local function state_of(value, where)
    assert(type(value) == "table" and math.type(value.region_index) == "integer",
        where .. " must name a generated mission state")
end

-- Each cutscene owns one variable holding how far it has come.
local function collect(content)
    local cuts, cut_of = {}, {}
    for _, place in ipairs(common.holders(content)) do
        local cut = place.holder.cutscene
        if cut ~= nil then
            local entry = {cut = cut, key = content.key .. ".cut." .. (#cuts + 1)}
            cuts[#cuts + 1] = entry
            cut_of[place.holder] = entry
        end
    end
    return cuts, cut_of
end

function cutscenes.check(content)
    for _, place in ipairs(common.holders(content)) do
        local cut = place.holder.cutscene
        if cut ~= nil then
            local where = place.where .. " cutscene"
            assert(type(cut) == "table", where .. " must be a table")
            state_of(cut.state, where .. " state")
            lib.one(cut.cinematic, where .. " cinematic")
            if cut.after ~= nil then state_of(cut.after, where .. " after") end
        end
    end
    for _, step in ipairs(content.steps or {}) do
        if step.ends ~= nil and step.ends.cutscene ~= nil then
            assert(step.ends.cutscene == true and step.cutscene ~= nil,
                "step " .. tostring(step.id) .. " ends on a cutscene it does not play")
        end
    end
end

function cutscenes.declare(content, builder)
    local cuts, cut_of = collect(content)
    if #cuts == 0 then return end
    builder:action("cutscene", function(context, _, holder, cut)
        context:set_variable(cut_of[holder].key, SELECTING)
        context:select_state(cut.state)
    end)
    builder:end_kind("cutscene", function(step)
        local key = cut_of[step].key
        return {function(_, state) return state:variable(key) == ENDED end}
    end)
end

function cutscenes.build(content, builder)
    local cuts = collect(content)
    if #cuts == 0 then return end

    local function held(context, state, region)
        for _, entry in ipairs(cuts) do
            local progress = state:variable(entry.key)
            if progress == SELECTING and entry.cut.state.region_index == region then
                context:set_variable(entry.key, PLAYING)
                context:slot(entry.cut.cinematic):set_cinematic_active{active = true}
            elseif progress == LANDING and entry.cut.after.region_index == region then
                context:set_variable(entry.key, ENDED)
                builder:advance(context, state)
            end
        end
    end
    -- Stop before the state change, or the rebuilt component plays the cutscene again.
    local function finish(context, state, entry)
        context:slot(entry.cut.cinematic):set_cinematic_active{active = false}
        if entry.cut.after == nil then
            context:set_variable(entry.key, ENDED)
            builder:advance(context, state)
            return
        end
        context:set_variable(entry.key, LANDING)
        context:select_state(entry.cut.after)
    end
    local function finish_reported(context, state, event)
        for _, entry in ipairs(cuts) do
            if state:variable(entry.key) == PLAYING
                and lib.is_slot(context, event, entry.cut.cinematic) then
                finish(context, state, entry)
            end
        end
    end

    builder:on("on_event_client_state_changed", function(context, state, event)
        if event.held_region_index ~= nil then held(context, state, event.held_region_index) end
    end)
    builder:on("on_event_region_changed", function(context, state, event)
        held(context, state, event.region_index)
    end)
    -- End and a refused start arrive here; a skip request has its own event kind.
    builder:on("on_event_cinematic_terminated", finish_reported)
    builder:on("on_event_cinematic_skip_requested", finish_reported)
    -- A reattach lands in the world, so a cutscene still playing is ended, not replayed.
    builder:on_load(function(context, state)
        for _, entry in ipairs(cuts) do
            if state:variable(entry.key) == PLAYING then finish(context, state, entry) end
        end
    end)
end

return cutscenes
