-- Titan. Open world: authored population per zone, respawns and public event sites.
-- content.lua is generated from the packages. sectors.lua sets each Lost Sector's encounter.
-- Live behavior is unverified.
local missions = require("missions")
local mission = require(missions.FLEET_FREEROAM)
local freeroam = require("lib.freeroam")
local content = require("fleet_freeroam.content")
local sectors = require("fleet_freeroam.sectors")
local events = require("fleet_freeroam.events")
local public_events = require("lib.public_events.runtime")

-- The Witches' Ritual site is authored region 56; it keeps its zone's rotation priority.
local RITUAL_SITE_REGION = 56
-- The Rig state also seeds two Pyramid monolith event groups that no script runs. They take 528
-- of the client's 1024 group registration entries, which leaves the Ritual flag and sigil groups
-- unregistered. Any slot names its object; the seed then leaves the whole object out.
local RITUAL_SITE_SEED_OMIT = {
    mission.Slot.PF2_EVENT_MONOLITH_CORE_OBJ_NORMAL_80BF6E60,
    mission.Slot.PF2_EVENT_MONOLITH_CORE_OBJ_NORMAL_80BF71E5,
}
-- The patrol units that stand on the Ritual ground leave while the event runs and return after
-- it, as the area clears for a public event in retail. The set is the seven units whose
-- authored anchor is inside or at the edge of the arena around the portal (-4.1, 678.6) and
-- the plates (18.9, 652.2) and (31.5, 679.2): the three interior simple squads (16 to 29 m from
-- the portal, one 8 m from plate 1) and the four Acolytes 20 m east of plate 2. The other 17
-- units of the zone stand 48 m or more from the nearest plate and stay.
local RITUAL_SITE_PATROL = {
    mission.Slot.PF2_INTERIOR_SIMPLE_SQUAD_1_80BF1E7C,
    mission.Slot.PF2_INTERIOR_ALT_SIMPLE_SQUAD_2_80BF1E8F,
    mission.Slot.PF2_INTERIOR_ALT_SIMPLE_SQUAD_1_80BF1E8F,
    mission.Slot.ACOLYTES_5,
    mission.Slot.ACOLYTES_6,
    mission.Slot.ACOLYTES_7,
    mission.Slot.ACOLYTES_8,
}
local zones = public_events.attach(content(mission, freeroam),
    RITUAL_SITE_REGION, mission.Slot.M_PUBLIC_EVENT_SENSOR_80BF1928,
    events.witches_ritual(mission), true, RITUAL_SITE_PATROL)
for _, zone in ipairs(zones) do
    if zone.region == RITUAL_SITE_REGION then zone.omit = RITUAL_SITE_SEED_OMIT end
end

local program = freeroam.new{zones = zones, sectors = sectors(mission, freeroam)}
-- A player who spawns straight into the Rig gets a seed adopted before the zone selects its
-- state, so the host applies this list to every seed as well.
program.seed_omit = RITUAL_SITE_SEED_OMIT
return program
