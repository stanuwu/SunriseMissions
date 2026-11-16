-- Shared squad placement for public events; live tracking stays in the host scope.
local lib = require("lib.mission_lib")

local squads = {}

-- The objective request has its own retained key beside the placement request.
local OBJECTIVE_SUFFIX = ".o"

--- Appends placement and objective keys to a retained or required request list.
---@param keys string[] Receives placement and objective keys.
---@param key string Placement key within the event scope.
function squads.append_request_keys(keys, key)
    keys[#keys + 1] = key
    keys[#keys + 1] = key .. OBJECTIVE_SUFFIX
end

--- True when a request identity matches this unit's retained placement or objective request.
function squads.owns_request(scope, key, request)
    return scope:variable(key) == request.value
        or scope:variable(key .. OBJECTIVE_SUFFIX) == request.value
end

--- Replaces a unit and retains its placement and optional objective request separately.
---@param unit Unit
---@param key string Placement key within the event scope.
---@param temperaments table[]|nil The squad's new temperament list; nil keeps its last list.
---@return userdata request Placement request; staging does not confirm client execution.
function squads.place(context, scope, unit, key, temperaments)
    local request, assignment =
        lib.place_unit(context, unit, context.sdk.squad_modes.replace, temperaments)
    scope:set_variable(key, request.value)
    if assignment ~= nil then
        scope:set_variable(key .. OBJECTIVE_SUFFIX, assignment.value)
    else
        scope:clear_variable(key .. OBJECTIVE_SUFFIX)
    end
    return request
end

--- True when a generation's terminal counts cover the unit's requested nonempty population.
---@param context table Borrowed callback context.
---@param unit Unit Authored unit with optional counts or cap.
---@param report table Count-only native report with spawn_generation and slot_counts.
---@return boolean ended Whether every requested member has ended.
function squads.counted_out(context, unit, report)
    if report.spawn_generation == nil or report.slot_counts == nil then return false end
    local squad = context:squad(unit.squad)
    local expected, total = unit.counts or squad.default_counts, 0
    for index = 1, squad.member_count do
        local count = expected[index] or 0
        if unit.counts == nil and unit.cap ~= nil then count = math.min(count, unit.cap) end
        if (report.slot_counts[index] or 0) < count then return false end
        total = total + count
    end
    return total > 0
end

--- Removes a squad using zero authored member counts.
function squads.retire(context, squad)
    lib.retire_squad(context, squad)
end

--- Retires a unit once while its placement request is retained. Clears only the placement key.
function squads.retire_if_placed(context, scope, unit, key)
    if scope:variable(key) == nil then return end
    squads.retire(context, unit.squad)
    scope:clear_variable(key)
end

---@class SquadUnit : Unit
---@field pods table Pod object slots the squad spawns from; empty for automatic placements.
---@field group integer|nil Index of a shared pod group that units take turns dropping.

--- Drops a unit's pods; a shared pod group is re-dropped when it is already standing.
---@param unit SquadUnit
---@param standing_prefix string Retained key prefix; the group index names the standing flag.
function squads.drop(context, scope, unit, standing_prefix)
    if #unit.pods == 0 then return end
    if unit.group == nil then
        context:activate_objects{slots = unit.pods, active = true}
        return
    end
    local key = standing_prefix .. unit.group
    if scope:variable(key) == true then
        context:activate_objects{slots = unit.pods, active = false}
    end
    context:activate_objects{slots = unit.pods, active = true}
    scope:set_variable(key, true)
end

--- Sends one placed actor along an authored path; the request is not tracked. The runtime
--- raises an error for a path with no destination point. A flight only moves an actor that
--- already stands, so the refusal must not stop the event: it is caught and reported.
---@return boolean sent False when the runtime refused the path; the actor stays where it is.
function squads.follow_path(context, actor, path)
    return (pcall(function()
        context:slot(actor):play_actor_path{path = context:slot(path)}
    end))
end

---@class FlightLeg
---@field curve string Slot id of an authored curve.
---@field first integer First named point of the curve to fly to.
---@field last integer Last named point of the curve to fly to.

--- Sends one actor the Host holds through the named points of authored curves, in order, along
--- each curve. play_actor_path always targets point 1; a curve with more points needs its points
--- named. A refused program leaves the actor where it is and is reported, as with a path.
---@param legs FlightLeg[]
---@return boolean sent False when the runtime refused a point or the program.
function squads.fly_points(context, actor, legs)
    return (pcall(function()
        local atoms = {}
        for _, leg in ipairs(legs) do
            local target = context:slot(leg.curve)
            for point = leg.first, leg.last do
                atoms[#atoms + 1] = {kind = context.sdk.atom_kinds.move_to, target = target,
                    value = point, enabled = true}
            end
        end
        context:slot(actor):run_atoms{atoms = atoms}
    end))
end

return squads
