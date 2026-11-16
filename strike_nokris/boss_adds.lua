-- Reconstructed damage-interval summons. Retail shows small Hive materializing as Nokris returns
-- to damage (video 20:14); which authored G squad belongs to which interval is a reconstruction.
-- Every squad is optional and no wave gates the encounter model.
return function(mission, objective, controller)
    local region = assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local waves = {
        {stage="damage", phase=1, squads={"SQ_THRALL_G_LEFT01","SQ_THRALL_G_RIGHT01",
            "SQ_TROOPER_G_1","SQ_SNIPER_G_1"}, indices={22,24,26,28}},
        {stage="damage", phase=2, squads={"SQ_THRALL_G_LEFT_CENTER","SQ_THRALL_G_RIGHT_CENTER",
            "SQ_TROOPER_G_2","SQ_SNIPER_G_2"}, indices={23,25,27,31}},
        {stage="final_damage", phase=3, squads={"SQ_CRUSADER_G_1","SQ_CRUSADER_G_2",
            "SQ_SNIPER_G_LEFT","SQ_SNIPER_G_RIGHT"}, indices={20,21,29,30}},
    }
    for index, wave in ipairs(waves) do
        local optional = {}
        for _, name in ipairs(wave.squads) do optional[name] = true end
        controller = require("strike_nokris.entry_population")(mission, objective, controller, {
            name="boss_adds"..index, region=region, registry=0xC55749AB, object=0x80F732CE,
            director="OBJ_NOKRIS_MAIN_LOOP", director_index=4, objective_count=5,
            squads=wave.squads, squad_indices=wave.indices, optional=optional,
            ready=function()
                local view = controller.boss_status and controller.boss_status()
                local model = view and not view.blocked and view.model
                return model ~= nil and model.stage == wave.stage and model.phase == wave.phase
            end,
        })
    end
    return controller
end
