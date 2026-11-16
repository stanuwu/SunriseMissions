-- Spire lane mechanics: waves, capture challengers and plates on the shared event.
-- Mutable state stays in the host scope.
local lib = require("lib.mission_lib")
local devices = require("lib.public_events.devices")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.spire_integration.settings")

local module = {}

--- Binds lane mechanics without retaining callback contexts or mutable encounter state.
---@param definition table Authored site references.
---@param ev table Shared event; its lifecycle supplies the clock.
---@param visuals table Bound Spire presentation operations.
---@return table lanes Bound wave and capture operations.
function module.new(definition, ev, visuals)
    local lanes = definition.lanes
    local opening = definition.opening
    local guards = definition.heroic.guards
    local lifecycle = ev.lifecycle
    local lane_logic = {}

    local function wave_key(lane_index) return c.WAVE_KEY .. lane_index end
    local function capture_key(lane_index) return c.CAPTURE_KEY .. lane_index end
    local function request_key(lane_index) return c.REQUEST_KEY .. lane_index end
    --- Each wave slot counts its own generations, so a lane keeps one mark per wave.
    local function ended_key(lane_index, wave) return c.ENDED_KEY .. lane_index .. "_" .. wave end
    --- Marks a heroic wave as placed and not yet ended.
    local function live_key(lane_index, wave) return c.LIVE_KEY .. lane_index .. "_" .. wave end
    local function disruptor_key(lane_index, index)
        return c.DISRUPTOR_KEY .. lane_index .. "_" .. index
    end

    --- Retains all squad requests; only the opening and lane waves are objective-critical.
    ---@return string[] tracked All placement and objective keys cleared at attempt start.
    ---@return string[] required Keys whose terminal failure aborts the event.
    function lane_logic.tracked_keys()
        local keys, required = {}, {}
        for lane_index = 0, #lanes do
            squads.append_request_keys(keys, request_key(lane_index))
            squads.append_request_keys(required, request_key(lane_index))
        end
        for lane_index, lane in ipairs(lanes) do
            for index = 1, #lane.disruptors do
                squads.append_request_keys(keys, disruptor_key(lane_index, index))
            end
        end
        for index = 1, #guards do
            squads.append_request_keys(keys, c.GUARD_KEY .. index)
        end
        return keys, required
    end

    --- Clears every lane key for a new attempt and sets the integration count.
    function lane_logic.reset(scope)
        scope:set_variable(c.DEAD_KEY, 0)
        scope:clear_variable(c.SACRIFICE_KEY)
        scope:set_variable(c.INTEGRATION_KEY, c.INTEGRATIONS)
        for lane_index, lane in ipairs(lanes) do
            for _, key in ipairs({c.SACRIFICE_KEY, c.CAPTURE_KEY, c.LANE_STAGE_KEY,
                c.BARRIER_SYNC_KEY, c.BARRIER_RUN_KEY, c.REPLACED_KEY,
                c.CHARGE_KEY, c.CONFLUX_CHARGE_KEY, c.WAVE_COUNT_KEY}) do
                scope:clear_variable(key .. lane_index)
            end
            for index = 1, #lane.disruptors do
                scope:clear_variable(disruptor_key(lane_index, index))
            end
            for wave = 1, #lane.waves do
                scope:clear_variable(ended_key(lane_index, wave))
                scope:clear_variable(live_key(lane_index, wave))
            end
        end
    end

    --- The Goblin wave's temperament list: normal Goblins walk in and sacrifice, heroic ones
    --- fight, so heroic clears the list the squad keeps. Other waves leave theirs alone.
    local function wave_temperaments(scope, lane, wave)
        if wave ~= c.WAVE_GOBLINS then return nil end
        return ev:heroic(scope) and {} or {lane.sacrifice}
    end

    --- True while any lane still has one of the big heroic squads out.
    local function solo_wave_live(scope)
        for lane_index = 1, #lanes do
            for _, wave in ipairs(c.HEROIC_WAVES) do
                if c.HEROIC_SOLO_WAVES[wave]
                    and scope:variable(live_key(lane_index, wave)) == true then
                    return true
                end
            end
        end
        return false
    end

    --- Returns the next heroic wave with nothing live on its slot, or nil if the lane is full.
    local function choose_heroic_wave(scope, count, lane_index)
        for step = 0, #c.HEROIC_WAVES - 1 do
            local wave = c.HEROIC_WAVES[(count + step) % #c.HEROIC_WAVES + 1]
            if c.HEROIC_SOLO_WAVES[wave] and solo_wave_live(scope) then
                wave = c.HEROIC_SOLO_SUBSTITUTE
            end
            if scope:variable(live_key(lane_index, wave)) ~= true then return wave end
        end
        return nil
    end

    --- Selects the next wave from the current mode and elapsed-time schedule.
    local function choose_wave(scope, count, lane_index)
        if ev:heroic(scope) then return choose_heroic_wave(scope, count, lane_index) end
        local schedule = c.MIDDLE_WAVES
        if lifecycle:remaining(scope) <= c.FINAL_MINUTE_SECONDS then
            schedule = c.FINAL_WAVES
        elseif lifecycle:elapsed(scope) < c.MINOTAURS_FROM_SECONDS then
            schedule = c.OPENING_WAVES
        end
        return schedule[count % #schedule + 1]
    end

    --- True once the member counts cover everything the placement asked for.
    local function all_ended(context, unit, ended)
        local squad = context:squad(unit.squad)
        for index = 1, squad.member_count do
            if (ended[index] or 0) < (squad.default_counts[index] or 0) then return false end
        end
        return true
    end

    --- Replaces one lane wave, retaining its identity and spawn request.
    function lane_logic.advance_lane(context, scope, lane_index, replacing)
        if lane_index == 0 then
            return
        end
        local lane = lanes[lane_index]
        local count = scope:variable(c.WAVE_COUNT_KEY .. lane_index) or 0
        local wave = choose_wave(scope, count, lane_index)
        if wave == nil then return end
        local previous = scope:variable(wave_key(lane_index)) or 0
        if previous >= 1 and previous <= #lane.waves and previous ~= wave then
            if scope:variable(live_key(lane_index, previous)) ~= true then
                squads.retire(context, lane.waves[previous].squad)
            end
        elseif replacing and previous == wave then
            scope:set_variable(c.REPLACED_KEY .. lane_index, scope:variable(c.TICK_KEY) or 0)
        end
        scope:set_variable(c.WAVE_COUNT_KEY .. lane_index, count + 1)
        scope:set_variable(wave_key(lane_index), wave)
        if ev:heroic(scope) then scope:set_variable(live_key(lane_index, wave), true) end
        squads.place(context, scope, lane.waves[wave], request_key(lane_index),
            wave_temperaments(scope, lane, wave))
    end

    --- Places the opening squad, when the policy keeps it, and the first wave of every lane.
    function lane_logic.open(context, scope)
        if c.PLACE_OPENING_SQUAD then squads.place(context, scope, opening, request_key(0)) end
        for lane_index = 1, #lanes do
            scope:set_variable(wave_key(lane_index), 0)
            lane_logic.advance_lane(context, scope, lane_index)
        end
    end

    --- Replaces every lane wave from the heroic schedule.
    function lane_logic.advance_all(context, scope)
        for lane_index = 1, #lanes do
            lane_logic.advance_lane(context, scope, lane_index, true)
        end
    end

    --- Adds each lane's next heroic wave beside its live ones, then waits for the next round.
    function lane_logic.reinforce(context, scope)
        for lane_index = 1, #lanes do
            lane_logic.advance_lane(context, scope, lane_index)
        end
        scope:start_timer(c.REINFORCE_TIMER, c.REINFORCE_MS)
    end

    --- Places the heroic guards with their objectives.
    function lane_logic.place_guards(context, scope)
        for index, guard in ipairs(guards) do
            squads.place(context, scope, guard, c.GUARD_KEY .. index)
        end
    end

    --- Places each capture challenger at most once per event attempt.
    local function send_disruptor(context, scope, lane_index, index)
        local key = disruptor_key(lane_index, index)
        if scope:variable(key) ~= nil then return end
        squads.place(context, scope, lanes[lane_index].disruptors[index], key)
    end

    --- Removes requested opening, lane, challenger and guard squads.
    function lane_logic.retire_live_waves(context, scope)
        if scope:variable(request_key(0)) ~= nil then
            squads.retire(context, opening.squad)
        end
        for lane_index, lane in ipairs(lanes) do
            local current = scope:variable(wave_key(lane_index)) or 0
            for wave, unit in ipairs(lane.waves) do
                if wave == current or scope:variable(live_key(lane_index, wave)) == true then
                    squads.retire(context, unit.squad)
                end
                scope:clear_variable(live_key(lane_index, wave))
            end
            for index, disruptor in ipairs(lane.disruptors) do
                local key = disruptor_key(lane_index, index)
                if scope:variable(key) ~= nil then
                    squads.retire(context, disruptor.squad)
                    scope:clear_variable(key)
                end
            end
        end
        for index, guard in ipairs(guards) do
            if scope:variable(c.GUARD_KEY .. index) ~= nil then
                squads.retire(context, guard.squad)
                scope:clear_variable(c.GUARD_KEY .. index)
            end
        end
    end

    --- Returns the lane and wave of a reporting slot, current or kept live, or nil.
    local function reporting_lane(context, scope, event)
        if lib.is_slot(context, event, opening.slot) then
            return 0, 0
        end
        for lane_index, lane in ipairs(lanes) do
            local current = scope:variable(wave_key(lane_index)) or 0
            for wave, unit in ipairs(lane.waves) do
                if (wave == current or scope:variable(live_key(lane_index, wave)) == true)
                    and lib.is_slot(context, event, unit.slot) then
                    return lane_index, wave
                end
            end
        end
        return nil
    end

    --- Coordinates the first charge, visual progress and challenger thresholds.
    local function follow_charge(context, scope, event)
        for lane_index, lane in ipairs(lanes) do
            if lib.is_slot(context, event, lane.plate)
                and scope:variable(capture_key(lane_index)) ~= true then
                local charging = (event.plate_progress or 0) > 0 or (event.plate_occupants or 0) > 0
                if charging and scope:variable(c.LANE_STAGE_KEY .. lane_index) == nil then
                    scope:set_variable(c.LANE_STAGE_KEY .. lane_index, c.LANE_CHARGING)
                    devices.set_position(context, scope, lane.devices[c.BARRIER_DEVICE],
                        c.CHARGE_KEY .. lane_index, c.BARRIER_WHITE, true)
                    devices.set_position(context, scope, lane.devices[c.CONFLUX_DEVICE],
                        c.CONFLUX_CHARGE_KEY .. lane_index, c.CONFLUX_ACTIVE)
                    send_disruptor(context, scope, lane_index, 1)
                    visuals.set_stream(context, scope, lane_index, true)
                end
                local progress = event.plate_progress or 0
                if scope:variable(c.LANE_STAGE_KEY .. lane_index) == c.LANE_CHARGING then
                    visuals.sync_barrier(context, scope, lane_index, progress,
                        (event.plate_occupants or 0) > 0)
                end
                if progress >= c.SECOND_DISRUPTOR_PROGRESS then
                    send_disruptor(context, scope, lane_index, 2)
                end
                if progress >= c.THIRD_DISRUPTOR_PROGRESS then
                    send_disruptor(context, scope, lane_index, 3)
                end
                return
            end
        end
    end

    --- Advances a defeated live wave while rejecting replacement-removal reports.
    function lane_logic.on_squad(context, scope, _, event)
        local lane_index, wave = reporting_lane(context, scope, event)
        if lane_index == nil then
            return false
        end
        if lane_index == 0 then
            if scope:variable(request_key(0)) == nil then
                return false
            end
            scope:clear_variable(request_key(0))
        elseif scope:variable(c.REPLACED_KEY .. lane_index) ~= nil then
            local replaced = scope:variable(c.REPLACED_KEY .. lane_index)
            local now = scope:variable(c.TICK_KEY) or 0
            scope:clear_variable(c.REPLACED_KEY .. lane_index)
            -- Ignore unversioned replacement removals only within the current service tick.
            if event.spawn_generation == nil and now - replaced < 1 then
                return false
            end
        end
        scope:set_variable(c.DEAD_KEY, (scope:variable(c.DEAD_KEY) or 0) + 1)
        if event.spawn_generation ~= nil then
            scope:set_variable(ended_key(lane_index, wave), event.spawn_generation)
        end
        scope:clear_variable(live_key(lane_index, wave))
        if wave == (scope:variable(wave_key(lane_index)) or 0) then
            lane_logic.advance_lane(context, scope, lane_index)
        end
        return false
    end

    --- Advances a wave whose members ended with no alive count, once per placement.
    function lane_logic.on_squad_counted(context, scope, site, event)
        local lane_index, wave = reporting_lane(context, scope, event)
        if lane_index == nil or event.spawn_generation == nil
            or event.spawn_generation == scope:variable(ended_key(lane_index, wave)) then
            return false
        end
        local unit = opening
        if lane_index > 0 then
            unit = lanes[lane_index].waves[wave]
        end
        if not all_ended(context, unit, event.slot_counts) then return false end
        return lane_logic.on_squad(context, scope, site, event)
    end

    --- Records objective counts without interpreting deaths as integrations.
    function lane_logic.on_objective(context, scope, _, event)
        for lane_index, lane in ipairs(lanes) do
            if lib.is_slot(context, event, lane.objective) then
                local key = c.SACRIFICE_KEY .. lane_index
                local previous = scope:variable(key) or 0
                local count = event.task_count or 0
                if count > previous then
                    scope:set_variable(key, count)
                    local sum = (scope:variable(c.SACRIFICE_KEY) or 0) + count - previous
                    scope:set_variable(c.SACRIFICE_KEY, sum)
                end
                return false
            end
        end
        return false
    end

    --- Applies plate reports and returns whether the heroic threshold is met.
    function lane_logic.on_object_state(context, scope, _, event)
        if event.plate_owner == nil then
            return false
        end
        if event.plate_owner < 0 then
            if event.plate_progress ~= nil then follow_charge(context, scope, event) end
            return false
        end
        local captured = 0
        for lane_index, lane in ipairs(lanes) do
            if lib.is_slot(context, event, lane.plate)
                and scope:variable(capture_key(lane_index)) ~= true then
                scope:set_variable(capture_key(lane_index), true)
                visuals.react_to_capture(context, scope, lane_index, lane)
            end
            if scope:variable(capture_key(lane_index)) == true then
                captured = captured + 1
            end
        end
        return captured == #lanes and not ev:heroic(scope)
            and lifecycle:remaining(scope) > c.HEROIC_MIN_REMAINING_SECONDS
    end

    return lane_logic
end

return module
