-- Nessus uses authored population per zone and the shared public-event lifecycle.
local missions = require("missions")
local mission = require(missions.PLANET_X_FREEROAM)
local freeroam = require("lib.freeroam")
local content = require("planet_x_freeroam.content")
local sectors = require("planet_x_freeroam.sectors")
local events = require("planet_x_freeroam.events")
local public_events = require("lib.public_events.runtime")

-- Watcher's Grave occupies authored region 8; its Spire follows the Director's selected slot.
local WATCHERS_GRAVE_REGION = 8
local zones = public_events.attach(content(mission, freeroam), WATCHERS_GRAVE_REGION,
    mission.Slot.M_PUBLIC_EVENT_SENSOR_80C037B5, events.watchers_grave(mission), true)

-- Only Spire has a controller here; other authored schedule selections wait for a supported slot.
for _, zone in ipairs(zones) do
    if zone.region == WATCHERS_GRAVE_REGION then zone.events = {zone.events[1]} end
end

return freeroam.new{zones = zones, sectors = sectors(mission, freeroam)}
