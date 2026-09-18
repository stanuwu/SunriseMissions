-- Normal-solo entry reconstruction for the build-86657 gauntlet occurrence.
-- The Simmumah exit is an explicit continuous-population policy, not an authored death claim.
-- Numbered siblings that share a used squad's spawn rule belong to the same wave; _ALT squads are alternates.
local population = require("strike_nokris.entry_population")
return function(mission, objective, controller)
    local region = assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local definitions = {
        {name="start_support",kind=31,index=37,volume_index=103,
            trigger="PT_START_SEED_PROPS",volume="SLOT_0067_80F734C7",
            passive_trigger=true,capture_arrival=true,
            director="OBJ_RITUAL_GAUNTLET_START",director_index=27,objective_count=2,
            squads={"SQ_START_SUPPORT"},squad_indices={1},
            ready=function(state)
                local value=state:variable("gstart.status")
                return value=="placed" or value=="objective_pending" or value=="running"
            end},
        {name="icy_approach",kind=31,index=38,volume_index=102,
            trigger="PT_START_SUPPORT",volume="TV_START_SUPPORT",
            director="OBJ_RITUAL_GAUNTLET_ENTRANCE",director_index=28,objective_count=6,
            squads={"SQ_ENTRANCE_START","SQ_ENTRANCE_SUPPORT","SQ_ENTRANCE_SUPPORT_1"},squad_indices={2,3,4},
            requires={"later.start_support.entered"}},
        {name="outer_doorway",kind=31,index=39,volume_index=104,
            trigger="PT_ENTRANCE_START",volume="SLOT_0068_80F734C7",
            director="OBJ_RITUAL_GAUNTLET_ENTRANCE",director_index=28,objective_count=6,
            squads={"SQ_ENTRANCE_SUPRISE"},squad_indices={5},
            requires={"later.icy_approach.entered"}},
        {name="ritual_quartet",kind=31,index=40,volume_index=105,
            trigger="PT_ENTRANCE_SUPRISE",volume="SLOT_0069_80F734C7",
            director="OBJ_RITUAL_GAUNTLET",director_index=29,objective_count=9,
            squads={"SQ_MAIN_PRAYING","SQ_MAIN_PRAYING_1"},squad_indices={8,11},
            requires={"later.outer_doorway.entered"}},
        {name="simmumah",kind=31,index=41,volume_index=108,
            trigger="PT_GAUNTLET_ENTER",volume="SLOT_006C_80F734C7",
            director="OBJ_RITUAL_GAUNTLET",director_index=29,objective_count=9,
            squads={"SQ_MAIN_ANCHOR_80F734C7","SQ_MAIN_SUPPORT_80F734C7",
                "SQ_MAIN_SUPPORT_1","SQ_MAIN_SUPPORT_2"},squad_indices={6,14,15,17},
            requires={"later.ritual_quartet.entered"}},
        {name="thrall_surge",kind=31,capture_arrival=true,index=42,volume_index=109,
            trigger="PT_GAUNTLET_STOP_PRAYING",volume="SLOT_006D_80F734C7",
            director="OBJ_RITUAL_GAUNTLET",director_index=29,objective_count=9,
            squads={"SQ_MAIN_EXIT_THRALL","SQ_MAIN_EXIT_THRALL_1","SQ_MAIN_EXIT_THRALL_2"},squad_indices={18,19,20},
            arm_ready=function(state)
                return state:variable("later.simmumah.entered")==true
            end,
            ready=function(state)
                -- All four selected jobs must first qualify alive in the same source lifetime.
                -- A reset, unknown population or changed spawn cannot satisfy this reconstruction.
                return state:variable("later.simmumah.status")=="population_zero"
                    and state:variable("later.ritual_quartet.status")=="population_zero"
                    and state:variable("later.simmumah.wave")=="transport_staged"
            end},
        {name="yellow_chambers",
            director="OBJ_RITUAL_TUNNEL",director_index=30,objective_count=5,
            squads={"SQ_TUNNEL_START","SQ_TUNNEL_START_1","SQ_TUNNEL_START_2"},squad_indices={22,23,24},
            -- The type-30 occupancy monitor (PM_GAUNTLET_SPAWN_EXIT_THRALLS, slot 43) never reports a
            -- change under the 0.5 DLL. Place the tunnel knights when the player leaves the summoning room.
            ready=function(state) return state:variable("later.thrall_surge.entered")==true end},
        {name="chamber_support",kind=31,capture_arrival=true,index=44,volume_index=111,
            trigger="PT_TUNNEL_SPAWN_SUPPORT",volume="SLOT_006F_80F734C7",
            director="OBJ_RITUAL_TUNNEL",director_index=30,objective_count=5,
            squads={"SQ_TUNNEL_SUPPORT","SQ_TUNNEL_SUPPORT_1"},squad_indices={25,26},
            arm_ready=function(state)
                return state:variable("later.thrall_surge.entered")==true
            end,
            requires={"later.yellow_chambers.entered"}},
    }
    local optional={SQ_ENTRANCE_SUPPORT_1=true,SQ_MAIN_EXIT_THRALL_1=true,
        SQ_TUNNEL_START_1=true,SQ_TUNNEL_START_2=true,SQ_TUNNEL_SUPPORT_1=true}
    for _, definition in ipairs(definitions) do
        definition.optional = optional
        definition.region, definition.registry, definition.object = region, 0x9E1E5EF6, 0x80F734C7
        controller = population(mission, objective, controller, definition)
    end
    local wave_request, wave_source
    for _, name in ipairs{"on_event_player_trigger", "on_event_effect_result"} do
        local previous = controller[name]
        controller[name] = function(context, state, event)
            if name=="on_event_effect_result" and wave_request and event.request_key:matches(wave_request) then
                wave_request = nil
                if event.source_generation ~= wave_source or event.outcome ~= "transport_staged" then
                    context:set_variable("later.simmumah.status", "blocked")
                    context:set_variable("later.simmumah.reason", "wave_refused")
                    context:set_variable("later.simmumah.wave", "refused")
                else
                    context:set_variable("later.simmumah.wave", "transport_staged")
                end
            end
            previous(context, state, event)
            if state:variable("later.simmumah.entered")
                and state:variable("later.simmumah.status")~="blocked"
                and not state:variable("later.simmumah.wave") then
                local wave = context:slot(mission.Slot.S_WAVE_SPAWN_HIVE_80F734C7)
                assert(wave.registry_key==0x9E1E5EF6 and wave.object_tag==0x80F734C7
                    and wave.slot_type==5 and wave.slot_index==33, "gauntlet wave binding mismatch")
                -- Exact emitter80BF4228; the type5 receipt is not native sequence completion.
                wave_request, wave_source = wave:play_sequence{}, event.source_generation
                context:set_variable("later.simmumah.wave", "submitted")
            end
        end
    end
    return controller
end
