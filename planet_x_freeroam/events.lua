local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local site = require("lib.public_events.spire_integration.site")
local spire = require("lib.public_events.spire_integration.encounter")
local ether = require("lib.public_events.ether_resupply.encounter")
local schedule = require("lib.public_events.schedule")

local events = {}

-- Watcher's Grave in the client's public-event schedule: the site roster keys of its two entries.
local SPIRE_SITE_KEY = 0x748A97BE
local ETHER_SITE_KEY = 0xAACE558D
-- Both entries share the one rally prefab of the zone.
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

--- Builds the Watcher's Grave Spire handler.
function events.watchers_grave(mission)
    local definition = site.bind(mission, WATCHERS_GRAVE)
    -- Preserve the native normal-state lifecycle; map nodes follow the separate schedule.
    definition.normal_event_state = true
    return scheduled(spire.new(definition), SPIRE_SITE_KEY)
end

-- Generated names of the Servitor site: prefab slots carry no registry suffix, zone sensors do.
local SERVITOR_PREFIX, SERVITOR_SUFFIX = "PF_EVENT_FALLEN_SERVITOR_1_", "_80C03459"
-- Authored counts: nine covers around the site, three Vandals on the skeleton-crew Skiff.
local SERVITOR_COVER_COUNT, SKELETON_CREW_COUNT = 9, 3

--- Resolves the Servitor site's content into the Ether Resupply definition.
local function bind_ether_resupply(mission)
    local Slot = mission.Slot
    local function slot(stem)
        return lib.one(Slot[SERVITOR_PREFIX .. stem], "servitor slot " .. stem)
    end
    local function sensor(stem)
        return lib.one(Slot[stem .. SERVITOR_SUFFIX], "servitor sensor " .. stem)
    end
    --- A unit of the site: the squad id places it, the squad slot reports its deaths.
    local function unit(stem)
        return {squad = lib.one(mission.Squad[SERVITOR_PREFIX .. stem], "servitor squad " .. stem),
            slot = slot(stem)}
    end
    local directive_sensor = sensor("M_DIRECTIVE_SENSOR")
    local directive = lib.one(mission.Directive.ETHER_RESUPPLY, "directive")
    assert(directive.sensor == directive_sensor,
        "directive belongs to another sensor: " .. directive.id)
    local area = slot("TV_OBJECTIVE_AND_ENGAGEMENT_BIND")
    -- The Prime takes its authored boss objective.
    local boss_objective = slot("OBJ_BOSS")
    local prime = unit("SQ_ULTRA_SERVITOR")
    prime.member = slot("SQ_ULTRA_SERVITOR_BOSS")
    prime.objective = boss_objective
    prime.task_group =
        lib.one(mission.TaskGroup[SERVITOR_PREFIX .. "OBJ_BOSS"], "boss task group").GROUP_0
    local skiff = unit("PF_FALLEN_SKIFF_SKELETON_CREW_SQ_DROPSHIP")
    local crew, cover = {}, {}
    for index = 1, SKELETON_CREW_COUNT do
        crew[index] = unit("SQ_SKELETON_CREW_VANDAL_" .. index)
    end
    for index = 0, SERVITOR_COVER_COUNT - 1 do cover[#cover + 1] = slot("O_COVER_" .. index) end
    return {
        prime = prime,
        resupply = {
            shield = slot("HO_INVINCIBLE_ULTRA"),
            filter = slot("OF_ULTRA_SERVITOR"),
            lone = unit("SQ_CELLKEEPER_SHIELD"),
            trio = {unit("SQ_CELLKEEPER_SERVITOR_1"), unit("SQ_CELLKEEPER_SERVITOR_2"),
                unit("SQ_CELLKEEPER_SERVITOR_3")},
            support = {
                {unit("SQ_SUPPORT_BASE_1"), unit("SQ_SUPPORT_MAJOR_1_TIER_1")},
                {unit("SQ_SUPPORT_BASE_2"), unit("SQ_SUPPORT_MAJOR_2_TIER_1")},
                {unit("SQ_SUPPORT_BASE_3"), unit("SQ_SCORCH_CAPTAIN")},
            },
            heroic_support = unit("SQ_MELEE_FODDER_TIER_2"),
            heroic_teleporter = slot("O_HEROIC_PLAYER_TELEPORTER"),
            enrage = slot("SEQ_BOSS_ENRAGE_CUE"),
            charge_end = slot("SEQ_BOSS_HEROIC_CHARGE_END"),
        },
        intro = {
            ketch = lib.one(Slot.KETCH_INTRO_PREFAB_1_O_KETCH_INTRO, "ketch intro"),
            sequence = slot("SEQ_INTRO_BEHAVIOR"),
            active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
            communion = lib.one(mission.Scene[SERVITOR_PREFIX .. "SCN_INTRO_ETHER_COMMUNION"],
                "communion scene"),
            beam = slot("O_SKY_BEAM"),
            cover = cover,
            skiff = skiff,
            crew = crew,
        },
        chest = slot("PF_REWARD_CHEST_CHEST_TIER0_OBJECT"),
        directive_sensor = directive_sensor,
        directive = directive,
        engagement = sensor("M_ENGAGEMENT_SENSOR"),
        engagement_volume = area,
        dialog = sensor("M_DIALOG_SENSOR"),
        music = sensor("M_MUSIC_SENSOR"),
        event_sensor = sensor("M_PUBLIC_EVENT_SENSOR"),
        event_area = area,
        navpoint = sensor("LOCATION_POINT"),
        rally = rally.bind(mission, WATCHERS_GRAVE_RALLY),
    }
end

--- Builds the Watcher's Grave Ether Resupply handler.
function events.watchers_grave_ether(mission)
    return scheduled(ether.new(bind_ether_resupply(mission)), ETHER_SITE_KEY)
end

return events
