-- Reconstructed entrance policy using generated build-matched definitions.
-- The alternative entrance squad shares a spawn anchor and is not placed alongside this pair.
-- The native relic knight is requested only after both crystal objects report ready.
-- One replacement follows the first qualified crystal transition.
-- Both qualified inactive crystal levels request the user-tested opening door position.
-- This reconstructed policy does not assert passage or authoritative mission completion.
local ledger = require("strike_nokris.squad_ledger")
local compact = require("strike_nokris.opening_state")
return function(mission, objective)
    assert(mission.name == "strike_nokris", "opening requires the strike scenario")
    local opening = assert(mission.states.STATE_80F729E1_0000_0000_80F729D5)
    local director = assert(mission.Slot.OBJ_RUNELOCKS)
    local tunnel_director = assert(mission.Slot.OBJ_TUNNELS)
    local crystals = {
        assert(mission.Slot.O_DOOR_CRYSTAL_0_80F72A79),
        assert(mission.Slot.O_DOOR_CRYSTAL_1_80F72A79),
    }
    local pending_crystals = {}
    local squads = {
        {squad = assert(mission.Squad.SQ_ENTRANCE_THRALL),
         slot = assert(mission.Slot.SQ_ENTRANCE_THRALL)},
        {squad = assert(mission.Squad.SQ_ENTRANCE_THRALL_1),
         slot = assert(mission.Slot.SQ_ENTRANCE_THRALL_1)},
    }
    local relic_index = #squads + 1
    squads[relic_index] = {
        squad = assert(mission.Squad.SQ_KNIGHT_RUNELOCKS_2),
        slot = assert(mission.Slot.SQ_KNIGHT_RUNELOCKS_2),
    }
    -- Distinct authored runelock positions; alternate and carrier-shared anchors are excluded.
    for _, name in ipairs{
        "SQ_TROOPER_RUNELOCKS", "SQ_TROOPER_RUNELOCKS_1",
        "SQ_TROOPER_RUNELOCKS_2", "SQ_TROOPER_RUNELOCKS_3",
        "SQ_SUPPORT_RUNELOCKS_1",
    } do
        squads[#squads + 1] = {
            squad = assert(mission.Squad[name]), slot = assert(mission.Slot[name]),
        }
    end
    for _, name in ipairs{
        "SQ_ENTRANCE_ANCHOR", "SQ_ENTRANCE_ANCHOR_1",
        "SQ_MAIN_ANCHOR_80F72AB8", "SQ_MAIN_SUPPORT_80F72AB8",
    } do
        squads[#squads + 1] = {
            squad = assert(mission.Squad[name]), slot = assert(mission.Slot[name]),
            director = tunnel_director,
        }
    end
    local pending_cleanup
    local pending = {}

    local function key(index)
        return "entry.squad" .. index
    end

    local controller = {
        initial_state = opening,
        on_event_client_state_changed = function(context, state, event)
            -- A held region is the authorization boundary for authored Host outputs.
            if state:variable("entry.region") == opening.region_index
                and event.held_region_index ~= opening.region_index then
                -- A later visit needs fresh levels from both objects. Keep the submission
                -- ledger: losing held authority does not authorize replacement spawns.
                for index = 1, #crystals do
                    local prefix = "entry.crystal" .. index .. "."
                    compact.set(context, state, prefix .. "live", false)
                    compact.set(context, state, prefix .. "spawned", false)
                end
            end
            context:set_variable("entry.region", event.held_region_index or -1)
            if event.held_region_index ~= opening.region_index then return end
            if not compact.get(state, "entry.crystals.submitted") then
                for index, slot in ipairs(crystals) do
                    pending_crystals[index] = context:slot(slot):set_object_active{active = true}
                end
                compact.set(context, state, "entry.crystals.submitted", true)
            end
            if state:variable("entry.placed") then return end
            context:set_variable("entry.ledger_version", 2)
            for index, definition in ipairs(squads) do
                if index ~= relic_index then
                    pending[index] = {request = context:squad(definition.squad):place{},
                                      placement = true}
                end
            end
            -- This records submission only. Native Sense authorizes the cost request below.
            context:set_variable("entry.placed", true)
        end,
        on_event_object_state = function(context, state, event)
            if not compact.get(state, "entry.crystals.submitted")
                or state:variable("entry.region") ~= opening.region_index then return end
            for index, definition in ipairs(crystals) do
                local slot = context:slot(definition)
                if event.registry_key == slot.registry_key
                    and event.object_tag == slot.object_tag
                    and event.slot_type == slot.slot_type
                    and event.slot_index == slot.slot_index then
                    -- These are native levels, not visual confirmation or a destruction count.
                    local prefix = "entry.crystal" .. index .. "."
                    compact.set(context, state, prefix .. "observed", true)
                    compact.set(context, state, prefix .. "live", event.alive)
                    compact.set(context, state, prefix .. "spawned", event.present)
                    compact.set(context, state, prefix .. "entry", event.entry_index)
                    compact.set(context, state, prefix .. "activation_revision", event.generation)
                    compact.set(context, state, prefix .. "sense_generation", event.sense_generation or -1)
                    if compact.get(state, "entry.failed") or compact.get(state, "entry.crystals.failed")
                        or compact.get(state, "entry.knight.placed") then
                        return
                    end
                    for crystal_index = 1, #crystals do
                        local crystal_prefix = "entry.crystal" .. crystal_index .. "."
                        if not compact.get(state, crystal_prefix .. "live")
                            or not compact.get(state, crystal_prefix .. "spawned") then return end
                    end
                    -- This uniquely bound authored knight owns the native relic-production chain.
                    -- Readiness chooses this reconstructed start, not an original phase boundary.
                    if compact.get(state, "entry.cleanup.submitted") then return end
                    pending_cleanup = context:slot(mission.Slot.TG_RELIC_CLEANUP_80F72A79):set_volume_active{
                        volume = context:slot(mission.Slot.SLOT_004C_80F72A79), active = false,
                    }
                    compact.set(context, state, "entry.cleanup.submitted", true)
                    return
                end
            end
        end,
        on_event_effect_result = function(context, state, event)
            if pending_cleanup and event.request_key:matches(pending_cleanup) then
                pending_cleanup = nil
                compact.set(context, state, "entry.cleanup.transported", event.outcome == "transport_staged")
                if event.outcome ~= "transport_staged" or compact.get(state, "entry.failed")
                    or compact.get(state, "entry.crystals.failed")
                    or state:variable("entry.region") ~= opening.region_index then
                    compact.set(context, state, "entry.failed", true)
                    return
                end
                for index = 1, #crystals do
                    if not compact.get(state, "entry.crystal" .. index .. ".live")
                        or not compact.get(state, "entry.crystal" .. index .. ".spawned") then
                        compact.set(context, state, "entry.failed", true)
                        return
                    end
                end
                -- E024 reconstructed start: transport is not native volume-removal proof.
                -- Slot76 removal still needs native verification in the next candidate test.
                pending[relic_index] = {
                    request = context:squad(squads[relic_index].squad):place{}, placement = true,
                }
                compact.set(context, state, "entry.knight.placed", true)
                return
            end
            for index = 1, #crystals do
                local request = pending_crystals[index]
                if request and event.request_key:matches(request) then
                    -- Transport is not native visibility or a valid crystal destruction.
                    compact.set(context, state, "entry.crystal" .. index .. ".transported",
                                         event.outcome == "transport_staged")
                    if event.outcome ~= "transport_staged" then
                        compact.set(context, state, "entry.crystals.failed", true)
                    end
                    pending_crystals[index] = nil
                    return
                end
            end
            for index = 1, #squads do
                local attempt = pending[index]
                if attempt and event.request_key:matches(attempt.request) then
                    if event.outcome ~= "transport_staged" then
                        compact.set(context, state, "entry.failed", true)
                    elseif attempt.placement then
                        ledger.set(context, state, key(index), "transported", true)
                    end
                    pending[index] = nil
                    return
                end
            end
        end,
        on_event_squad_state = function(context, state, event)
            -- Keep exact knight population evidence even after zero/removal or an output
            -- failure. A decrease is not proof of a kill or native relic creation.
            if compact.get(state, "entry.knight.placed")
                and state:variable("entry.region") == opening.region_index
                and event.source_generation and event.sense_generation
                and event.sense_generation > 0 then
                local slot = context:slot(squads[relic_index].slot)
                if event.registry_key == slot.registry_key
                    and event.object_tag == slot.object_tag
                    and event.slot_type == slot.slot_type
                    and event.slot_index == slot.slot_index then
                    compact.set(context, state, "entry.knight.reported_population_available", event.population_available ~= false)
                    if event.population_available ~= false then
                    -- Keep the original first-counter diagnostic for comparison. These latest
                    -- reconstructed levels are separate and make no death or relic-creation assertion.
                    compact.set(context, state, "entry.knight.reported_alive", event.alive_count)
                    compact.set(context, state, "entry.knight.reported_counter", event.sense_generation)
                    compact.set(context, state, "entry.knight.reported_spawn_generation", event.spawn_generation or -1)
                    local source = state:variable("entry.knight.obs_source")
                    local generation = state:variable("entry.knight.obs_generation")
                    if not source or (source == event.source_generation
                        and generation == event.sense_generation) then
                        context:set_variable("entry.knight.obs_source", event.source_generation)
                        context:set_variable("entry.knight.obs_generation", event.sense_generation)
                        context:set_variable("entry.knight.alive", event.alive_count)
                        context:set_variable("entry.knight.removal", event.removal_flag == true)
                        if event.alive_count > 0 then
                            context:set_variable("entry.knight.seen_alive", true)
                        elseif event.alive_count == 0 then
                            context:set_variable("entry.knight.zero_seen", true)
                            if state:variable("entry.knight.seen_alive") then
                                context:set_variable("entry.knight.zero_after_alive", true)
                            end
                        end
                        if event.removal_flag then
                            context:set_variable("entry.knight.removal_seen", true)
                        end
                    end
                    end
                end
            end
            -- A registration reset may first report zero population/echo. Retire the old
            -- job before the positive-population action guard can discard that observation.
            if event.registration_reset and state:variable("entry.region") == opening.region_index then
                for index, definition in ipairs(squads) do
                    local slot = context:slot(definition.slot)
                    if ledger.get(state, key(index), "revision")
                        and event.registry_key == slot.registry_key and event.object_tag == slot.object_tag
                        and event.slot_index == slot.slot_index and event.slot_type == slot.slot_type then
                        ledger.set(context, state, key(index), "registration_lost", true)
                    end
                end
            end
            if not state:variable("entry.placed")
                or compact.get(state, "entry.failed")
                or state:variable("entry.region") ~= opening.region_index
                or not event.sense_generation or event.sense_generation <= 0
                or not event.spawn_generation or event.spawn_generation <= 0
                or event.population_available == false
                or not event.source_generation or not event.alive_count or event.alive_count <= 0 then return end
            for index, definition in ipairs(squads) do
                local slot = context:slot(definition.slot)
                if event.registry_key == slot.registry_key
                    and event.object_tag == slot.object_tag
                    and event.slot_index == slot.slot_index
                    and event.slot_type == slot.slot_type then
                    if ledger.get(state, key(index), "registration_lost") then return end
                    if pending[index] or not ledger.get(state, key(index), "transported") then
                        return
                    end
                    local generation = ledger.get(state, key(index), "spawn_generation")
                    local source = ledger.get(state, key(index), "source")
                    -- Once adopted, a different native lifetime cannot inherit this cost job.
                    if generation and (generation ~= event.spawn_generation
                        or source ~= event.source_generation) then return end
                    local target = context:slot(definition.director or director)
                    local requested = ledger.get(state, key(index), "revision")
                    -- An older durable cost job was keyed to a wire counter. It cannot be
                    -- silently adopted into a spawn lifetime after a reload.
                    if requested and not generation then return end
                    if not requested then
                        -- A new placement starts at revision zero. Do not adopt another job.
                        -- Missing Sense .1 is unknown. The authored host's expected_revision
                        -- check below must validate zero; this does not assert an observed zero.
                        if event.objective_revision ~= nil and event.objective_revision ~= 0 then
                            return
                        end
                        local request = objective.assign(context, mission, definition.slot, target, -1)
                        pending[index] = {request = request}
                        ledger.adopt(context, key(index), event.source_generation,
                            event.sense_generation, event.spawn_generation, 1, -1)
                        return
                    end
                    local current = ledger.get(state, key(index), "group") or -1
                    local selected = objective.choose(event, objective.count(mission, target),
                                                      current, requested)
                    if selected ~= nil and selected ~= current then
                        local request = objective.assign(context, mission, definition.slot, target, selected)
                        pending[index] = {request = request}
                        ledger.set(context, state, key(index), "group", selected)
                    end
                    return
                end
            end
        end,
    }

    -- Bounded reconstruction: one second carrier, never a death or damage assertion.
    -- These observations belong to this VM. Reloads cannot adopt a partially observed run.
    local observed_crystals = {}
    local observed_knight
    local enabled = false
    local function block(context, reason)
        enabled = false
        context:set_variable("entry.replacement.blocked", true)
        context:set_variable("entry.replacement.reason", reason)
    end
    local function matches(event, slot)
        return event.registry_key == slot.registry_key and event.object_tag == slot.object_tag
            and event.slot_type == slot.slot_type and event.slot_index == slot.slot_index
    end
    local pending_gate
    local function try_gate(context, state)
        if not enabled or state:variable("entry.gate.submitted")
            or state:variable("entry.replacement.blocked")
            or state:variable("entry.region") ~= opening.region_index
            or compact.get(state, "entry.cleanup.transported") ~= true
            or compact.get(state, "entry.knight.placed") ~= true
            or ledger.get(state, key(relic_index), "transported") ~= true
            or compact.get(state, "entry.failed") or compact.get(state, "entry.crystals.failed") then
            return
        end
        for index = 1, #squads do
            if pending[index] then return end
        end
        local source
        for index = 1, #crystals do
            local crystal = observed_crystals[index]
            if not crystal or not crystal.seen_active
                or crystal.live ~= false or crystal.spawned ~= false
                or compact.get(state, "entry.crystal" .. index .. ".transported") ~= true then
                return
            end
            if source and source ~= crystal.source then return end
            source = crystal.source
        end
        -- E028 proved this channel/value for the opening door on client build 86657.
        -- Keep submission durable; VM-local evidence may never be reconstructed on reload.
        pending_gate = context:slot(mission.Slot.D_RUNELOCK_ENERGY_DOOR_80F72A79):set_channel{
            channel = context.sdk.device_channels.position,
            value = context.sdk.unit(1), snap = false,
        }
        context:set_variable("entry.gate.submitted", true)
        context:set_variable("entry.gate.result", "submitted")
    end
    local function try_replacement(context, state)
        if not enabled or state:variable("entry.replacement.submitted")
            or state:variable("entry.replacement.blocked")
            or state:variable("entry.region") ~= opening.region_index
            or compact.get(state, "entry.cleanup.transported") ~= true
            or compact.get(state, "entry.failed") or compact.get(state, "entry.crystals.failed")
            or pending[relic_index] or ledger.get(state, key(relic_index), "transported") ~= true
            or not observed_knight or not observed_knight.seen_alive
            or observed_knight.alive ~= 0 then return end
        local inactive = 0
        for index = 1, #crystals do
            local crystal = observed_crystals[index]
            if not crystal or not crystal.seen_active
                or crystal.source ~= observed_knight.source then return end
            if crystal.live == false and crystal.spawned == false then
                inactive = inactive + 1
            elseif crystal.live ~= true or crystal.spawned ~= true then
                return
            end
        end
        if inactive ~= 1 then return end
        -- Reset only the completed carrier's cost/observation lifetime before requesting another.
        context:clear_variable(key(relic_index))
        for _, field in ipairs{"obs_source", "obs_generation", "alive", "seen_alive",
                               "zero_seen", "zero_after_alive", "removal", "removal_seen"} do
            context:clear_variable("entry.knight." .. field)
        end
        pending[relic_index] = {
            request = context:squad(squads[relic_index].squad):place{}, placement = true,
        }
        context:set_variable("entry.replacement.source", observed_knight.source)
        context:set_variable("entry.replacement.previous_spawn", observed_knight.spawn)
        context:set_variable("entry.replacement.submitted", true)
    end

    controller.on_start = function(context, state)
        if state:variable("entry.placed") or state:variable("entry.replacement.blocked") then
            block(context, "retained_start")
        else
            enabled = true
        end
    end
    local client_state_changed = controller.on_event_client_state_changed
    controller.on_event_client_state_changed = function(context, state, event)
        if state:variable("entry.region") == opening.region_index
            and event.held_region_index ~= opening.region_index then block(context, "region_lost") end
        client_state_changed(context, state, event)
    end
    local object_state = controller.on_event_object_state
    controller.on_event_object_state = function(context, state, event)
        if enabled and state:variable("entry.region") == opening.region_index then
            for index, definition in ipairs(crystals) do
                if matches(event, context:slot(definition)) then
                    local prior = observed_crystals[index]
                    if not prior and (event.alive ~= true or event.present ~= true) then
                        -- Initial inactive auth0/entry-1 reports precede authored activation.
                        -- They establish no crystal lifetime and cannot authorize replacement.
                    elseif not event.source_generation or not event.sense_generation
                        or event.sense_generation <= 0 or event.entry_index == nil
                        or event.entry_index < 0 or event.generation == nil
                        or event.generation <= 0 then
                        block(context, "crystal_identity")
                    elseif prior and (prior.source ~= event.source_generation
                        or prior.entry ~= event.entry_index
                        or prior.activation ~= event.generation
                        or event.sense_generation < prior.counter
                        or (event.sense_generation == prior.counter
                            and (prior.live ~= event.alive or prior.spawned ~= event.present))) then
                        block(context, "crystal_drift")
                    else
                        observed_crystals[index] = {
                            source = event.source_generation, entry = event.entry_index,
                            activation = event.generation, counter = event.sense_generation,
                            live = event.alive, spawned = event.present,
                            seen_active = (prior and prior.seen_active)
                                or (event.alive == true and event.present == true),
                        }
                    end
                    break
                end
            end
        end
        object_state(context, state, event)
        try_replacement(context, state)
        try_gate(context, state)
    end
    local squad_state = controller.on_event_squad_state
    controller.on_event_squad_state = function(context, state, event)
        if matches(event, context:slot(squads[relic_index].slot)) then
            if state:variable("entry.replacement.submitted") then
                -- Late original reports must not become the new carrier's combat job.
                if ledger.get(state, key(relic_index), "transported") ~= true
                    or event.source_generation ~= state:variable("entry.replacement.source")
                    or not event.spawn_generation
                    or event.spawn_generation <= state:variable("entry.replacement.previous_spawn") then
                    return
                end
            elseif enabled and compact.get(state, "entry.knight.placed")
                and state:variable("entry.region") == opening.region_index then
                local prior = observed_knight
                -- The native removal level can already be set while this knight is alive.
                -- It neither invalidates a continuous population report nor proves a death.
                if not prior and (event.registration_reset or not event.source_generation
                    or not event.spawn_generation or event.spawn_generation <= 0
                    or not event.sense_generation or event.sense_generation <= 0
                    or event.population_available ~= true or not event.alive_count
                    or event.alive_count <= 0) then
                    -- Placement can precede its echo and first known population. Wait for
                    -- a living baseline; initial unknown/zero levels are not a lost lifetime.
                elseif event.registration_reset or not event.source_generation
                    or not event.spawn_generation or event.spawn_generation <= 0
                    or not event.sense_generation or event.sense_generation <= 0 then
                    block(context, "knight_identity")
                elseif prior and (prior.source ~= event.source_generation
                    or prior.spawn ~= event.spawn_generation or event.sense_generation < prior.counter
                    or (event.sense_generation == prior.counter and event.population_available == true
                        and prior.alive ~= event.alive_count)) then
                    block(context, "knight_drift")
                else
                    observed_knight = {
                        source = event.source_generation, spawn = event.spawn_generation,
                        counter = event.sense_generation,
                        alive = event.population_available == true and event.alive_count or nil,
                        seen_alive = (prior and prior.seen_alive)
                            or (event.population_available == true and event.alive_count > 0),
                    }
                end
            end
        end
        squad_state(context, state, event)
        try_replacement(context, state)
        try_gate(context, state)
    end
    local effect_result = controller.on_event_effect_result
    controller.on_event_effect_result = function(context, state, event)
        if pending_gate and event.request_key:matches(pending_gate) then
            pending_gate = nil
            context:set_variable("entry.gate.result", event.outcome)
            return
        end
        effect_result(context, state, event)
        try_replacement(context, state)
        try_gate(context, state)
    end
    -- Old per-field ledgers cannot be adopted after a schema change or erase spawn history.
    for _, name in ipairs{"on_start", "on_event_client_state_changed", "on_event_object_state",
        "on_event_squad_state", "on_event_effect_result"} do
        local handler = controller[name]
        controller[name] = function(context, state, event)
            if not compact.valid(state) then
                block(context, "opening_schema_mismatch")
                return
            end
            if state:variable("entry.placed") and state:variable("entry.ledger_version") ~= 2 then
                compact.set(context, state, "entry.failed", true)
                block(context, "opening_schema_mismatch")
                return
            end
            return handler(context, state, event)
        end
    end
    return controller
end
