-- Exact type-4 activation and continuous native levels for one encounter obligation.
-- Qualified inactivity is not by itself proof of a relic delivery or boss outcome.
return function(mission, controller, definition)
    local prefix = "crystals." .. definition.name .. "."
    local crystals = {}
    assert(type(definition.ready) == "function")
    assert(#definition.slots > 0 and #definition.slots <= 4)
    for index, name in ipairs(definition.slots) do
        crystals[index] = {definition=assert(mission.Slot[name])}
    end
    local initialized, submitted, held, source, submission_sequence
    local function set_status(context, value) context:set_variable(prefix .. "status", value) end
    local function block(context, reason)
        set_status(context, "blocked")
        context:set_variable(prefix .. "reason", reason)
    end
    local function after(left, right)
        return type(left) == "string" and type(right) == "string"
            and left ~= "" and left ~= "0" and #left <= 20
            and (#left > #right or (#left == #right and left > right))
    end
    local function eligible(state)
        return held == definition.region and source ~= nil
            and state:variable("route.invalidated") ~= true
            and state:variable(prefix .. "status") ~= "blocked"
    end
    local function matches(event, slot)
        return event.registry_key == slot.registry_key and event.object_tag == slot.object_tag
            and event.slot_type == slot.slot_type and event.slot_index == slot.slot_index
    end
    local function update(context, state)
        if not submitted or not eligible(state) then return end
        local ready, inactive = true, 0
        for _, crystal in ipairs(crystals) do
            if not crystal.transported then set_status(context, "activation_pending"); return end
            ready = ready and crystal.observed ~= nil
            if crystal.inactive then inactive = inactive + 1 end
        end
        context:set_variable(prefix .. "inactive", inactive)
        set_status(context, not ready and "awaiting_live"
            or (inactive == #crystals and "all_inactive" or "observing"))
    end
    local function activate(context, state, event)
        if submitted or not event or not eligible(state) or not definition.ready(state)
            or not after(event.mission_sequence, "0") then return end
        -- Validate the whole group before emitting its first activation.
        for index, crystal in ipairs(crystals) do
            local slot = context:slot(crystal.definition)
            assert(slot.registry_key == definition.registry and slot.object_tag == definition.object
                and slot.slot_type == 4 and slot.slot_index == definition.indices[index],
                "crystal group binding mismatch")
        end
        submitted, submission_sequence = true, event.mission_sequence
        set_status(context, "activation_pending")
        for _, crystal in ipairs(crystals) do
            crystal.request = context:slot(crystal.definition):set_object_active{active=true}
        end
    end
    local function wrap(name, handler)
        local previous = controller[name]
        controller[name] = function(context, state, event)
            if not initialized then
                initialized = true
                if state:variable(prefix .. "status") then block(context, "retained_reload") end
            end
            if previous then previous(context, state, event) end
            if submitted and definition.valid and not definition.valid(state) then
                block(context, "encounter_invalidated")
            end
            handler(context, state, event)
            activate(context, state, event)
        end
    end
    wrap("on_start", function() end)
    wrap("on_load", function(context) block(context, "retained_reload") end)
    wrap("on_event_client_state_changed", function(context, state, event)
        if submitted and (event.held_region_index ~= held or event.source_generation ~= source) then
            context:set_variable("route.invalidated", true)
            block(context, "held_or_source_lost")
        end
        held, source = event.held_region_index, event.source_generation
        if type(source) ~= "string" or source == "0" or source == "" then source = nil end
    end)
    wrap("on_event_effect_result", function(context, state, event)
        if not submitted or not eligible(state) then return end
        for _, crystal in ipairs(crystals) do
            if crystal.request and event.request_key:matches(crystal.request) then
                if event.source_generation ~= source or event.outcome ~= "transport_staged" then
                    block(context, "activation_refused")
                else
                    crystal.request, crystal.transported = nil, true
                    update(context, state)
                end
                return
            end
        end
    end)
    wrap("on_event_object_state", function(context, state, event)
        if not submitted or not eligible(state) then return end
        for _, crystal in ipairs(crystals) do
            if matches(event, context:slot(crystal.definition)) then
                if event.source_generation ~= source then block(context, "source_changed"); return end
                if not after(event.mission_sequence, submission_sequence) then return end
                local prior = crystal.observed
                if not prior and (event.alive ~= true or event.present ~= true) then return end
                if not event.sense_generation or event.sense_generation <= 0
                    or event.entry_index == nil or event.entry_index < 0
                    or not event.generation or event.generation <= 0
                    or type(event.alive) ~= "boolean" or type(event.present) ~= "boolean" then
                    block(context, "invalid_object_identity"); return
                end
                if prior and (event.entry_index ~= prior.entry
                    or event.generation ~= prior.activation
                    or event.sense_generation < prior.counter
                    or (event.sense_generation == prior.counter
                        and (event.alive ~= prior.live or event.present ~= prior.spawned))) then
                    block(context, "object_lifetime_changed"); return
                end
                if crystal.inactive and (event.alive or event.present) then
                    block(context, "object_reactivated"); return
                end
                crystal.observed = {entry=event.entry_index, activation=event.generation,
                    counter=event.sense_generation, live=event.alive, spawned=event.present}
                crystal.inactive = event.alive == false and event.present == false
                update(context, state)
                return
            end
        end
    end)
    -- A prior encounter can satisfy readiness during any of these native callbacks.
    for _, name in ipairs{"on_event_squad_state", "on_event_player_trigger", "on_event_trigger_entered"} do
        wrap(name, function() end)
    end
    return controller
end
