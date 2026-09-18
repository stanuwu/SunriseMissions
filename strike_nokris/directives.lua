-- Authored normal-strike HUD directives for the reconstructed Nokris route.
-- This is a progress publisher: it does not infer native mechanics or story/Xol state.
local compact = require("strike_nokris.opening_state")
local identity = require("strike_nokris.identity_text")

local FLOW_KEY = "directive.flow"
local FLOW_PREFIX = "D2"
local FLOW_LIMIT = 127
local DIRECTIVE_OBJECT = 0x80F7355F
local DIRECTIVE_REGISTRY = 0xAC8DBDA8
local DIRECTIVE_TYPE = 68
local DIRECTIVE_INDEX = 0
local DIRECTIVE_SLOT_ROW = 177377
local OPENING_REGION = 0
local RITUAL_REGION = 88
local FIRST_CUE_BIT = 1

local function is_event(event)
    local kind = type(event)
    return kind == "userdata" or kind == "table"
end

local function split(value)
    local result, start = {}, 1
    for index = 1, #value + 1 do
        if index > #value or string.byte(value, index) == 124 then
            result[#result + 1] = string.sub(value, start, index - 1)
            start = index + 1
        end
    end
    return result
end

local function small_integer(value, maximum)
    if type(value) ~= "string" or #value == 0 or #value > 3 then return end
    local result = 0
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 48 or byte > 57 then return end
        result = result * 10 + byte - 48
    end
    if result > maximum then return end
    return result
end

local function safe_reason(value)
    if type(value) ~= "string" or value == "" then return "none" end
    local result = {}
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte > 126 or byte == 124 then
            result[#result + 1] = "_"
        else
            result[#result + 1] = string.char(byte)
        end
    end
    value = table.concat(result)
    return #value <= 24 and value or string.sub(value, 1, 24)
end

local function initial_flow()
    return {step=0, operation="none", region=-1, source="-", sequence="0", history=0,
        status="idle", target=0, reason="none"}
end

local function encode(flow)
    local value = table.concat({FLOW_PREFIX, flow.step, flow.operation, flow.region, flow.source,
        flow.sequence, flow.history, flow.status, flow.target, safe_reason(flow.reason)}, "|")
    assert(#value <= FLOW_LIMIT, "directive flow exceeds Host variable capacity")
    return value
end

local function decode(value)
    if type(value) ~= "string" or #value > FLOW_LIMIT then return end
    local parts = split(value)
    if #parts ~= 10 or parts[1] ~= FLOW_PREFIX then return end
    local step, region, history, target = small_integer(parts[2], 9), nil,
        small_integer(parts[7], 1023), small_integer(parts[9], 9)
    if not step or not history or target == nil then return end
    if parts[3] ~= "none" and parts[3] ~= "set0" and parts[3] ~= "set1"
        and parts[3] ~= "clear" then return end
    if parts[4] == "-1" then
        region = -1
    else
        region = small_integer(parts[4], 255)
        if region == nil then return end
    end
    if parts[5] ~= "-" and not identity.positive_decimal(parts[5]) then return end
    if parts[6] ~= "0" and not identity.positive_decimal(parts[6]) then return end
    local status = parts[8]
    if status ~= "idle" and status ~= "pending" and status ~= "active"
        and status ~= "blocked" and status ~= "complete" then return end
    if parts[10] == "" then return end
    return {step=step, operation=parts[3], region=region, source=parts[5], sequence=parts[6],
        history=history, status=status, target=target, reason=parts[10]}
end

local function after(left, right)
    if type(left) ~= "string" or type(right) ~= "string" or left == "" or left == "0"
        or #left > 20 or not identity.positive_decimal(left) then return false end
    if right == "0" then return true end
    return #left > #right or (#left == #right and left > right)
end

local function bit_set(value, bit)
    return math.type(value) == "integer" and value & bit ~= 0
end

local function direct(state, name)
    local scalar = state:variable(name)
    if scalar ~= nil then return scalar end
    local ok, value = pcall(compact.get, state, name)
    return ok and value or nil
end

local function entry_crystals_ready(state)
    if direct(state, "entry.crystals.failed") == true then return false end
    for index = 1, 2 do
        for _, field in ipairs({"observed", "live", "spawned", "transported"}) do
            if direct(state, "entry.crystal" .. index .. "." .. field) ~= true then return false end
        end
    end
    return true
end

local function started_gauntlet(state)
    local status = state:variable("gstart.status")
    return status == "placed" or status == "objective_pending" or status == "running"
end

local function unblocked(state, prefix)
    return state:variable(prefix .. ".status") ~= "blocked"
end

local function prefight_arrived(state)
    local entry = state:variable("prefight.entry")
    return entry == "arrived" and unblocked(state, "later.prefight")
end

-- Retail (video report §2): "Find Nokris" from the opening (01:17) through the first crystal gate,
-- "Follow the Ritual Trail" from the Penumbral Depths transition (04:59.5) until the boss arena,
-- "Stop the Ritual" from the arena drop (14:08) to OBJECTIVE COMPLETE. Descriptions per stage are
-- the authored rows; the video does not resolve them.
local specs = {
    {symbol="FIND_NOKRIS_D7FC909A", hash=0xD7FC909A,
        title="Find Nokris", description="Investigate the Hive tunnels and find Nokris."},
    {symbol="FIND_NOKRIS_509FC035", hash=0x509FC035,
        title="Find Nokris", description="Remove the Hive barrier."},
    {symbol="FIND_NOKRIS", hash=0x361B759C,
        title="Find Nokris", description="Proceed through the Hive tunnels and find Nokris."},
    {symbol="FOLLOW_THE_RITUAL_TRAIL_5904D608", hash=0x5904D608,
        title="Follow the Ritual Trail", description="Break through the defenses."},
    {symbol="FOLLOW_THE_RITUAL_TRAIL_55FE7C71", hash=0x55FE7C71,
        title="Follow the Ritual Trail", description="Stop the ritual."},
    {symbol="FOLLOW_THE_RITUAL_TRAIL_46E8EA15", hash=0x46E8EA15,
        title="Follow the Ritual Trail", description="Proceed deeper into the tunnels and find Nokris."},
    {symbol="FOLLOW_THE_RITUAL_TRAIL_8D88BB8B", hash=0x8D88BB8B,
        title="Follow the Ritual Trail", description="Find a way through."},
    {symbol="STOP_THE_RITUAL_3F67C2F8", hash=0x3F67C2F8,
        title="Stop the Ritual", description="Interrupt the ritual."},
    {symbol="STOP_THE_RITUAL", hash=0x34C073E6,
        title="Stop the Ritual", description="Defeat Nokris."},
}

local function qualifies(index, state)
    if index == 1 then
        return state:variable("entry.placed") == true and bit_set(state:variable("dialogue.staged"), FIRST_CUE_BIT)
    elseif index == 2 then
        return entry_crystals_ready(state)
    elseif index == 3 then
        return state:variable("entry.gate.result") == "transport_staged"
    elseif index == 4 then
        return state:variable("entry.gate.result") == "transport_staged" and started_gauntlet(state)
    elseif index == 5 then
        return state:variable("later.ritual_quartet.entered") == true
            and unblocked(state, "later.ritual_quartet")
    elseif index == 6 then
        return state:variable("later.simmumah.status") == "population_zero"
    elseif index == 7 then
        return state:variable("later.arena.entered") == true and unblocked(state, "later.arena")
    elseif index == 8 then
        return prefight_arrived(state)
    elseif index == 9 then
        return state:variable("nokris.intro") == "transport_staged"
            and state:variable("later.boss_entry.status") == "running"
    end
    return false
end

return function(mission, controller)
    assert(mission.name == "strike_nokris", "directive publisher requires the Nokris strike")
    local owner = assert(mission.Slot.M_DIRECTIVE_SENSOR)
    local flow = initial_flow()
    local initialized, fenced, complete = false, false, false
    local captured_recovery, captured_spawn_recovery, captured_boss_retry
    local captured_portal_recovery, captured_portal_staged_recovery, captured_portal_boss_recovery
    local captured_portal_absent_boss
    local recovery_chant, recovery_spawn, recovery_spawn_staged
    local recovery_intro, recovery_cleanup, recovery_boss_retry_active, recovery_waiting_region
    local held, source = nil, nil
    local pending

    local function save(context)
        context:set_variable(FLOW_KEY, encode(flow))
    end

    local function stop(context, reason)
        if complete then return end
        fenced, pending = true, nil
        flow.operation, flow.status, flow.target, flow.reason = "none", "blocked", 0, reason
        save(context)
    end

    local function initialize(context, state)
        if initialized then return end
        initialized = true
        local retained = state:variable(FLOW_KEY)
        if retained ~= nil then
            local decoded = decode(retained)
            if not decoded then
                flow = initial_flow()
                stop(context, "corrupt")
            else
                flow = decoded
                -- One-shot recovery for captured client86657 PID14788/session11433003384888623105.
                -- The first safe reload correctly preserved the failed state, but every retained
                -- controller fenced itself. Recover only the exact post-reload snapshot after the
                -- captured same-spawn quartet reached zero; any changed identity/state refuses.
                captured_recovery = flow.step == 7 and flow.operation == "none" and flow.region == 88
                    and flow.source == "2" and flow.sequence == "3091" and flow.history == 127
                    and flow.status == "blocked" and flow.target == 0 and flow.reason == "reload_retained"
                    and state:variable("prefight.entry") == "blocked"
                    and state:variable("later.prefight.entered") == true
                    and state:variable("later.prefight.status") == "blocked"
                    and state:variable("later.prefight.reason") == "retained_reload"
                    and state:variable("later.arena.exit") == "transport_staged"
                    and state:variable("later.arena.status") == "blocked"
                    and state:variable("later.arena.reason") == "retained_reload"
                    and state:variable("crystals.arena.status") == "blocked"
                    and state:variable("crystals.arena.reason") == "retained_reload"
                    and state:variable("route.invalidated") == true
                captured_spawn_recovery = flow.step == 7 and flow.operation == "none"
                    and flow.region == 88 and flow.source == "2" and flow.sequence == "4955"
                    and flow.history == 127 and flow.status == "active" and flow.target == 0
                    and flow.reason == "none" and state:variable("prefight.entry") == "blocked"
                    and state:variable("later.prefight.entered") == true
                    and state:variable("later.prefight.status") == "blocked"
                    and state:variable("later.prefight.reason") == "clearance_observed"
                    and state:variable("gstart.status") == "armed"
                    and state:variable("later.arena.status") == "population_zero"
                    and state:variable("crystals.arena.status") == "all_inactive"
                    and state:variable("route.invalidated") == true
                captured_boss_retry = flow.step == 8 and flow.operation == "none"
                    and flow.region == 88 and flow.source == "2" and after(flow.sequence, "5471")
                    and flow.history == 127 and flow.status == "active" and flow.target == 0
                    and flow.reason == "none" and state:variable("prefight.entry") == "blocked"
                    and state:variable("later.prefight.status") == "blocked"
                    and state:variable("later.prefight.reason") == "clearance_observed"
                    and state:variable("later.boss_entry.entered") == true
                    and state:variable("later.boss_entry.status") == "running"
                    and state:variable("nokris.chant") == "transport_staged"
                    and state:variable("route.invalidated") == true
                captured_portal_recovery=flow.step==8 and flow.operation=="none"
                    and flow.region==88 and flow.source=="2" and flow.history==255 and flow.target==0
                    and state:variable("later.prefight.entered")==true
                    and state:variable("nokris.chant")=="transport_staged"
                    and ((flow.sequence=="2206" and flow.status=="active" and flow.reason=="none"
                        and state:variable("prefight.entry")=="arrived"
                        and state:variable("later.prefight.status")=="population_zero"
                        and state:variable("later.prefight.reason")=="clearance_observed"
                        and state:variable("nokris.intro")==nil
                        and state:variable("later.boss_entry.status")==nil
                        and state:variable("route.invalidated")~=true)
                    or (flow.sequence=="3425" and flow.status=="blocked" and flow.reason=="reload_retained"
                        and state:variable("prefight.entry")=="blocked"
                        and state:variable("later.prefight.status")=="blocked"
                        and state:variable("later.prefight.reason")=="retained_reload"
                        and state:variable("nokris.intro")=="blocked"
                        and state:variable("later.boss_entry.status")=="blocked"
                        and state:variable("later.boss_entry.reason")=="retained_reload"
                        and state:variable("route.invalidated")==true))
                captured_portal_staged_recovery=flow.step==8 and flow.operation=="none"
                    and flow.region==88 and flow.source=="2" and flow.history==255 and flow.target==0
                    and state:variable("later.prefight.entered")==true
                    and state:variable("nokris.chant")=="transport_staged"
                    and state:variable("route.invalidated")==true
                    and ((flow.sequence=="3754" and flow.status=="active" and flow.reason=="none"
                        and state:variable("prefight.entry")=="blocked"
                        and state:variable("later.prefight.status")=="blocked"
                        and state:variable("later.prefight.reason")=="clearance_observed"
                        and state:variable("nokris.intro")=="portal_staged"
                        and state:variable("later.boss_entry.status")==nil)
                    or (after(flow.sequence,"3753") and flow.status=="blocked" and flow.reason=="reload_retained"
                        and state:variable("prefight.entry")=="blocked"
                        and state:variable("later.prefight.status")=="blocked"
                        and state:variable("later.prefight.reason")=="retained_reload"
                        and state:variable("nokris.intro")=="blocked"
                        and state:variable("later.boss_entry.status")=="blocked"
                        and state:variable("later.boss_entry.reason")=="retained_reload"))
                captured_portal_boss_recovery=flow.step==8 and flow.operation=="none"
                    and flow.region==88 and flow.source=="2" and after(flow.sequence,"4236")
                    and flow.history==255 and flow.status=="active" and flow.target==0 and flow.reason=="none"
                    and state:variable("prefight.entry")=="blocked"
                    and state:variable("later.prefight.entered")==true
                    and state:variable("later.prefight.status")=="blocked"
                    and state:variable("later.prefight.reason")=="clearance_observed"
                    and state:variable("later.boss_entry.entered")==true
                    and state:variable("later.boss_entry.status")=="running"
                    and state:variable("nokris.chant")=="transport_staged"
                    and state:variable("nokris.intro")=="transport_staged"
                    and state:variable("route.invalidated")==true
                captured_portal_absent_boss=flow.step==9 and flow.operation=="none"
                    and flow.region==88 and flow.source=="2" and after(flow.sequence,"4788")
                    and flow.history==511 and flow.status=="active" and flow.target==0 and flow.reason=="none"
                    and state:variable("prefight.entry")=="arrived"
                    and state:variable("later.prefight.status")=="population_zero"
                    and state:variable("later.prefight.reason")=="clearance_observed"
                    and state:variable("later.boss_entry.entered")==true
                    and state:variable("later.boss_entry.status")=="running"
                    and state:variable("nokris.chant")=="transport_staged"
                    and state:variable("nokris.intro")=="transport_staged"
                    and state:variable("nokris.capability")==nil and state:variable("nokris.control")==nil
                    and state:variable("route.invalidated")~=true
                local captured_absent_retry=flow.step==9 and flow.operation=="none"
                    and flow.region==88 and flow.source=="2" and after(flow.sequence,"8026")
                    and flow.history==511 and flow.status=="active" and flow.target==0 and flow.reason=="none"
                    and state:variable("prefight.entry")=="arrived"
                    and state:variable("later.prefight.status")=="population_zero"
                    and state:variable("later.boss_entry.status")=="running"
                    and state:variable("nokris.intro")=="transport_staged"
                    and state:variable("nokris.capability")==nil and state:variable("nokris.control")==nil
                    and state:variable("route.invalidated")~=true
                local captured_observed_retry=flow.step==9 and flow.operation=="none"
                    and flow.region==88 and flow.source=="2" and after(flow.sequence,"7969")
                    and flow.history==511 and flow.status=="active" and flow.target==0 and flow.reason=="none"
                    and state:variable("prefight.entry")=="blocked"
                    and state:variable("later.prefight.status")=="blocked"
                    and state:variable("later.prefight.reason")=="clearance_observed"
                    and state:variable("later.boss_entry.status")=="running"
                    and state:variable("nokris.chant")=="transport_staged"
                    and state:variable("nokris.intro")=="transport_staged"
                    and state:variable("nokris.capability")==nil and state:variable("nokris.control")==nil
                    and state:variable("route.invalidated")==true
                local captured_deferred_retry=flow.step==9 and flow.operation=="none"
                    and flow.region==88 and flow.source=="2" and after(flow.sequence,"6255")
                    and flow.history==511 and flow.target==0
                    and ((flow.status=="active" and flow.reason=="none"
                            and state:variable("nokris.recovery")=="awaiting_client_state"
                            and (state:variable("later.prefight.status")=="blocked"
                                or (state:variable("later.prefight.status")=="population_zero"
                                    and state:variable("later.boss_entry.status")=="awaiting_client_state"
                                    and state:variable("nokris.control")==nil)))
                        or (flow.status=="blocked" and flow.reason=="reload_retained"
                            and state:variable("prefight.entry")=="arrived"
                            and state:variable("later.prefight.status")=="population_zero"
                            and state:variable("later.boss_entry.status")=="running"
                            and state:variable("nokris.intro")=="transport_staged"
                            and state:variable("nokris.capability")=="retained_boss_requires_reconciliation"
                            and state:variable("nokris.control")~=nil
                            and state:variable("route.invalidated")==true))
                if captured_absent_retry then
                    context:set_variable("nokris.recovery","awaiting_client_state")
                    flow.status,flow.reason="active","none"
                    save(context)
                elseif captured_observed_retry then
                    context:set_variable("nokris.recovery","reattach_observed_boss")
                    flow.status,flow.reason="active","none"
                    save(context)
                elseif captured_deferred_retry then
                    context:set_variable("nokris.recovery","awaiting_client_state")
                    flow.status,flow.reason="active","none"
                    save(context)
                elseif captured_recovery or captured_spawn_recovery or captured_boss_retry
                    or captured_portal_recovery or captured_portal_staged_recovery
                    or captured_portal_boss_recovery or captured_portal_absent_boss then
                    flow.status, flow.reason = "active", "none"
                elseif flow.status == "complete" then
                    complete = true
                else
                    stop(context, "reload_retained")
                end
            end
        end
    end

    local function restore_captured_prefight(context)
        for _, key in ipairs({"arena.mechanics.blocked", "carriers.arena.reason",
            "crystals.arena.reason", "gstart.reason", "later.arena.reason",
            "later.arena_support2.reason", "later.arena_support3.reason",
            "later.boss_entry.reason", "later.chamber_support.reason",
            "later.icy_approach.reason", "later.outer_doorway.reason",
            "later.ritual_quartet.reason", "later.simmumah.reason",
            "later.start_support.reason", "later.thrall_surge.reason",
            "later.yellow_chambers.reason"}) do context:clear_variable(key) end
        context:set_variable("arena.entry", "arrived")
        context:set_variable("carriers.arena.status", "complete")
        context:set_variable("crystals.arena.status", "all_inactive")
        context:set_variable("gstart.status", "running")
        for _, name in ipairs({"arena", "arena_support2", "arena_support3", "chamber_support",
            "icy_approach", "outer_doorway", "ritual_quartet", "simmumah", "start_support",
            "thrall_surge", "yellow_chambers"}) do
            context:set_variable("later." .. name .. ".status", "population_zero")
        end
        context:set_variable("later.yellow_chambers.monitor",
            "773|1148|1|1|baseline|occupied_arrival|transport_staged")
        context:clear_variable("later.boss_entry.status")
        context:set_variable("prefight.entry", "arrived")
        context:set_variable("later.prefight.status", "population_zero")
        context:set_variable("later.prefight.reason", "clearance_observed")
        context:clear_variable("route.invalidated")
        save(context)
    end

    local function submit_captured_spawn(context)
        local chant_slot=context:slot(mission.Slot.S_HIVE_CHANT_SOUND_0_80F732FD)
        assert(chant_slot.object_tag==0x80F732FD and chant_slot.registry_key==0xEE4C3055
            and chant_slot.slot_type==5 and chant_slot.slot_index==7,
            "captured recovery chant binding mismatch")
        recovery_chant=assert(chant_slot:play_sequence{}, "captured recovery chant request missing")
        recovery_spawn=assert(context:squad(mission.Squad.NOKRIS_BOSS_SQUAD):place{},
            "captured recovery Nokris request missing")
        context:set_variable("nokris.chant", "submitted")
        context:set_variable("later.boss_entry.entered", true)
        context:set_variable("later.boss_entry.status", "placement_pending")
    end

    local function submit_captured_boss_retry(context)
        recovery_boss_retry_active=true
        recovery_spawn=assert(context:squad(mission.Squad.NOKRIS_BOSS_SQUAD):place{},
            "captured boss retry request missing")
        context:clear_variable("nokris.intro")
        context:set_variable("later.boss_entry.entered", true)
        context:set_variable("later.boss_entry.status", "placement_pending")
    end

    local function submit_captured_intro(context)
        local scene=assert(mission.Scene.EXP_ULTRA_WIZARD_NOKRIS_INTRO_SCENE)
        recovery_intro=assert(context:scene(scene):activate{}, "captured recovery intro request missing")
        context:set_variable("nokris.intro", "submitted")
        context:set_variable("later.boss_entry.status", "intro_pending")
    end

    local function submit_captured_cleanup(context)
        local toggle=context:slot(mission.Slot.TG_RELIC_CLEANUP_80F732CE)
        local volume=context:slot(mission.Slot.SLOT_014C_80F732CE)
        assert(toggle.object_tag==0x80F732CE and toggle.registry_key==0xC55749AB
            and toggle.slot_type==32 and toggle.slot_index==141,
            "captured recovery cleanup binding mismatch")
        assert(volume.object_tag==0x80F732CE and volume.registry_key==0xC55749AB
            and volume.slot_type==60 and volume.slot_index==332,
            "captured recovery cleanup volume mismatch")
        recovery_cleanup=assert(toggle:set_volume_active{volume=volume,active=false},
            "captured recovery cleanup request missing")
        context:set_variable("nokris.intro", "cleanup_submitted")
    end

    local function exact_owner(context)
        local slot = context:slot(owner)
        assert(slot.object_tag == DIRECTIVE_OBJECT and slot.registry_key == DIRECTIVE_REGISTRY
            and slot.slot_type == DIRECTIVE_TYPE and slot.slot_index == DIRECTIVE_INDEX,
            "Strange Terrain directive binding mismatch")
        return slot
    end

    local function authored(index)
        local spec = specs[index]
        local directive = assert(mission.Directive[spec.symbol], "missing authored directive")
        assert(directive.slot_row == DIRECTIVE_SLOT_ROW and directive.name_hash == spec.hash
            and directive.element == 0 and directive.title == spec.title
            and directive.description == spec.description, "authored directive identity mismatch")
        return directive
    end

    local function latest()
        local result = flow.step
        for index = flow.step + 1, 9 do
            if flow.history & (1 << (index - 1)) ~= 0 then result = index end
        end
        return result > flow.step and result or nil
    end

    local function submit_set(context, index)
        local slot = exact_owner(context)
        local directive = authored(index)
        local request = slot:set_directive{directive=directive, state=0}
        assert(request, "directive request did not return a request key")
        pending = {request=request, operation="set0", index=index, source=source, region=held}
        flow.operation, flow.status, flow.target = "set0", "pending", index
        flow.region, flow.source = held, source
        flow.reason = "none"
        save(context)
    end

    local function submit_final(context, state)
        if state:variable("nokris.capability") ~= "model_complete" then return false end
        local slot = exact_owner(context)
        local directive = authored(9)
        local request = slot:set_directive{directive=directive, state=1}
        assert(request, "directive completion request did not return a request key")
        pending = {request=request, operation="set1", index=9, source=source, region=held}
        flow.operation, flow.status, flow.target = "set1", "pending", 9
        flow.region, flow.source = held, source
        flow.reason = "none"
        save(context)
        return true
    end

    local function submit_clear(context)
        local slot = exact_owner(context)
        local request = slot:clear_directives()
        assert(request, "directive clear request did not return a request key")
        pending = {request=request, operation="clear", index=9, source=source, region=held}
        flow.operation, flow.status, flow.target = "clear", "pending", 0
        flow.region, flow.source = held, source
        flow.reason = "none"
        save(context)
    end

    -- Keep causal milestones while another directive's transport receipt is pending.
    local function collect(context, state)
        if fenced or complete or source == nil or (held ~= OPENING_REGION and held ~= RITUAL_REGION)
            or state:variable("route.invalidated") == true then return end
        local observed = flow.history
        for index = 1, 9 do
            if qualifies(index, state) then observed = observed | (1 << (index - 1)) end
        end
        if observed ~= flow.history then flow.history = observed; save(context) end
    end

    local function dispatch(context, state)
        collect(context, state)
        if fenced or complete or pending or held == nil or source == nil
            or (held ~= OPENING_REGION and held ~= RITUAL_REGION)
            or state:variable("route.invalidated") == true then return end
        if flow.step >= 9 then
            if state:variable("nokris.capability") == "model_complete" then submit_final(context, state) end
            return
        end
        local target = latest()
        if target then submit_set(context, target) end
    end

    local function update_sequence(context, event)
        if not is_event(event) or not identity.positive_decimal(event.mission_sequence) then return false end
        if after(event.mission_sequence, flow.sequence) then flow.sequence = event.mission_sequence end
        if flow.status ~= "idle" then save(context) end
        return true
    end

    local function request_matches(event)
        return pending and (type(event.request_key) == "userdata" or type(event.request_key) == "table")
            and event.request_key:matches(pending.request)
    end

    local function receive(context, state, event)
        if not request_matches(event) then return false end
        if event.source_generation ~= pending.source then
            stop(context, "receipt_source")
            return true
        end
        if event.held_region_index ~= nil and event.held_region_index ~= OPENING_REGION
            and event.held_region_index ~= RITUAL_REGION then
            stop(context, "receipt_region")
            return true
        end
        if not identity.positive_decimal(event.mission_sequence) then return true end
        if event.outcome ~= "transport_staged" then
            stop(context, "refused")
            return true
        end
        if after(event.mission_sequence, flow.sequence) then flow.sequence = event.mission_sequence end
        local operation, index = pending.operation, pending.index
        pending = nil
        if operation == "set0" then
            flow.step = math.max(flow.step, index)
            flow.operation, flow.status, flow.target, flow.reason = "none", "active", 0, "none"
            save(context)
        elseif operation == "set1" then
            if state:variable("nokris.capability") ~= "model_complete" then
                stop(context, "completion_lost")
                return true
            end
            flow.operation, flow.status, flow.target, flow.reason = "none", "active", 0, "none"
            save(context)
            submit_clear(context)
        else
            if state:variable("nokris.capability") ~= "model_complete" or held ~= RITUAL_REGION
                or source == nil or state:variable("route.invalidated") == true then
                stop(context, "clear_lifecycle")
                return true
            end
            flow.operation, flow.status, flow.target, flow.reason = "none", "complete", 0, "none"
            complete = true
            save(context)
        end
        return true
    end

    local function client_state(context, event)
        local next_source = event.source_generation
        local next_region = event.held_region_index
        if type(next_source) ~= "string" or not identity.positive_decimal(next_source) then
            if pending then stop(context, "source_invalid") end
            held, source = next_region, nil
            return
        end
        if source ~= nil and next_source ~= source then
            stop(context, "source_changed")
            return
        end
        if pending and ((next_region ~= OPENING_REGION and next_region ~= RITUAL_REGION)
            or next_source ~= pending.source) then
            stop(context, "pending_region")
            return
        end
        if not update_sequence(context, event) then return end
        held, source = next_region, next_source
        if flow.status == "active" or flow.status == "pending" then
            -- EventHandle exposes the native absent region (-1) as nil.
            -- Persist the explicit sentinel while dispatch continues to require a held region.
            flow.region, flow.source = held or -1, source
            save(context)
        end
    end

    local function wrap(name)
        local previous = controller[name]
        controller[name] = function(context, state, event)
            initialize(context, state)
            if name=="on_load" and state:variable("nokris.recovery")=="awaiting_client_state" then
                -- Keep the ordinary entry owner ineligible until a fresh client-state event has
                -- populated the replacement VM's native-observation held region.
                context:set_variable("later.prefight.status","blocked")
            end
            if previous then previous(context, state, event) end
            if fenced or complete then return end
            if name == "on_load" then
                if state:variable("nokris.recovery")=="reattach_observed_boss" then
                    restore_captured_prefight(context)
                    context:clear_variable("nokris.recovery")
                    context:set_variable("nokris.intro","transport_staged")
                    context:set_variable("later.boss_entry.status","running")
                elseif state:variable("nokris.recovery")=="awaiting_client_state" then
                    recovery_boss_retry_active=true
                    recovery_waiting_region=true
                    restore_captured_prefight(context)
                    context:set_variable("later.boss_entry.status","awaiting_client_state")
                elseif captured_portal_absent_boss then
                    restore_captured_prefight(context)
                    captured_portal_absent_boss=nil
                    held,source=88,"2"
                    recovery_boss_retry_active=true
                    submit_captured_boss_retry(context)
                elseif captured_portal_boss_recovery then
                    restore_captured_prefight(context)
                    captured_portal_boss_recovery=nil
                    held,source=88,"2"
                    recovery_boss_retry_active=true
                    submit_captured_boss_retry(context)
                elseif captured_portal_staged_recovery then
                    restore_captured_prefight(context)
                    captured_portal_staged_recovery=nil
                    held,source=88,"2"
                    recovery_boss_retry_active=true
                    submit_captured_boss_retry(context)
                elseif captured_portal_recovery then
                    restore_captured_prefight(context)
                    captured_portal_recovery=nil
                    held,source=88,"2"
                elseif captured_boss_retry then
                    restore_captured_prefight(context)
                    captured_boss_retry = nil
                    held, source = 88, "2"
                    submit_captured_boss_retry(context)
                elseif captured_spawn_recovery then
                    restore_captured_prefight(context)
                    captured_spawn_recovery = nil
                    held, source = 88, "2"
                    submit_set(context, 8)
                    submit_captured_spawn(context)
                elseif captured_recovery then
                    restore_captured_prefight(context)
                    captured_recovery = nil
                    -- Reload itself does not emit a fresh client-state edge. Replay only the
                    -- captured binding into the composed Lua callbacks so their normal owners
                    -- can submit work; no population or transport receipt is manufactured.
                    controller.on_event_client_state_changed(context, state, {
                        held_region_index=88, source_generation="2", mission_sequence="3092",
                    })
                elseif flow.status ~= "idle" then stop(context, "reload") end
                return
            end
            if name == "on_event_client_state_changed" and recovery_waiting_region then
                if event.source_generation=="2" and event.held_region_index==88 then
                    recovery_waiting_region=nil
                    context:clear_variable("nokris.recovery")
                    submit_captured_boss_retry(context)
                else
                    -- A real boundary crossing commonly reports the departed region first.
                    -- Retain no identity from it; wait for the subsequent exact region-88 view.
                    context:clear_variable("route.invalidated")
                    context:set_variable("later.boss_entry.status","awaiting_client_state")
                    return
                end
            end
            if name == "on_event_effect_result" and event and event.request_key then
                local chant_receipt=recovery_chant and event.request_key:matches(recovery_chant)
                local spawn_receipt=recovery_spawn and event.request_key:matches(recovery_spawn)
                local intro_receipt=recovery_intro and event.request_key:matches(recovery_intro)
                local cleanup_receipt=recovery_cleanup and event.request_key:matches(recovery_cleanup)
                if chant_receipt or spawn_receipt or intro_receipt or cleanup_receipt then
                    if event.source_generation~="2" or event.outcome~="transport_staged" then
                        context:set_variable("route.invalidated", true)
                        context:set_variable("later.boss_entry.status", "blocked")
                    elseif chant_receipt then
                        recovery_chant=nil
                        context:set_variable("nokris.chant", "transport_staged")
                    elseif spawn_receipt then
                        recovery_spawn=nil
                        recovery_spawn_staged=true
                        context:set_variable("later.boss_entry.status", "placement_staged")
                    elseif intro_receipt then
                        recovery_intro=nil
                        context:set_variable("nokris.intro", "scene_staged")
                        submit_captured_cleanup(context)
                    else
                        recovery_cleanup=nil
                        if recovery_boss_retry_active then
                            recovery_boss_retry_active=nil
                            restore_captured_prefight(context)
                        end
                        context:set_variable("nokris.intro", "transport_staged")
                        context:set_variable("later.boss_entry.entered", true)
                        context:set_variable("later.boss_entry.status", "running")
                    end
                    return
                end
            end
            if name == "on_event_squad_state" and recovery_spawn_staged and event
                and event.source_generation=="2" and event.registry_key==0xC55749AB
                and event.object_tag==0x80F732CE and event.slot_type==1 and event.slot_index==0
                and event.population_available==true and event.alive_count and event.alive_count>0
                and event.spawn_generation and event.spawn_generation>0 then
                recovery_spawn_staged=nil
                if recovery_boss_retry_active then
                    submit_captured_intro(context)
                else
                    context:set_variable("later.boss_entry.status", "running")
                    dispatch(context, state)
                end
                return
            end
            if name == "on_event_client_state_changed" then
                client_state(context, event or {})
                dispatch(context, state)
                return
            end
            if name == "on_event_effect_result" and request_matches(event) then
                if receive(context, state, event) and not fenced and not complete then
                    dispatch(context, state)
                end
                return
            end
            if not is_event(event) or event.source_generation ~= source or held == nil then return end
            if not update_sequence(context, event) then return end
            dispatch(context, state)
        end
    end

    for _, name in ipairs({"on_start", "on_load", "on_event_client_state_changed", "on_event_object_state",
        "on_event_squad_state", "on_event_effect_result", "on_event_player_trigger", "on_event_trigger_entered",
        "on_event_trigger_exited", "on_event_trigger_state", "on_event_native_reaction"}) do
        wrap(name)
    end
    return controller
end
