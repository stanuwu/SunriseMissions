-- Transport waves shield the Prime until their escorts fall or leave.
local lib = require("lib.mission_lib")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.ether_resupply.settings")

local transports = {}
-- Only the two open stages own a shield and an expiry timer.
local LONE, BETWEEN, TRIO, FINISHED = "lone", "between", "trio", "finished"

--- Binds the site's combatants. All mutable wave state belongs to the running event scope.
function transports.new(ev, prime, site)
    local combat = {}
    local lone, trio = {site.lone}, site.trio
    local trio_squads = {}
    for index, unit in ipairs(trio) do trio_squads[index] = unit.squad end

    local function support_key(wave, index)
        return c.SUPPORT_KEY .. wave .. "." .. index
    end

    local function shield(context, enabled)
        local hop_on = context:slot(site.shield)
        if enabled then
            local filter = context:slot(site.filter)
            filter:set_object_filter{squad = context:slot(prime.slot)}
            hop_on:attach_hop_on{filter = filter}
        else
            hop_on:detach_hop_on{}
        end
    end

    local function open_wave(context, scope, stage, escorts, timer)
        scope:set_variable(c.TRANSPORT_STAGE, stage)
        scope:clear_variable(c.WITHDRAWN)
        for index, unit in ipairs(escorts) do
            scope:clear_variable(c.FALL_KEY .. index)
            squads.place(context, scope, unit, c.TRANSPORT_KEY .. index)
        end
        shield(context, true)
        scope:start_timer(timer, c.TRANSPORT_WINDOW_MS)
    end

    -- Close eligibility before retirement can publish another population change.
    local function close_wave(context, scope, stage)
        local escorts, timer, next_stage = trio, c.TRIO_TIMER, FINISHED
        if stage == LONE then escorts, timer, next_stage = lone, c.LONE_TIMER, BETWEEN end
        scope:set_variable(c.TRANSPORT_STAGE, next_stage)
        scope:clear_variable(c.WITHDRAWN)
        scope:cancel_timer(timer)
        shield(context, false)
        for index, unit in ipairs(escorts) do
            squads.retire_if_placed(context, scope, unit, c.TRANSPORT_KEY .. index)
            scope:clear_variable(c.FALL_KEY .. index)
        end
    end

    --- Opens each wave once, on a live hit to the Prime's own combatant slot.
    function combat.damage(context, scope, report)
        if not lib.is_slot(context, report, prime.member) then return end
        local health = report.health
        if type(health) ~= "number" or not (health > 0 and health <= 1) then return end
        local stage = scope:variable(c.TRANSPORT_STAGE)
        if stage == nil and health <= c.LONE_HEALTH then
            scope:set_variable(c.LONE_START_HEALTH, health)
            open_wave(context, scope, LONE, lone, c.LONE_TIMER)
        elseif stage == BETWEEN and health <= c.TRIO_HEALTH
            and health < scope:variable(c.LONE_START_HEALTH) then
            open_wave(context, scope, TRIO, trio, c.TRIO_TIMER)
        end
    end

    -- A queued timer callback and the final squad report can arrive in the same update.
    local function within_trio_window(scope)
        local withdrawal = tonumber(scope.state:timer(scope:key(c.TRIO_TIMER)))
        local deadline = tonumber(scope.state:timer(scope:key(c.KEY)))
        if withdrawal == nil or deadline == nil then return false end
        scope:start_timer(c.WINDOW_CLOCK, 0)
        local now = tonumber(scope.state:timer(scope:key(c.WINDOW_CLOCK)))
        scope:cancel_timer(c.WINDOW_CLOCK)
        return now < withdrawal and now < deadline
    end

    local function reported_escort(context, scope, escorts, report)
        for index, unit in ipairs(escorts) do
            if scope:variable(c.TRANSPORT_KEY .. index) ~= nil
                and lib.is_slot(context, report, unit.slot) then
                return index, unit
            end
        end
    end

    --- Reconciles one squad's alive fall and member loss, which can arrive on separate updates.
    function combat.squad(context, scope, report)
        local stage = scope:variable(c.TRANSPORT_STAGE)
        if stage ~= LONE and stage ~= TRIO then return end
        local escorts = stage == LONE and lone or trio
        local index, unit = reported_escort(context, scope, escorts, report)
        local generation = report.spawn_generation
        if unit == nil or generation == nil or report.initial_observation
            or not report.population_available then
            return
        end
        local fall_key = c.FALL_KEY .. index
        local previous = scope:variable(fall_key)
        if previous ~= nil and previous ~= generation then return end
        if report.removal_flag then scope:set_variable(c.WITHDRAWN, true) end
        if report.previous_alive_count > 0 then scope:set_variable(fall_key, generation) end
        if scope:variable(fall_key) ~= generation
            or not squads.counted_out(context, unit, report) then
            return
        end
        scope:clear_variable(c.TRANSPORT_KEY .. index)
        for member = 1, #escorts do
            if scope:variable(c.TRANSPORT_KEY .. member) ~= nil then return end
        end
        -- The cohort checks the current placements. Squad Sense does not identify the killer.
        local heroic = stage == TRIO and not scope:variable(c.WITHDRAWN)
            and within_trio_window(scope) and context:cohort{squads = trio_squads}.cleared
        close_wave(context, scope, stage)
        if heroic then ev:commit_heroic(context, scope) end
    end

    --- Dispatches timed reinforcements and withdraws Transports on their own deadlines.
    function combat.timer(context, scope, name)
        if name == c.SUPPORT_TIMER then
            local wave = (scope:variable(c.SUPPORT_WAVE) or 0) + 1
            if site.support[wave] == nil then return end
            scope:set_variable(c.SUPPORT_WAVE, wave)
            for index, unit in ipairs(site.support[wave]) do
                squads.place(context, scope, unit, support_key(wave, index))
            end
            if wave < #site.support then scope:start_timer(name, c.SUPPORT_INTERVAL_MS) end
            return
        end
        local stage = scope:variable(c.TRANSPORT_STAGE)
        if (stage == LONE and name == c.LONE_TIMER) or (stage == TRIO and name == c.TRIO_TIMER) then
            close_wave(context, scope, stage)
        end
    end

    --- A refused placement cannot supply the wave's required escorts.
    function combat.failed(context, scope, report)
        local stage = scope:variable(c.TRANSPORT_STAGE)
        if stage ~= LONE and stage ~= TRIO then return end
        local escorts = stage == LONE and lone or trio
        for index = 1, #escorts do
            local key = c.TRANSPORT_KEY .. index
            if scope:variable(key) == report.request_key.value then
                scope:clear_variable(key)
                close_wave(context, scope, stage)
                return
            end
        end
    end

    --- Enrages the standing Prime, enables the heroic teleporter and sends in explosive Shanks.
    function combat.heroic(context, scope)
        context:slot(site.enrage):play_sequence{}
        context:activate_objects{slots = {site.heroic_teleporter}, active = true}
        squads.place(context, scope, site.heroic_support, c.HEROIC_SHANKS)
        ev:say(context, c.CUE_HEROIC)
    end

    --- Retires placed support, drops any shield and ends the heroic charge.
    function combat.stop(context, scope)
        local stage = scope:variable(c.TRANSPORT_STAGE)
        if stage == LONE or stage == TRIO then close_wave(context, scope, stage) end
        if ev:heroic(scope) then
            context:slot(site.charge_end):play_sequence{}
            context:activate_objects{slots = {site.heroic_teleporter}, active = false}
            squads.retire_if_placed(context, scope, site.heroic_support, c.HEROIC_SHANKS)
        end
        for wave, units in ipairs(site.support) do
            for index, unit in ipairs(units) do
                squads.retire_if_placed(context, scope, unit, support_key(wave, index))
            end
        end
        scope:clear_variable(c.TRANSPORT_STAGE)
        scope:clear_variable(c.LONE_START_HEALTH)
        scope:clear_variable(c.SUPPORT_WAVE)
    end

    return combat
end

return transports
