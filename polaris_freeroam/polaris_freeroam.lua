-- Mars. Open world: authored population per zone, respawns and public event sites.
-- content.lua is generated from the packages. sectors.lua sets each Lost Sector's encounter.
-- Live behavior is unverified.
local missions = require("missions")
local mission = require(missions.POLARIS_FREEROAM)
local freeroam = require("lib.freeroam")
local content = require("polaris_freeroam.content")
local sectors = require("polaris_freeroam.sectors")
local events = require("polaris_freeroam.events")
local public_events = require("lib.public_events.runtime")

-- The Injection Rig site is authored region 8; it keeps its zone's rotation priority.
local RIG_SITE_REGION = 8
local zones = public_events.attach(content(mission, freeroam), RIG_SITE_REGION,
    mission.Slot.M_PUBLIC_EVENT_SENSOR_80F6B2FD, events.injection_rig(mission), true)

local program = freeroam.new{zones = zones, sectors = sectors(mission, freeroam)}

-- These objective groups have no encounter owner yet; do not spawn them as ordinary patrol.
local conditional_squads = {
    [mission.Squad.COMMANDER] = true,
    [mission.Squad.COURIER_1] = true,
    [mission.Squad.COURIER_2] = true,
    [mission.Squad.PHALANX_CABALTWO_COLLECT_1] = true,
    [mission.Squad.PHALANX_CABALTWO_COLLECT_2] = true,
    [mission.Squad.PHALANX_CABALTWO_COLLECT_3] = true,
    [mission.Squad.PHALANX_CABALTWO_COLLECT_4] = true,
    [mission.Squad.PHALANX_CABALTWO_COLLECT_5] = true,
}

-- Filter after freeroam assigns indices so retained patrol and event keys keep their owners.
for _, zone in ipairs(zones) do
    if zone.region == RIG_SITE_REGION then
        for index = #zone.patrol, 1, -1 do
            if conditional_squads[zone.patrol[index].squad] then
                table.remove(zone.patrol, index)
            end
        end
    end
end

return program
