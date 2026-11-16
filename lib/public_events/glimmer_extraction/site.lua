-- Binds one authored Glimmer Extraction prefab. Placements share its layout and differ in root
-- prefab, registry tag, unnamed volumes and rally prefab.
local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local site_names = require("lib.public_events.site_names")
local glimmer = require("lib.public_events.glimmer_extraction.encounter")

local site = {}

-- Extraction crews move through three drill sites in order. Reconstructed: a placement that
-- authors more than three uses its first three.
local SITE_COUNT = 3
-- Authored heroic waves in escalating order; the finale boss comes with the last wave.
local HEROIC_WAVES = {"SQ_HEROIC_INITIAL_LIGHT_WAVE", "SQ_HEROIC_STEALTH_MELEE_WAVE",
    "SQ_HEROIC_HEAVY_WAVE", "SQ_HEROIC_FINALE_WAVE", "SQ_HEROIC_FINALE_BOSS"}
local CAPTAINS = {"SQ_DEFENDER_BOSS", "SQ_DEFENDER_BOSS_1", "SQ_DEFENDER_BOSS_2"}
-- Rows of the directive sensor by title and name hash.
local EXTRACTION_ROW = {"GLIMMER_EXTRACTION", 0x500F79DD}
local PURSUE_ROW = {"PURSUE_THE_FALLEN", 0x65C91560}
local DEFEND_ROW = {"DEFEND_GLIMMER", 0x116AEEB0}

---@class GlimmerPlacement
---@field tag string Object tag of the placement.
---@field root string Root prefab stem in key form; placements name it differently.
---@field volumes string[] Stems of the unnamed volumes beside the prefab; with the drills' own
--- engagement volumes their union is the event area and may reach past the three sites.
---@field rally string Object tag of the rally prefab beside the first drill site.
---@field rally_volume string|nil Stem of the rally's volume when the site names its own.

--- Resolves a placement's authored content into the extraction definition.
---@param mission table Generated mission module.
---@param placement GlimmerPlacement
---@return table definition Input of the Glimmer Extraction encounter.
function site.bind(mission, placement)
    local Slot, Squad = mission.Slot, mission.Squad
    local object = site_names.object(mission, placement.tag, placement.root)
    local function slot(stem) return Slot[object.prefab(stem)] end
    local function zone_slot(stem) return Slot[object.zone(stem)] end
    local function unit(stem)
        return {squad = lib.one(Squad[object.prefab(stem)], "glimmer squad " .. stem),
            slot = slot(stem)}
    end
    local sites, volumes = {}, {}
    for index = 1, SITE_COUNT do
        local prefix = "PF_PLACEMENT_" .. (index - 1) .. "_"
        local drill = prefix .. "PF_FALLEN_DRILL_"
        local deco = drill .. "PF_FALLEN_DRILL_DECO_"
        local objective = object.prefab(drill .. "OBJ_DRILL_DEFENSE")
        local group = lib.one(mission.TaskGroup[objective], "drill task group " .. index).GROUP_0
        local function fighters(stem)
            local fighter = unit(stem)
            fighter.objective = Slot[objective]
            fighter.task_group = group
            fighter.spawn_rule = slot(drill .. "SR_DRILL_NEAR")
            return fighter
        end
        local dropship = unit(drill .. "SQ_DROPSHIP")
        dropship.spawn_rule = slot(drill .. "SR_DROPSHIP")
        -- Radial covers around the drill; placements author three or four.
        local equipment = {slot(deco .. "O_DRILL"), slot(deco .. "O_DRILL_BEACON")}
        for _, cover in ipairs(object.numbered(deco .. "O_RADIAL_COV_")) do
            equipment[#equipment + 1] = Slot[cover]
        end
        sites[index] = {
            equipment = equipment,
            machine = slot(prefix .. "PF_EVENT_MULTIPOINT_GENERATOR_"
                .. glimmer.MACHINE_SLOT .. "_O_GENERATOR"),
            dropship = dropship,
            crew = fighters("SQ_DEFENDERS_" .. (index - 1)),
            extractors = fighters("SQ_DEFENDER_ANCHORS_" .. (index - 1)),
            captain = fighters(CAPTAINS[index]),
        }
        -- Not every drill names its engagement volume.
        local engagement = object.find(drill .. "TV_ENGAGEMENT")
        if engagement ~= nil then volumes[#volumes + 1] = Slot[engagement] end
    end
    for _, stem in ipairs(placement.volumes) do volumes[#volumes + 1] = zone_slot(stem) end
    local final = "PF_PLACEMENT_" .. (SITE_COUNT - 1) .. "_"
    local heroic_rule = slot(final .. "PF_FALLEN_DRILL_SR_DRILL_HEROIC")
    local heroic_waves = {}
    for index, stem in ipairs(HEROIC_WAVES) do
        heroic_waves[index] = unit(stem)
        heroic_waves[index].spawn_rule = heroic_rule
    end
    local directive_sensor = zone_slot("M_DIRECTIVE_SENSOR")
    local function row(name)
        return site_names.directive(mission, name[1], name[2], directive_sensor)
    end
    -- The Gulch authors no location point; its site then has no passive marker.
    local navpoint = object.find_zone("LOCATION_POINT")
    return {
        sites = sites,
        heroic_waves = heroic_waves,
        ketch = slot("PF_INTRO_FLIGHT_KETCH_O_KETCH"),
        intro = slot("SEQ_INTRO"),
        active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
        zone = slot(final .. "O_COUNTDOWN_ZONE"),
        ring = slot(final .. "O_CAPTURE_RING"),
        pile = slot(final .. "O_GLIMMER_0"),
        chest = slot(final .. "CHEST_PREFAB_CHEST_TIER0_OBJECT"),
        directive_sensor = directive_sensor,
        directive = row(EXTRACTION_ROW),
        pursue = row(PURSUE_ROW),
        heroic_directive = row(DEFEND_ROW),
        engagement = zone_slot("M_ENGAGEMENT_SENSOR"),
        engagement_volumes = volumes,
        dialog = zone_slot("M_DIALOG_SENSOR"),
        music = zone_slot("M_MUSIC_SENSOR"),
        event_sensor = zone_slot("M_PUBLIC_EVENT_SENSOR"),
        event_area = volumes[1],
        navpoint = navpoint ~= nil and Slot[navpoint] or nil,
        rally = rally.bind_object(mission, placement.rally, placement.rally_volume),
    }
end

return site
