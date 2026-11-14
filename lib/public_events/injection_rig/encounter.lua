-- Injection Rig mechanics: each Infiltrator Psion's death burns the
-- dome and opens one vent tier; a vent hit on every tier commits heroic. A Valus ends either way.
local lib = require("lib.mission_lib")
local event = require("lib.public_events.event")
local presentation = require("lib.public_events.presentation")
local runtime = require("lib.public_events.runtime")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.injection_rig.settings")
local visual_module = require("lib.public_events.injection_rig.visuals")

local module = {}

--- Builds the Injection Rig handler; its retained keys require the site's freeroam scope.
---@param definition table Authored site references.
---@return table handler Freeroam site handler.
function module.new(definition)
    local psion = definition.psion
    local commander = definition.commander
    local waves = definition.waves
    local heroic_waves = definition.heroic_waves
    local vents = definition.vents
    local visuals = visual_module.new(definition)
    -- Each site's sensor orders the same authored lines differently.
    local settings = setmetatable(definition.cues, {__index = c})

    return event.new(definition, settings, function(ev)
        local hooks = {}

        --- Returns a wave's retained placement key.
        local function wave_key(stage, index)
            return c.WAVE_KEY .. stage .. "." .. index
        end

        --- Places the supporting squads of one stage; later stages are stronger.
        local function send_stage(context, scope, stage)
            for index, unit in ipairs(waves[stage]) do
                squads.place(context, scope, unit, wave_key(stage, index))
            end
        end

        --- True when every tier took a vent hit during its own window.
        local function all_vents_hit(scope)
            for tier = 1, #vents do
                if scope:variable(c.VENT_KEY .. tier) ~= true then return false end
            end
            return true
        end

        --- Closes the open tier, if any; a repeated close changes nothing.
        local function close_window(context, scope)
            local tier = scope:variable(c.OPEN_KEY)
            if tier == nil then return end
            scope:clear_variable(c.OPEN_KEY)
            scope:cancel_timer(c.BURN_TIMER)
            visuals.close_tier(context, scope, tier)
        end

        --- Retires every live squad this attempt placed.
        local function retire_squads(context, scope)
            for stage, stage_waves in ipairs(waves) do
                for index, unit in ipairs(stage_waves) do
                    squads.retire_if_placed(context, scope, unit, wave_key(stage, index))
                end
            end
            for index, unit in ipairs(heroic_waves) do
                squads.retire_if_placed(context, scope, unit, c.HEROIC_WAVE_KEY .. index)
            end
            squads.retire_if_placed(context, scope, psion, c.PSION_KEY)
            squads.retire_if_placed(context, scope, commander, c.COMMANDER_KEY)
        end

        --- Returns the Valus counter.
        local function valus_progress(scope)
            return {scope:variable(c.VALUS_DEAD_KEY) == true and 1 or 0, 1}
        end

        --- Returns the retained ended-generation key of a Psion or Valus unit.
        local function ended_key(unit)
            return unit == psion and c.PSION_ENDED_KEY or c.VALUS_ENDED_KEY
        end

        --- Retains an ended generation when the report carries one.
        local function record_ended(scope, unit, report)
            if report.spawn_generation ~= nil then
                scope:set_variable(ended_key(unit), report.spawn_generation)
            end
        end

        --- Starts the burn after a Psion's death; its tier stays open for one window.
        local function open_window(context, scope, tier)
            scope:set_variable(c.OPEN_KEY, tier)
            visuals.open_tier(context, scope, tier)
            ev:goal(context, scope, presentation.directive.enter)
            scope:start_timer(c.BURN_TIMER, c.BURN_MS[tier])
        end

        --- Ends a burn: the next Psion stands, or the third burn brings the normal Valus.
        local function end_window(context, scope)
            close_window(context, scope)
            scope:start_timer(c.SHIELD_TIMER, c.SHIELD_CLEAR_MS)
            local killed = scope:variable(c.PSIONS_KEY) or 0
            if killed >= c.PSION_COUNT then
                scope:set_variable(c.FINAL_KEY, true)
                squads.place(context, scope, commander, c.COMMANDER_KEY)
                ev:goal(context, scope, presentation.directive.enter)
                return
            end
            ev:goal(context, scope, presentation.directive.enter)
            send_stage(context, scope, killed + 1)
            scope:start_timer(c.PSION_TIMER, c.NEXT_PSION_MS)
        end

        -- On Mars: alert with the incoming row, the rig falls, then joining.
        hooks.incoming = {
            {delay_ms = c.ALERT_AFTER_LEAVE_MS, run = function(context, scope)
                visuals.fly_in(context, scope)
                ev:show_incoming(context, scope, presentation.directive.enter)
                ev:say(context, settings.CUE_ALERT)
            end},
            {delay_ms = c.DEPLOY_AFTER_ALERT_MS, run = visuals.deploy},
        }
        hooks.start_delay_ms = c.START_AFTER_DEPLOY_MS
        hooks.timers = {c.PSION_TIMER, c.BURN_TIMER, c.COUNT_TIMER, c.SHIELD_TIMER}
        hooks.device_keys = {c.SHIP_KEY, c.SPIRE_KEY, c.PYLON_KEY, c.SHIELD_KEY,
            c.SHIELD_LARGE_KEY}
        hooks.scenery = definition.scenery

        -- The rig, each Psion and the Valus are required; failed supporting squads are not.
        hooks.required = {c.RIG_REQUEST_KEY}
        squads.append_request_keys(hooks.required, c.PSION_KEY)
        squads.append_request_keys(hooks.required, c.COMMANDER_KEY)
        hooks.tracked = {}
        for _, key in ipairs(hooks.required) do hooks.tracked[#hooks.tracked + 1] = key end
        for stage, stage_waves in ipairs(waves) do
            for index = 1, #stage_waves do
                squads.append_request_keys(hooks.tracked, wave_key(stage, index))
            end
        end
        for index = 1, #heroic_waves do
            squads.append_request_keys(hooks.tracked, c.HEROIC_WAVE_KEY .. index)
        end

        --- The burn shows Evacuate, each Valus has its own counter, otherwise Psions count.
        function hooks.goal(scope)
            if ev:heroic(scope) then
                return {directive = definition.heroic_directive, total_seconds = c.EVENT_SECONDS,
                    progress = valus_progress(scope), navpoint = definition.navpoint}
            end
            if scope:variable(c.OPEN_KEY) ~= nil then
                return {directive = definition.evacuate_directive, total_seconds = c.EVENT_SECONDS,
                    navpoint = definition.navpoint}
            end
            if scope:variable(c.FINAL_KEY) == true then
                return {directive = definition.final_directive, total_seconds = c.EVENT_SECONDS,
                    progress = valus_progress(scope), navpoint = definition.navpoint}
            end
            return {
                directive = definition.directive,
                total_seconds = c.EVENT_SECONDS,
                progress = {scope:variable(c.PSIONS_KEY) or 0, c.PSION_COUNT},
                navpoint = definition.navpoint,
            }
        end

        --- Resets the attempt's phase state and sends the opening crew; the first Psion follows.
        function hooks.on_start(context, scope)
            scope:set_variable(c.ATTEMPT_KEY, (scope:variable(c.ATTEMPT_KEY) or 0) + 1)
            scope:set_variable(c.PSIONS_KEY, 0)
            scope:clear_variable(c.OPEN_KEY)
            scope:clear_variable(c.FINAL_KEY)
            scope:clear_variable(c.VALUS_DEAD_KEY)
            scope:clear_variable(c.PSION_ENDED_KEY)
            scope:clear_variable(c.VALUS_ENDED_KEY)
            for tier = 1, #vents do scope:clear_variable(c.VENT_KEY .. tier) end
            visuals.begin(context)
            send_stage(context, scope, 1)
            scope:start_timer(c.PSION_TIMER, c.FIRST_PSION_MS)
        end

        --- The Valus and the heroic squads arrive; the rig stays until the fight ends.
        function hooks.on_heroic(context, scope)
            visuals.raise_heroic_dome(context, scope)
            squads.place(context, scope, commander, c.COMMANDER_KEY)
            for index, unit in ipairs(heroic_waves) do
                squads.place(context, scope, unit, c.HEROIC_WAVE_KEY .. index)
            end
        end

        --- Closes any open window; ending squads stay alive until cleanup.
        function hooks.on_stop(context, scope)
            close_window(context, scope)
            if ev:phase(scope) ~= runtime.phase.ending then retire_squads(context, scope) end
        end

        --- Selects the rig's exit from the attempt's outcome.
        function hooks.on_finish(context, scope)
            visuals.withdraw(context, scope, ev:heroic(scope))
        end

        --- Retires what the ending left standing, then removes the rig's controls.
        function hooks.on_cleanup(context, scope)
            retire_squads(context, scope)
            return visuals.cleanup(context, scope)
        end

        --- Counts one Psion per placement and ends heroic on the Valus; other deaths are support.
        function hooks.on_squad(context, scope, _, report)
            if scope:variable(c.PSION_KEY) ~= nil and lib.is_slot(context, report, psion.slot) then
                scope:clear_variable(c.PSION_KEY)
                record_ended(scope, psion, report)
                local killed = (scope:variable(c.PSIONS_KEY) or 0) + 1
                scope:set_variable(c.PSIONS_KEY, killed)
                ev:goal(context, scope, presentation.directive.enter)
                scope:start_timer(c.COUNT_TIMER, c.COUNT_ROW_MS)
                return false
            end
            if scope:variable(c.COMMANDER_KEY) ~= nil
                and lib.is_slot(context, report, commander.slot) then
                scope:clear_variable(c.COMMANDER_KEY)
                record_ended(scope, commander, report)
                scope:set_variable(c.VALUS_DEAD_KEY, true)
                ev:goal(context, scope, presentation.directive.enter)
                ev:finish(context, scope, true)
            end
            return false
        end

        --- Ends a Psion or Valus that left no alive report, once per placement.
        function hooks.on_squad_counted(context, scope, site, report)
            local generation = report.spawn_generation
            if generation == nil or report.initial_observation == true then return false end
            for _, unit in ipairs({psion, commander}) do
                if lib.is_slot(context, report, unit.slot) then
                    if generation == scope:variable(ended_key(unit)) then return false end
                    local squad = context:squad(unit.squad)
                    local ended = report.slot_counts
                    for index = 1, squad.member_count do
                        if (ended[index] or 0) < (squad.default_counts[index] or 0) then
                            return false
                        end
                    end
                    return hooks.on_squad(context, scope, site, report)
                end
            end
            return false
        end

        --- A weak point destroyed during its own window counts once; closed tiers report nothing.
        function hooks.on_damage(context, scope, _, report)
            local tier = scope:variable(c.OPEN_KEY)
            if tier == nil or report.health ~= 0
                or scope:variable(c.VENT_KEY .. tier) == true
                or not lib.is_slot(context, report, vents[tier].monitor) then
                return false
            end
            scope:set_variable(c.VENT_KEY .. tier, true)
            visuals.mark_destroyed(context, scope, tier)
            if tier == c.PSION_COUNT and all_vents_hit(scope) then
                close_window(context, scope)
                scope:start_timer(c.SHIELD_TIMER, c.SHIELD_CLEAR_MS)
                ev:say(context, settings.CUE_VENTS)
                ev:commit_heroic(context, scope,
                    math.max(ev:remaining(scope), c.HEROIC_MIN_SECONDS))
            end
            return false
        end

        --- Places the next Psion or ends the open burn.
        function hooks.on_timer(context, scope, _, _, name)
            if name == c.PSION_TIMER then
                squads.place(context, scope, psion, c.PSION_KEY)
            elseif name == c.COUNT_TIMER then
                local killed = scope:variable(c.PSIONS_KEY)
                ev.lifecycle:restart_clock(scope,
                    math.min(ev:remaining(scope) + c.KILL_SECONDS[killed], c.EVENT_SECONDS))
                open_window(context, scope, killed)
            elseif name == c.BURN_TIMER then
                end_window(context, scope)
            elseif name == c.SHIELD_TIMER then
                visuals.clear_burn_dome(context)
            end
            return false
        end

        return hooks
    end)
end

return module
