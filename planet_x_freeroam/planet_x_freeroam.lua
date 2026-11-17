-- Nessus. Open world: authored population per zone, respawns and public event sites.
-- content.lua is generated from the packages. sectors.lua sets each Lost Sector's encounter.
local missions = require("missions")
local mission = require(missions.PLANET_X_FREEROAM)
local freeroam = require("lib.freeroam")
local content = require("planet_x_freeroam.content")
local sectors = require("planet_x_freeroam.sectors")
local events = require("planet_x_freeroam.events")
local public_events = require("lib.public_events.runtime")

-- The map selects the Spire or Servitor site in this shared zone.
local WATCHERS_GRAVE_REGION = 8
local zones = public_events.attach(content(mission, freeroam), WATCHERS_GRAVE_REGION,
    mission.Slot.M_PUBLIC_EVENT_SENSOR_80C037B5, events.watchers_grave(mission), true)
public_events.attach(zones, WATCHERS_GRAVE_REGION,
    mission.Slot.M_PUBLIC_EVENT_SENSOR_80C03459, events.watchers_grave_ether(mission), false)

-- Each other area has one Spire placement; it leads its zone's rotation.
for _, placed in ipairs(events.spires(mission)) do
    public_events.attach(zones, placed.region, placed.sensor, placed.handler, true)
end

-- The Cistern's rig is authored region 88.
local CISTERN_REGION = 88
public_events.attach(zones, CISTERN_REGION, mission.Slot.M_PUBLIC_EVENT_SENSOR_80C0806D,
    events.cistern_rig(mission), true)

-- The drill site of Artifact's Edge is authored region 104.
local ARTIFACTS_EDGE_REGION = 104
public_events.attach(zones, ARTIFACTS_EDGE_REGION, mission.Slot.M_PUBLIC_EVENT_SENSOR_80C08DD2,
    events.artifacts_edge(mission), true)

-- Extractions follow the Spire or the rig in their areas' rotations.
for _, placed in ipairs(events.extractions(mission)) do
    public_events.attach(zones, placed.region, placed.sensor, placed.handler, false)
end

return freeroam.new{zones = zones, sectors = sectors(mission, freeroam), event_locations = {
    [WATCHERS_GRAVE_REGION] = "Nessus / Watcher's Grave",
    [24] = "Nessus / Exodus Black",
    [64] = "Nessus / Hallows",
    [CISTERN_REGION] = "Nessus / The Cistern",
    [ARTIFACTS_EDGE_REGION] = "Nessus / Artifact's Edge",
    [240] = "Nessus / Glade of Echoes",
    [296] = "Nessus / The Tangle",
}}
