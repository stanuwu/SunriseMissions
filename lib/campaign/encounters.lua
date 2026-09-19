-- Encounters: squads placed once their step has started and their trigger or monitor reported.
-- They live in a second graph, so each graph stays inside the step and fact limits.
local lib = require("lib.mission_lib")
local flow = require("lib.flow")
local common = require("lib.campaign.common")
local speak = common.speak

local encounters = {name = "encounters"}

-- Assign the objective before the placement. A squad body that changes after its members exist
-- reports alive 0 for about a second, and a cohort reads that as cleared. A unit with a count
-- places every member lane at that count instead of the package default. A unit with no group of
-- its own starts on the approach group, when the holder names one.
local function place_units(context, objective, units, approach)
    for _, unit in ipairs(units or {}) do
        if objective ~= nil then
            context:slot(unit.source):assign_combat_objective{
                objective = context:slot(objective), task_group = unit.group or approach,
            }
        end
        local squad = context:squad(unit.squad)
        local request = {}
        if unit.count ~= nil then
            local counts = squad:counts()
            for lane = 1, counts.count do counts:set(lane, unit.count) end
            request.counts = counts
        end
        squad:place(request)
    end
end

local function populate(content, builder, context, state, encounter)
    place_units(context, encounter.objective, encounter.squads, encounter.approach)
    speak(content, context, encounter)
    builder:run_actions(context, state, encounter)
    if encounter.on_start ~= nil then encounter.on_start(context) end
end

function encounters.check(content, builder)
    local legs = builder:need("legs")
    for _, place in ipairs(common.holders(content)) do
        local squads = place.holder.place
        if squads ~= nil then
            assert(place.item, place.where .. " place belongs in a sequence item")
            assert(type(squads.squads) == "table" and #squads.squads > 0,
                place.where .. " place needs a nonempty squad list")
        end
        local assign = place.holder.assign
        if assign ~= nil then
            lib.one(assign.objective, place.where .. " assign objective")
            assert(type(assign.group) == "table" and assign.group.group_index ~= nil,
                place.where .. " assign needs one mission.TaskGroup group")
            assert(type(assign.squads) == "table" and #assign.squads > 0,
                place.where .. " assign needs a nonempty squad list")
        end
    end
    for _, encounter in ipairs(content.encounters or {}) do
        lib.one(encounter.id, "encounter id")
        assert(legs.step_ids[encounter.after or "arrival"],
            encounter.id .. " waits on an unknown step")
        if encounter.trigger ~= nil then
            assert(legs.armed[encounter.trigger], encounter.id .. " waits on a trigger no leg arms")
        end
        if encounter.monitor ~= nil then
            assert(legs.watched[encounter.monitor],
                encounter.id .. " waits on a monitor no leg watches")
        end
    end
end

function encounters.declare(content, builder)
    -- Gives squads already alive their group. A new evaluation would move them onto their task,
    -- so it keeps the revision the placement or the performance left.
    builder:action("assign", function(context, _, _, assign)
        for _, unit in ipairs(assign.squads) do
            context:slot(unit.source):assign_combat_objective{
                objective = context:slot(assign.objective), task_group = assign.group}
        end
    end)
    -- A sequence item places its own squads later than its encounter does.
    builder:action("place", function(context, _, _, place)
        place_units(context, place.objective, place.squads, place.approach)
    end)
    local placed = {}
    for _, encounter in ipairs(content.encounters or {}) do placed[encounter.id] = encounter end
    -- `graph` is the placement graph, set by build; nil when no encounter declares a placement.
    local service = {}
    --- @return A condition that holds once every squad of the named encounters is gone.
    function service.cleared(ids)
        local squads = {}
        for _, id in ipairs(ids) do
            for _, unit in ipairs(lib.one(placed[id], "encounter " .. id).squads) do
                squads[#squads + 1] = unit.squad
            end
        end
        return function(context) return context:cohort{squads = squads}.cleared end
    end
    --- @return True once the named encounter has placed in this attempt.
    function service.placed(context, state, id)
        return service.graph ~= nil and service.graph:started(context, state, id)
    end
    builder:provide("encounters", service)
end

function encounters.build(content, builder)
    local facts, fact_of, graph = {}, {}, nil
    for _, encounter in ipairs(content.encounters or {}) do
        local source = encounter.trigger or encounter.monitor
        if source ~= nil and fact_of[source] == nil then
            local id = "t" .. (#facts + 1)
            fact_of[source] = id
            facts[#facts + 1] = {id = id, observe = function(context, _, event)
                return lib.is_slot(context, event, source)
            end}
        end
    end
    -- Trigger facts latch, so an encounter whose trigger fired early places once its step starts.
    local core = builder:need("core")
    local placements = {}
    for _, encounter in ipairs(content.encounters or {}) do
        local after = encounter.after or "arrival"
        local source = encounter.trigger or encounter.monitor
        -- The arrival step is waiting from the start, so arrival itself must have happened.
        local function begun(context, state)
            if after == "arrival" then return core.graph():fact(context, state, "arrival") end
            return core.graph():started(context, state, after)
        end
        local when = function(context, state)
            return begun(context, state) and (source == nil
                or graph:fact(context, state, fact_of[source]))
        end
        placements[#placements + 1] = {id = encounter.id, when = when,
            run = function(context, state)
                populate(content, builder, context, state, encounter)
            end}
    end
    if #placements > 0 then
        graph = flow.new{key = content.key .. ".enc", facts = facts, steps = placements}
        builder:graph(graph)
        builder:need("encounters").graph = graph
    end
end

return encounters
