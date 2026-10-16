-- Prepare the authored quartet after the arena exit, then gate its own type31 arrival.
-- The population admission and player arrival are separate facts: the former keeps the
-- original SQ_PRAYING placement, while prefight.entry records a qualified arrival after trigger arming.
return function(mission, objective, controller)
    local region=assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    controller=require("strike_nokris.entry_population")(mission, objective, controller, {
        name="prefight", registry=0xEE4C3055, object=0x80F732FD, region=region,
        director="OBJ_NOKRIS_BOSS_PREFIGHT", director_index=5, objective_count=2,
        squads={"SQ_PRAYING"}, squad_indices={0},
        -- Only this prepared ritual quartet may reconsider a native initialization restart.
        prepare_rebaseline=true,
        -- This is an explicit predicate population. The trigger below is independently
        -- armed so an early player crossing cannot become a population side effect.
        ready=function(state)
            return state:variable("later.arena.exit")=="transport_staged"
                and state:variable("later.arena.status")~="blocked"
                and state:variable("crystals.arena.status")~="blocked"
        end,
    })

    local decimal=require("strike_nokris.identity_text").positive_decimal
    local held,source,request,request_source,arm_sequence,arrival,bound
    local function after(left,right)
        return decimal(left) and (right=="0" or decimal(right))
            and (#left>#right or (#left==#right and left>right))
    end
    local function active(entry)
        return entry=="arm_pending" or entry=="armed" or entry=="arrived"
    end
    local function qualified(state)
        return held==region and source~=nil
            and state:variable("entry.gate.result")=="transport_staged"
            and state:variable("later.arena.exit")=="transport_staged"
            and state:variable("later.arena.status")~="blocked"
            and state:variable("crystals.arena.status")~="blocked"
            and state:variable("later.prefight.status")~="blocked"
            and state:variable("route.invalidated")~=true
    end
    local function matches(event,slot)
        return event.registry_key==slot.registry_key and event.object_tag==slot.object_tag
            and event.slot_type==slot.slot_type and event.slot_index==slot.slot_index
    end
    local function stop(context,reason)
        request,request_source,arm_sequence,arrival=nil,nil,nil,nil
        context:set_variable("prefight.entry","blocked")
        context:set_variable("later.prefight.status","blocked")
        context:set_variable("route.invalidated",true)
    end
    local function arm(context,state,event)
        local entry=state:variable("prefight.entry")
        if entry or request or not qualified(state) or not event or not after(event.mission_sequence,"0") then
            return
        end
        local trigger=context:slot(mission.Slot.PT_START_PREFIGHT)
        local volume=context:slot(mission.Slot.TV_START_PREFIGHT)
        assert(trigger.registry_key==0xEE4C3055 and trigger.object_tag==0x80F732FD
            and trigger.slot_type==31 and trigger.slot_index==9,
            "prefight entrance binding mismatch")
        assert(volume.registry_key==0xEE4C3055 and volume.object_tag==0x80F732FD
            and volume.slot_type==60 and volume.slot_index==10,
            "prefight volume binding mismatch")
        request=assert(trigger:fire_trigger{},"prefight trigger request missing")
        request_source,arm_sequence=source,event.mission_sequence
        context:set_variable("prefight.entry","arm_pending")
    end

    for _,name in ipairs{"on_start","on_load","on_event_client_state_changed",
        "on_event_player_trigger","on_event_effect_result","on_event_squad_state",
        "on_event_object_state","on_event_trigger_entered","on_event_trigger_exited",
        "on_event_trigger_state"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            if previous then previous(context,state,event) end
            local entry=state:variable("prefight.entry")
            if name=="on_load" then
                stop(context,"retained_reload")
                return
            end
            if name=="on_start" then
                if entry then stop(context,"retained_reload") end
                return
            end
            if name=="on_event_client_state_changed" then
                if bound and (active(entry) or state:variable("later.prefight.entered")==true)
                    and (event.held_region_index~=held or event.source_generation~=source) then
                    stop(context,"held_or_source_lost")
                    entry="blocked"
                end
                held,source=event.held_region_index,event.source_generation
                if not decimal(source) then source=nil end
                bound=true
            end
            if entry=="blocked" then return end
            if state:variable("route.invalidated")==true
                or state:variable("later.prefight.status")=="blocked"
                or (active(entry) and not qualified(state)) then
                if active(entry) or state:variable("later.prefight.entered")==true then
                    stop(context,"route_lost")
                end
                return
            end
            if name=="on_event_player_trigger" and active(entry) and arm_sequence
                and event.source_generation==source and after(event.mission_sequence,arm_sequence) then
                local trigger=context:slot(mission.Slot.PT_START_PREFIGHT)
                if matches(event,trigger) and event.volume_registry_key==0xEE4C3055
                    and event.volume_slot_type==60 and event.volume_slot_index==10 then
                    arrival=true
                    if entry=="armed" then
                        context:set_variable("prefight.entry","arrived")
                    end
                end
            elseif name=="on_event_effect_result" and request
                and event.request_key and event.request_key:matches(request) then
                local accepted=event.source_generation==request_source
                    -- A correlated effect receipt may retain its request's causal sequence.
                    -- Player arrival above still requires a strictly later observation.
                    and (event.mission_sequence==arm_sequence or after(event.mission_sequence,arm_sequence))
                    and event.outcome=="transport_staged"
                request=nil
                if not accepted or not qualified(state) then
                    stop(context,"arm_refused")
                elseif arrival then
                    context:set_variable("prefight.entry","arrived")
                else
                    context:set_variable("prefight.entry","armed")
                end
            end
            arm(context,state,event)
        end
    end
    return controller
end
