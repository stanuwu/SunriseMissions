-- Cabal Excavation mechanics: the override plate, wave groups
-- from drop pods, the carrier's bombardment, the Thresher and the heroic Valus.
local lib = require("lib.mission_lib")
local event = require("lib.public_events.event")
local presentation = require("lib.public_events.presentation")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.cabal_excavation.settings")
local visual_module = require("lib.public_events.cabal_excavation.visuals")

local module = {}

-- A refused heroic-trigger squad leaves normal play running but cannot qualify for heroic.
local THRESHER_FAILED_KEY = c.THRESHER_KEY .. ".failed"

--- Counts players in a plate occupancy mask.
local function occupants(mask)
    local count = 0
    for _ = 1, c.OCCUPANT_BITS do
        count = count + mask % 2
        mask = mask // 2
    end
    return count
end

--- Builds the Cabal Excavation handler; its retained keys require the site's freeroam scope.
---@param definition table Authored site references.
---@return table handler Freeroam site handler.
function module.new(definition)
    local waves = definition.waves
    local heroic_waves = definition.heroic_waves
    local threshers = definition.threshers
    local sniper = definition.sniper
    local valus = definition.valus
    local zone = definition.zone
    local visuals = visual_module.new(definition)

    return event.new(definition, c, function(ev)
        local hooks = {}

        --- Returns the retained key naming whether a wave is alive.
        local function live_key(index)
            return c.WAVE_LIVE_KEY .. index
        end

        --- Drops the unit's pods, then places it with its authored counts.
        local function place(context, scope, unit, key)
            squads.drop(context, scope, unit, c.POD_GROUP_KEY)
            squads.place(context, scope, unit, key)
        end

        --- Sends the next wave; a wave that is still alive is skipped.
        local function send_wave(context, scope)
            local count = scope:variable(c.WAVE_COUNT_KEY) or 0
            local wave = c.WAVE_ORDER[count % #c.WAVE_ORDER + 1]
            scope:set_variable(c.WAVE_COUNT_KEY, count + 1)
            if scope:variable(live_key(wave)) ~= true then
                scope:set_variable(live_key(wave), true)
                place(context, scope, waves[wave], c.WAVE_REQUEST_KEY .. wave)
            end
        end

        --- Retires every live squad this attempt placed.
        local function retire_squads(context, scope)
            for index, wave in ipairs(waves) do
                if scope:variable(live_key(index)) == true then
                    squads.retire(context, wave.squad)
                    scope:clear_variable(live_key(index))
                end
            end
            squads.retire_if_placed(context, scope, sniper, c.SNIPER_KEY)
            squads.retire_if_placed(context, scope, valus, c.VALUS_KEY)
            -- A Thresher is an actor its program spawned: the actor is retired, then its squad.
            for index, thresher in ipairs(threshers) do
                if scope:variable(c.THRESHER_KEY .. index) ~= nil then
                    context:slot(thresher.pilot):retire_actor()
                end
                squads.retire_if_placed(context, scope, thresher, c.THRESHER_KEY .. index)
            end
            for index, guard in ipairs(heroic_waves) do
                squads.retire_if_placed(context, scope, guard, c.GUARD_KEY .. index)
            end
            for index = 1, #definition.pod_groups do
                scope:clear_variable(c.POD_GROUP_KEY .. index)
            end
            scope:clear_variable(c.THRESHER_FLYING_KEY)
        end

        --- Returns the live wave index that this death report names, or nil.
        local function dead_wave(context, scope, report)
            for index, wave in ipairs(waves) do
                if scope:variable(live_key(index)) == true
                    and lib.is_slot(context, report, wave.slot) then
                    return index
                end
            end
            return nil
        end

        --- Returns the placed Thresher index that this death report names, or nil.
        local function dead_thresher(context, scope, report)
            for index, thresher in ipairs(threshers) do
                if scope:variable(c.THRESHER_KEY .. index) ~= nil
                    and scope:variable(THRESHER_FAILED_KEY .. index) ~= true
                    and lib.is_slot(context, report, thresher.slot) then
                    return index
                end
            end
            return nil
        end

        --- Returns the placed unit a squad report names and its ended-generation key, or nil.
        local function reported_unit(context, scope, report)
            local wave = dead_wave(context, scope, report)
            if wave ~= nil then return waves[wave], c.ENDED_WAVE_KEY .. wave end
            local thresher = dead_thresher(context, scope, report)
            if thresher ~= nil then
                return threshers[thresher], c.ENDED_THRESHER_KEY .. thresher
            end
            if scope:variable(c.VALUS_KEY) ~= nil and lib.is_slot(context, report, valus.slot) then
                return valus, c.ENDED_VALUS_KEY
            end
            return nil
        end

        --- True once the member counts cover everything the authored placement asked for.
        local function all_ended(context, unit, ended)
            local squad = context:squad(unit.squad)
            for index = 1, squad.member_count do
                if (ended[index] or 0) < (squad.default_counts[index] or 0) then return false end
            end
            return true
        end

        --- Flies the first Thresher as its points are authored: the spawning program's entrance
        --- ability brings it from its staging anchor to the entrance point, then it flies laps
        --- through every named point of its two curves until it is shot down or the event stops.
        local function fly_thresher(context, scope)
            if scope:variable(THRESHER_FAILED_KEY .. 1) == true then return end
            local thresher = threshers[1]
            if scope:variable(c.THRESHER_FLYING_KEY) == nil then
                local request = context:slot(thresher.pilot):run_atoms{spawn = true, atoms = {
                    {kind = context.sdk.atom_kinds.ability, ability = thresher.enter,
                        target = context:slot(definition.thresher_entrance)},
                }}
                scope:set_variable(c.THRESHER_KEY .. 1, request.value)
                scope:set_variable(c.THRESHER_FLYING_KEY, true)
                scope:start_timer(c.THRESHER_TIMER, c.THRESHER_ENTRANCE_MS)
                return
            end
            -- A Thresher that was shot down or refuses its lap is sent no further one.
            if scope:variable(c.THRESHER_KEY .. 1) == nil
                or not squads.fly_points(context, thresher.pilot, definition.thresher_lap) then
                scope:clear_variable(c.THRESHER_FLYING_KEY)
                return
            end
            scope:start_timer(c.THRESHER_TIMER, c.THRESHER_LAP_MS)
        end

        -- After the flag leaves: carrier with the event row, alert, lander.
        hooks.incoming = {
            {delay_ms = c.SHIP_AFTER_LEAVE_MS, run = function(context, scope)
                visuals.fly_in(context, scope)
                ev:show_incoming(context, scope, presentation.directive.enter)
            end},
            {delay_ms = c.ALERT_AFTER_SHIP_MS, run = function(context)
                ev:say(context, c.CUE_ALERT)
            end},
            {delay_ms = c.LAND_AFTER_ALERT_MS, run = visuals.land},
        }
        hooks.start_delay_ms = c.START_AFTER_LAND_MS
        hooks.timers = {c.INTRO_TIMER, c.WAVE_TIMER, c.THRESHER_TIMER, c.BOMBARD_TIMER}
        hooks.tracked = {c.LANDER_REQUEST_KEY, c.ZONE_REQUEST_KEY}
        for index = 1, #waves do
            squads.append_request_keys(hooks.tracked, c.WAVE_REQUEST_KEY .. index)
        end
        squads.append_request_keys(hooks.tracked, c.VALUS_KEY)
        hooks.required = {}
        for _, key in ipairs(hooks.tracked) do hooks.required[#hooks.required + 1] = key end
        squads.append_request_keys(hooks.tracked, c.SNIPER_KEY)
        for index = 1, #threshers do
            squads.append_request_keys(hooks.tracked, c.THRESHER_KEY .. index)
        end
        for index = 1, #heroic_waves do
            squads.append_request_keys(hooks.tracked, c.GUARD_KEY .. index)
        end
        hooks.scenery = {definition.lander.object, definition.ship.object, zone, definition.ring}
        hooks.device_keys = {c.LANDER_KEY, c.SHIP_KEY}

        --- Retains Thresher delivery failure without aborting normal play or retrying placement.
        function hooks.on_failure(context, scope, report)
            for index = 1, #threshers do
                if squads.owns_request(scope, c.THRESHER_KEY .. index, report.request_key) then
                    scope:set_variable(THRESHER_FAILED_KEY .. index, true)
                    scope:cancel_timer(c.THRESHER_TIMER)
                    scope:clear_variable(c.THRESHER_FLYING_KEY)
                    return
                end
            end
        end

        --- The override row counts occupants against present members; heroic shows the Valus.
        --- A membership change reposts either row: the client times the marker only outside it.
        function hooks.goal(scope)
            if ev:heroic(scope) then
                return {directive = definition.heroic_directive, total_seconds = c.HEROIC_SECONDS,
                    counts_members = true}
            end
            return {
                directive = definition.directive,
                total_seconds = c.EVENT_SECONDS,
                progress = {scope:variable(c.OCCUPANTS_KEY) or 0, ev:members(scope)},
                counts_members = true,
            }
        end

        --- Opens the site: lander mining, footprint, covers, sniper and the timers.
        function hooks.on_start(context, scope)
            scope:set_variable(c.DEAD_KEY, 0)
            scope:set_variable(c.OCCUPANTS_KEY, 0)
            scope:set_variable(c.WAVE_COUNT_KEY, 0)
            scope:clear_variable(c.CAPTURED_KEY)
            scope:clear_variable(c.THRESHER_FLYING_KEY)
            scope:clear_variable(c.ENDED_VALUS_KEY)
            for index = 1, #threshers do
                scope:clear_variable(THRESHER_FAILED_KEY .. index)
                scope:clear_variable(c.ENDED_THRESHER_KEY .. index)
            end
            for index = 1, #definition.pod_groups do
                scope:clear_variable(c.POD_GROUP_KEY .. index)
            end
            for index = 1, #waves do
                scope:clear_variable(live_key(index))
                scope:clear_variable(c.ENDED_WAVE_KEY .. index)
            end
            visuals.mine(context, scope)
            visuals.open_site(context, scope)
            place(context, scope, sniper, c.SNIPER_KEY)
            scope:start_timer(c.INTRO_TIMER, c.INTRO_MS)
            scope:start_timer(c.BOMBARD_TIMER, c.BOMBARD_MS)
            scope:start_timer(c.WAVE_TIMER, c.FIRST_WAVE_MS)
            scope:start_timer(c.THRESHER_TIMER, c.THRESHER_MS)
        end

        --- Ends the normal drops; the Valus and all guards drop with one landing of their pods.
        function hooks.on_heroic(context, scope)
            scope:cancel_timer(c.WAVE_TIMER)
            place(context, scope, valus, c.VALUS_KEY)
            squads.drop(context, scope, heroic_waves[1], c.POD_GROUP_KEY)
            for index, guard in ipairs(heroic_waves) do
                squads.place(context, scope, guard, c.GUARD_KEY .. index)
            end
        end

        hooks.on_stop = retire_squads

        --- A heroic win destroys the lander, any other ending withdraws it; the carrier departs.
        --- The override footprint and its ring leave with the objective, not with the chest.
        function hooks.on_finish(context, scope, succeeded)
            context:activate_objects{slots = {zone, definition.ring}, active = false}
            if succeeded and ev:heroic(scope) then
                visuals.destroy_lander(context, scope)
            else
                visuals.withdraw(context, scope)
            end
            visuals.fly_out(context, scope)
        end

        hooks.on_cleanup = visuals.cleanup

        --- Follows the native plate: occupancy updates the counter, ownership completes it.
        function hooks.on_object_state(context, scope, _, report)
            if report.plate_owner == nil or not lib.is_slot(context, report, zone)
                or ev:heroic(scope) then
                return false
            end
            local count = occupants(report.plate_occupants or 0)
            if count ~= scope:variable(c.OCCUPANTS_KEY) then
                scope:set_variable(c.OCCUPANTS_KEY, count)
                ev:goal(context, scope, presentation.directive.enter)
            end
            if report.plate_owner >= 0 and scope:variable(c.CAPTURED_KEY) ~= true then
                scope:set_variable(c.CAPTURED_KEY, true)
                ev:finish(context, scope, true)
            end
            return false
        end

        --- Records wave deaths, commits heroic on the Thresher and succeeds on the Valus.
        function hooks.on_squad(context, scope, _, report)
            local _, ended = reported_unit(context, scope, report)
            if ended ~= nil and report.spawn_generation ~= nil then
                scope:set_variable(ended, report.spawn_generation)
            end
            local wave = dead_wave(context, scope, report)
            if wave ~= nil then
                scope:clear_variable(live_key(wave))
                scope:set_variable(c.DEAD_KEY, (scope:variable(c.DEAD_KEY) or 0) + 1)
                return false
            end
            local thresher = dead_thresher(context, scope, report)
            if thresher ~= nil then
                scope:clear_variable(c.THRESHER_KEY .. thresher)
                ev:say(context, c.CUE_SHIP_DOWN)
                if not ev:heroic(scope)
                    and ev:remaining(scope) > c.HEROIC_MIN_REMAINING_SECONDS then
                    ev:commit_heroic(context, scope, c.HEROIC_SECONDS)
                end
                return false
            end
            if scope:variable(c.VALUS_KEY) ~= nil and lib.is_slot(context, report, valus.slot) then
                scope:clear_variable(c.VALUS_KEY)
                ev:finish(context, scope, true)
            end
            return false
        end

        --- Ends a unit whose members all ended with no alive count, once per generation.
        function hooks.on_squad_counted(context, scope, site, report)
            local unit, ended = reported_unit(context, scope, report)
            if unit == nil or report.spawn_generation == nil
                or report.spawn_generation == scope:variable(ended)
                or not all_ended(context, unit, report.slot_counts) then
                return false
            end
            return hooks.on_squad(context, scope, site, report)
        end

        --- Handles the intro, bombardment, wave and Thresher timers.
        function hooks.on_timer(context, scope, _, _, name)
            if name == c.INTRO_TIMER then
                visuals.finish_intro(context)
            elseif name == c.BOMBARD_TIMER then
                visuals.bombard(context)
            elseif name == c.WAVE_TIMER then
                send_wave(context, scope)
                scope:start_timer(c.WAVE_TIMER, c.WAVE_INTERVAL_MS)
            elseif name == c.THRESHER_TIMER then
                fly_thresher(context, scope)
            end
            return false
        end

        return hooks
    end)
end

return module
