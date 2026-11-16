-- Spire Integration mechanics: lane waves, capture plates that
-- commit heroic and the spire's endings.
local lib = require("lib.mission_lib")
local event = require("lib.public_events.event")
local presentation = require("lib.public_events.presentation")
local c = require("lib.public_events.spire_integration.settings")
local visual_module = require("lib.public_events.spire_integration.visuals")
local lane_module = require("lib.public_events.spire_integration.lanes")

local module = {}

--- Builds the Spire handler; its retained keys require the site's exclusive freeroam scope.
---@param definition table Authored site references.
---@return table handler Freeroam site handler.
function module.new(definition)
    local monitors = definition.monitors
    local visuals = visual_module.new(definition)

    return event.new(definition, c, function(ev)
        local lane_logic = lane_module.new(definition, ev, visuals)
        local hooks = {}

        -- After the flag leaves: beacon and construction with the event row,
        -- the row's completion, the alert, then the start.
        hooks.incoming = {
            {delay_ms = c.BEACON_AFTER_LEAVE_MS, run = function(context, scope)
                context:activate_objects{slots = {definition.beacon}, active = true}
                visuals.build_centre(context)
                ev:show_incoming(context, scope, presentation.directive.enter,
                    definition.incoming)
            end},
            {delay_ms = c.ROW_SHOWN_MS, run = function(context, scope)
                ev:show_incoming(context, scope, presentation.directive.complete,
                    definition.incoming)
            end},
            {delay_ms = c.ALERT_AFTER_ROW_MS, run = function(context, scope)
                if definition.join_lines == nil then ev:say(context, c.CUE_ALERT) end
            end},
        }
        hooks.start_delay_ms = c.START_AFTER_ALERT_MS
        hooks.timers = {c.INTRO_TIMER, c.JOIN_LINE_TIMER, c.REINFORCE_TIMER}
        hooks.tracked, hooks.required = lane_logic.tracked_keys()
        hooks.scenery = visuals.scenery()
        hooks.device_keys = visuals.device_keys()
        -- Heroic success uses the explosion band. Normal success uses the slow dissolve.
        hooks.prelude = {delay_ms = c.END_EXPLODE_MS, run = function(context, scope)
            local value = ev:heroic(scope) and c.SPIRE_EXPLODE or c.SPIRE_DISSOLVE
            visuals.destroy_spire(context, scope, value)
        end}

        --- Both rows count the remaining integrations; heroic has its own clock.
        --- A membership change reposts the row: the client times the marker only outside it.
        function hooks.goal(scope)
            local row = {
                directive = definition.directive,
                total_seconds = c.EVENT_SECONDS,
                progress = {scope:variable(c.INTEGRATION_KEY) or c.INTEGRATIONS, c.INTEGRATIONS},
                counts_members = true,
            }
            if ev:heroic(scope) then
                row.directive = definition.heroic.directive
                row.total_seconds = c.HEROIC_SECONDS
            end
            return row
        end

        --- Opens the site: props and covers, the intro, the opening squad and the first waves.
        function hooks.on_start(context, scope)
            lane_logic.reset(scope)
            visuals.begin_event(context)
            scope:start_timer(c.INTRO_TIMER, c.INTRO_MS)
            lane_logic.open(context, scope)
        end

        --- Heroic brings the authored sequence, clouds and scenes, the guards and the line.
        function hooks.on_heroic(context, scope)
            visuals.start_heroic(context)
            lane_logic.place_guards(context, scope)
            scope:start_timer(c.REINFORCE_TIMER, c.REINFORCE_MS)
            ev:say(context, c.CUE_HEROIC)
        end

        --- Retires every placed squad; a live attempt also withdraws the lane presentation.
        function hooks.on_stop(context, scope, live)
            lane_logic.retire_live_waves(context, scope)
            if not live then return end
            if ev:heroic(scope) then visuals.stop_heroic(context) end
            visuals.stop_lanes(context, scope)
        end

        --- A failed attempt dissolves the spire at once; success tears it down in the prelude.
        function hooks.on_finish(context, scope, succeeded)
            if not succeeded then visuals.destroy_spire(context, scope, c.SPIRE_DISSOLVE) end
        end

        --- Keep the spire revision across attempts when the event removes its scenery.
        function hooks.on_cleanup() end

        --- The clock running out with integrations left is the success.
        function hooks.on_deadline(context, scope)
            ev:finish(context, scope, true)
            return false
        end

        --- The first occupied lane monitor admits the arrival cue.
        function hooks.on_trigger(context, scope, _, report)
            if report.occupied ~= true then return false end
            for _, monitor in ipairs(monitors) do
                if lib.is_slot(context, report, monitor) then ev:announce(context, scope) end
            end
            return false
        end

        hooks.on_squad = lane_logic.on_squad
        hooks.on_squad_counted = lane_logic.on_squad_counted
        hooks.on_objective = lane_logic.on_objective

        --- Counts accepted sacrifice completions; the runtime owns input replay protection.
        ---@param context SunriseContext Current callback's request context.
        ---@param scope table Active site's retained state.
        ---@param _ table Current site; unused.
        ---@param report SunriseIncidentReceivedEvent Accepted incident from this binding.
        ---@return boolean released False; a failed event retains its ending and cleanup.
        function hooks.on_incident(context, scope, _, report)
            if report.incident_target ~= c.SACRIFICE_INCIDENT then return false end
            local remaining = scope:variable(c.INTEGRATION_KEY) - 1
            scope:set_variable(c.INTEGRATION_KEY, remaining)
            if remaining == 0 then
                ev:finish(context, scope, false)
            else
                ev:goal(context, scope, presentation.directive.enter)
            end
            return false
        end

        --- Plate reports; the third capture commits heroic and replaces every wave.
        function hooks.on_object_state(context, scope, site, report)
            if lane_logic.on_object_state(context, scope, site, report) then
                ev:commit_heroic(context, scope, c.HEROIC_SECONDS)
                lane_logic.advance_all(context, scope)
            end
            return false
        end

        --- Finishes the intro sequence without changing the active waves.
        function hooks.on_timer(context, scope, _, _, name)
            if name == c.INTRO_TIMER then
                visuals.finish_intro(context, scope)
            elseif name == c.JOIN_LINE_TIMER then
                ev:say(context, definition.join_lines.second)
            elseif name == c.REINFORCE_TIMER then
                lane_logic.reinforce(context, scope)
            end
            return false
        end

        return hooks
    end)
end

return module
