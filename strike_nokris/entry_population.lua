-- Reconstructed entry populations use exact native triggers and bounded combat directors.
-- Entry and known-zero population are observations, not normal-death or ritual outcomes.
return function(mission, objective, controller, definition)
    local function settled_region(event)
        -- Client-state messages restate only the leg that moved. The Host's held value is the
        -- retained after-image; nil current/pending fields on a later delta are not settlement.
        return event.held_region_index==definition.region
    end
    local prefix = "later." .. definition.name .. "."
    local trigger = definition.trigger and assert(mission.Slot[definition.trigger])
    local volume = definition.volume and assert(mission.Slot[definition.volume])
    local director = assert(mission.Slot[definition.director])
    local squads = {}
    for index, name in ipairs(definition.squads) do
        squads[index] = {squad=assert(mission.Squad[name]), slot=assert(mission.Slot[name]),
            -- An optional squad that cannot be resolved or placed is skipped, never a route block.
            optional=definition.optional~=nil and definition.optional[name]==true}
    end
    assert(#squads > 0 and #squads <= 6)
    -- Combatants bound before placement, as scene spawn does, so their type-2 Sense reports health.
    local combatants = {}
    for index, name in ipairs(definition.combatants or {}) do combatants[index] = assert(mission.Slot[name]) end
    local bindings
    local initialized, held, source, submitted, armed, entered, arm_sequence
    local arm_request, candidate
    local jobs = {}
    local monitor, admission, receipt
    local function diagnostic(context)
        if definition.reconcile_occupied then
            local reason = (candidate and not entered and "arrival_pending_prerequisites")
                or admission or (not submitted and "waiting_prerequisites")
                or (not monitor and "waiting_report") or (not monitor.available and "waiting_valid_report")
                or (not monitor.occupied and "waiting_occupied") or "waiting_confirmation"
            context:set_variable(prefix .. "monitor", (arm_sequence or "0") .. "|"
                .. (monitor and monitor.sequence or "0") .. "|" .. tostring(monitor and monitor.counter or 0)
                .. "|" .. (monitor and monitor.occupied and "1" or "0") .. "|"
                .. (monitor and monitor.continuity or "unknown") .. "|"
                .. reason .. "|" .. (receipt or "none"))
        end
    end

    local function status(context, value) context:set_variable(prefix .. "status", value) end
    -- Preparation diagnostics reuse this controller's existing reason variable, so a
    -- rebaselining population adds no durable key. Definitions that cannot rebaseline
    -- never write them and keep their previous state surface exactly.
    local function diagnose(context, reason)
        if definition.prepare_rebaseline then context:set_variable(prefix .. "reason", reason) end
    end
    local function stop(context, reason)
        status(context, "blocked")
        context:set_variable(prefix .. "reason", reason)
        candidate, monitor = nil, nil
        diagnostic(context)
    end
    local function initialize(context, state)
        if not initialized then
            initialized = true
            if state:variable(prefix .. "status") then stop(context, "retained_reload") end
        end
    end
    local function eligible(state)
        return held == definition.region and source ~= nil
            and state:variable("route.invalidated") ~= true
            and state:variable(prefix .. "status") ~= "blocked"
    end
    local function after(left, right)
        return type(left) == "string" and type(right) == "string"
            and left ~= "" and left ~= "0" and #left <= 20
            and (#left > #right or (#left == #right and left > right))
    end
    local function matches(event, slot)
        return event.registry_key == slot.registry_key and event.object_tag == slot.object_tag
            and event.slot_type == slot.slot_type and event.slot_index == slot.slot_index
    end
    local function verify_slot(slot, kind, index)
        assert(slot.registry_key == definition.registry and slot.object_tag == definition.object
            and slot.slot_type == kind and slot.slot_index == index, "entry population binding mismatch")
    end
    local function captured_portal_reload(state)
        if definition.name~="boss_entry" or state:variable("nokris.chant")~="transport_staged" then return false end
        local flow=state:variable("directive.flow")
        local before=flow=="D2|8|none|88|2|2206|255|active|0|none"
            and state:variable("prefight.entry")=="arrived"
            and state:variable("later.prefight.status")=="population_zero"
            and state:variable("later.prefight.reason")=="clearance_observed"
            and state:variable("nokris.intro")==nil
            and state:variable("later.boss_entry.status")==nil
            and state:variable("route.invalidated")~=true
        local suffix="|255|blocked|0|reload_retained"
        local sequence=type(flow)=="string" and string.sub(flow,1,15)=="D2|8|none|88|2|"
            and string.sub(flow,-#suffix)==suffix and tonumber(string.sub(flow,16,#flow-#suffix))
        local after=sequence and sequence>=3425
            and state:variable("prefight.entry")=="blocked"
            and state:variable("later.prefight.status")=="blocked"
            and state:variable("later.prefight.reason")=="retained_reload"
            and state:variable("nokris.intro")=="blocked"
            and state:variable("later.boss_entry.status")=="blocked"
            and state:variable("later.boss_entry.reason")=="retained_reload"
            and state:variable("route.invalidated")==true
        return before or after
    end
    local function prerequisites(state)
        -- Predecessors admit this trigger once; their later lifetime does not own this job.
        if state:variable("entry.gate.result") ~= "transport_staged" then return false end
        if definition.ready and not definition.ready(state) then return false end
        for _, key in ipairs(definition.requires or {}) do
            if state:variable(key) ~= true then return false end
        end
        return true
    end
    local function place(context, state)
        if not eligible(state) or not armed or not candidate or entered then return end
        if definition.capture_arrival and not prerequisites(state) then
            diagnostic(context); return
        end
        if #combatants > 0 and not bindings then
            -- The binding must commit in an earlier frame than the type-1 placement.
            bindings = {}
            for index, slot in ipairs(combatants) do
                bindings[index] = context:slot(slot):bind_combatant_to_squad{}
            end
            status(context, "binding_pending")
            return
        end
        if bindings and #bindings > 0 then return end
        entered = true
        context:set_variable(prefix .. "entered", true)
        for index, squad in ipairs(squads) do
            if squad.optional then
                local ok, request = pcall(function() return context:squad(squad.squad):place{} end)
                jobs[index] = ok and request and {placement=request} or {skipped=true}
            else
                jobs[index] = {placement=context:squad(squad.squad):place{}}
            end
        end
        status(context, "placement_pending")
        diagnostic(context)
        candidate = nil
    end
    local function arm(context, state, sequence)
        -- A restored terminal population is already owned evidence; do not place it again merely
        -- because a new VM has no transient submitted flag.
        if state:variable(prefix .. "status") == "population_zero" then return end
        if submitted or not eligible(state)
            or state:variable("entry.gate.result") ~= "transport_staged"
            or (definition.arm_ready and not definition.arm_ready(state))
            or (not definition.capture_arrival and not prerequisites(state))
            or not after(sequence, "0") then return end
        assert(not definition.passive_trigger
            or (definition.kind == 31 and definition.capture_arrival),
            "a shared trigger must be a captured type31 arrival")
        assert(not definition.capture_arrival or definition.kind == 31
            or (definition.kind == 30 and definition.reconcile_occupied),
            "arrival capture requires a player trigger or typed occupancy monitor")
        local sensor = trigger and context:slot(trigger)
        local combat = context:slot(director)
        if definition.kind then
            verify_slot(sensor, definition.kind, definition.index)
            verify_slot(context:slot(volume), 60, definition.volume_index)
        end
        verify_slot(combat, 3, definition.director_index)
        for index, squad in ipairs(squads) do
            verify_slot(context:slot(squad.slot), 1, definition.squad_indices[index])
        end
        submitted, arm_sequence = true, sequence
        diagnostic(context)
        if not definition.kind then
            -- An explicit mission predicate can admit authored support without inventing a trigger.
            assert(type(definition.ready)=="function")
            armed,candidate=true,sequence
            place(context,state)
        elseif definition.passive_trigger then
            armed = true
            status(context, "observing")
        elseif definition.kind == 31 then
            arm_request = sensor:fire_trigger{}
            status(context, "arm_pending")
        else
            -- A type30 edge is accepted only from the Host's continuity-checked reducer.
            -- No guessed occupancy Auth filter/value is written to activate the monitor.
            assert(definition.kind == 30)
            armed = true
            status(context, "observing")
        end
    end
    local function choose(context, state, index)
        local job = jobs[index]
        if not eligible(state) or not job or job.request or not job.observed
            or not job.observed.available or not job.observed.alive or job.observed.alive <= 0 then return end
        local selected = objective.choose({objective_revision=job.observed.revision,
            task_costs=job.observed.costs}, definition.objective_count, job.group, 1)
        if selected ~= nil and selected ~= job.group then
            job.request = objective.assign(context, mission, squads[index].slot, context:slot(director), selected)
            job.group = selected
        end
    end
    local function wrap(name, handler)
        local previous = controller[name]
        controller[name] = function(context, state, event)
            initialize(context, state)
            if previous then previous(context, state, event) end
            handler(context, state, event)
            if event then arm(context, state, event.mission_sequence) end
            if definition.capture_arrival then place(context, state) end
        end
    end
    wrap("on_start", function() end)
    wrap("on_load", function(context,state)
        if not captured_portal_reload(state) then stop(context,"retained_reload") end
    end)
    wrap("on_event_client_state_changed", function(context, state, event)
        local event_held=settled_region(event) and definition.region or nil
        if submitted and (event_held ~= held or event.source_generation ~= source) then
            context:set_variable("route.invalidated", true)
            stop(context, "held_or_source_lost")
        end
        if held ~= event_held or source ~= event.source_generation then
            monitor, candidate = nil, nil
        end
        held, source = event_held, event.source_generation
        if type(source) ~= "string" or source == "0" or source == "" then source = nil end
        arm(context, state, event.mission_sequence)
    end)
    local function entry(context, state, event)
        if not eligible(state) or not submitted or entered or event.source_generation ~= source
            or not matches(event, context:slot(trigger)) or not after(event.mission_sequence, arm_sequence) then return end
        if definition.kind == 31 and (event.volume_registry_key ~= definition.registry
            or event.volume_slot_type ~= 60 or event.volume_slot_index ~= definition.volume_index) then return end
        admission = admission or "enter_edge"
        candidate = candidate or event.mission_sequence
        place(context, state)
    end
    if definition.kind then
        wrap(definition.kind == 31 and "on_event_player_trigger" or "on_event_trigger_entered", entry)
    end
    if definition.kind == 30 then
        wrap("on_event_trigger_state", function(context, state, event)
            if not definition.reconcile_occupied or not eligible(state) or entered
                or event.source_generation ~= source or not matches(event, context:slot(trigger)) then return end
            if monitor and not after(event.mission_sequence, monitor.sequence) then return end
            if event.continuity == "duplicate" then return end
            local prior = monitor
            local available = event.available == true and type(event.occupied) == "boolean"
                and math.type(event.sense_generation) == "integer" and event.sense_generation > 0
            monitor = {sequence=event.mission_sequence,counter=event.sense_generation or 0,
                available=available,occupied=available and event.occupied,continuity=event.continuity or "invalid"}
            if not available or not event.occupied or (event.continuity ~= "consecutive"
                and (prior or event.continuity ~= "baseline")) then
                candidate, admission = nil, nil
                diagnostic(context); return
            end
            -- These monitors watch before combat prerequisites settle. A fresh occupied report
            -- after sensor arming records arrival; a later exit cancels it before placement.
            if definition.capture_arrival and submitted and after(event.mission_sequence, arm_sequence)
                and (event.continuity == "consecutive" or (not prior and event.continuity == "baseline")) then
                admission, candidate = "occupied_arrival", event.mission_sequence
                place(context, state)
                diagnostic(context); return
            end
            -- Corroboration is a new native report after admission, never a cached level or timer.
            if submitted and prior and prior.occupied and event.continuity == "consecutive"
                and event.sense_generation == prior.counter + 1 and after(event.mission_sequence, arm_sequence) then
                admission, candidate = "occupied_confirm", event.mission_sequence
                place(context, state)
            end
            diagnostic(context)
        end)
        wrap("on_event_trigger_exited", function(context, _, event)
            if not entered and event.source_generation == source and matches(event, context:slot(trigger)) then
                candidate, admission = nil, nil
                -- A state and its derived exit share one causal sequence. Preserve that qualified
                -- empty report; an edge without its matching report leaves no cached baseline.
                if not monitor or monitor.sequence ~= event.mission_sequence then monitor = nil end
                diagnostic(context)
            end
        end)
    end
    wrap("on_event_effect_result", function(context, state, event)
        if eligible(state) then
            if arm_request and event.request_key:matches(arm_request) then
                if event.source_generation ~= source or event.outcome ~= "transport_staged" then
                    stop(context, "arm_refused")
                else
                    arm_request, armed = nil, true
                    status(context, "armed")
                    place(context, state)
                end
            elseif bindings and #bindings > 0 then
                for index, request in ipairs(bindings) do
                    if event.request_key:matches(request) then
                        if event.source_generation ~= source or event.outcome ~= "transport_staged" then
                            stop(context, "binding_refused"); return
                        end
                        table.remove(bindings, index)
                        if #bindings == 0 then place(context, state) end
                        break
                    end
                end
            else
                for index, job in ipairs(jobs) do
                    local placement = job.placement and event.request_key:matches(job.placement)
                    local assignment = job.request and event.request_key:matches(job.request)
                    if placement or assignment then
                        if placement then receipt = event.outcome; diagnostic(context) end
                        if placement and squads[index].optional and event.source_generation == source
                            and event.outcome ~= "transport_staged" then
                            jobs[index] = {skipped=true}
                        elseif event.source_generation ~= source or event.outcome ~= "transport_staged" then
                            stop(context, "output_refused")
                        elseif placement then
                            job.placement, job.transported = nil, true
                        else
                            -- The exact outstanding request identity settles here. An older
                            -- receipt cannot restore population evidence a restart discarded.
                            job.request = nil
                            if job.observed then choose(context, state, index)
                            else diagnose(context, "waiting_living_baseline") end
                        end
                        break
                    end
                end
            end
        end
        arm(context, state, event.mission_sequence)
    end)
    wrap("on_event_squad_state", function(context, state, event)
        if not eligible(state) then return end
        for index, squad in ipairs(squads) do
            local job = jobs[index]
            if job and job.transported and matches(event, context:slot(squad.slot)) then
                -- Native field8 alone does not invalidate a continuously observed squad.
                -- Completion still requires every selected job's qualified population zero.
                if event.source_generation ~= source then
                    stop(context, "squad_lifetime_lost"); return
                end
                -- The accepted placement owns one spawn identity for this encounter. A
                -- different echo is a replacement, never a preparation restart.
                if job.spawn ~= nil and event.spawn_generation ~= job.spawn then
                    stop(context, "squad_lifetime_changed"); return
                end
                -- A restart is reconsidered only inside this encounter, source, region and
                -- owned placement, with the same spawn identity, before confirmed combat
                -- objective admission or accepted clearance. The restart report must itself be
                -- the fresh native initialization; every other reset stays an identity loss.
                if event.registration_reset and (job.observed ~= nil or job.rebaseline) then
                    if definition.prepare_rebaseline and event.initial_observation == true
                        and job.admitted ~= true and job.cleared ~= true
                        and event.spawn_generation ~= nil and event.sense_generation
                        and event.sense_generation > 0 then
                        -- Discard the old population evidence. The counter restart contributes
                        -- no progress: the discarded report is never adopted as a baseline.
                        job.observed, job.rebaseline = nil, true
                        status(context, "preparing")
                        diagnose(context, "initialization_restart")
                    else
                        stop(context, "squad_lifetime_lost")
                    end
                    return
                end
                if not event.sense_generation or event.sense_generation <= 0 then return end
                local prior, rebaseline = job.observed, job.rebaseline
                local costs = {}
                for task = 1, definition.objective_count do
                    costs[task] = event.task_costs and event.task_costs[task]
                end
                if rebaseline then
                    -- Require a subsequent available and living observation as the new
                    -- baseline. Missing population never means zero, and a detached zero is
                    -- not accepted clearance.
                    if event.population_available ~= true or not event.alive_count or event.alive_count <= 0 then
                        diagnose(context, "waiting_living_baseline"); return
                    end
                    job.rebaseline = false
                elseif prior and event.sense_generation <= prior.counter then
                    local same = event.sense_generation == prior.counter and event.alive_count == prior.alive
                        and (event.population_available == true) == prior.available
                        and event.objective_revision == prior.revision
                    for task = 1, definition.objective_count do
                        same = same and costs[task] == prior.costs[task]
                    end
                    if not same then stop(context, "squad_report_reversed") end
                    return
                elseif not prior and (event.population_available ~= true or not event.alive_count
                    or event.alive_count <= 0 or not event.spawn_generation or event.spawn_generation <= 0
                    or (event.objective_revision ~= nil and event.objective_revision ~= 0)) then return end
                job.observed = {spawn=event.spawn_generation, counter=event.sense_generation,
                    alive=event.alive_count, available=event.population_available == true,
                    revision=event.objective_revision, costs=costs}
                job.spawn = event.spawn_generation
                -- Fresh native objective-revision evidence is what proves an assignment
                -- applied. The transport receipt alone never does.
                if type(event.objective_revision) == "number" and event.objective_revision > 0 then
                    job.admitted = true
                end
                if not job.assigned then
                    -- The first request is issued once per encounter. A restart never repeats
                    -- it merely because its transport receipt has not returned yet.
                    job.request = objective.assign(context, mission, squad.slot, context:slot(director), -1)
                    job.group, job.assigned = -1, true
                elseif job.admitted then
                    choose(context, state, index)
                else
                    diagnose(context, "waiting_objective_confirmation")
                end
                local zero = #jobs == #squads
                for _, member in ipairs(jobs) do
                    zero = zero and (member.skipped or (member.transported and member.observed
                        and member.observed.available and member.observed.alive == 0))
                end
                if zero then
                    for _, member in ipairs(jobs) do member.cleared = true end
                    status(context, "population_zero")
                    diagnose(context, "clearance_observed")
                else
                    status(context, "running")
                    if job.admitted then diagnose(context, "waiting_clearance") end
                end
                return
            end
        end
    end)
    if not definition.kind then
        wrap("on_event_object_state", function() end)
    end
    if #combatants > 0 then
        -- Diagnostic only: records whether the bound combatant reports health at all.
        wrap("on_event_damage_state", function(context, _, event)
            for _, slot in ipairs(combatants) do
                if event.source_generation == source and matches(event, context:slot(slot)) then
                    context:set_variable(prefix .. "health", string.format("%d|%.4f|%.4f",
                        event.revision or -1, event.health or -1, event.shield or -1))
                end
            end
        end)
    end
    return controller
end
