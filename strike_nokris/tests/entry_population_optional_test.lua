-- Run from the repository root with a stock Lua 5.4: lua strike_nokris/tests/entry_population_optional_test.lua
package.path = "./?.lua;" .. package.path
local population = require("strike_nokris.entry_population")

local function run(case)
    local vars, requests, seq = {["entry.gate.result"]="transport_staged"}, {}, 0
    local slots = {
        DIR={registry_key=1,object_tag=2,slot_type=3,slot_index=9},
        A={registry_key=1,object_tag=2,slot_type=1,slot_index=0},
        B={registry_key=1,object_tag=2,slot_type=1,slot_index=1},
        C={registry_key=1,object_tag=2,slot_type=1,slot_index=2},
    }
    local mission = {Slot={DIR="DIR",A="A",B="B",C="C"}, Squad={A="A",B="B",C="C"}}
    local function key(name)
        return {name=name, matches=function(self, other) return self == other end}
    end
    local context = {
        set_variable=function(_, k, v) vars[k]=v end,
        clear_variable=function(_, k) vars[k]=nil end,
        slot=function(_, name) return slots[name] end,
        squad=function(_, name)
            if case.unresolvable == name then error("squad not runnable") end
            return {place=function() local k=key(name); requests[name]=k; return k end}
        end,
    }
    local state = {variable=function(_, k) return vars[k] end}
    local objective = {
        assign=function(_, _, slot) local k=key("assign"); requests["assign:"..tostring(slot)]=k; return k end,
        choose=function() return nil end,
    }
    local controller = population(mission, objective, {}, {
        name="t", region=7, registry=1, object=2, director="DIR", director_index=9, objective_count=2,
        squads={"A","B","C"}, squad_indices={0,1,2}, optional={B=true,C=true},
        ready=function() return true end,
    })
    local function ev(extra)
        seq = seq + 1
        local e = {mission_sequence=tostring(seq), source_generation="5", held_region_index=7}
        for k, v in pairs(extra or {}) do e[k]=v end
        return e
    end
    controller.on_event_client_state_changed(context, state, ev())
    assert(vars["later.t.entered"] == true, "not placed")
    for _, name in ipairs{"A","B","C"} do
        local request = requests[name]
        if request then
            local outcome = case.refused == name and "refused" or "transport_staged"
            controller.on_event_effect_result(context, state, ev{request_key=request, outcome=outcome})
        end
    end
    assert(vars["later.t.status"] ~= "blocked", "blocked: " .. tostring(vars["later.t.reason"]))
    local counter = 0
    local function sense(name, alive)
        counter = counter + 1
        local s = slots[name]
        controller.on_event_squad_state(context, state, ev{registry_key=1, object_tag=2, slot_type=1,
            slot_index=s.slot_index, spawn_generation=1, sense_generation=counter,
            population_available=true, alive_count=alive, objective_revision=0})
    end
    for _, name in ipairs{"A","B","C"} do
        if name ~= case.unresolvable and name ~= case.refused then sense(name, 2) end
    end
    for _, name in ipairs{"A","B","C"} do
        if name ~= case.unresolvable and name ~= case.refused then sense(name, 0) end
    end
    assert(vars["later.t.status"] == "population_zero",
        case.label .. ": status=" .. tostring(vars["later.t.status"]))
    print("ok  " .. case.label)
end

run{label="all squads place"}
run{label="optional squad unresolvable", unresolvable="B"}
run{label="optional squad refused", refused="C"}
local ok = pcall(run, {label="required squad refused", refused="A"})
assert(not ok, "a refused required squad must still block")
print("ok  required squad refused still blocks")

-- A bound combatant is armed in an earlier frame than its squad placement and reports health.
do
    local vars, placed, bind = {["entry.gate.result"]="transport_staged"}, false, nil
    local slots = {DIR={registry_key=1,object_tag=2,slot_type=3,slot_index=9},
        A={registry_key=1,object_tag=2,slot_type=1,slot_index=0},
        K={registry_key=1,object_tag=2,slot_type=2,slot_index=1}}
    local function key() return {matches=function(self, other) return self == other end} end
    slots.K.bind_combatant_to_squad = function() bind = key(); return bind end
    local context = {set_variable=function(_, k, v) vars[k]=v end, slot=function(_, n) return slots[n] end,
        squad=function() return {place=function() placed = true; return key() end} end}
    local state = {variable=function(_, k) return vars[k] end}
    local controller = population({Slot={DIR="DIR",A="A",K="K"}, Squad={A="A"}}, {}, {}, {
        name="t", region=7, registry=1, object=2, director="DIR", director_index=9, objective_count=2,
        squads={"A"}, squad_indices={0}, combatants={"K"}, ready=function() return true end})
    local e = {mission_sequence="1", source_generation="5", held_region_index=7}
    controller.on_event_client_state_changed(context, state, e)
    assert(bind and not placed and vars["later.t.status"] == "binding_pending", "bind must precede placement")
    controller.on_event_effect_result(context, state,
        {mission_sequence="2", source_generation="5", request_key=bind, outcome="transport_staged"})
    assert(placed and vars["later.t.entered"] == true, "placement must follow the binding receipt")
    controller.on_event_damage_state(context, state, {mission_sequence="3", source_generation="5",
        registry_key=1, object_tag=2, slot_type=2, slot_index=1, revision=1, health=0.5, shield=0})
    assert(vars["later.t.health"] == "1|0.5000|0.0000", tostring(vars["later.t.health"]))
    print("ok  combatant binds before placement and records health")
end
