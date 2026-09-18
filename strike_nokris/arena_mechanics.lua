-- Build86657 reconstruction: ultra attachment28 selects the arena0 biped candidate.
-- Transport proves an owned write, not immunity. Cleanup53 targets exact volume119.
return function(mission, controller, region)
    local held, source, spawn, cleanup_request, shield_request, beam_request
    local cleanup_next, shield_next, beam_next, beam_state
    local function valid(state)
        return held==region and source~=nil and state:variable("route.invalidated")~=true
            and state:variable("later.arena.status")~="blocked"
            and state:variable("crystals.arena.status")~="blocked"
            and state:variable("arena.mechanics.blocked")~=true
    end
    local function stop(context)
        context:set_variable("arena.mechanics.blocked",true)
        context:set_variable("route.invalidated",true)
        cleanup_request,shield_request,beam_request=nil,nil,nil
    end
    local function slot(context,name,kind,index)
        local value=context:slot(assert(mission.Slot[name]))
        assert(value.object_tag==0x80F733F4 and value.registry_key==0xF236EBA9
            and value.slot_type==kind and value.slot_index==index,"arena mechanics binding mismatch")
        return value
    end
    local function cleanup(context,active)
        cleanup_request=slot(context,"TG_RELIC_CLEANUP_80F733F4",32,53):set_volume_active{
            volume=slot(context,"SLOT_0077_80F733F4",60,119),active=active}
        cleanup_next=active and "restored" or "disabled"
        context:set_variable("arena.cleanup","submitted")
    end
    local function shield(context,active)
        shield_request=slot(context,"HO_SHIELD_ULTRA",26,28):set_squad_attachment{
            source=slot(context,"SQ_OGRE_ARENA_1",1,0),spawn_generation=spawn,active=active}
        shield_next=active and "selected" or "cleared"
        context:set_variable("arena.attachment","submitted")
    end
    -- The crystal-to-bubble beams (video 5.3) are the arena's hop-on30. Its authored object
    -- filter50 names the beam hosts; a bare squad selection attaches it to the ogre with no
    -- crystal endpoint (run BE3E5817: accepted, repaired, nothing rendered). Cosmetic: a refusal
    -- is recorded and never fences the mechanics. The Host variable budget is full (128 keys),
    -- so this state is VM-local; reload already stops this controller.
    local beam_revision=0
    local function beam(context,active)
        local requests={}
        local filter=slot(context,"OF_CRYSTAL_BEAM_HOPON_80F733F4",34,50)
        if active then
            local names={"O_DOOR_CRYSTAL_0_80F733F4","O_DOOR_CRYSTAL_1_80F733F4","O_DOOR_CRYSTAL_2","O_DOOR_CRYSTAL_3"}
            local indices={31,33,35,37}
            local crystals={}
            for index,name in ipairs(names) do crystals[index]=slot(context,name,4,indices[index]) end
            requests[#requests+1]=filter:set_object_filter{targets=crystals}
        end
        beam_revision=beam_revision+1
        requests[#requests+1]=slot(context,"HO_CRYSTAL_BEAM_80F733F4",26,30):set_mission_effect{
            filter=active and filter or nil,enabled=active,revision=beam_revision}
        beam_request=requests
        beam_next=active and "selected" or "cleared"
        beam_state="submitted"
    end
    local function advance(context,state)
        if not valid(state) or state:variable("later.arena.entered")~=true then return end
        if not state:variable("arena.cleanup") then cleanup(context,false) end
        local crystals_done=state:variable("crystals.arena.status")=="all_inactive"
        if spawn and state:variable("arena.cleanup")=="disabled"
            and not state:variable("arena.attachment") then shield(context,true) end
        if spawn and state:variable("arena.attachment")=="selected" and not beam_state then beam(context,true) end
        if crystals_done and state:variable("arena.attachment")=="selected" then shield(context,false) end
        if crystals_done and beam_state=="selected" then beam(context,false) end
        if crystals_done and state:variable("arena.attachment")=="cleared"
            and state:variable("later.arena.status")=="population_zero"
            and state:variable("arena.cleanup")=="disabled" then cleanup(context,true) end
    end
    for _,name in ipairs{"on_event_client_state_changed","on_event_player_trigger",
        "on_event_squad_state","on_event_object_state","on_event_effect_result","on_load"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            if name=="on_event_client_state_changed" then
                if state:variable("arena.cleanup") and (held~=event.held_region_index
                    or source~=event.source_generation) then stop(context) end
                held,source=event.held_region_index,event.source_generation
                if type(source)~="string" or source=="" or source=="0" then source=nil end
            end
            if previous then previous(context,state,event) end
            if name=="on_load" then
                if state:variable("arena.cleanup") then stop(context) end
                return
            end
            if not valid(state) then
                if cleanup_request or shield_request then stop(context) end
                return
            end
            if name=="on_event_squad_state" and event.object_tag==0x80F733F4
                and event.registry_key==0xF236EBA9 and event.slot_type==1 and event.slot_index==0
                and state:variable("later.arena.status")=="running" then
                -- The entry controller first requires its placement receipt and living baseline.
                if event.source_generation~=source or (event.registration_reset and spawn)
                    or (spawn and event.spawn_generation~=spawn) then stop(context); return end
                if not spawn and event.population_available==true and event.alive_count
                    and event.alive_count>0 and event.spawn_generation and event.spawn_generation>0
                    and event.sense_generation and event.sense_generation>0 then spawn=event.spawn_generation end
            end
            if name=="on_event_effect_result" then
                local field,next_value
                if beam_request then
                    for index,request in ipairs(beam_request) do
                        if event.request_key:matches(request) then
                            if event.source_generation~=source or event.outcome~="transport_staged" then
                                beam_request=nil; beam_state="refused"
                            else
                                table.remove(beam_request,index)
                                if #beam_request==0 then beam_request=nil; beam_state=beam_next end
                            end
                            break
                        end
                    end
                end
                if cleanup_request and event.request_key:matches(cleanup_request) then
                    cleanup_request=nil; field,next_value="arena.cleanup",cleanup_next
                elseif shield_request and event.request_key:matches(shield_request) then
                    shield_request=nil; field,next_value="arena.attachment",shield_next
                end
                if field then
                    if event.source_generation~=source or event.outcome~="transport_staged" then
                        stop(context); return
                    end
                    context:set_variable(field,next_value)
                end
            end
            advance(context,state)
        end
    end
    return controller
end
