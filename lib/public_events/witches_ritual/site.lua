-- Binds the Titan Witches' Ritual site (region 56, registry 80BF1928) from generated content.
local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local c = require("lib.public_events.witches_ritual.settings")

local site = {}

local PREFIX = "PF_EVENT_HIVE_RITUAL_1_"
-- Rally flag whose spawn-override volume covers the arena: the volume shape 80BF6C10 appears in
-- the 80BF197E registry record, which was read directly.
local RALLY_SUFFIX = "_80BF197E"
local SITE_SUFFIX = "_80BF1928"
-- Acolyte wave stems by send order; the encounter settings index into this list.
local WAVE_STEMS = {
    "SQ_ACOLYTES_SIGIL_1_G_1", "SQ_ACOLYTES_SIGIL_2_G_1",
    "SQ_ACOLYTES_SIGIL_1_G_2", "SQ_ACOLYTES_SIGIL_2_G_2",
}
-- Knights in arrival order. A suffix selects the squad's spawn rule while keeping its base slot.
local KNIGHT_VARIANTS = {
    {
        {slot = "SQ_KNIGHT_SIGIL_1_INITIAL_NON_MAJOR", suffix = "_000121BD"},
        {slot = "SQ_KNIGHT_SIGIL_1_G_1", suffix = "_000121B9"},
        {slot = "SQ_KNIGHT_SIGIL_1_G_2"},
    },
    {
        {slot = "SQ_KNIGHT_SIGIL_2_INITIAL_NON_MAJOR", suffix = "_000121BE"},
        {slot = "SQ_KNIGHT_SIGIL_2_G_1", suffix = "_000121BB"},
        {slot = "SQ_KNIGHT_SIGIL_2_G_2"},
    },
}
-- Portal stems by send order once the portal opens; their authored spawn rules place them.
local PORTAL_STEMS = {
    "SQ_THRALL_G_1", "SQ_THRALL_G_2", "SQ_THRALL_G_3",
    "SQ_EXPLOSIVE_THRALL_G_1", "SQ_EXPLOSIVE_THRALL_G_2",
}

--- Resolves the site's authored content into the Witches' Ritual event definition.
---@param mission table Generated Titan mission module.
---@return table definition Input of the Witches' Ritual encounter.
function site.bind(mission)
    local Slot, Squad = mission.Slot, mission.Squad
    local function slot(stem) return lib.one(Slot[PREFIX .. stem], "ritual slot " .. stem) end
    local function sensor(stem)
        return lib.one(Slot[stem .. SITE_SUFFIX], "ritual sensor " .. stem)
    end
    local function unit(stem, suffix)
        local name = stem .. (suffix or "")
        return {name = name, slot = slot(stem),
            squad = lib.one(Squad[PREFIX .. name], "ritual squad " .. name)}
    end

    local wizards, knights, acolytes, circles, runes = {}, {}, {}, {}, {}
    local shield_filters, shield_hop_ons, disrupt, restore, increment = {}, {}, {}, {}, {}
    for index = 1, c.WIZARD_COUNT do
        increment[index] = slot("SEQ_DARK_ARTIFACT_INCREMENT_" .. (index - 1))
        runes[index] = {}
        for rune = 0, c.RUNES_PER_ARTIFACT - 1 do
            runes[index][rune + 1] = lib.one(Slot["D_ARTIFACT_" .. index .. "_RUNE_" .. rune],
                "artifact " .. index .. " rune " .. rune)
        end
        wizards[index] = unit("SQ_MEDITATION_WIZARD_" .. index)
        knights[index] = {}
        for ordinal, knight in ipairs(KNIGHT_VARIANTS[index]) do
            knights[index][ordinal] = unit(knight.slot, knight.suffix)
        end
        acolytes[index] = unit("SQ_ACOLYTES_SIGIL_" .. index .. "_INITIAL")
        circles[index] = slot("PM_SIGIL_" .. index)
        shield_filters[index] = slot("OF_INVUL_SHIELD_WIZARD_" .. index)
        shield_hop_ons[index] = slot("HO_INVUL_SHIELD_WIZARD_" .. index)
        disrupt[index] = slot("SEQ_DARK_ARTIFACT_SHIELD_DISRUPTED_" .. (index - 1))
        restore[index] = slot("SEQ_DARK_ARTIFACT_SHIELD_RESTORED_" .. (index - 1))
    end
    local waves, portal_waves = {}, {}
    for _, stem in ipairs(WAVE_STEMS) do waves[#waves + 1] = unit(stem) end
    for _, stem in ipairs(PORTAL_STEMS) do portal_waves[#portal_waves + 1] = unit(stem) end
    local thralls = {}
    for index = 0, c.HEROIC_THRALLS - 1 do
        thralls[#thralls + 1] = unit("SQ_EXPLOSIVE_THRALL_HEROIC_INTRO" .. index)
    end
    local directive_sensor = sensor("M_DIRECTIVE_SENSOR")
    local function row(key)
        local found = lib.one(mission.Directive[key], "ritual directive " .. key)
        assert(found.sensor == directive_sensor, "directive belongs to another sensor: " .. key)
        return found
    end
    local rally_definition = rally.bind(mission, RALLY_SUFFIX)
    -- The flag stands outside the authored volume, so rally admits all present players.
    rally_definition.settled = true
    rally_definition.admit_everyone = true
    local arena = lib.one(Slot["SLOT_0089" .. SITE_SUFFIX], "arena volume")
    local wizard_directive = row("WITCHES_RITUAL_85FECB3D")
    -- Reconstructed Sorcerer placement at a single Wizard spawn point inside the arena.
    local sorcerer = unit("SQ_WIZARD_BOSS")
    sorcerer.spawn_rule = slot("SR_INITIAL_WIZARD_1")
    return {
        directive_sensor = directive_sensor,
        engagement = sensor("M_ENGAGEMENT_SENSOR"),
        engagement_volumes = {arena},
        dialog = sensor("M_DIALOG_SENSOR"),
        join_lines = {first = c.CUE_ALERT, second = c.CUE_START, delay_ms = c.JOIN_LINE_DELAY_MS},
        music = sensor("M_MUSIC_SENSOR"),
        chest = slot("PF_REWARD_CHEST_CHEST_TIER0_OBJECT"),
        rally = rally_definition,
        event_sensor = sensor("M_PUBLIC_EVENT_SENSOR"),
        event_area = arena,
        navpoint = lib.one(Slot.LOCATION_POINT, "location point"),
        -- Authored rows: wizards counter, portal open, Sorcerer, Champion.
        directive = wizard_directive,
        incoming = wizard_directive,
        portal_directive = row("WITCHES_RITUAL_D74CC554"),
        boss_directive = row("WITCHES_RITUAL_CA8DDA16"),
        heroic_directive = row("WITCHES_RITUAL"),
        -- Ritual mechanics and scenery.
        wizards = wizards,
        knights = knights,
        acolytes = acolytes,
        waves = waves,
        portal_waves = portal_waves,
        sorcerer = sorcerer,
        champion = unit("SQ_DARKBLADE"),
        thralls = thralls,
        circles = circles,
        plates = {lib.one(Slot.D_SIGIL_PLATFORM_1, "sigil platform 1"),
            lib.one(Slot.D_SIGIL_PLATFORM_2, "sigil platform 2")},
        shield_filters = shield_filters,
        shield_hop_ons = shield_hop_ons,
        disrupt = disrupt,
        restore = restore,
        increment = increment,
        -- The pillars beside the portal and the portal's own device, in the plates' registry.
        artifacts = {lib.one(Slot.D_DARK_ARTIFACT_1, "dark artifact 1"),
            lib.one(Slot.D_DARK_ARTIFACT_2, "dark artifact 2")},
        runes = runes,
        gateway = slot("D_GATEWAY_PORTAL"),
        crystals = {slot("O_HEROIC_CRYSTAL1"), slot("O_HEROIC_CRYSTAL2")},
        crystal_channels = {slot("CH_CHANNEL_SENSOR_HUB_CRYSTAL1"),
            slot("CH_CHANNEL_SENSOR_HUB_CRYSTAL2")},
        portal = {slot("O_GATEWAY_PORTAL"), slot("O_GATEWAY_PHYSICS_1"),
            slot("O_GATEWAY_PHYSICS_2")},
        startup = slot("O_STARTUP_FX_OBJECT"),
        intro = slot("SEQ_INTRO_BEHAVIOR"),
        active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
    }
end

return site
