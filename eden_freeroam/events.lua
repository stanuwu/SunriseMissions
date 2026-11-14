local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local blight = require("lib.public_events.taken_blight.encounter")
local site = require("lib.public_events.spire_integration.site")
local spire = require("lib.public_events.spire_integration.encounter")

local events = {}

-- Generated names of this registry carry its key.
local BLIGHT_REGISTRY = "_80BD9894"
local BLIGHT_PREFIX = "TAKEN_INFECTION_CORE_"
-- Reconstructed flag-use binding to client incident object definition 7043, as at Nessus.
-- Authored Blight objects per group and small Blights per group.
local BLIGHT_OBJECTS, POOLS = 3, 3
-- Reconstructed location order; authored group 0 sits inside the rally's spawn override volume.
-- Each location brings the next difficulty with its authored tether squad count.
local LOCATIONS = {
    {group = 0, difficulty = "EASY", tethers = 2},
    {group = 1, difficulty = "MEDIUM", tethers = 3},
    {group = 2, difficulty = "HARD", tethers = 3},
}
-- The generated name of group 1's engagement volume is a bare slot; the trigger table names it.
local GROUP_VOLUMES = {[0] = "BLIGHT_GROUPS_0_ENGAGEMENT_TRIGGER_VOLUME",
    [1] = "SLOT_00C1", [2] = "BLIGHT_GROUPS_2_ENGAGEMENT_TRIGGER_VOLUME"}

-- Gage's account of Io: on joining, Ghost's exchange with Asher, then Asher's call to act. The
-- delay is cue 1's authored window.
local JOIN_LINES = {first = 1, second = 0, delay_ms = 8292}

--- Generated names of the Giant's Scar Spire. This prefab authors no location point, so the
--- marker uses its block location. The rally pairing is reconstructed from volume overlap.
local GIANTS_SCAR = {
    prefab = function(stem) return "EVENT_VEXBLOCK_1_" .. stem end,
    zone = function(stem) return stem .. "_80C37C70" end,
    cover = function(index) return "EVENT_VEXBLOCK_1_O_VEX_COV_" .. index end,
    area = {"SLOT_0096", "SLOT_00D1"},
    navpoint = "EVENT_VEXBLOCK_1_PF_VEXBLOCK_AP_VEX_BLOCK",
    rally_key = "_80C374B7",
    rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VEX_BLOCK",
}

--- Binds the region 136 Taken Blight.
local function bind_site(mission)
    local Slot, Squad, TaskGroup = mission.Slot, mission.Squad, mission.TaskGroup
    local function slot(stem)
        local key = (stem == "SLOT_00C1" and stem or BLIGHT_PREFIX .. stem) .. BLIGHT_REGISTRY
        return lib.one(Slot[key], "blight slot " .. stem)
    end
    local function squad(stem)
        return lib.one(Squad[BLIGHT_PREFIX .. stem .. BLIGHT_REGISTRY], "blight squad " .. stem)
    end
    --- First task group of an authored objective.
    local function first_group(stem)
        local groups = lib.one(TaskGroup[BLIGHT_PREFIX .. stem .. BLIGHT_REGISTRY],
            "blight task groups " .. stem)
        return lib.one(groups.GROUP_0, "blight task group " .. stem)
    end
    --- A squad with its authored objective and the spawn rule it starts from.
    local function unit(stem, objective_stem, rule_stem)
        local placed = {squad = squad(stem), slot = slot(stem), spawn_rule = slot(rule_stem)}
        if objective_stem ~= nil then
            placed.objective = slot(objective_stem)
            placed.task_group = first_group(objective_stem)
        end
        return placed
    end

    local scenery = {}
    local function keep(object)
        scenery[#scenery + 1] = object
        return object
    end
    local locations = {}
    for _, entry in ipairs(LOCATIONS) do
        local group = "BLIGHT_GROUPS_" .. entry.group .. "_"
        local big = group .. "BIG_BLIGHT_"
        local center_rule = group .. "CENTER_SPAWN_RULE"
        local blights = {}
        for index = 1, BLIGHT_OBJECTS do
            blights[index] = keep(slot(big .. "BLIGHT_0" .. index .. "_OBJECT"))
        end
        local units = {
            unit(entry.difficulty .. "_FLOATER_SQUAD", group .. "FLOATER_OBJECTIVE", center_rule),
            unit(entry.difficulty .. "_ANCHOR_SQUAD", nil, center_rule),
        }
        local pools = {}
        for index = 0, POOLS - 1 do
            local pool = group .. "EVENT_TAKEN_INFECTION_POOL_" .. index .. "_"
            if index < entry.tethers then
                units[#units + 1] = unit(entry.difficulty .. "_TETHER_SQUAD_" .. index,
                    pool .. "POOL_OBJECTIVE", pool .. "POOL_SPAWN_RULE")
                pools[#pools + 1] = {
                    objects = {keep(slot(pool .. "TAKEN_PYLON_OBJECT")),
                        keep(slot(pool .. "TAKEN_BLIGHT_AND_TETHER_ZAP_OBJECT"))},
                    sequence = slot(pool .. "TAKEN_BLIGHT_SEQUENCE"),
                }
            end
        end
        locations[#locations + 1] = {
            blights = blights,
            -- The first of three Blight objects is the reconstructed health target.
            target = blights[1],
            monitor = slot(big .. "BLIGHT_DAMAGE"),
            shield = slot(big .. "TAKEN_SHIELD_SPAWNING_SEQUENCE"),
            pools = pools,
            navpoint = slot(group .. "EVENT_TAKEN_INFECTION_POOL_2_TAKEN_BLIGHT_NAVPOINT"),
            units = units,
            center_rule = slot(center_rule),
        }
    end

    local volumes = {}
    for _, entry in ipairs(LOCATIONS) do
        volumes[#volumes + 1] = slot(GROUP_VOLUMES[entry.group])
    end
    local directive_sensor = lib.one(Slot.M_DIRECTIVE_SENSOR_80BD9894, "directive sensor")
    local directive = lib.one(mission.Directive.TAKEN_BLIGHT, "blight directive")
    local pursue = lib.one(mission.Directive.PURSUE_THE_BLIGHT, "pursue directive")
    local heroic = lib.one(mission.Directive.DEFEAT_THE_BLIGHTMAKER, "heroic directive")
    for _, row in ipairs({directive, pursue, heroic}) do
        assert(row.sensor == directive_sensor, "row belongs to another sensor: " .. row.id)
    end
    local rally_sensor = lib.one(Slot.M_DIRECTIVE_SENSOR_80BD98BE, "rally directive sensor")
    local last_group = "BLIGHT_GROUPS_" .. LOCATIONS[#LOCATIONS].group .. "_"
    return {
        locations = locations,
        -- Passive site marker of the shared lifecycle; goal rows name their own location.
        navpoint = locations[1].navpoint,
        scenery = scenery,
        ultra = {squad = squad("ULTRA_SQUAD"), slot = slot("ULTRA_SQUAD")},
        intro = slot("INTRO_BEHAVIOR_SEQUENCE"),
        active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
        -- One authored chest serves the event; the retail chest stood at the last location.
        chest = slot(last_group .. "CHEST_PREFAB_CHEST_TIER0_OBJECT"),
        directive_sensor = directive_sensor,
        directive = directive,
        -- The passive row names the event; goal rows may hold the last attempt's state.
        incoming = directive,
        pursue_directive = pursue,
        heroic_directive = heroic,
        engagement = lib.one(Slot.M_ENGAGEMENT_SENSOR_80BD9894, "engagement sensor"),
        engagement_volumes = volumes,
        dialog = lib.one(Slot.M_DIALOG_SENSOR_80BD9894, "dialog sensor"),
        music = lib.one(Slot.M_MUSIC_SENSOR_80BD9894, "music sensor"),
        event_sensor = lib.one(Slot.M_PUBLIC_EVENT_SENSOR_80BD9894, "public event sensor"),
        event_area = volumes[1],
        -- Reconstructed pairing from volume overlap; no authored link names the rally's event.
        rally = {
            flag = lib.one(Slot.PF_PUBLIC_EVENT_RALLY_POINT_RALLY_FLAG_80BD98BE, "rally flag"),
            device = lib.one(Slot.PF_PUBLIC_EVENT_RALLY_POINT_RALLY_FLAG_DEVICE_80BD98BE,
                "flag device"),
            sensor = rally_sensor,
            engagement = lib.one(Slot.M_ENGAGEMENT_SENSOR_80BD98BE, "rally engagement sensor"),
            volume = lib.one(Slot.RALLY_POINT_SPAWN_OVERRIDE_VOLUME, "rally volume"),
            directive = rally.find_directive(mission, rally_sensor),
            incident_target = rally.FLAG_INCIDENT,
        },
    }
end

--- Builds the region 136 Taken Blight handler.
function events.taken_blight(mission)
    return blight.new(bind_site(mission))
end

--- Builds the Giant's Scar Spire handler.
function events.giants_scar(mission)
    local definition = site.bind(mission, GIANTS_SCAR)
    definition.join_lines = JOIN_LINES
    return spire.new(definition)
end

return events
