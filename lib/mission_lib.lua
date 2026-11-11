-- Shared helpers. The sandbox has no pairs, next, string.match or math.random.
local lib = {}

-- A nil constant would end an ipairs list early and hide the missing name.
function lib.one(value, name)
    assert(value ~= nil, "missing mission constant: " .. name)
    return value
end

function lib.list(...)
    local values = {...}
    for index = 1, select("#", ...) do
        assert(values[index] ~= nil, "mission list entry " .. index .. " is missing")
    end
    return values
end

-- All scopes share the native mission variable and timer stores.
local Scope = {}
Scope.__index = Scope

function Scope:key(name)
    return self.tag .. "." .. name
end

function Scope:variable(name)
    return self.state:variable(self:key(name))
end

function Scope:set_variable(name, value)
    self.context:set_variable(self:key(name), value)
end

function Scope:clear_variable(name)
    return self.context:clear_variable(self:key(name))
end

function Scope:start_timer(name, milliseconds)
    return self.context:start_timer(self:key(name), milliseconds)
end

function Scope:cancel_timer(name)
    return self.context:cancel_timer(self:key(name))
end

function lib.scope(context, state, tag)
    assert(type(tag) == "string" and #tag > 0, "a scope needs a tag")
    return setmetatable({context = context, state = state, tag = tag}, Scope)
end

--- @return The unprefixed timer name when this tag owns it, otherwise nil.
function lib.timer_name(tag, elapsed)
    if type(elapsed) ~= "string" then
        return nil
    end
    local head = tag .. "."
    if string.sub(elapsed, 1, #head) ~= head then
        return nil
    end
    return string.sub(elapsed, #head + 1)
end

--- @return True when the event names this slot.
function lib.is_slot(context, event, slot)
    return event.slot ~= nil and event.slot.id == context:slot(slot).id
end

function lib.place_all(context, squads, mode)
    for _, squad in ipairs(squads) do
        context:squad(squad):place{mode = mode}
    end
end

---@class Unit
---@field squad string Squad id.
---@field slot string|nil Squad sensor slot reporting its state.
---@field counts integer[]|nil Explicit member counts per authored lane.
---@field cap integer|nil Upper bound per lane applied to the authored counts.
---@field objective string|nil Combat objective slot assigned before the placement.
---@field task_group integer|nil Task group of that objective.
---@field spawn_rule string|nil Spawn rule slot.
---@field member string|nil Combatant slot bound to the squad after the placement.

--- Places one unit: counts, objective, spawn rule and member binding; returns the request.
---@param unit Unit
---@return userdata placement Placement request; existing callers may ignore the second return.
---@return userdata|nil assignment Objective request, when the unit has an objective.
function lib.place_unit(context, unit, mode)
    local squad = context:squad(unit.squad)
    local counts = squad:counts()
    if unit.counts ~= nil then
        assert(#unit.counts == counts.count, "unit counts must match the authored lanes")
        for index, value in ipairs(unit.counts) do counts:set(index, value) end
    elseif unit.cap ~= nil then
        local authored = squad.default_counts
        for index = 1, counts.count do
            if (authored[index] or 0) > unit.cap then counts:set(index, unit.cap) end
        end
    end
    local assignment
    if unit.objective ~= nil then
        assignment = context:slot(unit.slot):assign_combat_objective{
            objective = context:slot(unit.objective), task_group = unit.task_group,
        }
    end
    local request = squad:place{counts = counts, mode = mode,
        spawn_rule = unit.spawn_rule ~= nil and context:slot(unit.spawn_rule) or nil}
    if unit.member ~= nil then context:slot(unit.member):bind_combatant_to_squad() end
    return request, assignment
end

--- Retires every member of a squad with zero counts; returns the request.
function lib.retire_squad(context, squad_id)
    local squad = context:squad(squad_id)
    local counts = squad:counts()
    for index = 1, counts.count do
        counts:set(index, 0)
    end
    return squad:place{counts = counts, mode = context.sdk.squad_modes.replace}
end

function lib.activate_scenes(context, scenes)
    for _, scene in ipairs(scenes) do
        context:scene(scene):activate{}
    end
end

-- A sensor holds one state. Its object must be active first.
function lib.play_idles(context, idles)
    for _, idle in ipairs(idles) do
        context:slot(idle.sensor):play_performance{state = idle.state}
    end
end

return lib
