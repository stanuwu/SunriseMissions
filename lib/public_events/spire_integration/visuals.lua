-- Spire scenery and lane presentation: the centre build, barriers, conflux pillars, bug streams,
-- the heroic clouds and scenes, and the spire's endings. Retained values stay in the host scope.
local devices = require("lib.public_events.devices")
local c = require("lib.public_events.spire_integration.settings")

local module = {}

--- Binds Spire presentation to site content; all revisions remain in the host scope.
---@param definition table Authored site references.
---@return table visuals Bound presentation operations.
function module.new(definition)
    local lanes = definition.lanes
    local heroic = definition.heroic
    local intro = definition.intro
    local active = definition.active
    local spire = definition.spire
    local stream_target = definition.stream_target
    local barrier_props = definition.barrier_props
    local conflux_props = definition.conflux_props
    local plates = definition.plates
    local beacon = definition.beacon
    local cover = definition.cover
    local chest = definition.chest
    local visuals = {}

    --- Cached position keys for every lane's barrier and conflux device.
    ---@return string[] keys Position keys owned by these visuals.
    function visuals.device_keys()
        local keys = {}
        for lane_index = 1, #lanes do
            keys[#keys + 1] = c.CHARGE_KEY .. lane_index
            keys[#keys + 1] = c.CONFLUX_CHARGE_KEY .. lane_index
        end
        return keys
    end

    --- Objects the shared event removes with the chest at cleanup.
    function visuals.scenery()
        local slots = {spire, beacon, stream_target}
        for _, list in ipairs({cover, barrier_props, conflux_props, plates}) do
            for _, slot in ipairs(list) do slots[#slots + 1] = slot end
        end
        return slots
    end

    --- Selects the authored spire ending.
    function visuals.destroy_spire(context, scope, value)
        context:activate_objects{slots = {spire}, active = true, position = {value = value}}
    end

    --- Binds the stream target before attaching the lane's hop-on to it.
    function visuals.set_stream(context, scope, lane_index, on)
        local lane = lanes[lane_index]
        if on then
            context:slot(lane.stream_filter):set_object_filter{target = context:slot(stream_target)}
            context:slot(lane.stream):attach_hop_on{filter = context:slot(lane.stream_filter)}
        else
            context:slot(lane.stream):detach_hop_on{}
        end
    end

    --- Sets the object timer of each slot in place; elapsed counts up from the total.
    local function set_timers(context, slots, remaining, total, running)
        for _, slot in ipairs(slots) do
            context:slot(slot):set_interactable_object{active = true, respawn = false,
                timer = {elapsed = total - remaining, remaining = remaining,
                    active = running == true}}
        end
    end

    --- Stops the lane stream and selects its completed prop presentation.
    function visuals.react_to_capture(context, scope, lane_index, lane)
        if scope:variable(c.LANE_STAGE_KEY .. lane_index) == c.LANE_CHARGING then
            visuals.set_stream(context, scope, lane_index, false)
        end
        scope:set_variable(c.LANE_STAGE_KEY .. lane_index, c.LANE_CAPTURED)
        devices.set_position(context, scope, lane.devices[c.BARRIER_DEVICE],
            c.CHARGE_KEY .. lane_index, c.BARRIER_WHITE, true)
        devices.set_position(context, scope, lane.devices[c.CONFLUX_DEVICE],
            c.CONFLUX_CHARGE_KEY .. lane_index, c.CONFLUX_COMPLETE)
    end

    --- Updates charge timing in place on occupancy changes or a progress step.
    function visuals.sync_barrier(context, scope, lane_index, progress, held)
        local synced = scope:variable(c.BARRIER_SYNC_KEY .. lane_index)
        local running = scope:variable(c.BARRIER_RUN_KEY .. lane_index)
        if synced ~= nil and running == held and progress - synced < c.BARRIER_SYNC_STEP then
            return
        end
        scope:set_variable(c.BARRIER_SYNC_KEY .. lane_index, progress)
        scope:set_variable(c.BARRIER_RUN_KEY .. lane_index, held)
        local remaining = math.floor(c.PLATE_CHARGE_SECONDS * (1 - progress) + 0.5)
        if remaining < 0 then remaining = 0 end
        set_timers(context, {lanes[lane_index].barrier}, remaining, c.PLATE_CHARGE_SECONDS, held)
    end

    --- Activates the central objects before starting their authored intro sequence.
    function visuals.build_centre(context)
        context:activate_objects{slots = {spire, stream_target}, active = true}
        context:slot(intro):play_sequence{}
    end

    --- Starts the authored heroic sequence, clouds and scenes.
    function visuals.start_heroic(context)
        context:slot(heroic.audio):play_sequence{}
        context:activate_objects{slots = heroic.clouds, active = true}
        for _, scene in ipairs(heroic.scenes) do
            context:scene(scene):activate{}
        end
    end

    --- Stops heroic scenes before deactivating their cloud objects.
    function visuals.stop_heroic(context)
        for _, scene in ipairs(heroic.scenes) do
            context:scene(scene):stop{}
        end
        context:activate_objects{slots = heroic.clouds, active = false}
    end

    --- Stops lane streams and selects withdrawal; the skeleton clears the music.
    function visuals.stop_lanes(context, scope)
        for lane_index, lane in ipairs(lanes) do
            if scope:variable(c.LANE_STAGE_KEY .. lane_index) == c.LANE_CHARGING then
                visuals.set_stream(context, scope, lane_index, false)
            end
            devices.set_position(context, scope, lane.devices[c.BARRIER_DEVICE],
                c.CHARGE_KEY .. lane_index, c.BARRIER_WITHDRAWN, true)
            devices.set_position(context, scope, lane.devices[c.CONFLUX_DEVICE],
                c.CONFLUX_CHARGE_KEY .. lane_index, c.CONFLUX_COMPLETE)
        end
    end

    --- Activates lane components before the objective and combat are started.
    function visuals.begin_event(context)
        context:activate_objects{slots = {chest}, active = false}
        context:activate_objects{slots = cover, active = true}
        context:activate_objects{slots = {beacon}, active = false}
        context:activate_objects{slots = barrier_props, active = true}
        set_timers(context, barrier_props, 0, c.EVENT_SECONDS, false)
        context:activate_objects{slots = conflux_props, active = true}
        set_timers(context, conflux_props, c.EVENT_SECONDS, c.EVENT_SECONDS, false)
        context:activate_objects{slots = plates, active = true, capture_plate = true}
        for _, lane in ipairs(lanes) do
            context:slot(lane.devices[c.BARRIER_DEVICE]):transition{
                transition = context.sdk.device_transitions.open}
        end
    end

    --- Starts the active sequence and idles barriers that have not begun charging.
    function visuals.finish_intro(context, scope)
        context:slot(active):play_sequence{}
        for lane_index, lane in ipairs(lanes) do
            if scope:variable(c.LANE_STAGE_KEY .. lane_index) == nil then
                devices.set_position(context, scope, lane.devices[c.BARRIER_DEVICE],
                    c.CHARGE_KEY .. lane_index, c.BARRIER_IDLE, true)
            end
        end
    end

    return visuals
end

return module
