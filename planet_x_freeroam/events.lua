local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local site = require("lib.public_events.spire_integration.site")
local spire = require("lib.public_events.spire_integration.encounter")
local schedule = require("lib.public_events.schedule")

local events = {}

-- The Spire entry in the authored Watcher's Grave public-event schedule.
local SPIRE_SITE_KEY = 0x748A97BE
-- The site uses the zone's authored rally prefab.
local WATCHERS_GRAVE_RALLY = "_80C03220"

--- Generated names of the Spire at Watcher's Grave; zone sensors omit the prefab prefix.
local WATCHERS_GRAVE = {
    prefab = function(stem) return "PF_VEXBLOCK01_" .. stem .. "_80C037B5" end,
    zone = function(stem) return stem .. "_80C037B5" end,
    cover = function(index) return "PF_VEXBLOCK01_O_VEX_COV_" .. index end,
    area = {"SLOT_0096"},
    navpoint = "LOCATION_POINT_80C037B5",
    rally_key = WATCHERS_GRAVE_RALLY,
}

--- Starts a site on the map's own clock: rally with the seconds left, or active at once. The zone
--- hands a slot picked for another site to that site by this key.
local function scheduled(handler, site_key)
    handler.site_key = site_key
    handler.schedule = function(context) return schedule.arrival(context, site_key) end
    return handler
end

--- Builds the Watcher's Grave Spire handler on the shared event skeleton.
function events.watchers_grave(mission)
    local definition = site.bind(mission, WATCHERS_GRAVE)
    -- Preserve the native normal-state lifecycle; map nodes follow the separate schedule.
    definition.normal_event_state = true
    return scheduled(spire.new(definition), SPIRE_SITE_KEY)
end

return events
