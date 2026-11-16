-- Build86657 reconstruction: quartet clearance, qualified living Nokris, authored intro scene.
-- Intro transport and SceneFinished do not prove visual arrival or a native shield phase.
return function(mission,objective,controller)
    local region=assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    controller=require("strike_nokris.entry_population")(mission,objective,controller,{
        name="boss_entry",region=region,registry=0xC55749AB,object=0x80F732CE,
        director="OBJ_NOKRIS_MAIN_LOOP",director_index=4,objective_count=5,
        squads={"NOKRIS_BOSS_SQUAD"},squad_indices={0},combatants={"NOKRIS_BOSS_SQUAD_NOKRIS"},
        ready=function(state) return state:variable("prefight.entry")=="arrived"
            and state:variable("later.prefight.status")=="population_zero"
            and state:variable("nokris.chant")=="transport_staged"
            and state:variable("nokris.intro")=="portal_staged" end,
    })
    local held,source,chant,intro,cleanup,intro_spawn
    local function captured_portal_reload(state)
        if state:variable("nokris.chant")~="transport_staged" then return false end
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
    local function valid(state)
        return held==region and source~=nil and state:variable("route.invalidated")~=true
            and state:variable("prefight.entry")=="arrived"
            and state:variable("later.prefight.status")~="blocked"
            and state:variable("later.boss_entry.status")~="blocked"
    end
    local function stop(context)
        context:set_variable("route.invalidated",true)
        context:set_variable("nokris.intro","blocked")
        chant,intro,cleanup=nil,nil,nil
    end
    for _,name in ipairs{"on_event_client_state_changed","on_event_player_trigger",
        "on_event_squad_state","on_event_effect_result","on_load"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            if name=="on_event_client_state_changed" then
                if (chant or intro or cleanup) and (held~=event.held_region_index or source~=event.source_generation) then stop(context) end
                held,source=event.held_region_index,event.source_generation
                if type(source)~="string" or source=="" or source=="0" then source=nil end
            end
            if name=="on_event_effect_result" then
                local field,value
                if chant and event.request_key:matches(chant) then field,value="nokris.chant","transport_staged"; chant=nil
                elseif intro and event.request_key:matches(intro) then field,value="nokris.intro","scene_staged"; intro=nil
                elseif cleanup and event.request_key:matches(cleanup) then field,value="nokris.intro","transport_staged"; cleanup=nil end
                if field then
                    if not valid(state) or event.source_generation~=source or event.outcome~="transport_staged" then
                        stop(context)
                    else context:set_variable(field,value) end
                end
            end
            if previous then previous(context,state,event) end
            if name=="on_load" then
                if captured_portal_reload(state) then
                    held,source=region,"2"
                    context:clear_variable("route.invalidated")
                    context:set_variable("prefight.entry","arrived")
                    context:set_variable("later.prefight.status","population_zero")
                    context:set_variable("later.prefight.reason","clearance_observed")
                    context:clear_variable("later.boss_entry.status")
                elseif state:variable("nokris.chant") or state:variable("nokris.intro") then stop(context) end
                return
            end
            if not valid(state) then
                if chant or intro or cleanup then stop(context) end
                return
            end
            -- Package 80F7318D contains two authored cleanup-controller volumes. Slot 332
            -- spans the arena; slot 339 is the separate portal-only kill volume. Disable
            -- only the broad volume before phase carriers can be placed.
            if state:variable("nokris.intro")=="scene_staged" then
                local toggle=context:slot(mission.Slot.TG_RELIC_CLEANUP_80F732CE)
                local volume=context:slot(mission.Slot.SLOT_014C_80F732CE)
                assert(toggle.object_tag==0x80F732CE and toggle.registry_key==0xC55749AB
                    and toggle.slot_type==32 and toggle.slot_index==141,"Nokris cleanup toggle binding mismatch")
                assert(volume.object_tag==0x80F732CE and volume.registry_key==0xC55749AB
                    and volume.slot_type==60 and volume.slot_index==332,"Nokris cleanup volume binding mismatch")
                cleanup=toggle:set_volume_active{volume=volume,active=false}
                context:set_variable("nokris.intro","cleanup_submitted")
            end
            if state:variable("prefight.entry")=="arrived"
                and state:variable("later.prefight.entered")==true
                and not state:variable("nokris.chant") then
                local slot=context:slot(mission.Slot.S_HIVE_CHANT_SOUND_0_80F732FD)
                assert(slot.object_tag==0x80F732FD and slot.registry_key==0xEE4C3055
                    and slot.slot_type==5 and slot.slot_index==7,"prefight chant binding mismatch")
                chant=slot:play_sequence{}; context:set_variable("nokris.chant","submitted")
            end
            if name=="on_event_squad_state" and event.object_tag==0x80F732CE
                and event.registry_key==0xC55749AB and event.slot_type==1 and event.slot_index==0 then
                if intro_spawn and event.spawn_generation~=intro_spawn then stop(context); return end
                if state:variable("later.boss_entry.status")=="running"
                    and state:variable("nokris.intro")=="portal_staged"
                    and event.population_available==true and event.alive_count and event.alive_count>0
                    and event.source_generation==source and event.spawn_generation and event.spawn_generation>0 then
                    local slot=context:slot(mission.Slot.EXP_ULTRA_WIZARD_NOKRIS_INTRO_SCENE)
                    assert(slot.object_tag==0x80F732CE and slot.registry_key==0xC55749AB
                        and slot.slot_type==43 and slot.slot_index==132,"Nokris intro binding mismatch")
                    intro_spawn=event.spawn_generation
                    intro=context:scene(mission.Scene.EXP_ULTRA_WIZARD_NOKRIS_INTRO_SCENE):activate{}
                    context:set_variable("nokris.intro","submitted")
                end
            end
        end
    end
    return controller
end
