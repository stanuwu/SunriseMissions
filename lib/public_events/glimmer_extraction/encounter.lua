-- Glimmer Extraction mechanics on the shared event skeleton: one attempt follows the crew through
-- three sites; a machine destroyed at every site turns the last clear into the heroic defense.
local lib = require("lib.mission_lib")
local event = require("lib.public_events.event")
local presentation = require("lib.public_events.presentation")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.glimmer_extraction.settings")

local module = {
    -- Bound by the site definition; see the settings for why this one slot.
    MACHINE_SLOT = c.MACHINE_SLOT,
}

--- Builds the Glimmer Extraction handler; its retained keys require the site's freeroam scope.
---@param definition table Authored site references.
---@return table handler Freeroam site handler.
function module.new(definition)
    local sites = definition.sites
    local heroic_waves = definition.heroic_waves
    local last_site = #sites

    return event.new(definition, c, function(ev)
        local hooks = {}

        --- Returns the current site's index and references.
        local function current(scope)
            local index = scope:variable(c.SITE_KEY) or 1
            return index, sites[index]
        end

        --- Places a site unit under its site-indexed request key.
        local function place(context, scope, unit, key, index)
            squads.place(context, scope, unit, key .. index)
        end

        --- Retires a unit when its request key says it is live.
        local function retire(context, scope, unit, key)
            if scope:variable(key) == nil then return end
            squads.retire(context, unit.squad)
            scope:clear_variable(key)
        end

        --- Retires every unit a site may still hold.
        local function retire_site(context, scope, index)
            local site = sites[index]
            retire(context, scope, site.dropship, c.DROPSHIP_KEY .. index)
            retire(context, scope, site.crew, c.CREW_KEY .. index)
            retire(context, scope, site.extractors, c.EXTRACTORS_KEY .. index)
            retire(context, scope, site.captain, c.CAPTAIN_KEY .. index)
        end

        --- Starts one site: equipment, dropship and crew; the machine follows on its timer.
        local function open_site(context, scope, index)
            local site = sites[index]
            scope:set_variable(c.SITE_KEY, index)
            scope:set_variable(c.STAGE_KEY, c.STAGE_CREW)
            scope:set_variable(c.DEFEATED_KEY, 0)
            context:activate_objects{slots = site.equipment, active = true}
            place(context, scope, site.dropship, c.DROPSHIP_KEY, index)
            place(context, scope, site.crew, c.CREW_KEY, index)
            place(context, scope, site.extractors, c.EXTRACTORS_KEY, index)
            scope:start_timer(c.MACHINE_TIMER, c.MACHINE_MS)
        end

        --- True when this attempt destroyed the machine at every site.
        local function all_machines_gone(scope)
            for index = 1, last_site do
                if scope:variable(c.MACHINE_GONE_KEY .. index) ~= true then return false end
            end
            return true
        end

        --- Ends a cleared site: the crew moves on, or the last site decides the outcome.
        local function clear_site(context, scope, index)
            scope:cancel_timer(c.MACHINE_TIMER)
            retire_site(context, scope, index)
            if index < last_site then
                scope:set_variable(c.STAGE_KEY, c.STAGE_RELOCATING)
                context:activate_objects{slots = sites[index].equipment, active = false}
                ev:say(context, index == 1 and c.CUE_MOVED or c.CUE_MOVED_AGAIN)
                -- The old deadline must not end a cleared site; the row hides this clock.
                ev.lifecycle:restart_clock(scope, c.EVENT_SECONDS)
                ev:show_incoming(context, scope, presentation.directive.enter, definition.pursue)
                scope:start_timer(c.RELOCATE_TIMER, c.RELOCATE_MS)
            elseif all_machines_gone(scope) then
                scope:set_variable(c.STAGE_KEY, c.STAGE_DEFEND)
                ev:commit_heroic(context, scope, c.HEROIC_SECONDS)
            else
                ev:finish(context, scope, true)
            end
        end

        --- Records a machine's disappearance at the current site while its crew still stands.
        local function observe_machine(scope, index, report)
            local generation = report.generation
            if type(generation) ~= "number" or generation <= 0 then return end
            local seen_key = c.MACHINE_SEEN_KEY .. index
            if report.present == true then
                scope:set_variable(seen_key, generation)
            elseif scope:variable(seen_key) == generation then
                scope:set_variable(c.MACHINE_GONE_KEY .. index, true)
            end
        end

        --- Follows the native plate: progress updates the row, ownership completes the defense.
        local function observe_plate(context, scope, report)
            local steps = math.floor((report.plate_progress or 0) * 100 / c.PERCENT_STEP)
            local percent = steps * c.PERCENT_STEP
            if percent ~= (scope:variable(c.PERCENT_KEY) or 0) then
                scope:set_variable(c.PERCENT_KEY, percent)
                ev:goal(context, scope, presentation.directive.enter)
            end
            if report.plate_owner >= 0 and scope:variable(c.CAPTURED_KEY) ~= true then
                scope:set_variable(c.CAPTURED_KEY, true)
                ev:finish(context, scope, true)
            end
        end

        --- Sends the next heroic wave; the plate alone ends the defense.
        local function send_wave(context, scope)
            local count = (scope:variable(c.WAVE_COUNT_KEY) or 0) + 1
            scope:set_variable(c.WAVE_COUNT_KEY, count)
            place(context, scope, heroic_waves[count], c.WAVE_KEY, count)
            if count < #heroic_waves then
                scope:start_timer(c.WAVE_TIMER, c.HEROIC_WAVE_MS)
            end
        end

        -- Reference order after the flag leaves: alert, ketch with the skiffs, then the crew.
        hooks.incoming = {
            {delay_ms = c.ALERT_AFTER_LEAVE_MS, run = function(context)
                ev:say(context, c.CUE_ALERT)
            end},
            {delay_ms = c.KETCH_AFTER_ALERT_MS, run = function(context, scope)
                context:activate_objects{slots = {definition.ketch}, active = true}
                context:slot(definition.intro):play_sequence{}
                ev:show_incoming(context, scope, presentation.directive.enter)
            end},
        }
        hooks.start_delay_ms = c.START_AFTER_KETCH_MS
        hooks.timers = {c.MACHINE_TIMER, c.RELOCATE_TIMER, c.WAVE_TIMER}
        hooks.tracked = {c.ZONE_REQUEST_KEY}
        for index = 1, last_site do
            squads.append_request_keys(hooks.tracked, c.EXTRACTORS_KEY .. index)
            squads.append_request_keys(hooks.tracked, c.CAPTAIN_KEY .. index)
        end
        -- The extractors, the captain and the plate decide the outcome; the rest only support.
        hooks.required = {}
        for _, key in ipairs(hooks.tracked) do hooks.required[#hooks.required + 1] = key end
        for index = 1, last_site do
            squads.append_request_keys(hooks.tracked, c.DROPSHIP_KEY .. index)
            squads.append_request_keys(hooks.tracked, c.CREW_KEY .. index)
        end
        for index = 1, #heroic_waves do
            squads.append_request_keys(hooks.tracked, c.WAVE_KEY .. index)
        end
        hooks.scenery = {definition.ketch, definition.zone, definition.ring, definition.pile}
        for _, site in ipairs(sites) do
            for _, slot in ipairs(site.equipment) do hooks.scenery[#hooks.scenery + 1] = slot end
            hooks.scenery[#hooks.scenery + 1] = site.machine
        end

        --- The extraction row counts the crew; the heroic row follows the plate.
        function hooks.goal(scope)
            if ev:heroic(scope) then
                return {directive = definition.heroic_directive, total_seconds = c.HEROIC_SECONDS,
                    progress = {scope:variable(c.PERCENT_KEY) or 0, 100}}
            end
            return {directive = definition.directive, total_seconds = c.EVENT_SECONDS,
                progress = {scope:variable(c.DEFEATED_KEY) or 0, c.CREW_TOTAL}}
        end

        --- Clears retained attempt state, then opens the first site.
        function hooks.on_start(context, scope)
            for index = 1, last_site do
                scope:clear_variable(c.MACHINE_SEEN_KEY .. index)
                scope:clear_variable(c.MACHINE_GONE_KEY .. index)
            end
            for _, key in ipairs({c.WAVE_COUNT_KEY, c.PERCENT_KEY, c.CAPTURED_KEY}) do
                scope:clear_variable(key)
            end
            open_site(context, scope, 1)
            context:slot(definition.active):play_sequence{}
        end

        --- Opens the glimmer pile and its plate at the last site, with the first heroic wave.
        function hooks.on_heroic(context, scope)
            ev:say(context, c.CUE_HEROIC)
            context:activate_objects{slots = {definition.pile, definition.ring}, active = true}
            local requests = context:activate_objects{slots = {definition.zone}, active = true,
                capture_plate = true}
            scope:set_variable(c.ZONE_REQUEST_KEY, requests[1].value)
            send_wave(context, scope)
        end

        --- Retires every live squad of this attempt.
        function hooks.on_stop(context, scope)
            for index = 1, last_site do retire_site(context, scope, index) end
            for index, wave in ipairs(heroic_waves) do
                retire(context, scope, wave, c.WAVE_KEY .. index)
            end
        end

        --- Scenery leaves through the shared final cleanup.
        function hooks.on_finish() end

        --- The shared scenery list holds every removal this family needs.
        function hooks.on_cleanup() return {} end

        --- Advances the current site's crew; reports from any other site or stage are stale.
        function hooks.on_squad(context, scope, _, report)
            local index, site = current(scope)
            local stage = scope:variable(c.STAGE_KEY)
            if stage == c.STAGE_CREW and scope:variable(c.EXTRACTORS_KEY .. index) ~= nil
                and lib.is_slot(context, report, site.extractors.slot) then
                scope:clear_variable(c.EXTRACTORS_KEY .. index)
                scope:set_variable(c.STAGE_KEY, c.STAGE_CAPTAIN)
                scope:set_variable(c.DEFEATED_KEY, c.EXTRACTORS)
                place(context, scope, site.captain, c.CAPTAIN_KEY, index)
                ev:goal(context, scope, presentation.directive.enter)
            elseif stage == c.STAGE_CAPTAIN and scope:variable(c.CAPTAIN_KEY .. index) ~= nil
                and lib.is_slot(context, report, site.captain.slot) then
                scope:clear_variable(c.CAPTAIN_KEY .. index)
                scope:set_variable(c.DEFEATED_KEY, c.CREW_TOTAL)
                ev:goal(context, scope, presentation.directive.enter)
                clear_site(context, scope, index)
            end
            return false
        end

        --- Routes the plate during the defense and the machine while its crew stands.
        function hooks.on_object_state(context, scope, _, report)
            local stage = scope:variable(c.STAGE_KEY)
            if stage == c.STAGE_DEFEND then
                if report.plate_owner ~= nil and lib.is_slot(context, report, definition.zone) then
                    observe_plate(context, scope, report)
                end
            elseif stage == c.STAGE_CREW or stage == c.STAGE_CAPTAIN then
                local index, site = current(scope)
                if lib.is_slot(context, report, site.machine) then
                    observe_machine(scope, index, report)
                end
            end
            return false
        end

        --- Handles the machine, relocation and heroic wave timers.
        function hooks.on_timer(context, scope, _, _, name)
            if name == c.MACHINE_TIMER then
                local _, site = current(scope)
                context:activate_objects{slots = {site.machine}, active = true}
            elseif name == c.RELOCATE_TIMER then
                local index = current(scope)
                open_site(context, scope, index + 1)
                ev.lifecycle:restart_clock(scope, c.EVENT_SECONDS)
                ev:goal(context, scope, presentation.directive.enter)
            elseif name == c.WAVE_TIMER then
                send_wave(context, scope)
            end
            return false
        end

        --- Uses the same completion path when the native generation ends before an alive fall.
        function hooks.on_squad_counted(context, scope, site, report)
            local _, current_site = current(scope)
            for _, unit in ipairs({current_site.extractors, current_site.captain}) do
                if lib.is_slot(context, report, unit.slot)
                    and squads.counted_out(context, unit, report) then
                    return hooks.on_squad(context, scope, site, report)
                end
            end
            return false
        end

        return hooks
    end)
end

return module
