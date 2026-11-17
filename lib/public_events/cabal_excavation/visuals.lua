-- Cabal Excavation scenery: the carrier, the lander, the override footprint, the covers and
-- the bombardment.
local devices = require("lib.public_events.devices")
local c = require("lib.public_events.cabal_excavation.settings")

local module = {}

--- Binds the site's scenery moves; retained device values stay in the host scope.
---@param definition table Authored site references.
---@return table visuals Bound scenery operations.
function module.new(definition)
    local lander = definition.lander
    local ship = definition.ship
    local zone = definition.zone
    local ring = definition.ring
    local cover = definition.cover
    local pods = definition.pods
    local artillery = definition.artillery
    local intro = definition.intro
    local active = definition.active
    local visuals = {}

    --- Brings the carrier in and darkens the site through the authored intro sequence.
    function visuals.fly_in(context, scope)
        context:activate_objects{slots = {ship.object}, active = true}
        scope:clear_variable(c.SHIP_KEY)
        devices.set_position(context, scope, ship.device, c.SHIP_KEY, c.SHIP_ARRIVAL, true)
        context:slot(intro):play_sequence{}
    end

    --- Lands the first authored barrage.
    function visuals.bombard(context)
        context:activate_objects{slots = artillery, active = true}
    end

    --- Sends the carrier away at the ending.
    function visuals.fly_out(context, scope)
        devices.set_position(context, scope, ship.device, c.SHIP_KEY, c.SHIP_DEPARTURE, true)
    end

    --- Fires the carrier's beam at the landing spot.
    function visuals.beam(context, scope)
        devices.set_position(context, scope, ship.device, c.SHIP_KEY, c.SHIP_DROP_BEAM, true)
    end

    --- Creates the lander in its authored arrival state.
    function visuals.land(context, scope)
        local requests = context:activate_objects{slots = {lander.object}, active = true}
        scope:set_variable(c.LANDER_REQUEST_KEY, requests[1].value)
        scope:clear_variable(c.LANDER_KEY)
    end

    --- Selects the authored mining branch.
    function visuals.mine(context, scope)
        devices.set_position(context, scope, lander.device, c.LANDER_KEY, c.LANDER_MINING, true)
    end

    --- Selects the authored withdrawal branch; its timeline removes the lander.
    function visuals.withdraw(context, scope)
        devices.set_position(context, scope, lander.device, c.LANDER_KEY, c.LANDER_WITHDRAWAL,
            true)
    end

    --- Selects the authored destruction branch; its timeline removes the lander.
    function visuals.destroy_lander(context, scope)
        devices.set_position(context, scope, lander.device, c.LANDER_KEY, c.LANDER_DESTRUCTION,
            true)
    end

    --- Opens the override footprint and the authored cover; the plate draws its own ring.
    function visuals.open_site(context, scope)
        local requests = context:activate_objects{slots = {zone}, active = true,
            capture_plate = true}
        scope:set_variable(c.ZONE_REQUEST_KEY, requests[1].value)
        if c.RING_WITH_ZONE then
            context:activate_objects{slots = {ring}, active = true}
        end
        context:activate_objects{slots = cover, active = true}
    end

    --- Starts the authored active sequence after the intro window.
    function visuals.finish_intro(context)
        context:slot(active):play_sequence{}
    end

    --- Removes the covers, pods and barrage and forgets the device positions.
    ---@return table requests Final-state removal requests retained by the shared cleanup.
    function visuals.cleanup(context, scope)
        local requests = {}
        for _, slots in ipairs({cover, pods, artillery}) do
            for _, request in ipairs(context:activate_objects{slots = slots, active = false}) do
                requests[#requests + 1] = request
            end
        end
        scope:clear_variable(c.LANDER_KEY)
        scope:clear_variable(c.SHIP_KEY)
        return requests
    end

    return visuals
end

return module
