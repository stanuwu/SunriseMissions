-- Reconstructed cue timing over authored build86657 dialogue; transport is not audible completion.
local compact=require("strike_nokris.opening_state")
local ledger=require("strike_nokris.squad_ledger")
return function(mission,controller,provider)
    local owner=assert(mission.Slot.M_DIALOG_SENSOR)
    local cues=assert(mission.DialogueCue.M_DIALOG_SENSOR)
    local opening=assert(mission.states.STATE_80F729E1_0000_0000_80F729D5).region_index
    local ritual=assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local ordinals={assert(cues.CUE_1),assert(cues.CUE_5),assert(cues.CUE_6),assert(cues.CUE_7),
        assert(cues.CUE_9),assert(cues.CUE_10),assert(cues.CUE_11),assert(cues.CUE_12),
        -- Appended so the first eight keep their seen/staged bits: intel (9), relic hint (10),
        -- chant reaction (11), and Nokris's taunts for the three protected intervals and the
        -- final damage interval (12-15). Their timing is reconstructed, not authored.
        assert(cues.CUE_3),assert(cues.CUE_4),assert(cues.CUE_2),
        assert(cues.CUE_17),assert(cues.CUE_18),assert(cues.CUE_19),assert(cues.CUE_20)}
    local initialized,blocked,held,source,pending
    local seen,queued,staged=0,0,0
    local requests,applied,started,finished={},0,0,0
    local decimal=require("strike_nokris.identity_text").positive_decimal
    local function playback(context,reason)
        context:set_variable("dialogue.playback",tostring(applied).."|"..tostring(started).."|"
            ..tostring(finished).."|"..reason)
    end
    -- A future native provider must join its cue/application identity to the owned Host request.
    -- Production passes none: transport does not manufacture playback observations.
    local function observe_playback(context,event)
        if not provider or type(provider.read)~="function" or type(provider.supports)~="function" then return end
        local inputs=provider.read(event) or {}
        assert(type(inputs)=="table" and #inputs<=8,"bounded playback batch required")
        for _,input in ipairs(inputs) do
            local row
            if type(input)=="table" then
                for _,value in ipairs(requests) do
                    if input.request_key and input.request_key:matches(value.request) then row=value; break end
                end
            end
            if not row or input.source_generation~=source or event.source_generation~=source
                or input.region~=held or input.region~=row.region or input.cue~=row.cue
                or input.object_tag~=0x80F7355F or input.registry_key~=0xAC8DBDA8
                or input.slot_type~=53 or input.slot_index~=2 then playback(context,"foreign")
            elseif not row.staged then playback(context,"not_staged")
            elseif not decimal(input.sequence) then playback(context,"invalid_sequence")
            elseif row.sequence and (#input.sequence<#row.sequence
                or (#input.sequence==#row.sequence and input.sequence<=row.sequence)) then
                playback(context,"stale")
            elseif provider.supports(input.kind)~=true then playback(context,"unavailable")
            elseif input.kind=="client_applied" then
                applied=applied | row.bit; row.sequence=input.sequence; playback(context,"observed")
            elseif input.kind=="playback_started" and applied & row.bit~=0 then
                started=started | row.bit; row.sequence=input.sequence; playback(context,"observed")
            elseif input.kind=="playback_finished" and started & row.bit~=0 then
                finished=finished | row.bit; row.sequence=input.sequence; playback(context,"observed")
            else playback(context,"out_of_order") end
        end
    end
    local function stop(context,reason)
        blocked=true; queued=0; pending=nil
        context:set_variable("dialogue.status","blocked")
        context:set_variable("dialogue.reason",reason)
    end
    local function initialize(context,state)
        if initialized then return end
        initialized=true
        if state:variable("dialogue.status") or state:variable("dialogue.seen")
            or state:variable("dialogue.source") then stop(context,"retained_dialogue")
        else playback(context,provider and "awaiting" or "unavailable") end
    end
    local function remember(context,index)
        local bit=1 << (index-1)
        if seen & bit~=0 then return end
        seen=seen | bit; queued=queued | bit
        context:set_variable("dialogue.seen",seen)
    end
    local function collect(context,state)
        if held==opening then
            if state:variable("entry.placed")==true and ledger.get(state,"entry.squad1","transported")==true
                and not compact.get(state,"entry.failed") then remember(context,1) end
            local ready=not compact.get(state,"entry.crystals.failed")
            for index=1,2 do
                local prefix="entry.crystal"..index.."."
                for _,field in ipairs{"observed","live","spawned","transported"} do
                    ready=ready and compact.get(state,prefix..field)==true
                end
            end
            if ready then remember(context,2) end
            if compact.get(state,"entry.knight.placed") and not compact.get(state,"entry.failed") then
                remember(context,9)
            end
            -- The carrier's qualified zero after living is when its relic is on the floor.
            if state:variable("entry.knight.zero_after_alive")==true then remember(context,10) end
        elseif held==ritual then
            local start=state:variable("gstart.status")
            if state:variable("entry.gate.result")=="transport_staged"
                and (start=="placement_submitted" or start=="placed" or start=="objective_pending" or start=="running") then
                remember(context,3)
            end
            for index,name in ipairs{"icy_approach","ritual_quartet","prefight"} do
                if state:variable("later."..name..".entered")==true
                    and state:variable("later."..name..".status")~="blocked"
                    and (name~="prefight" or state:variable("prefight.entry")=="arrived") then remember(context,index+3) end
            end
            if state:variable("nokris.chant")=="transport_staged" then remember(context,11) end
            if state:variable("nokris.intro")=="transport_staged"
                and state:variable("later.boss_entry.status")=="running" then remember(context,7) end
            local view=controller.boss_status and controller.boss_status()
            local model=view and not view.blocked and view.model
            if model and model.stage=="shield" and model.phase>=1 and model.phase<=3 then
                remember(context,11+model.phase)
            elseif model and model.stage=="final_damage" then remember(context,15) end
            -- Cue 12 is the victory line. Only the accepted completion model selects it; a
            -- carrier/boss population zero never does.
            if state:variable("nokris.capability")=="model_complete" then remember(context,8) end
        end
        -- Possession has no production ingress: the opening relic hint keys on the carrier's zero instead.
    end
    local function dispatch(context)
        if pending or queued==0 then return end
        for index,cue in ipairs(ordinals) do
            local bit=1 << (index-1)
            if queued & bit~=0 then
                local slot=context:slot(owner)
                -- The SDK resolves this shared owner against the current state-local occurrence.
                assert(slot.object_tag==0x80F7355F and slot.registry_key==0xAC8DBDA8
                    and slot.slot_type==53 and slot.slot_index==2,"Strange Terrain dialogue binding mismatch")
                pending={request=slot:play_dialogue_cue{cue=cue},bit=bit,cue=cue,region=held}
                requests[#requests+1]=pending
                queued=queued & ~bit
                context:set_variable("dialogue.pending",cue)
                context:set_variable("dialogue.status","submitted")
                return
            end
        end
    end
    for _,name in ipairs{"on_start","on_load","on_event_client_state_changed","on_event_object_state",
        "on_event_squad_state","on_event_effect_result","on_event_player_trigger","on_event_trigger_entered"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            initialize(context,state)
            if previous then previous(context,state,event) end
            if name=="on_load" then stop(context,"retained_dialogue"); return end
            if blocked or name=="on_start" then return end
            if state:variable("route.invalidated")==true then stop(context,"route_invalidated"); return end
            if name=="on_event_client_state_changed" then
                local generation=event.source_generation
                if source and generation~=source then stop(context,"dialogue_source_lost"); return end
                if pending and event.held_region_index~=held then stop(context,"pending_dialogue_region_lost"); return end
                if event.held_region_index~=held then queued=0 end
                held=event.held_region_index
                if type(generation)~="string" or generation=="" or generation=="0" then return end
                if held~=opening and held~=ritual then return end
                source=generation; context:set_variable("dialogue.source",source)
            end
            if not source or (held~=opening and held~=ritual) then return end
            local receipt=name=="on_event_effect_result" and pending and event.request_key
                and event.request_key:matches(pending.request)
            if receipt then
                if event.source_generation~=source or event.effect~="slot.play_dialogue_cue"
                    or event.outcome~="transport_staged" then stop(context,"dialogue_receipt_refused"); return end
                staged=staged | pending.bit; pending.staged=true; pending=nil
                context:set_variable("dialogue.staged",staged)
                context:set_variable("dialogue.pending",-1)
                context:set_variable("dialogue.status","transport_staged")
            end
            if event.source_generation~=source then return end
            collect(context,state); dispatch(context)
            observe_playback(context,event)
        end
    end
    return controller
end
