-- The European Dead Zone. Open world: authored zone population, respawns and public event sites.
-- content.lua is generated from the packages. sectors.lua sets each Lost Sector's encounter.
-- Live behavior is unverified.
local missions = require("missions")
local mission = require(missions.EDZ_FREEROAM)
local freeroam = require("lib.freeroam")
local content = require("edz_freeroam.content")
local sectors = require("edz_freeroam.sectors")
local events = require("edz_freeroam.events")
local public_events = require("lib.public_events.runtime")

-- The Cabal drill site is authored region 80; its supported event retains rotation priority.
local DRILL_SITE_REGION = 80
local zones = public_events.attach(content(mission, freeroam), DRILL_SITE_REGION,
    mission.Slot.M_PUBLIC_EVENT_SENSOR_80BE4370, events.winding_cove(mission), true)
-- Glimmer Extraction leads the rotation of each area it is authored in; Firebase Hades is 96.
local EXTRACTION_REGION = 96
for _, placed in ipairs(events.extractions(mission)) do
    public_events.attach(zones, placed.region, placed.sensor, placed.handler, true)
end

-- Ether Resupply leads the Outskirts rotation (region 24) and follows the extraction at
-- Firebase Hades.
local ETHER_SITE_REGION = 24
for _, placed in ipairs(events.ether_resupplies(mission)) do
    public_events.attach(zones, placed.region, placed.sensor, placed.handler,
        placed.region == ETHER_SITE_REGION)
end

-- Weapons Exchange shares its areas with other events and does not lead their rotations.
for _, placed in ipairs(events.weapons_exchanges(mission)) do
    public_events.attach(zones, placed.region, placed.sensor, placed.handler, false)
end

-- The Injection Rig site is authored region 312; it keeps its zone's rotation priority.
local RIG_SITE_REGION = 312
public_events.attach(zones, RIG_SITE_REGION, mission.Slot.M_PUBLIC_EVENT_SENSOR_80BE140D,
    events.injection_rig(mission), true)

return freeroam.new{zones = zones, sectors = sectors(mission, freeroam), event_locations = {
    [DRILL_SITE_REGION] = "EDZ / Winding Cove",
    [EXTRACTION_REGION] = "EDZ / Firebase Hades",
    [ETHER_SITE_REGION] = "EDZ / Outskirts",
    [RIG_SITE_REGION] = "EDZ / Sunken Isles",
    [280] = "EDZ / The Gulch",
    [408] = "EDZ / Trostland",
    [448] = "EDZ / The Sludge",
}}
