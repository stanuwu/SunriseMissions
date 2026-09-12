local lib = require("lib.mission_lib")

-- The berth objective has three authored groups; costs of 2040 are unreachable.
local GROUP_COUNT = 3
local UNREACHABLE_COST = 2040
-- Initial cost requests use revision 1; provocation starts a fresh pass.
local OBJECTIVE_REVISION = 1
local DECISION_PREFIX = "berth.combat."
local REVISION_PREFIX = "berth.costrev."
local PROVOKED_PREFIX = "berth.provoked."
local ALIVE_PREFIX = "berth.alive."
local HEALTH_PREFIX = "berth.health."
-- Objective revisions are positive signed 31-bit counters.
local MAXIMUM_REVISION = 2147483647
-- Squad Sense carries a six-bit live count.
local MAXIMUM_ALIVE = 63
-- Guards and cinematic actors each have eight authored squads.
local SQUADS_PER_GROUP = 8

local function alive_count(event)
    local alive = event.alive_count
    if type(alive) == "number" and alive >= 0 and alive <= MAXIMUM_ALIVE
        and alive % 1 == 0 then
        return alive
    end
    return nil
end

-- Missing costs cannot choose or clear an authored group.
local function choose_group(costs, current)
    if type(costs) ~= "table" then
        return nil
    end
    local best, lowest = -1, UNREACHABLE_COST
    for index = 1, GROUP_COUNT do
        local cost = costs[index]
        if type(cost) ~= "number" or cost ~= cost or cost < 0
            or cost > UNREACHABLE_COST then
            return nil
        end
        if cost < lowest then
            best, lowest = index - 1, cost
        end
    end
    if best >= 0 and current >= 0 and costs[current + 1] == lowest then
        return current
    end
    return best
end

return function(mission)
    local objective = lib.one(mission.Slot.OBJ_BERTH_GUARDS, "berth combat objective")
    local squads = lib.list(
        mission.Slot.SQ_BERTH_0_GUARD,
        mission.Slot.SQ_BERTH_1_GUARD,
        mission.Slot.SQ_BERTH_2_GUARD,
        mission.Slot.SQ_BERTH_3_GUARD,
        mission.Slot.SQ_BERTH_4_GUARD,
        mission.Slot.SQ_BERTH_5_GUARD,
        mission.Slot.SQ_BERTH_6_GUARD,
        mission.Slot.SQ_BERTH_7_GUARD,
        mission.Slot.SQ_BERTH_0_CINE,
        mission.Slot.SQ_BERTH_1_CINE,
        mission.Slot.SQ_BERTH_2_CINE,
        mission.Slot.SQ_BERTH_3_CINE,
        mission.Slot.SQ_BERTH_4_CINE,
        mission.Slot.SQ_BERTH_5_CINE,
        mission.Slot.SQ_BERTH_6_CINE,
        mission.Slot.SQ_BERTH_7_CINE
    )
    local scenes = {
        lib.one(mission.Scene.SCENE_BERTH_GUARD_INTRO_0, "guard scene 0"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_INTRO_1, "guard scene 1"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_INTRO_2, "guard scene 2"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_INTRO_3, "guard scene 3"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_INTRO_4, "guard scene 4"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_INTRO_5, "guard scene 5"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_INTRO_6, "guard scene 6"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_INTRO_7, "guard scene 7"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_CINE_0, "cine scene 0"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_CINE_1, "cine scene 1"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_CINE_2, "cine scene 2"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_CINE_3, "cine scene 3"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_CINE_4, "cine scene 4"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_CINE_5, "cine scene 5"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_CINE_6, "cine scene 6"),
        lib.one(mission.Scene.SCENE_BERTH_GUARD_CINE_7, "cine scene 7"),
    }
    local combatants = lib.list(
        mission.Slot.SQ_BERTH_0_GUARD_CELL_1,
        mission.Slot.SQ_BERTH_1_GUARD_CELL_1,
        mission.Slot.SQ_BERTH_2_GUARD_CELL_1,
        mission.Slot.SQ_BERTH_3_GUARD_CELL_1,
        mission.Slot.SQ_BERTH_4_GUARD_CELL_1,
        mission.Slot.SQ_BERTH_5_GUARD_CELL_1,
        mission.Slot.SQ_BERTH_6_GUARD_CELL_1,
        mission.Slot.SQ_BERTH_7_GUARD_CELL_1,
        mission.Slot.SQ_BERTH_0_CINE_CELL_1,
        mission.Slot.SQ_BERTH_1_CINE_CELL_1,
        mission.Slot.SQ_BERTH_2_CINE_CELL_1,
        mission.Slot.SQ_BERTH_3_CINE_CELL_1,
        mission.Slot.SQ_BERTH_4_CINE_CELL_1,
        mission.Slot.SQ_BERTH_5_CINE_CELL_1,
        mission.Slot.SQ_BERTH_6_CINE_CELL_1,
        mission.Slot.SQ_BERTH_7_CINE_CELL_1
    )

    local function find_squad(context, event)
        if event == nil or event.slot_type ~= 1 then
            return nil
        end
        for index, declaration in ipairs(squads) do
            local squad = context:slot(declaration)
            if event.registry_key == squad.registry_key
                and event.slot_type == squad.slot_type
                and event.slot_index == squad.slot_index then
                return squad, index
            end
        end
        return nil
    end

    local function revision_of(state, squad)
        local revision = state:variable(REVISION_PREFIX .. squad.slot_index) or OBJECTIVE_REVISION
        if type(revision) ~= "number" or revision % 1 ~= 0 or revision < 1
            or revision > MAXIMUM_REVISION then
            return nil
        end
        return revision
    end

    local function assign(context, state, squad, revision, group, refresh_awareness)
        -- The scene owns spawning even after the squad enters combat.
        squad:assign_combat_objective{
            objective = context:slot(objective), revision = revision,
            task_group = group, reserved = true,
            refresh_player_awareness = refresh_awareness or false,
        }
        if state:variable(DECISION_PREFIX .. squad.slot_index) ~= group then
            context:set_variable(DECISION_PREFIX .. squad.slot_index, group)
        end
        if state:variable(REVISION_PREFIX .. squad.slot_index) ~= revision then
            context:set_variable(REVISION_PREFIX .. squad.slot_index, revision)
        end
        return true
    end

    local function provoke(context, state, index)
        local first = ((index - 1) // SQUADS_PER_GROUP) * SQUADS_PER_GROUP + 1
        local members = {}
        for member_index = first, first + SQUADS_PER_GROUP - 1 do
            local member = context:slot(squads[member_index])
            if not state:variable(PROVOKED_PREFIX .. member.slot_index) then
                local revision = revision_of(state, member)
                if revision == nil or revision == MAXIMUM_REVISION then
                    return false
                end
                members[#members + 1] = {
                    squad = member, scene = scenes[member_index], revision = revision + 1,
                }
            end
        end
        for _, member in ipairs(members) do
            context:scene(member.scene):stop{}
            assign(context, state, member.squad, member.revision, -1, true)
            context:set_variable(PROVOKED_PREFIX .. member.squad.slot_index, true)
        end
        return #members > 0
    end

    local function injured(context, state, index, squad)
        -- These actors spawn at full primary health and have no secondary pool.
        local health = state:variable(HEALTH_PREFIX .. squad.slot_index)
        return type(health) == "number" and health >= 0 and health < 1
            and (state:variable(ALIVE_PREFIX .. squad.slot_index) or 0) > 0
            and not state:variable(PROVOKED_PREFIX .. squad.slot_index)
            and provoke(context, state, index)
    end

    -- TODO: salute at the door's half-open crossing. Only also_sighted plays an animation and a
    -- voice without ending the guard pose, and no server input reaches it: the sequence atom
    -- always builds a guard-releasing action.
    return {
        bind = function(context)
            for _, declaration in ipairs(combatants) do
                context:slot(declaration):bind_combatant_to_squad{}
            end
        end,
        -- Each scene creates its reserved member before starting the actor program.
        start_scenes = function(context, state)
            for index, declaration in ipairs(squads) do
                local squad = context:slot(declaration)
                if state:variable(PROVOKED_PREFIX .. squad.slot_index) == nil then
                    context:scene(scenes[index]):activate{}
                    context:set_variable(PROVOKED_PREFIX .. squad.slot_index, false)
                end
            end
        end,
        -- Cost calculation may run while held; a firing-area task needs actual provocation.
        on_squad_state = function(context, state, event)
            local squad, index = find_squad(context, event)
            if squad == nil then
                return false
            end
            local alive = alive_count(event)
            if alive == nil then return false end
            if state:variable(ALIVE_PREFIX .. squad.slot_index) ~= alive then
                context:set_variable(ALIVE_PREFIX .. squad.slot_index, alive)
            end
            if alive == 0 then return false end
            if injured(context, state, index, squad) then return true end
            local current = state:variable(DECISION_PREFIX .. squad.slot_index)
            local revision = revision_of(state, squad)
            if revision == nil or (current ~= nil and (type(current) ~= "number"
                or current % 1 ~= 0 or current < -1 or current >= GROUP_COUNT)) then
                return false
            end
            if not state:variable(PROVOKED_PREFIX .. squad.slot_index) then
                if current ~= -1 then
                    return assign(context, state, squad, revision, -1)
                end
                return false
            end
            if current == nil then
                return assign(context, state, squad, revision, -1)
            end
            if event.objective_revision ~= revision then
                return false
            end
            local selected = choose_group(event.task_costs, current)
            if selected == nil or selected == current then
                return false
            end
            return assign(context, state, squad, revision, selected)
        end,
        -- A verified hit provokes every squad in the same authored group.
        on_squad_provoked = function(context, state, event)
            local squad, index = find_squad(context, event)
            if squad == nil or state:variable(PROVOKED_PREFIX .. squad.slot_index) then
                return false
            end
            return provoke(context, state, index)
        end,
        on_damage_state = function(context, state, event)
            if event == nil or event.slot_type ~= 2 then return false end
            for index, declaration in ipairs(combatants) do
                local actor = context:slot(declaration)
                if actor.registry_key == event.registry_key
                    and actor.slot_index == event.slot_index then
                    local squad = context:slot(squads[index])
                    local health = event.health
                    if type(health) ~= "number" or health ~= health
                        or health < 0 or health > 1 then
                        health = -1
                    end
                    context:set_variable(HEALTH_PREFIX .. squad.slot_index, health)
                    return injured(context, state, index, squad) or false
                end
            end
            return false
        end,
        on_entity_died = function(context, state, event)
            local squad, index = find_squad(context, event)
            if squad == nil then return false end
            local previous = alive_count{alive_count = event.previous_alive_count}
            local alive = alive_count(event)
            if previous == nil or previous <= 0 or alive == nil or alive >= previous then
                return false
            end
            context:set_variable(ALIVE_PREFIX .. squad.slot_index, alive)
            return provoke(context, state, index)
        end,
    }
end
