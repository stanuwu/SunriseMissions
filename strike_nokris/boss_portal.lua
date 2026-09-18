-- The authored portal sequence is event-driven: once before boss admission and once per native health gate.
local decimal=require("strike_nokris.identity_text").positive_decimal
local phases=require("strike_nokris.phase_plan")
local function positive(value) return math.type(value)=="integer" and value>0 end
return function(mission,controller)
    local region=assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local held,source,request,request_stage,request_phase
    local initial_started,last_phase=false,0
    local spires_started=false
    local visual_requests={}
    local fenced=false
    -- Shield/tether hop-ons host on Nokris through their authored type-34 filters; a bare squad
    -- selection rendered nothing (run BE3E5817). Revisions and live lines are VM-local: the Host
    -- variable budget is full and reload already fences this controller.
    local effect_revisions,active_lines,active_count={},{},0
    local function status(context,stage,result)
        if stage=="initial" then
            context:set_variable("nokris.intro",result=="pending" and "portal_submitted"
                or result=="staged" and "portal_staged" or "blocked")
        end
    end
    local function slot(context)
        local value=context:slot(mission.Slot.PF_NOKRIS_HIVE_PORTAL_1_S_WAVE_SPAWN_HIVE)
        assert(value.object_tag==0x80F732CE and value.registry_key==0xC55749AB
            and value.slot_type==5 and value.slot_index==19,"Nokris portal sequence binding mismatch")
        return value
    end
    local function submit(context,stage,phase)
        if fenced or request then return false end
        request=assert(slot(context):play_sequence{},"Nokris portal sequence returned no request")
        request_stage,request_phase=stage,phase
        if stage=="initial" then initial_started=true end
        status(context,stage,"pending")
        return true
    end
    local function stop(context,stage,route)
        request=nil; request_stage=nil; request_phase=nil; fenced=true
        status(context,stage,"blocked")
        if route then context:set_variable("route.invalidated",true) end
    end
    local function object(context,symbol,index,active)
        local value=context:slot(mission.Slot[symbol])
        assert(value.object_tag==0x80F732CE and value.registry_key==0xC55749AB
            and value.slot_type==4 and value.slot_index==index,"Nokris visual binding mismatch")
        visual_requests[#visual_requests+1]=assert(value:set_object_active{active=active})
    end
    local function effect(context,symbol,index,filter_symbol,filter_index,selection,active)
        local value=context:slot(mission.Slot[symbol])
        assert(value.object_tag==0x80F732CE and value.registry_key==0xC55749AB
            and value.slot_type==26 and value.slot_index==index,"Nokris phase line binding mismatch")
        local filter
        if active then
            filter=context:slot(mission.Slot[filter_symbol])
            assert(filter.object_tag==0x80F732CE and filter.registry_key==0xC55749AB
                and filter.slot_type==34 and filter.slot_index==filter_index,"Nokris phase filter binding mismatch")
            visual_requests[#visual_requests+1]=assert(filter:set_object_filter(selection))
        end
        effect_revisions[index]=(effect_revisions[index] or 0)+1
        visual_requests[#visual_requests+1]=assert(value:set_mission_effect{
            filter=filter,enabled=active,revision=effect_revisions[index]})
    end
    -- A tether hosts on its crystal (the arena beams only rendered once their filter named the
    -- crystals; the wizard filter selecting Nokris rendered nothing in run B09BC0FA).
    local function line(context,number,crystal_symbol,active)
        local selection=active and {target=context:slot(mission.Slot[crystal_symbol])} or nil
        effect(context,"PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_"..number.."_HO_EXP_ULTRA_WIZARD_NOKRIS_SHIELD",
            34+(number-1)*7,"PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_"..number.."_SPAWNER_FILTER",149+(number-1)*2,selection,active)
    end
    local function bubble(context,active)
        local selection=active and {squad=context:slot(mission.Slot.NOKRIS_BOSS_SQUAD)} or nil
        effect(context,"HO_EXP_ULTRA_WIZARD_NOKRIS_SHIELD",137,"NOKRIS_SHIELD_FILTER",160,selection,active)
    end
    -- Retail: a tether disappears when its crystal breaks, the bubble when the last one does.
    local function crystal_state(context,event)
        if event.object_tag~=0x80F732CE or event.registry_key~=0xC55749AB or event.slot_type~=4 then return end
        local entry=active_lines[event.slot_index]
        if not entry then return end
        if event.alive and event.present then
            if not entry.seen then
                entry.seen=true
                object(context,"PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_"..entry.number..
                    "_OB_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_SPAWNER_NAMED",30+entry.number*7,false)
            end
            return
        end
        if not entry.seen or event.alive or event.present then return end
        active_lines[event.slot_index]=nil; active_count=active_count-1
        line(context,entry.number,nil,false)
        if active_count==0 then bubble(context,false) end
    end
    -- The authored per-crystal sequence is the spire crumble; the spawner object is removed once its
    -- crystal reports present (run D6EA20F6: deactivating it at onset made the spire vanish).
    local function sequence(context,number)
        local value=context:slot(mission.Slot["PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_"..number.."_SE_EXP_ULTRA_WIZARD_NOKRIS_SHIELD"])
        assert(value.object_tag==0x80F732CE and value.registry_key==0xC55749AB
            and value.slot_type==5 and value.slot_index==39+(number-1)*7,"Nokris crumble sequence binding mismatch")
        visual_requests[#visual_requests+1]=assert(value:play_sequence{})
    end
    local function raise_spires(context)
        if spires_started then return end
        spires_started=true
        for number=1,6 do object(context,"PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_"..number..
            "_OB_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_SPAWNER_NAMED",30+number*7,true) end
    end
    local function raise_environment(context)
        object(context,"PF_NOKRIS_HIVE_PORTAL_1_O_STARTUP_FX_OBJECT",10,true)
        object(context,"PF_NOKRIS_HIVE_PORTAL_1_O_GATEWAY_PORTAL",11,true)
        raise_spires(context)
    end
    local function activate_phase_visual(context,spawn_generation,phase)
        local definition=assert(phases[phase])
        local boss=context:slot(mission.Slot.NOKRIS_BOSS_SQUAD)
        assert(boss.object_tag==0x80F732CE and boss.registry_key==0xC55749AB
            and boss.slot_type==1 and boss.slot_index==0,"Nokris visual boss binding mismatch")
        assert(positive(spawn_generation),"Nokris visual spawn generation required")
        for member,crystal in ipairs(definition.crystals) do
            local number=(crystal-38)//7+1
            sequence(context,number)
            if not active_lines[crystal] then active_count=active_count+1 end
            active_lines[crystal]={number=number,seen=false}
            line(context,number,definition.crystal_symbols[member],true)
        end
        bubble(context,true)
        if phase==1 then
            visual_requests[#visual_requests+1]=assert(context:scene(
                mission.Scene.EXP_ULTRA_WIZARD_NOKRIS_PORTAL_SCENE):activate{})
            visual_requests[#visual_requests+1]=assert(context:scene(
                mission.Scene.EXP_ULTRA_WIZARD_NOKRIS_SHIELD_PHASE1_SCENE):activate{})
        end
    end
    local function activate_visual_probe(context,spawn_generation)
        raise_environment(context)
        activate_phase_visual(context,spawn_generation,1)
    end
    local function captured_visual_probe(state)
        local flow=state:variable("directive.flow")
        local active_suffix="|511|active|0|none"
        local blocked_suffix="|511|blocked|0|reload_retained"
        local prefix=type(flow)=="string" and string.sub(flow,1,15)=="D2|9|none|88|2|"
        local suffix=prefix and (string.sub(flow,-#active_suffix)==active_suffix and active_suffix
            or string.sub(flow,-#blocked_suffix)==blocked_suffix and blocked_suffix)
        local sequence=suffix and tonumber(string.sub(flow,16,#flow-#suffix))
        local active=suffix==active_suffix and state:variable("later.boss_entry.status")=="running"
            and state:variable("nokris.intro")=="transport_staged"
        local blocked=suffix==blocked_suffix and state:variable("later.boss_entry.status")=="blocked"
            and state:variable("nokris.intro")=="blocked"
        return sequence and sequence>=5156 and (active or blocked)
            and state:variable("route.invalidated")==true
    end
    local function captured_reload(state)
        local flow=state:variable("directive.flow")
        local before=flow=="D2|8|none|88|2|2206|255|active|0|none"
            and state:variable("prefight.entry")=="arrived"
            and state:variable("later.prefight.status")=="population_zero"
            and state:variable("later.prefight.reason")=="clearance_observed"
            and state:variable("nokris.intro")==nil
            and state:variable("later.boss_entry.status")==nil
            and state:variable("route.invalidated")~=true
        local after=flow=="D2|8|none|88|2|3425|255|blocked|0|reload_retained"
            and state:variable("prefight.entry")=="blocked"
            and state:variable("later.prefight.status")=="blocked"
            and state:variable("later.prefight.reason")=="retained_reload"
            and state:variable("nokris.intro")=="blocked"
            and state:variable("later.boss_entry.status")=="blocked"
            and state:variable("later.boss_entry.reason")=="retained_reload"
            and state:variable("route.invalidated")==true
        return state:variable("nokris.chant")=="transport_staged" and (before or after)
    end
    for _,name in ipairs{"on_start","on_load","on_event_client_state_changed","on_event_squad_state",
        "on_event_object_state","on_event_player_trigger","on_event_effect_result","on_event_native_reaction"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            local visual_reload=name=="on_load" and captured_visual_probe(state)
            local portal_reload=name=="on_load" and captured_reload(state)
            if previous then previous(context,state,event) end
            if name=="on_load" then
                if visual_reload then
                    activate_visual_probe(context,2)
                elseif portal_reload then
                    held,source=region,"2"
                    submit(context,"initial")
                end
                return
            end
            if name=="on_event_client_state_changed" then
                local active=spires_started or initial_started or request~=nil or last_phase>0
                local departed=active and held==region
                    and (event.source_generation~=source or event.held_region_index~=region)
                held,source=event.held_region_index,event.source_generation
                if departed then
                    request=nil; request_stage=nil; request_phase=nil; fenced=true; return
                end
            end
            if fenced or held~=region or not decimal(source) then return end
            if name=="on_event_object_state" then crystal_state(context,event) end
            if state:variable("route.invalidated")~=true
                and state:variable("later.arena.exit")=="transport_staged" then
                raise_spires(context)
            end
            if name=="on_event_effect_result" and request and event.request_key
                and event.request_key:matches(request) then
                local stage,phase=request_stage,request_phase
                request=nil; request_stage=nil; request_phase=nil
                if event.source_generation~=source or event.outcome~="transport_staged" then
                    stop(context,stage,stage=="initial"); return
                end
                if stage=="initial" then
                    status(context,stage,"staged")
                    raise_environment(context)
                else
                    if not phase or phase~=last_phase+1 then stop(context,stage,false); return end
                    last_phase=phase; status(context,stage,"staged")
                end
            end
            if not initial_started and state:variable("nokris.intro")==nil
                and state:variable("prefight.entry")=="arrived"
                and state:variable("later.prefight.status")=="population_zero"
                and state:variable("nokris.chant")=="transport_staged" then
                submit(context,"initial")
            end
            if name~="on_event_native_reaction" or request or last_phase>=3
                or event.source_generation~=source or event.native_admission~="reaction"
                or not positive(event.health_phase) or event.health_phase~=last_phase+1
                or not decimal(event.capture_sequence) then return end
            local view=controller.boss_status and controller.boss_status()
            local model=view and view.model
            if not model or not view.encounter_owned or view.blocked or model.source~=source
                or model.boss~=event.spawn_generation or model.phase+1~=event.health_phase
                or (model.stage~="opening_damage" and model.stage~="damage") then return end
            if submit(context,"phase"..event.health_phase,event.health_phase) then
                activate_phase_visual(context,event.spawn_generation,event.health_phase)
            end
        end
    end
    return controller
end
