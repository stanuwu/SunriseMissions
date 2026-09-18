-- Semantic completion model. These inputs require native producers; this module does not
-- manufacture them from population zero, scene completion, elapsed time or lifetime Auth.
local record=require("strike_nokris.state_record")
local identity_schema=record.schema("F1",{
    {name="source",kind="string",limit=20},{name="sequence",kind="string",limit=20},
    {name="epoch",kind="integer"},{name="boss",kind="integer"},
})
local flow_schema=record.schema("F2",{
    {name="stage",kind="integer"},{name="phase",kind="integer"},{name="mask",kind="integer"},
    {name="serial",kind="integer"},{name="checkpoint",kind="integer"},
})
local pending_schema=record.schema("F3",{
    {name="kind",kind="integer"},{name="serial",kind="integer"},{name="member",kind="integer"},
    {name="transported",kind="boolean"},
})
local carrier_schema=record.schema("F4",{{name="first",kind="integer"},{name="second",kind="integer"}})
local stages={"opening_damage","activating","shield","releasing","damage","final_damage",
    "retiring","resetting","checkpoint","result","reward","exit","complete","blocked","awaiting_boss"}
local kinds={"activate_phase","release_phase","replace_carrier","retire_encounter",
    "publish_reset","resume_checkpoint","publish_result","grant_reward","request_exit"}
local function positive(value) return math.type(value)=="integer" and value>0 end
local decimal=require("strike_nokris.identity_text").positive_decimal
local function after(value,previous)
    return decimal(value) and (#value>#previous or (#value==#previous and value>previous))
end

return function(context,state,prefix,initial,phases)
    assert(type(prefix)=="string" and #prefix<=40 and #phases==3)
    local crystal_slots={}
    for _,phase in ipairs(phases) do
        assert(#phase.crystals==2)
        for _,slot in ipairs(phase.crystals) do
            assert(positive(slot) and not crystal_slots[slot],"phase crystals must have distinct exact slots")
            crystal_slots[slot]=true
        end
    end
    local keys={prefix..".identity",prefix..".flow",prefix..".pending",prefix..".carriers"}
    local identity=record.read(state,keys[1],identity_schema)
    local flow=record.read(state,keys[2],flow_schema)
    local pending=record.read(state,keys[3],pending_schema)
    local carriers=record.read(state,keys[4],carrier_schema)
    local function save()
        record.write(context,keys[1],identity_schema,identity)
        record.write(context,keys[2],flow_schema,flow)
        record.write(context,keys[3],pending_schema,pending)
        record.write(context,keys[4],carrier_schema,carriers)
    end
    if identity.source then
        -- In-flight native effects need reconciliation, never a replay caused by VM restore.
        flow.stage=14
        context:set_variable(prefix..".reason","retained_model_requires_reconciliation")
    else
        assert(decimal(initial.source) and positive(initial.epoch) and positive(initial.boss))
        identity={source=initial.source,sequence="0",epoch=initial.epoch,boss=initial.boss}
        flow={stage=1,phase=0,mask=0,serial=0,checkpoint=4}
    end
    save()
    local function block(reason)
        flow.stage=14; context:set_variable(prefix..".reason",reason); save()
        return false,reason
    end
    local function issue(kind,member)
        assert(not pending.kind,"completion model cannot overwrite an unresolved command")
        if flow.serial==math.maxinteger then return block("transaction_sequence_exhausted") end
        flow.serial=flow.serial+1
        pending={kind=kind,serial=flow.serial,member=member or 0,transported=false}
        return true
    end
    local function transaction()
        return pending.kind and (tostring(identity.epoch)..":"..tostring(pending.serial)) or nil
    end
    local function current_generation(member) return member==1 and carriers.first or carriers.second end
    local function set_generation(member,value)
        if member==1 then carriers.first=value else carriers.second=value end
    end
    local function advance()
        if flow.stage~=3 or pending.kind then return end
        if (flow.mask & 3)==3 then
            flow.stage=4; issue(2); return
        end
        for member=1,2 do
            if (flow.mask & (1 << (member+1)))~=0 then issue(3,member); return end
        end
    end
    local model={}
    -- Preserve pending transaction history while fencing every downstream output consumer.
    function model.invalidate(reason)
        assert(type(reason)=="string" and #reason>0 and #reason<=127)
        return block(reason)
    end
    function model.view()
        return {stage=stages[flow.stage],phase=flow.phase,consumed=flow.mask & 3,
            epoch=identity.epoch,source=identity.source,boss=identity.boss,
            checkpoint=flow.checkpoint,reason=state:variable(prefix..".reason")}
    end
    function model.output()
        if not pending.kind or flow.stage==14 then return nil end
        return {kind=kinds[pending.kind],transaction=transaction(),epoch=identity.epoch,
            phase=flow.phase,member=pending.member,checkpoint=flow.checkpoint,
            transported=pending.transported,definition=phases[flow.phase]}
    end
    function model.observe(event)
        if flow.stage==14 or flow.stage==13 then return false,"terminal_model" end
        if type(event)~="table" or event.epoch~=identity.epoch or event.source~=identity.source
            or event.boss~=identity.boss then return false,"foreign_lifetime" end
        if not after(event.sequence,identity.sequence) then return false,"old_or_invalid_sequence" end
        local kind=event.kind
        local member=event.member
        local generation=current_generation(member)
        if kind=="phase_onset" then
            if (flow.stage~=1 and flow.stage~=5) or pending.kind
                or not positive(event.phase) or event.phase~=flow.phase+1 or event.phase>3 then return false,"phase_order" end
            flow.phase=event.phase; flow.mask=0; carriers={}; flow.stage=2; issue(1)
        elseif kind=="transport" then
            if not pending.kind or event.transaction~=transaction() then return false,"foreign_transaction" end
            if event.outcome~="transport_staged" then return block("command_transport_not_staged") end
            pending.transported=true
        elseif kind=="shield_ready" then
            if flow.stage~=2 or pending.kind~=1 or not pending.transported
                or event.transaction~=transaction() or event.phase~=flow.phase then return false,"shield_not_admitted" end
            pending={}; flow.stage=3
        elseif kind=="carrier_ready" then
            if flow.stage~=3 or event.phase~=flow.phase or (member~=1 and member~=2)
                or not positive(event.generation) then return false,"carrier_identity" end
            local lost=(flow.mask & (1 << (member+1)))~=0
            if lost then
                if pending.kind~=3 or pending.member~=member or not pending.transported
                    or event.transaction~=transaction() or not generation
                    or event.generation<=generation then return false,"replacement_not_admitted" end
                flow.mask=flow.mask & ~(1 << (member+1)); pending={}
            elseif generation then
                if event.generation~=generation then return block("carrier_lifetime_changed") end
            end
            set_generation(member,event.generation)
        elseif kind=="crystal_consumed" or kind=="relic_lost" then
            if flow.stage~=3 or event.phase~=flow.phase or (member~=1 and member~=2)
                or not generation or event.generation~=generation then return false,"foreign_relic_lifetime" end
            local consumed=1 << (member-1)
            local lost=1 << (member+1)
            if kind=="crystal_consumed" then
                if event.crystal~=phases[flow.phase].crystals[member] then return false,"wrong_crystal" end
                if (flow.mask & lost)~=0 then return block("loss_consumption_requires_reconciliation") end
                flow.mask=flow.mask | consumed
            else
                if event.cause~="out_of_bounds" and event.cause~="destroyed_unused" then return false,"not_positive_relic_loss" end
                if (flow.mask & consumed)==0 then flow.mask=flow.mask | lost end
            end
        elseif kind=="phase_released" then
            if flow.stage~=4 or pending.kind~=2 or not pending.transported
                or event.transaction~=transaction() or event.phase~=flow.phase
                or event.support_retired~=true or event.immunity_removed~=true then return false,"release_not_accepted" end
            pending={}; flow.stage=flow.phase==3 and 6 or 5
        elseif kind=="boss_defeated" then
            if flow.stage~=6 or pending.kind or event.cause~="normal_death" then return false,"not_final_verdict" end
            flow.stage=10; issue(7)
        elseif kind=="result_accepted" then
            -- No reward or exit commands follow: an accepted result completes the model.
            if pending.kind~=7 or not pending.transported or event.transaction~=transaction()
                then return false,"terminal_transaction_not_accepted" end
            if event.success~=true then return false,"successful_result_not_accepted" end
            pending={}; flow.stage=13
        elseif kind=="wipe" then
            if not positive(event.checkpoint) or event.checkpoint>4 or flow.stage>=10 then return false,"reset_scope" end
            if flow.stage>=7 and flow.stage<=9 then return false,"reset_already_pending" end
            if pending.kind then return block("reset_requires_output_reconciliation") end
            flow.checkpoint=event.checkpoint; flow.stage=7; issue(4)
        elseif kind=="retirement_accepted" then
            if pending.kind~=4 or not pending.transported or event.transaction~=transaction()
                or event.actors_retired~=true or event.relics_retired~=true or event.scenes_retired~=true then
                return false,"retirement_not_accepted"
            end
            pending={}; flow.stage=8; issue(5)
        elseif kind=="reset_accepted" then
            if pending.kind~=5 or not pending.transported or event.transaction~=transaction()
                or not positive(event.new_epoch) or event.new_epoch<=identity.epoch or not decimal(event.new_source) then
                return false,"reset_epoch_not_accepted"
            end
            pending={}; carriers={}; flow.mask=0; flow.phase=0; flow.stage=9
            identity.epoch=event.new_epoch; identity.source=event.new_source; identity.boss=0
            identity.sequence="0"; issue(6); save(); return flow.stage~=14
        elseif kind=="checkpoint_ready" then
            if pending.kind~=6 or not pending.transported or event.transaction~=transaction()
                or event.checkpoint~=flow.checkpoint then return false,"checkpoint_not_accepted" end
            pending={}; flow.stage=15
        elseif kind=="boss_ready" then
            if flow.stage~=15 or pending.kind or not positive(event.new_boss)
                or event.intro_staged~=true then return false,"boss_entry_not_ready" end
            identity.boss=event.new_boss; flow.stage=1
        else return false,"unsupported_semantic_input" end
        identity.sequence=event.sequence
        advance(); save()
        if flow.stage==14 then return false,state:variable(prefix..".reason") end
        return true
    end
    return model
end
