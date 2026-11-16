-- Reconstructed one-shot population at the first post-lock authored entry volume.
-- Native entry selects this population; neither transport nor entry means combat completion.
return function(mission, objective, controller)
    assert(mission.name == "strike_nokris")
    local function settled_region(event,region)
        -- The current/pending legs are sparse delta fields. Held is the retained after-image.
        return event.held_region_index==region
    end
    local gauntlet_state = assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7)
    local region = gauntlet_state.region_index
    local trigger = assert(mission.Slot.PT_START_SEED_PROPS)
    local volume = assert(mission.Slot.SLOT_0067_80F734C7)
    local squad = assert(mission.Squad.SQ_START_THRALL)
    local squad_slot = assert(mission.Slot.SQ_START_THRALL)
    local director = assert(mission.Slot.OBJ_RITUAL_GAUNTLET_START)
    local initialized, held, source = false, nil, nil
    local arm_request, placement_request, objective_request
    local seed_request, seed_selected
    local candidate, adopted, arm_sequence
    local submitted, armed, consumed, placement, group

    local function status(context, value) context:set_variable("gstart.status", value) end
    local function stop(context, why)
        status(context, "blocked")
        context:set_variable("gstart.reason", why)
        candidate = nil
    end
    local function initialize(context, state)
        if not initialized then
            initialized = true
            -- Request handles and a partial native observation are VM-local.
            if state:variable("gstart.status") then stop(context, "retained_reload") end
        end
    end
    local function eligible(state)
        return state:variable("gstart.status") ~= "blocked" and held == region and source ~= nil
    end
    local function reconsider_objective(context, state)
        if not eligible(state) or objective_request or not adopted or adopted.available ~= true
            or not adopted.alive or adopted.alive <= 0 then return end
        local combat = context:slot(director)
        -- Copy scalar observations, never retain event userdata beyond its callback.
        local selected = objective.choose({objective_revision=adopted.revision,
            task_costs={[1]=adopted.cost1,[2]=adopted.cost2}}, objective.count(mission, combat), group, 1)
        if selected ~= nil and selected ~= group then
            objective_request = objective.assign(context, mission, squad_slot, combat, selected)
            group = selected
            status(context, "objective_pending")
        end
    end
    local function matches(event, slot)
        return event.registry_key == slot.registry_key and event.object_tag == slot.object_tag
            and event.slot_type == slot.slot_type and event.slot_index == slot.slot_index
    end
    local function valid_sequence(value)
        -- Host event views supply canonical uint64 decimal strings.
        return type(value) == "string" and value ~= "" and value ~= "0" and #value <= 20
    end
    local function after(left, right)
        return valid_sequence(left) and valid_sequence(right)
            and (#left > #right or (#left == #right and left > right))
    end
    local function place_if_ready(context, state)
        if not eligible(state) or not candidate or not armed or consumed then return end
        consumed = true
        placement_request = context:squad(squad):place{}
        placement = "submitted"
        status(context, "placement_submitted")
        candidate = nil
    end
    local function try_arm(context, state, sequence)
        if not eligible(state) or submitted
            or state:variable("entry.gate.result") ~= "transport_staged"
            or not valid_sequence(sequence) then return end
        -- Holding a region does not change the script-selected mission seed. Select its exact
        -- generated state before any gauntlet arm; later scene requests retain publication checks.
        if not seed_selected then
            if not seed_request then
                seed_request = context:select_state(gauntlet_state)
                status(context, "seed_submitted")
            end
            return
        end
        local target, linked = context:slot(trigger), context:slot(volume)
        assert(target.object_tag == 0x80F734C7 and target.registry_key == 0x9E1E5EF6
            and target.slot_type == 31 and target.slot_index == 37,
            "gauntlet trigger identity mismatch")
        assert(linked.object_tag == target.object_tag and linked.registry_key == target.registry_key
            and linked.slot_type == 60 and linked.slot_index == 103,
            "gauntlet volume identity mismatch")
        local combat = context:slot(director)
        assert(combat.object_tag == target.object_tag and combat.registry_key == target.registry_key
            and combat.slot_type == 3
            and combat.slot_index == 27,
            "gauntlet director identity mismatch")
        arm_request = target:fire_trigger{}
        arm_sequence = sequence
        submitted = true
        status(context, "arm_submitted")
    end

    local client_state = controller.on_event_client_state_changed
    controller.on_event_client_state_changed = function(context, state, event)
        initialize(context, state)
        if client_state then client_state(context, state, event) end
        local event_held=settled_region(event,region) and region or nil
        if (submitted or seed_request or seed_selected) and (event_held ~= region
            or event.source_generation ~= source) then
            stop(context, "held_or_source_lost")
        end
        held, source = event_held, event.source_generation
        if source == "0" or type(source) ~= "string" then source = nil end
        try_arm(context, state, event.mission_sequence)
    end

    local load = controller.on_load
    controller.on_load = function(context, state)
        initialize(context, state)
        stop(context, "retained_reload")
        if load then load(context, state) end
    end
    local start = controller.on_start
    controller.on_start = function(context, state)
        initialize(context, state)
        local retained = state:variable("entry.placed") or state:variable("entry.gate.submitted")
            or state:variable("entry.gate.result")
        if start then start(context, state) end
        if retained then stop(context, "retained_start") end
    end

    local player_trigger = controller.on_event_player_trigger
    controller.on_event_player_trigger = function(context, state, event)
        initialize(context, state)
        if player_trigger then player_trigger(context, state, event) end
        if not eligible(state) or not submitted or consumed
            or event.source_generation ~= source then return end
        local target, linked = context:slot(trigger), context:slot(volume)
        if not matches(event, target) or event.volume_registry_key ~= linked.registry_key
            or event.volume_slot_type ~= linked.slot_type
            or event.volume_slot_index ~= linked.slot_index
            or not after(event.mission_sequence, arm_sequence) then return end
        -- Buffer at most one attributed entry while its arm transport receipt is pending.
        candidate = candidate or event.mission_sequence
        place_if_ready(context, state)
    end

    local effect_result = controller.on_event_effect_result
    controller.on_event_effect_result = function(context, state, event)
        initialize(context, state)
        if effect_result then effect_result(context, state, event) end
        -- State variables read the callback's candidate, including the opening gate receipt above.
        if eligible(state) then
            local kind
            if seed_request and event.request_key:matches(seed_request) then kind = "seed"
            elseif arm_request and event.request_key:matches(arm_request) then kind = "arm"
            elseif placement_request and event.request_key:matches(placement_request) then kind = "placement"
            elseif objective_request and event.request_key:matches(objective_request) then kind = "objective" end
            if kind then
                if event.source_generation ~= source or event.outcome ~= "transport_staged" then
                    stop(context, "receipt_refused")
                elseif kind == "seed" then
                    seed_request = nil
                    seed_selected = true
                    status(context, "seed_selected")
                elseif kind == "arm" then
                    arm_request = nil
                    armed = true
                    status(context, "armed")
                    place_if_ready(context, state)
                elseif kind == "placement" then
                    placement_request = nil
                    placement = "transport_staged"
                    status(context, "placed")
                else
                    objective_request = nil
                    status(context, "running")
                    reconsider_objective(context, state)
                end
            end
        end
        try_arm(context, state, event.mission_sequence)
    end

    local squad_state = controller.on_event_squad_state
    controller.on_event_squad_state = function(context, state, event)
        initialize(context, state)
        if squad_state then squad_state(context, state, event) end
        if not eligible(state) or placement ~= "transport_staged"
            or not matches(event, context:slot(squad_slot)) then return end
        -- Native field8 can remain set across living and empty reports in one lifetime.
        -- It supplies no identity-loss or completion authority for this population policy.
        if event.source_generation ~= source then
            stop(context, "squad_lifetime_lost"); return
        end
        -- The requested first echo can itself carry a valid living baseline; unchanged
        -- successors are suppressed by the native reducer. Only an adopted reset loses identity.
        if event.registration_reset and adopted then
            stop(context, "squad_lifetime_lost"); return
        end
        if adopted and event.spawn_generation ~= adopted.spawn then
            stop(context, "squad_lifetime_changed"); return
        end
        if not event.sense_generation or event.sense_generation <= 0 then return end
        local cost1 = event.task_costs and event.task_costs[1]
        local cost2 = event.task_costs and event.task_costs[2]
        if adopted and event.sense_generation <= adopted.sense then
            if event.sense_generation < adopted.sense or event.alive_count ~= adopted.alive
                or event.objective_revision ~= adopted.revision
                or (event.population_available == true) ~= adopted.available
                or cost1 ~= adopted.cost1 or cost2 ~= adopted.cost2 then
                stop(context, "squad_report_reversed")
            end
            return
        end
        if adopted then
            adopted.sense, adopted.alive = event.sense_generation, event.alive_count
            adopted.revision, adopted.cost1, adopted.cost2 = event.objective_revision, cost1, cost2
            adopted.available = event.population_available == true
        end
        if objective_request or event.population_available ~= true
            or not event.alive_count or event.alive_count <= 0
            or not event.spawn_generation or event.spawn_generation <= 0
            or not event.sense_generation or event.sense_generation <= 0 then return end
        local combat = context:slot(director)
        if not adopted then
            if event.objective_revision ~= nil and event.objective_revision ~= 0 then return end
            adopted = {spawn = event.spawn_generation, sense = event.sense_generation,
                alive = event.alive_count, revision = event.objective_revision,
                available = event.population_available == true,
                cost1 = cost1, cost2 = cost2}
            objective_request = objective.assign(context, mission, squad_slot, combat, -1)
            group = -1
            status(context, "objective_pending")
        else
            reconsider_objective(context, state)
        end
    end
    return controller
end
