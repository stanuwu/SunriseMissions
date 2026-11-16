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
-- The Glimmer Extraction multipoint site is authored region 96.
local EXTRACTION_REGION = 96
public_events.attach(zones, EXTRACTION_REGION, mission.Slot.M_PUBLIC_EVENT_SENSOR_80BE5D9B,
    events.multipoint_extraction(mission), true)

-- The first Ether Resupply site is authored region 24; it keeps its zone's rotation priority.
local ETHER_SITE_REGION = 24
public_events.attach(zones, ETHER_SITE_REGION, mission.Slot.M_PUBLIC_EVENT_SENSOR_80BE2C5D,
    events.ether_resupply(mission), true)

-- The Weapons Exchange site shares region 24 with Ether Resupply; it does not lead the rotation.
public_events.attach(zones, ETHER_SITE_REGION, mission.Slot.M_PUBLIC_EVENT_SENSOR_80BE2ECB,
    events.weapons_exchange(mission), false)

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
