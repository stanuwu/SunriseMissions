-- Weapons Exchange mechanics: the opening squads, the Arsenal
-- Walker's dropship, the cache barriers opened by player deposits and the heroic second Walker.
local lib = require("lib.mission_lib")
local event = require("lib.public_events.event")
local presentation = require("lib.public_events.presentation")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.weapons_exchange.settings")

local module = {}

---@class WeaponsDrop
---@field carrier integer Roster index of the dropship squad.
---@field walker integer Roster index of the Walker squad.
---@field pilot string Combatant slot of the dropship pilot.
---@field path string Entrance path slot the pilot follows.
---@field minions integer Roster index of the squad that arrives with the Walker.

--- Builds the Weapons Exchange handler; its retained keys require the site's freeroam scope.
---@param definition table Authored site references; roster entries are placed by index.
---@return table handler Freeroam site handler.
function module.new(definition)
    local roster = definition.roster
    local arrays = definition.arrays
    local drops = definition.drops

    return event.new(definition, c, function(ev)
        local hooks = {}

        --- Returns the retained key naming whether a roster unit is alive.
        local function live_key(id)
            return c.LIVE_KEY .. id
        end

        --- Places one unit and marks it alive; its request stays tracked by the shared skeleton.
        local function place(context, scope, id)
            scope:set_variable(live_key(id), true)
            squads.place(context, scope, roster[id], c.REQUEST_KEY .. id)
        end

        --- Retires every live squad this attempt placed.
        local function retire_squads(context, scope)
            for id, unit in ipairs(roster) do
                if scope:variable(live_key(id)) ~= nil then
                    squads.retire(context, unit.squad)
                    scope:clear_variable(live_key(id))
                end
            end
            scope:clear_variable(c.PATH_KEY)
        end

        --- Returns the roster index whose live squad this death report names, or nil.
        local function dead_unit(context, scope, report)
            for id, unit in ipairs(roster) do
                if scope:variable(live_key(id)) == true
                    and lib.is_slot(context, report, unit.slot) then
                    return id
                end
            end
            return nil
        end

        --- True once every opening squad is gone.
        local function opening_cleared(scope)
            for _, id in ipairs(definition.opening) do
                if scope:variable(live_key(id)) == true then return false end
            end
            return true
        end

        --- Counts the cache arrays whose barrier is down.
        local function open_arrays(scope)
            local count = 0
            for index = 1, #arrays do
                if scope:variable(c.OPEN_KEY .. index) == true then count = count + 1 end
            end
            return count
        end

        --- Drops one carrier with its cargo, then sends the pilot along the entrance path.
        ---@param index integer Index in definition.drops; the retained path flag holds it.
        local function fly_in(context, scope, index)
            local drop = drops[index]
            local pending = scope:variable(c.PATH_KEY)
            if pending == index then
                scope:clear_variable(c.PATH_KEY)
                squads.follow_path(context, drop.pilot, drop.path)
                return
            end
            place(context, scope, drop.carrier)
            place(context, scope, drop.walker)
            place(context, scope, drop.minions)
            scope:set_variable(c.PATH_KEY, index)
            scope:start_timer(c.PATH_TIMER, c.PATH_MS)
        end

        -- After the flag leaves: ketch with the event row, then the alert.
        hooks.incoming = {
            {delay_ms = c.KETCH_AFTER_LEAVE_MS, run = function(context, scope)
                -- A site without the intro Ketch prefab opens with the sequence alone.
                if definition.ketch ~= nil then
                    context:activate_objects{slots = {definition.ketch}, active = true}
                end
                context:slot(definition.sequences.intro):play_sequence{}
                ev:show_incoming(context, scope, presentation.directive.enter)
            end},
            {delay_ms = c.ALERT_AFTER_KETCH_MS, run = function(context)
                ev:say(context, c.CUE_ALERT)
            end},
        }
        hooks.start_delay_ms = c.START_AFTER_ALERT_MS
        hooks.timers = {c.PATH_TIMER}
        hooks.tracked = {}
        hooks.required = {}
        for id = 1, #roster do
            squads.append_request_keys(hooks.tracked, c.REQUEST_KEY .. id)
        end
        -- Only squads that gate the event abort it when refused; escorts and guards do not.
        for _, id in ipairs(definition.critical) do
            squads.append_request_keys(hooks.required, c.REQUEST_KEY .. id)
        end
        hooks.scenery = {definition.ketch}
        for _, array in ipairs(arrays) do
            for _, slot in ipairs(array.props) do hooks.scenery[#hooks.scenery + 1] = slot end
        end

        --- The row follows the phase: opening, Walker, then heroic.
        function hooks.goal(scope)
            if ev:heroic(scope) then
                return {directive = definition.heroic_directive, total_seconds = c.HEROIC_SECONDS}
            end
            if scope:variable(c.CALLED_KEY) == true then
                return {directive = definition.walker_directive, total_seconds = c.EVENT_SECONDS}
            end
            return {directive = definition.directive, total_seconds = c.EVENT_SECONDS}
        end

        --- Opens the site: the barriers stand and the opening squads arrive.
        function hooks.on_start(context, scope)
            scope:clear_variable(c.CALLED_KEY)
            scope:clear_variable(c.WALKER_DEAD_KEY)
            scope:clear_variable(c.HEROIC_DEAD_KEY)
            scope:clear_variable(c.PATH_KEY)
            for id = 1, #roster do scope:clear_variable(live_key(id)) end
            for index, array in ipairs(arrays) do
                scope:clear_variable(c.OPEN_KEY .. index)
                for receptacle = 1, #array.receptacles do
                    scope:clear_variable(c.DEPOSIT_KEY .. index .. "." .. receptacle)
                end
                context:activate_objects{slots = array.props, active = true}
            end
            context:slot(definition.sequences.active):play_sequence{}
            for _, id in ipairs(definition.opening) do place(context, scope, id) end
        end

        --- The second Walker arrives with its escort; the sensor row follows from the skeleton.
        function hooks.on_heroic(context, scope)
            ev:say(context, c.CUE_CACHES)
            context:slot(definition.sequences.heroic):play_sequence{}
            for _, id in ipairs(definition.heroic_escort) do place(context, scope, id) end
            fly_in(context, scope, definition.heroic_drop)
        end

        hooks.on_stop = retire_squads

        --- No scenery moves at the ending; the shared cleanup removes the props.
        function hooks.on_finish() end

        --- Final removals are the scenery list alone.
        function hooks.on_cleanup() end

        --- Calls the Walker once the opening squads are gone and arms the receptacles.
        local function call_walker(context, scope)
            scope:set_variable(c.CALLED_KEY, true)
            context:slot(definition.sequences.inbound):play_sequence{}
            fly_in(context, scope, definition.walker_drop)
            for _, array in ipairs(arrays) do
                for _, receptacle in ipairs(array.receptacles) do
                    context:slot(receptacle):set_interactable_object{track_owner = true}
                end
            end
            ev:goal(context, scope, presentation.directive.enter)
        end

        --- Ends the event once every Walker that was called is down.
        local function walker_down(context, scope)
            if scope:variable(c.WALKER_DEAD_KEY) ~= true then return end
            if ev:heroic(scope) and scope:variable(c.HEROIC_DEAD_KEY) ~= true then return end
            ev:finish(context, scope, true)
        end

        --- Records deaths: the opening clears into the Walker; the Walkers end the event.
        function hooks.on_squad(context, scope, _, report)
            local id = dead_unit(context, scope, report)
            if id == nil then return false end
            scope:clear_variable(live_key(id))
            if id == drops[definition.walker_drop].walker then
                scope:set_variable(c.WALKER_DEAD_KEY, true)
                walker_down(context, scope)
            elseif id == drops[definition.heroic_drop].walker then
                scope:set_variable(c.HEROIC_DEAD_KEY, true)
                walker_down(context, scope)
            elseif scope:variable(c.CALLED_KEY) ~= true and opening_cleared(scope) then
                call_walker(context, scope)
            end
            return false
        end

        --- A refused opening guard is not a kill; it leaves the opening so play can continue.
        function hooks.on_failure(context, scope, report)
            for _, id in ipairs(definition.opening) do
                if squads.owns_request(scope, c.REQUEST_KEY .. id, report.request_key) then
                    scope:clear_variable(live_key(id))
                    if scope:variable(c.CALLED_KEY) ~= true and opening_cleared(scope) then
                        call_walker(context, scope)
                    end
                    return
                end
            end
        end

        --- Finds the array and receptacle position that an interaction report names.
        local function receptacle_of(context, report)
            for index, array in ipairs(arrays) do
                for position, slot in ipairs(array.receptacles) do
                    if lib.is_slot(context, report, slot) then return index, position end
                end
            end
            return nil
        end

        --- Records one deposit; a full array drops its barrier and three open caches go heroic.
        --- Deposits need the Walker's charges, so they count only after it was called.
        function hooks.on_interaction(context, scope, _, report)
            local index, position = receptacle_of(context, report)
            if index == nil or scope:variable(c.CALLED_KEY) ~= true or ev:heroic(scope)
                or report.owner_key == nil then
                return false
            end
            local key = c.DEPOSIT_KEY .. index .. "." .. position
            if scope:variable(key) ~= nil then return false end
            scope:set_variable(key, report.owner_key)
            context:slot(arrays[index].receptacles[position]):set_interactable_object{
                used = true, track_owner = true}
            for receptacle = 1, #arrays[index].receptacles do
                if scope:variable(c.DEPOSIT_KEY .. index .. "." .. receptacle) == nil then
                    return false
                end
            end
            scope:set_variable(c.OPEN_KEY .. index, true)
            context:activate_objects{slots = arrays[index].shields, active = false}
            if open_arrays(scope) == #arrays
                and ev:remaining(scope) > c.HEROIC_MIN_REMAINING_SECONDS then
                ev:commit_heroic(context, scope, c.HEROIC_SECONDS)
            end
            return false
        end

        --- Sends the pilot along the entrance path once its squad stands.
        function hooks.on_timer(context, scope, _, _, name)
            if name == c.PATH_TIMER then
                local pending = scope:variable(c.PATH_KEY)
                if pending ~= nil then fly_in(context, scope, pending) end
            end
            return false
        end

        --- Uses the same completion path when the native generation ends before an alive fall.
        function hooks.on_squad_counted(context, scope, site, report)
            local id = dead_unit(context, scope, report)
            if id ~= nil and squads.counted_out(context, roster[id], report) then
                return hooks.on_squad(context, scope, site, report)
            end
            return false
        end

        return hooks
    end)
end

return module
