-- Reconstructed serial availability: the round's qualified inactive crystal admits the next
-- authored carrier. Only a dead carrier's relic can deactivate it, so the crystal is the round's
-- end. The carrier's own alive count cannot be: on 0.5 a re-placed slot's second lifetime never
-- reports one (run 2026-09-17 23:51, slot 15 spawn 2: 36 reports, no alive field).
return function(mission,objective,controller,definition)
    assert(#definition.squads>0 and #definition.squads<=6 and #definition.indices==#definition.squads)
    local prefix="carriers."..definition.name.."."
    local held,source,current,round= nil,nil,nil,0
    local last_spawn,last_assigned={},{}
    local function status(context,value) context:set_variable(prefix.."status",value) end
    local function stop(context,reason)
        status(context,"blocked"); context:set_variable(prefix.."reason",reason)
        context:set_variable("route.invalidated",true)
    end
    local function valid(state)
        return held==definition.region and source~=nil and state:variable("route.invalidated")~=true
            and state:variable(prefix.."status")~="blocked" and definition.valid(state)
    end
    local function slot(context,name,index)
        local value=context:slot(assert(mission.Slot[name]))
        assert(value.object_tag==definition.object and value.registry_key==definition.registry
            and value.slot_type==1 and value.slot_index==index,"serial carrier binding mismatch")
        return value
    end
    local function choose(context)
        if not current or not current.transported or not current.observed or current.assignment then return end
        local observed=current.observed
        if not observed.available or not observed.alive or observed.alive<=0 then return end
        local selected=-1
        if current.assigned then selected=objective.choose({objective_revision=observed.revision,
            task_costs=observed.costs},definition.objective_count,current.group,1) end
        if not current.assigned or (selected~=nil and selected~=current.group) then
            current.assignment=objective.assign(context,mission,mission.Slot[current.name],
                context:slot(mission.Slot[definition.director]),selected)
            current.group=selected; current.assigned=true
        end
    end
    local function advance(context,state)
        if not valid(state) then return end
        local inactive=definition.inactive(state) or 0
        if inactive<0 or inactive>round or inactive%1~=0 then stop(context,"crystal_obligation_drift"); return end
        if inactive<round-1 or (state:variable(prefix.."status")=="complete" and inactive~=round) then
            stop(context,"crystal_obligation_reversed"); return
        end
        if current then
            if not current.transported or current.assignment or inactive~=round then return end
            if round==#definition.squads then status(context,"complete"); return end
        elseif not definition.ready(state) then return end
        round=round+1
        local name,index=definition.squads[round],definition.indices[round]
        -- A round may name a fallback (the earlier, proven carrier of its side) for a squad the
        -- catalog refuses to resolve; a crashed VM would otherwise end the strike here.
        local fallback=definition.fallback and definition.fallback[round]
        if fallback and not pcall(function() return context:squad(mission.Squad[name]) end) then
            name,index,fallback=fallback.squad,fallback.index,nil
        end
        slot(context,name,index)
        local director=context:slot(mission.Slot[definition.director])
        -- 0.5.0 slot handles carry no objective_count; the task groups come from the SDK catalog.
        assert(director.object_tag==definition.object and director.registry_key==definition.registry
            and director.slot_type==3 and director.slot_index==definition.director_index,
            "serial carrier director mismatch")
        current={name=name,index=index,fallback=fallback}
        current.placement=context:squad(mission.Squad[name]):place{}
        context:set_variable(prefix.."round",round); status(context,"placement_pending")
    end
    for _,name in ipairs{"on_start","on_load","on_event_client_state_changed",
        "on_event_player_trigger","on_event_squad_state","on_event_object_state","on_event_effect_result"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            if previous then previous(context,state,event) end
            if name=="on_start" or name=="on_load" then
                if state:variable(prefix.."status") then stop(context,"retained_reload") end
                return
            end
            if name=="on_event_client_state_changed" then
                if current and (event.held_region_index~=held or event.source_generation~=source) then
                    stop(context,"held_or_source_lost")
                end
                held,source=event.held_region_index,event.source_generation
                if type(source)~="string" or source=="" or source=="0" then source=nil end
            end
            if not valid(state) then return end
            if current and name=="on_event_squad_state" and event.registry_key==definition.registry
                and event.object_tag==definition.object and event.slot_type==1 and event.slot_index==current.index then
                if event.source_generation~=source then stop(context,"carrier_identity_lost"); return end
                local prior=current.observed
                -- Requested initial/replacement echoes can carry their first living baseline.
                if event.registration_reset and prior then
                    stop(context,"carrier_identity_lost"); return
                end
                if not prior and last_spawn[current.index] and event.spawn_generation
                    and event.spawn_generation<=last_spawn[current.index] then return end
                if prior and event.spawn_generation~=prior.spawn then stop(context,"carrier_lifetime_changed"); return end
                if not event.sense_generation or event.sense_generation<=0 then return end
                if prior and event.sense_generation<=prior.counter then
                    local same=event.sense_generation==prior.counter and event.alive_count==prior.alive
                        and (event.population_available==true)==prior.available and event.objective_revision==prior.revision
                    for task=1,definition.objective_count do
                        same=same and (event.task_costs and event.task_costs[task])==prior.costs[task]
                    end
                    if not same then stop(context,"carrier_report_reversed") end
                    return
                end
                if not prior and (event.population_available~=true or not event.alive_count or event.alive_count<=0
                    or not event.spawn_generation or event.spawn_generation<=0) then return end
                -- A slot reused by a later round keeps the objective revision the Host composed for
                -- its previous carrier (run 09EDA740: slot 15 respawned at revision 1; run B09BC0FA:
                -- slot 19's first report echoed a synthesized 0, the Host still held 1 and refused
                -- expected_revision 0). Adopt from our own transported assignment, never from the
                -- first echo. A fresh slot must still start unassigned.
                local reused=last_spawn[current.index]~=nil
                if not prior and not reused and event.objective_revision~=nil and event.objective_revision~=0 then return end
                local costs={}
                for task=1,definition.objective_count do costs[task]=event.task_costs and event.task_costs[task] end
                current.observed={spawn=event.spawn_generation,counter=event.sense_generation,
                    alive=event.alive_count,available=event.population_available==true,
                    revision=event.objective_revision,costs=costs}
                if not prior and reused and last_assigned[current.index] then
                    -- Already at revision 1 on the Host: adopt it; the cost-based regrouping
                    -- reassigns at expected revision 1 once a report echoes it with costs.
                    current.assigned=true; current.group=-1
                end
                last_spawn[current.index]=event.spawn_generation
                choose(context)
            end
            if current and name=="on_event_effect_result" then
                local placement=current.placement and event.request_key:matches(current.placement)
                local assignment=current.assignment and event.request_key:matches(current.assignment)
                if placement or assignment then
                    if placement and current.fallback and event.source_generation==source
                        and event.outcome~="transport_staged" then
                        -- The fresh slot was refused: run this round on its side's proven carrier.
                        local fallback=current.fallback
                        slot(context,fallback.squad,fallback.index)
                        current={name=fallback.squad,index=fallback.index}
                        current.placement=context:squad(mission.Squad[fallback.squad]):place{}
                        return
                    end
                    if event.source_generation~=source or event.outcome~="transport_staged" then stop(context,"output_refused"); return end
                    if placement then current.placement=nil; current.transported=true; status(context,"running")
                    else current.assignment=nil; last_assigned[current.index]=true end
                    choose(context)
                end
            end
            advance(context,state)
        end
    end
    return controller
end
