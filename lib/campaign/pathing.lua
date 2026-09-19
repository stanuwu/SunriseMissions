-- Pathing: an encounter that names the task groups of its objective sends each of its squads to
-- the group that costs the least. The client reports every group's cost with each squad state.
-- A squad moves when another group is cheaper and stays put on a tie, which keeps it from
-- swapping between two zones whose quantised costs alternate.
--   groups = mission.TaskGroup.<OBJECTIVE>   on an encounter that also names its `objective`, or
--                                            inside the `place` of a sequence item
--   approach = mission.TaskGroup.<OBJECTIVE>.GROUP_<n>   the same places, instead of `groups`
-- With an approach, every squad starts on that group and is assigned it again, forcing a new
-- evaluation, the first time it reports alive in an attempt. It is never moved off it, so a
-- Legionary on a jetpack group makes its own way to the firing area.
--   hold = true        on an encounter with `groups`: its squads stand where they are placed, on
--                      no group, until a `release = {"<encounter id>"}` action lets them route
local lib = require("lib.mission_lib")
local combat = require("lib.combat")
local common = require("lib.campaign.common")

local pathing = {name = "pathing"}

-- An objective owns at most 24 task groups, named GROUP_0 to GROUP_23.
local GROUP_COUNT = 24

-- The groups of one objective in index order.
local function ordered(groups)
    local list = {}
    for index = 0, GROUP_COUNT - 1 do
        local group = groups["GROUP_" .. index]
        if group ~= nil then list[#list + 1] = group end
    end
    return list
end

-- A hold lasts until its release, and both are per attempt.
local function released_key(context, id)
    return "released." .. tostring(context.attempt_generation) .. "." .. id
end

local function relink(context, event, route, unit)
    local objective = context:slot(route.objective)
    local current, assigned = event:task_group{objective = objective}
    if not assigned then return end
    local selected, known = combat.lowest_cost(event, route.groups, current)
    if not known or selected == nil or combat.same_group(selected, current) then return end
    context:slot(unit.source):assign_combat_objective{objective = objective, task_group = selected}
end

-- Each squad is sent to its approach group once per attempt and group: the mark is a mission
-- variable. The route that owns a report is the one whose group the squad was placed on.
--- @return True when the report belongs to this route.
local function reinforce(context, state, event, route, unit)
    local objective = context:slot(route.objective)
    local current, assigned = event:task_group{objective = objective}
    if not assigned or not combat.same_group(current, route.approach) then return false end
    local mark = "approach." .. tostring(context.attempt_generation) .. "." .. unit.source .. "."
        .. route.approach.group_index
    if not state:variable(mark) then
        context:set_variable(mark, true)
        context:slot(unit.source):assign_combat_objective{objective = objective,
            task_group = route.approach, reconsider = true, refresh_player_awareness = true}
    end
    return true
end

-- An encounter places its own squads; a sequence item places through `place`.
local function placing(holder)
    return holder.place or holder
end

function pathing.check(content)
    local held = {}
    for _, encounter in ipairs(content.encounters or {}) do
        if encounter.hold ~= nil then
            assert(encounter.hold == true and encounter.groups ~= nil,
                "encounter " .. tostring(encounter.id) .. " holds only with task groups")
            held[encounter.id] = true
        end
    end
    for _, place in ipairs(common.holders(content)) do
        local source = placing(place.holder)
        local release = place.holder.release
        if release ~= nil then
            assert(type(release) == "table" and #release > 0, place.where .. " release needs ids")
            for _, id in ipairs(release) do
                assert(held[id], place.where .. " releases an encounter that holds nothing: " .. id)
            end
        end
        if source.groups ~= nil then
            assert(source.objective ~= nil, place.where .. " names task groups but no objective")
            assert(type(source.groups) == "table" and #ordered(source.groups) > 0,
                place.where .. " groups must be a mission.TaskGroup entry")
        end
        if source.approach ~= nil then
            assert(source.objective ~= nil, place.where .. " names an approach but no objective")
            assert(source.groups == nil, place.where .. " takes groups or an approach, not both")
            assert(type(source.approach) == "table" and source.approach.group_index ~= nil,
                place.where .. " approach must be one mission.TaskGroup group")
        end
    end
end

function pathing.declare(content, builder)
    builder:action("release", function(context, _, _, ids)
        for _, id in ipairs(ids) do context:set_variable(released_key(context, id), true) end
    end)
end

function pathing.build(content, builder)
    local routes = {}
    for _, place in ipairs(common.holders(content)) do
        local source = placing(place.holder)
        if source.groups ~= nil or source.approach ~= nil then
            routes[#routes + 1] = {id = place.holder.id, hold = place.holder.hold,
                objective = source.objective,
                groups = source.groups ~= nil and ordered(source.groups) or nil,
                approach = source.approach, squads = source.squads or {}}
        end
    end
    if #routes == 0 then return end
    -- A squad that reports nothing alive has no position to route from.
    builder:on("on_event_squad_state", function(context, state, event)
        if event.alive_count <= 0 then return end
        for _, route in ipairs(routes) do
            for _, unit in ipairs(route.squads) do
                if lib.is_slot(context, event, unit.source) then
                    if route.approach ~= nil then
                        if reinforce(context, state, event, route, unit) then return end
                    else
                        if not route.hold or state:variable(released_key(context, route.id)) then
                            relink(context, event, route, unit)
                        end
                        return
                    end
                end
            end
        end
    end)
end

return pathing
