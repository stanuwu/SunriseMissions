-- Injection Rig scenery: the carrier, the rig, its dome and the vent controls.
local devices = require("lib.public_events.devices")
local c = require("lib.public_events.injection_rig.settings")

local module = {}

--- Binds the site's scenery moves; retained device values stay in the host scope.
---@param definition table Authored site references.
---@return table visuals Bound scenery operations.
function module.new(definition)
    local ship = definition.ship
    local rig = definition.rig
    local pylon = definition.pylon
    local shields = definition.shields
    local visuals = {}

    --- Queues the next hop-on revision; an absent filter removes the vent's spawned objects.
    local function set_hop_on(context, scope, hop_on, filter)
        local revision = (scope:variable(c.HOP_ON_REVISION_KEY) or 0) + 1
        scope:set_variable(c.HOP_ON_REVISION_KEY, revision)
        return context:slot(hop_on):set_hop_on{
            filter = filter ~= nil and context:slot(filter) or nil, revision = revision,
        }
    end

    --- Names the rig as a filter's target; hop-ons spawn on its matches.
    local function target_rig(context, filter)
        context:slot(filter):set_object_filter{target = context:slot(rig.object)}
    end

    --- Returns the vents a tier opens; the lone tier rotates with the attempt.
    local function open_vents(scope, tier)
        local vents = definition.vents[tier].hop_ons
        if tier ~= c.LONE_VENT_TIER then return vents end
        return {vents[(scope:variable(c.ATTEMPT_KEY) or 0) % #vents + 1]}
    end

    --- Brings the carrier in through the authored intro sequence.
    function visuals.fly_in(context, scope)
        context:activate_objects{slots = {ship.object}, active = true}
        devices.set_position(context, scope, ship.device, c.SHIP_KEY, c.SHIP_ARRIVAL, true)
        context:slot(definition.intro):play_sequence{}
    end

    --- Places the rig; the first request is the required rig object. Domes wait for their phase.
    function visuals.deploy(context, scope)
        local requests = context:activate_objects{slots = rig.objects, active = true}
        scope:set_variable(c.RIG_REQUEST_KEY, requests[1].value)
        devices.set_position(context, scope, rig.device, c.SPIRE_KEY, c.SPIRE_DEPLOYED, false)
        devices.set_position(context, scope, pylon.device, c.PYLON_KEY, c.PYLON_IDLE, true)
    end

    --- Raises one dome; a dome only stands while the reference shows it.
    local function raise_dome(context, scope, shield, key)
        context:activate_objects{slots = {shield.object}, active = true}
        devices.set_position(context, scope, shield.device, key, c.SHIELD_UP, true)
    end

    --- Raises the lasting dome the reference keeps up from heroic to the ending.
    function visuals.raise_heroic_dome(context, scope)
        raise_dome(context, scope, shields[2], c.SHIELD_LARGE_KEY)
    end

    --- Removes the burn dome once its authored lowering has played.
    function visuals.clear_burn_dome(context)
        context:activate_objects{slots = {shields[1].object}, active = false}
    end

    --- Starts the authored active sequence.
    function visuals.begin(context)
        context:slot(definition.active):play_sequence{}
    end

    --- Burns the dome and opens one tier: its weak point and the hop-ons of its open vents.
    function visuals.open_tier(context, scope, tier)
        local vent = definition.vents[tier]
        devices.set_position(context, scope, pylon.device, c.PYLON_KEY, c.PYLON_BURN, true)
        raise_dome(context, scope, shields[1], c.SHIELD_KEY)
        context:activate_objects{slots = definition.burn_objects, active = true}
        context:activate_objects{slots = {vent.object}, active = true}
        context:slot(vent.monitor):watch_damage{target = context:slot(vent.object)}
        target_rig(context, definition.open_filter)
        for _, hop_on in ipairs(open_vents(scope, tier)) do
            set_hop_on(context, scope, hop_on, definition.open_filter)
        end
    end

    --- Shows a tier's destroyed vents.
    function visuals.mark_destroyed(context, scope, tier)
        target_rig(context, definition.destroyed_filter)
        set_hop_on(context, scope, definition.vents[tier].destroyed, definition.destroyed_filter)
    end

    --- Ends the burn: the tier shuts and the dome cools.
    function visuals.close_tier(context, scope, tier)
        for _, hop_on in ipairs(definition.vents[tier].hop_ons) do
            set_hop_on(context, scope, hop_on, nil)
        end
        context:activate_objects{slots = {definition.vents[tier].object}, active = false}
        context:activate_objects{slots = definition.burn_objects, active = false}
        devices.set_position(context, scope, shields[1].device, c.SHIELD_KEY, c.SHIELD_DOWN, true)
        devices.set_position(context, scope, pylon.device, c.PYLON_KEY, c.PYLON_IDLE, true)
    end

    --- Lowers the dome and sends the pylon and the carrier away whatever the outcome.
    ---@param heroic boolean Selects the rig's authored heroic exit.
    function visuals.withdraw(context, scope, heroic)
        target_rig(context, definition.exit_filter)
        set_hop_on(context, scope, heroic and definition.exit_heroic or definition.exit_normal,
            definition.exit_filter)
        devices.set_position(context, scope, shields[1].device, c.SHIELD_KEY, c.SHIELD_DOWN, true)
        devices.set_position(context, scope, shields[2].device, c.SHIELD_LARGE_KEY, c.SHIELD_DOWN,
            true)
        devices.set_position(context, scope, pylon.device, c.PYLON_KEY, c.PYLON_EXIT, true)
        devices.set_position(context, scope, ship.device, c.SHIP_KEY, c.SHIP_DEPARTURE, true)
    end

    --- Removes every vent control and burn object an interrupted attempt could leave behind.
    ---@return table requests Final-state removal requests retained by the shared cleanup.
    function visuals.cleanup(context, scope)
        local requests = {}
        for _, vent in ipairs(definition.vents) do
            for _, hop_on in ipairs(vent.hop_ons) do
                requests[#requests + 1] = set_hop_on(context, scope, hop_on, nil)
            end
            requests[#requests + 1] = set_hop_on(context, scope, vent.destroyed, nil)
            for _, request in ipairs(context:activate_objects{slots = {vent.object},
                active = false}) do
                requests[#requests + 1] = request
            end
        end
        for _, request in ipairs(context:activate_objects{slots = definition.burn_objects,
            active = false}) do
            requests[#requests + 1] = request
        end
        for _, hop_on in ipairs({definition.exit_normal, definition.exit_heroic}) do
            requests[#requests + 1] = set_hop_on(context, scope, hop_on, nil)
        end
        return requests
    end

    return visuals
end

return module
