-- Reconstructed arena admission and exit. The exit combines continuous empty
-- populations with all four qualified inactive crystals, without asserting native boss death.
return function(mission, objective, controller)
    local region = assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local function settled_region(event)
        -- The current/pending legs are sparse delta fields. Held is the retained after-image.
        return event.held_region_index==region
    end
    -- Prepare the room on the preceding approach admission. Its own entrance only
    -- admits the first carrier, and can arrive before the preparation receipts settle.
    local gate_held, gate_source, gate_request, gate_sequence, gate_arrival, gate_armed
    local function gate_stop(context)
        gate_request, gate_arrival, gate_armed = nil, nil, nil
        context:set_variable("arena.entry", "blocked")
        context:set_variable("route.invalidated", true)
    end
    local function after(left, right)
        return type(left)=="string" and type(right)=="string" and left~="" and left~="0"
            and #left<=20 and (#left>#right or (#left==#right and left>right))
    end
    for _, name in ipairs{"on_start", "on_load", "on_event_client_state_changed",
        "on_event_player_trigger", "on_event_effect_result"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            if previous then previous(context,state,event) end
            if name=="on_start" or name=="on_load" then
                if state:variable("arena.entry") then gate_stop(context) end
                return
            end
            if name=="on_event_client_state_changed" then
                local event_held=settled_region(event) and region or nil
                if state:variable("arena.entry") and (event_held~=gate_held
                    or event.source_generation~=gate_source) then gate_stop(context) end
                gate_held,gate_source=event_held,event.source_generation
                if type(gate_source)~="string" or gate_source=="" or gate_source=="0" then gate_source=nil end
            end
            if gate_held~=region or not gate_source or state:variable("route.invalidated")==true
                or state:variable("arena.entry")=="blocked" then return end
            if not state:variable("arena.entry") and state:variable("entry.gate.result")=="transport_staged"
                and state:variable("later.yellow_chambers.entered")==true
                and after(event.mission_sequence,"0") then
                local trigger=context:slot(mission.Slot.PT_ARENA_ENTER)
                local volume=context:slot(mission.Slot.TV_ARENA_ENTER)
                assert(trigger.registry_key==0xF236EBA9 and trigger.object_tag==0x80F733F4
                    and trigger.slot_type==31 and trigger.slot_index==52
                    and volume.registry_key==0xF236EBA9 and volume.object_tag==0x80F733F4
                    and volume.slot_type==60 and volume.slot_index==100,"arena entrance binding mismatch")
                gate_sequence=event.mission_sequence
                gate_request=trigger:fire_trigger{}
                context:set_variable("arena.entry","arm_pending")
            end
            if name=="on_event_player_trigger" and gate_sequence and event.source_generation==gate_source
                and after(event.mission_sequence,gate_sequence)
                and event.registry_key==0xF236EBA9 and event.object_tag==0x80F733F4
                and event.slot_type==31 and event.slot_index==52
                and event.volume_registry_key==0xF236EBA9 and event.volume_slot_type==60
                and event.volume_slot_index==100 then gate_arrival=true end
            if name=="on_event_effect_result" and gate_request and event.request_key:matches(gate_request) then
                if event.source_generation~=gate_source or event.outcome~="transport_staged" then
                    gate_stop(context); return
                end
                gate_request,gate_armed=nil,true
                context:set_variable("arena.entry","armed")
            end
            if gate_arrival and gate_armed and state:variable("arena.entry")~="arrived" then
                context:set_variable("arena.entry","arrived")
            end
        end
    end
    controller = require("strike_nokris.entry_population")(mission, objective, controller, {
        name="arena", region=region, registry=0xF236EBA9, object=0x80F733F4,
        ready=function(state) return state:variable("later.chamber_support.entered")==true end,
        director="OBJ_RITUAL_ARENA", director_index=27, objective_count=16,
        -- Arena0 is the biped ogre candidate. Arena2/6 are exact type-16 turret supports.
        squads={"SQ_OGRE_ARENA_1", "SQ_ANCHOR_ARENA_1", "SQ_ANCHOR_ARENA_2",
            "SQ_ACOLYTE_ARENA_1_A", "SQ_ACOLYTE_ARENA_2", "SQ_ACOLYTE_ARENA_3"},
        squad_indices={0,2,6,10,13,14}, requires={"later.chamber_support.entered"},
    })
    controller = require("strike_nokris.crystal_group")(mission, controller, {
        name="arena", region=region, registry=0xF236EBA9, object=0x80F733F4,
        slots={"O_DOOR_CRYSTAL_0_80F733F4", "O_DOOR_CRYSTAL_1_80F733F4",
            "O_DOOR_CRYSTAL_2", "O_DOOR_CRYSTAL_3"}, indices={31,33,35,37},
        ready=function(state) return state:variable("later.arena.entered")==true end,
        valid=function(state) return state:variable("later.arena.status")~="blocked" end,
    })
    controller = require("strike_nokris.arena_mechanics")(mission, controller, region)
    controller = require("strike_nokris.serial_carriers")(mission,objective,controller,{
        name="arena",region=region,registry=0xF236EBA9,object=0x80F733F4,
        -- Four authored carriers on four fresh slots: a re-placed slot never reports alive on 0.5.
        squads={"SQ_KNIGHT_ARENA_LEFT_1","SQ_KNIGHT_ARENA_RIGHT_1",
            "SQ_KNIGHT_ARENA_LEFT_2","SQ_KNIGHT_ARENA_RIGHT_2"},indices={15,19,17,21},
        fallback={[3]={squad="SQ_KNIGHT_ARENA_LEFT_1",index=15},[4]={squad="SQ_KNIGHT_ARENA_RIGHT_1",index=19}},
        director="OBJ_RITUAL_ARENA",director_index=27,objective_count=16,
        ready=function(state) return state:variable("arena.entry")=="arrived"
            and state:variable("arena.cleanup")=="disabled"
            and state:variable("arena.attachment")=="selected"
            and state:variable("crystals.arena.status")=="observing" end,
        valid=function(state) return state:variable("later.arena.status")~="blocked"
            and state:variable("crystals.arena.status")~="blocked" end,
        inactive=function(state) return state:variable("crystals.arena.inactive") end,
    })
    for phase=2,3 do
        local threshold=phase-1
        controller=require("strike_nokris.entry_population")(mission,objective,controller,{
            name="arena_support"..phase,region=region,registry=0xF236EBA9,object=0x80F733F4,
            director="OBJ_RITUAL_ARENA",director_index=27,objective_count=16,
            squads=phase==2 and {"SQ_PHASE_2_SUPPORT_1"}
                or {"SQ_PHASE_3_SUPPORT_1","SQ_PHASE_3_SUPPORT_2","SQ_PHASE_3_SUPPORT_3"},
            squad_indices=phase==2 and {23} or {24,25,26},
            optional={SQ_PHASE_3_SUPPORT_2=true,SQ_PHASE_3_SUPPORT_3=true},
            ready=function(state) return (state:variable("crystals.arena.inactive") or 0)>=threshold
                and state:variable("arena.cleanup")=="disabled"
                and state:variable("carriers.arena.status")~="blocked" end,
        })
    end
    -- Same-wave siblings of the opening acolytes, and each carrier's authored escort. None of
    -- these gate the exit: the door still opens on the crystals and the original populations.
    local extras={
        {name="arena_acolytes",squads={"SQ_ACOLYTE_ARENA_1_B","SQ_ACOLYTE_ARENA_1_C"},indices={11,12},round=0},
        {name="arena_escort1",squads={"SQ_SUPPORT_ARENA_LEFT_1"},indices={16},round=1},
        {name="arena_escort2",squads={"SQ_SUPPORT_ARENA_RIGHT_1"},indices={20},round=2},
        {name="arena_escort3",squads={"SQ_SUPPORT_ARENA_LEFT_2"},indices={18},round=3},
        {name="arena_escort4",squads={"SQ_SUPPORT_ARENA_RIGHT_2"},indices={22},round=4},
    }
    for _,extra in ipairs(extras) do
        controller=require("strike_nokris.entry_population")(mission,objective,controller,{
            name=extra.name,region=region,registry=0xF236EBA9,object=0x80F733F4,
            director="OBJ_RITUAL_ARENA",director_index=27,objective_count=16,
            squads=extra.squads,squad_indices=extra.indices,
            optional={[extra.squads[1]]=true,[extra.squads[2] or extra.squads[1]]=true},
            ready=function(state) return state:variable("later.arena.entered")==true
                and (state:variable("carriers.arena.round") or 0)>=extra.round
                and state:variable("carriers.arena.status")~="blocked" end,
        })
    end
    local held, source, request, request_source
    local function ready(state)
        return held==region and source~=nil
            and state:variable("route.invalidated")~=true
            and state:variable("later.arena.status")=="population_zero"
            and state:variable("crystals.arena.status")=="all_inactive"
            and state:variable("arena.attachment")=="cleared"
            and state:variable("arena.cleanup")=="restored"
            and state:variable("carriers.arena.status")=="complete"
            and state:variable("later.arena_support2.status")=="population_zero"
            and state:variable("later.arena_support3.status")=="population_zero"
    end
    for _, name in ipairs{"on_event_client_state_changed", "on_event_object_state",
        "on_event_squad_state", "on_event_effect_result"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            if name=="on_event_client_state_changed" then
                held,source=event.held_region_index,event.source_generation
                if type(source)~="string" or source=="" or source=="0" then source=nil end
            end
            previous(context,state,event)
            if request and not ready(state) then
                context:set_variable("later.arena.exit","invalidated")
                request=nil
            end
            if name=="on_event_effect_result" and request and event.request_key:matches(request) then
                request=nil
                context:set_variable("later.arena.exit",
                    event.source_generation==request_source and event.outcome or "source_changed")
            end
            if ready(state) and not state:variable("later.arena.exit") then
                local door=context:slot(mission.Slot.D_EXIT_DOOR)
                assert(door.registry_key==0xF236EBA9 and door.object_tag==0x80F733F4
                    and door.slot_type==23 and door.slot_index==39,"arena exit binding mismatch")
                -- Exact resource80BEE6D3 matches runelocks. This requests its tested position;
                -- the receipt does not prove collision removal or physical passage here.
                request=door:set_channel{channel=context.sdk.device_channels.position,
                    value=context.sdk.unit(1),snap=false}
                request_source=source
                context:set_variable("later.arena.exit","submitted")
            end
        end
    end
    return controller
end
