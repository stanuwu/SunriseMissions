-- Binds one authored Injection Rig prefab. Sites share its layout and differ in generated names.
local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")

local site = {}

local PREFAB = "PF_EVENT_CABAL_SPIRE_1_"
-- Supporting squads by stage: one stage per Psion, later ones the stronger tier.
local WAVES = {
    {"SQ_ENGAGEMENT_SKELETON_CREW_A", "SQ_ENGAGEMENT_SKELETON_CREW_B", "SQ_CENTER_GRP_1_TIER_1"},
    {"SQ_OUTSIDE_GRP_2_TIER_1", "SQ_OUTSIDE_GRP_3_TIER_1", "SQ_MELEE_GRP_4_TIER_1"},
    {"SQ_CENTER_GRP_1_TIER_2", "SQ_OUTSIDE_GRP_2_TIER_2", "SQ_MELEE_GRP_4_TIER_2"},
}
local HEROIC_WAVES = {"SQ_HEROIC_OUTSIDE_GROUP_1", "SQ_HEROIC_OUTSIDE_GROUP_2", "SQ_HEROIC_MELEE"}
-- Reference Interceptors fight during heroic; their authored rules name their own pods.
local INTERCEPTORS = {"SQ_INTERCEPTOR_1", "SQ_INTERCEPTOR_2"}
-- Tiers in opening order: each names its weak point and its vent controls.
local VENTS = {
    {weakpoint = "3_TOP", tier = "TOP"},
    {weakpoint = "2_MID", tier = "MID"},
    {weakpoint = "1_BOT", tier = "BOT"},
}
local VENT_LETTERS = {"A", "B", "C"}
local DANGER_LIGHTS = 4

---@class RigCues
---@field CUE_ALERT integer Rig approaching.
---@field CUE_START integer Guardians engage.
---@field CUE_VENTS integer All vents destroyed.
---@field CUE_FAILED integer The Cabal got away.
---@field CUE_SUCCESS integer The rig left beaten.
---@field CUE_HEROIC_SUCCESS integer The rig exploded.
---@field CUE_HEROIC_FAILED integer No authored heroic line; the failure line stands in.

---@class RigSiteNames
---@field suffix string Generated suffix of the sensors beside the prefab.
---@field navpoint string Generated name of the passive marker slot.
---@field cues RigCues Cue ordinals; sensors order the same lines differently.
---@field psion_row string Directive key of the Psion counter.
---@field evacuate_row string Directive key of the burn row.
---@field valus_row string Directive key of the heroic Valus counter; its table flag is set.
---@field final_row string Directive key of the normal Valus counter; its table flag is clear.
---@field rally_key string|nil Generated suffix of the rally paired with this site.

--- Resolves a site's authored content into the rig event definition.
---@param mission table Generated mission module.
---@param ids RigSiteNames
---@return table definition Input of the rig encounter.
function site.bind(mission, ids)
    local Slot, Squad, Directive = mission.Slot, mission.Squad, mission.Directive
    local function slot(stem)
        return lib.one(Slot[PREFAB .. stem], "rig slot " .. stem)
    end
    local function zone_slot(stem)
        return lib.one(Slot[stem .. ids.suffix], "rig sensor " .. stem)
    end
    --- A unit of the site; no task group lets native evaluation choose among the objective's.
    local function unit(stem, objective)
        return {squad = lib.one(Squad[PREFAB .. stem], "rig squad " .. stem), slot = slot(stem),
            objective = objective}
    end
    local function units(stems, objective)
        local list = {}
        for _, stem in ipairs(stems) do list[#list + 1] = unit(stem, objective) end
        return list
    end

    local objective = slot("OBJ_MAIN")
    local waves = {}
    for stage, stems in ipairs(WAVES) do waves[stage] = units(stems, objective) end
    local vents = {}
    for tier, names in ipairs(VENTS) do
        local hop_ons = {}
        for _, letter in ipairs(VENT_LETTERS) do
            hop_ons[#hop_ons + 1] = slot("HO_SPIRE_" .. names.tier .. "_" .. letter .. "_OPEN")
        end
        vents[tier] = {object = slot("O_CABAL_SPIRE_WEAKPOINT_" .. names.weakpoint),
            monitor = slot("DMG_SPIRE_WEAKPOINT_" .. names.tier), hop_ons = hop_ons,
            destroyed = slot("HO_SPIRE_" .. names.tier .. "_DESTROYED")}
    end
    local burn_objects = {slot("O_DAMAGE_VOLUME")}
    for index = 0, DANGER_LIGHTS - 1 do
        burn_objects[#burn_objects + 1] = slot("O_CABAL_SPIRE_DANGER_LIGHT_" .. index)
    end
    local spire = slot("O_CABAL_SPIRE")
    local pylon = slot("CABAL_PYLON")
    local beacon = slot("O_SPIRE_BEACON")
    local shield = slot("SHIELD_OBJECT")
    local shield_large = slot("SHIELD_LARGE_OBJECT")
    local avoidance = slot("O_DYNAMIC_AVOIDANCE_VOLUME")
    local tank_avoidance = slot("O_TANK_AVOIDANCE_VOLUME")
    local ship = slot("O_EVENT_INTRO_SHIP")
    local engagement_volume = slot("TV_ENGAGEMENT")
    local rally_definition
    if ids.rally_key ~= nil then
        rally_definition = rally.bind(mission, ids.rally_key)
    end
    local psion_directive = lib.one(Directive[ids.psion_row], "rig Psion directive")
    local heroic_waves = units(HEROIC_WAVES, slot("OBJ_HEROIC"))
    for _, interceptor in ipairs(units(INTERCEPTORS)) do
        heroic_waves[#heroic_waves + 1] = interceptor
    end
    return {
        -- Shared event definition.
        directive_sensor = zone_slot("M_DIRECTIVE_SENSOR"),
        engagement = zone_slot("M_ENGAGEMENT_SENSOR"),
        engagement_volume = engagement_volume,
        dialog = zone_slot("M_DIALOG_SENSOR"),
        music = zone_slot("M_MUSIC_SENSOR"),
        event_sensor = zone_slot("M_PUBLIC_EVENT_SENSOR"),
        event_area = engagement_volume,
        navpoint = lib.one(Slot[ids.navpoint], "rig location point"),
        chest = slot("PF_REWARD_CHEST_CHEST_TIER0_OBJECT"),
        rally = rally_definition,
        directive = psion_directive,
        -- Named here because goal rows follow retained phase state until the attempt starts.
        incoming = psion_directive,
        evacuate_directive = lib.one(Directive[ids.evacuate_row], "rig evacuate directive"),
        heroic_directive = lib.one(Directive[ids.valus_row], "rig Valus directive"),
        final_directive = lib.one(Directive[ids.final_row], "rig normal Valus directive"),
        cues = ids.cues,
        -- Rig mechanics and scenery.
        ship = {object = ship, device = slot("D_EVENT_INTRO_SHIP")},
        rig = {object = spire,
            objects = {spire, pylon, beacon, avoidance, tank_avoidance},
            device = slot("D_CABAL_SPIRE")},
        pylon = {device = slot("D_PYLON")},
        -- Burn dome, then the lasting heroic dome. Which object is which is inferred.
        shields = {{object = shield, device = slot("SHIELD_DEVICE")},
            {object = shield_large, device = slot("SHIELD_LARGE_DEVICE")}},
        scenery = {ship, spire, pylon, beacon, shield, shield_large, avoidance, tank_avoidance},
        burn_objects = burn_objects,
        vents = vents,
        open_filter = slot("OF_SPIRE_OPEN"),
        destroyed_filter = slot("OF_SPIRE_VENTS_DESTROYED_FILTER"),
        exit_filter = slot("OF_SPIRE_EXIT"),
        exit_normal = slot("HO_SPIRE_EXIT_NORMAL"),
        exit_heroic = slot("HO_SPIRE_EXIT_HEROIC"),
        intro = slot("SEQ_INTRO_BEHAVIOR"),
        active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
        waves = waves,
        heroic_waves = heroic_waves,
        psion = unit("SQ_KEYHOLDER_PSION"),
        commander = unit("SQ_COMMANDER"),
    }
end

return site
