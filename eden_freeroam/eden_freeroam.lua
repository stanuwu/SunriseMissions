-- Io. Open world: authored population per zone, respawns and public event sites.
-- content.lua is generated from the packages. sectors.lua sets each Lost Sector's encounter.
-- Live behavior is unverified.
local missions = require("missions")
local mission = require(missions.EDEN_FREEROAM)
local freeroam = require("lib.freeroam")
local content = require("eden_freeroam.content")
local sectors = require("eden_freeroam.sectors")
local events = require("eden_freeroam.events")
local public_events = require("lib.public_events.runtime")

-- The Taken Blight site is authored region 136; its supported event retains rotation priority.
local BLIGHT_SITE_REGION = 136
local zones = public_events.attach(content(mission, freeroam), BLIGHT_SITE_REGION,
    mission.Slot.M_PUBLIC_EVENT_SENSOR_80BD9894, events.taken_blight(mission), true)

-- The Giant's Scar Spire is authored region 160, with the same rotation priority.
local GIANTS_SCAR_REGION = 160
zones = public_events.attach(zones, GIANTS_SCAR_REGION,
    mission.Slot.M_PUBLIC_EVENT_SENSOR_80C37C70, events.giants_scar(mission), true)

return freeroam.new{zones = zones, sectors = sectors(mission, freeroam), event_locations = {
    [BLIGHT_SITE_REGION] = "Io / Lost Oasis",
    [GIANTS_SCAR_REGION] = "Io / Giant's Scar",
}}
