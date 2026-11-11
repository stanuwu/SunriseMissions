-- Taken Blight follows three authored locations; reconstructed integrity counts whole-squad clears.
-- Heroic reads watched object health; the native health/buff target join remains unverified.
local lib = require("lib.mission_lib")
local event = require("lib.public_events.event")
local presentation = require("lib.public_events.presentation")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.taken_blight.settings")

local module = {}

---@class BlightLocation
---@field blights string[] Authored Blight objects of this location.
---@field target string Object the damage monitor watches.
---@field monitor string Type-20 damage monitor.
---@field shield string Taken shield sequence.
---@field pools table[] {objects: string[], sequence: string} of each small Blight in use.
---@field navpoint string Marker of this location.
---@field units Unit[] Authored squads of this location's difficulty.
---@field center_rule string Spawn rule at the middle of this location.

--- Builds the Taken Blight handler; its retained keys require the site's freeroam scope.
---@param definition table Authored site references.
---@return table handler Freeroam site handler.
function module.new(definition)
    local locations = definition.locations
    local ultra = definition.ultra

    return event.new(definition, c, function(ev)
        local hooks = {}

        --- Returns the location the attempt is at.
        local function here(scope)
            return locations[scope:variable(c.LOCATION_KEY) or 1]
        end

        --- Returns the retained key naming whether a squad is alive.
        local function live_key(index)
            return c.SQUAD_LIVE_KEY .. index
        end

        --- Returns the clock total of the current location.
        local function location_seconds(scope)
            if (scope:variable(c.LOCATION_KEY) or 1) == 1 then return c.EVENT_SECONDS end
            return c.PURSUE_SECONDS
        end

        --- Creates a location's Blight; a refusal aborts because the event has no other target.
        local function arrive(context, scope, location)
            local requests = context:activate_objects{slots = location.blights, active = true}
            scope:set_variable(c.BLIGHT_REQUEST_KEY, requests[1].value)
        end

        --- Removes a location's Blight and small Blights.
        local function depart(context, location)
            context:activate_objects{slots = location.blights, active = false}
            for _, pool in ipairs(location.pools) do
                context:activate_objects{slots = pool.objects, active = false}
            end
        end

        --- Opens the fight: shield, small Blights, the damage watch and the location's squads.
        local function open_location(context, scope, location)
            context:slot(location.shield):play_sequence{}
            for _, pool in ipairs(location.pools) do
                context:activate_objects{slots = pool.objects, active = true}
                context:slot(pool.sequence):play_sequence{}
            end
            local watch = context:slot(location.monitor):watch_damage{
                target = context:slot(location.target)}
            scope:set_variable(c.DAMAGE_REQUEST_KEY, watch.value)
            scope:set_variable(c.WATCHED_KEY, scope:variable(c.LOCATION_KEY))
            scope:clear_variable(c.HEALTH_SEEN_KEY)
            for index, unit in ipairs(location.units) do
                scope:set_variable(live_key(index), true)
                squads.place(context, scope, unit, c.SQUAD_REQUEST_KEY .. index)
            end
            scope:set_variable(c.INTEGRITY_KEY, c.INTEGRITY_MAX)
        end

        --- Forgets the previous attempt before anything of the new one is created.
        local function reset(scope)
            scope:set_variable(c.LOCATION_KEY, 1)
            for _, key in ipairs({c.PURSUING_KEY, c.FINAL_KEY, c.ULTRA_KEY, c.WATCHED_KEY,
                c.HEALTH_SEEN_KEY}) do
                scope:clear_variable(key)
            end
            for index = 1, c.MAX_SQUADS do scope:clear_variable(live_key(index)) end
        end

        --- Counts the current location's squads still alive.
        local function alive(scope, location)
            local count = 0
            for index = 1, #location.units do
                if scope:variable(live_key(index)) == true then count = count + 1 end
            end
            return count
        end

        --- Retires this attempt's live squads; cleared flags make later reports stale.
        local function retire_squads(context, scope)
            local location = here(scope)
            for index, unit in ipairs(location.units) do
                if scope:variable(live_key(index)) == true then
                    squads.retire(context, unit.squad)
                    scope:clear_variable(live_key(index))
                end
            end
            if scope:variable(c.ULTRA_KEY) == true then
                squads.retire(context, ultra.squad)
                scope:clear_variable(c.ULTRA_KEY)
            end
        end

        --- Moves the Blight on, or opens the final window at the last location.
        local function location_cleared(context, scope)
            if (scope:variable(c.LOCATION_KEY) or 1) >= #locations then
                scope:set_variable(c.FINAL_KEY, true)
                scope:start_timer(c.FINAL_TIMER, c.FINAL_WINDOW_MS)
                ev:goal(context, scope, presentation.directive.enter)
                return
            end
            scope:set_variable(c.PURSUING_KEY, true)
            ev:say(context, c.CUE_MOVE)
            ev.lifecycle:restart_clock(scope, c.PURSUE_SECONDS)
            ev:goal(context, scope, presentation.directive.enter)
            scope:start_timer(c.ARRIVE_TIMER, c.ARRIVE_MS)
        end

        --- Records one current-location squad death; Integrity follows the squads left.
        ---@return boolean handled True when the report named a live squad.
        local function squad_died(context, scope, report)
            local location = here(scope)
            for index, unit in ipairs(location.units) do
                if scope:variable(live_key(index)) == true
                    and lib.is_slot(context, report, unit.slot) then
                    scope:clear_variable(live_key(index))
                    local left = alive(scope, location)
                    scope:set_variable(c.INTEGRITY_KEY,
                        c.INTEGRITY_MAX * left // #location.units)
                    if left == 0 then
                        location_cleared(context, scope)
                    else
                        ev:goal(context, scope, presentation.directive.enter)
                    end
                    return true
                end
            end
            return false
        end

        -- Reference order after the flag leaves: darkening with the row, alert, the Blight.
        hooks.incoming = {
            {delay_ms = c.INTRO_AFTER_LEAVE_MS, run = function(context, scope)
                reset(scope)
                context:slot(definition.intro):play_sequence{}
                ev:show_incoming(context, scope, presentation.directive.enter,
                    definition.directive)
            end},
            {delay_ms = c.ALERT_AFTER_INTRO_MS, run = function(context)
                ev:say(context, c.CUE_ALERT)
            end},
            {delay_ms = c.ARRIVE_AFTER_ALERT_MS, run = function(context, scope)
                arrive(context, scope, locations[1])
            end},
        }
        hooks.start_delay_ms = c.START_AFTER_ARRIVE_MS
        hooks.timers = {c.ARRIVE_TIMER, c.FIGHT_TIMER, c.FINAL_TIMER}
        hooks.tracked = {c.BLIGHT_REQUEST_KEY}
        for index = 1, c.MAX_SQUADS do
            squads.append_request_keys(hooks.tracked, c.SQUAD_REQUEST_KEY .. index)
        end
        squads.append_request_keys(hooks.tracked, c.ULTRA_REQUEST_KEY)
        hooks.required = {}
        for _, key in ipairs(hooks.tracked) do hooks.required[#hooks.required + 1] = key end
        -- A lost watch costs the heroic route only; normal play continues.
        hooks.tracked[#hooks.tracked + 1] = c.DAMAGE_REQUEST_KEY
        hooks.scenery = definition.scenery

        --- Rows: the Blight's Integrity, the move to the next location, then the Blightmaker.
        function hooks.goal(scope)
            if ev:heroic(scope) then
                return {directive = definition.heroic_directive,
                    total_seconds = c.HEROIC_SECONDS, navpoint = here(scope).navpoint}
            end
            if scope:variable(c.PURSUING_KEY) == true then
                local next_location = (scope:variable(c.LOCATION_KEY) or 1) + 1
                return {directive = definition.pursue_directive,
                    total_seconds = c.PURSUE_SECONDS,
                    navpoint = locations[next_location].navpoint}
            end
            return {
                directive = definition.directive,
                total_seconds = location_seconds(scope),
                -- A progress label alone does not declare the SDK's integer counter capability.
                progress = definition.directive.counter == true
                    and {scope:variable(c.INTEGRITY_KEY) or c.INTEGRITY_MAX, c.INTEGRITY_MAX}
                    or nil,
                navpoint = here(scope).navpoint,
            }
        end

        --- The first Blight is already standing; the fight opens with the clock.
        function hooks.on_start(context, scope)
            context:slot(definition.active):play_sequence{}
            open_location(context, scope, locations[1])
        end

        --- The Blightmaker replaces the fight at the Blight that died, once.
        function hooks.on_heroic(context, scope)
            local location = here(scope)
            for _, name in ipairs(hooks.timers) do scope:cancel_timer(name) end
            scope:clear_variable(c.PURSUING_KEY)
            scope:clear_variable(c.FINAL_KEY)
            scope:clear_variable(c.WATCHED_KEY)
            retire_squads(context, scope)
            depart(context, location)
            scope:set_variable(c.ULTRA_KEY, true)
            local boss = {squad = ultra.squad, slot = ultra.slot,
                spawn_rule = location.center_rule}
            squads.place(context, scope, boss, c.ULTRA_REQUEST_KEY)
            ev:say(context, c.CUE_HEROIC)
        end

        hooks.on_stop = retire_squads

        --- The Blight goes at a normal ending; its authored exit animation is unrecovered.
        function hooks.on_finish(context, scope)
            if not ev:heroic(scope) then depart(context, here(scope)) end
        end

        --- The skeleton removes the scenery; this family holds no other final state.
        function hooks.on_cleanup() end

        --- Advances Integrity on squad clears and succeeds on the Blightmaker's death.
        function hooks.on_squad(context, scope, _, report)
            if squad_died(context, scope, report) then return false end
            if scope:variable(c.ULTRA_KEY) == true
                and lib.is_slot(context, report, ultra.slot) then
                scope:clear_variable(c.ULTRA_KEY)
                ev:finish(context, scope, true)
            end
            return false
        end

        --- Commits heroic when the watched Blight, seen alive, reports zero health.
        function hooks.on_damage(context, scope, _, report)
            local watched = scope:variable(c.WATCHED_KEY)
            if watched == nil or ev:heroic(scope) or type(report.health) ~= "number"
                or not lib.is_slot(context, report, locations[watched].monitor) then
                return false
            end
            if report.health > 0 then
                scope:set_variable(c.HEALTH_SEEN_KEY, true)
            elseif scope:variable(c.HEALTH_SEEN_KEY) == true then
                ev:commit_heroic(context, scope, c.HEROIC_SECONDS)
            end
            return false
        end

        --- Handles the move stages and the end of the final window.
        function hooks.on_timer(context, scope, _, _, name)
            if name == c.ARRIVE_TIMER then
                depart(context, here(scope))
                scope:clear_variable(c.WATCHED_KEY)
                local index = scope:variable(c.LOCATION_KEY) + 1
                arrive(context, scope, locations[index])
                scope:start_timer(c.FIGHT_TIMER, c.FIGHT_AFTER_ARRIVE_MS)
            elseif name == c.FIGHT_TIMER then
                local index = scope:variable(c.LOCATION_KEY) + 1
                scope:set_variable(c.LOCATION_KEY, index)
                scope:clear_variable(c.PURSUING_KEY)
                open_location(context, scope, locations[index])
                ev:goal(context, scope, presentation.directive.enter)
            elseif name == c.FINAL_TIMER and scope:variable(c.FINAL_KEY) == true then
                ev:finish(context, scope, true)
            end
            return false
        end

        --- Uses the same completion path when the native generation ends before an alive fall.
        function hooks.on_squad_counted(context, scope, site, report)
            local units = {ultra, table.unpack(here(scope).units)}
            for _, unit in ipairs(units) do
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
