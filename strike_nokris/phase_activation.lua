-- Typed activation batches for the reconstructed Nokris roster. Transport is not native readiness.
local record=require("strike_nokris.state_record")
local schema=record.schema("P1",{
    {name="source",kind="string",limit=20},{name="epoch",kind="integer"},
    {name="serial",kind="integer"},{name="phase",kind="integer"},{name="status",kind="integer"},
})
local statuses={"pending","transport_staged","blocked"}
local function positive(value) return math.type(value)=="integer" and value>0 end
local identity_text=require("strike_nokris.identity_text")
local decimal=identity_text.positive_decimal
local function transaction(value)
    local first,second=identity_text.transaction_parts(value)
    if not first then return end
    local epoch,serial=tonumber(first),tonumber(second)
    if not positive(epoch) or not positive(serial) or tostring(epoch)~=first or tostring(serial)~=second then return end
    return epoch,serial
end

return function(mission,model,context,state,prefix,phases)
    assert(type(prefix)=="string" and #prefix<=40 and #phases==3)
    local key,mask_key,reason_key=prefix..".batch",prefix..".mask",prefix..".reason"
    local saved=record.read(state,key,schema)
    local mask=state:variable(mask_key) or 0
    local requests={}
    -- Support waves trickle: the next squad is placed once the previously placed one reports its
    -- population (retail staggers its spawns; run D6EA20F6 placed six squads in one batch and every
    -- add spawned within 235 ms, the boss-room spawn lag). Queue state is VM-local like the requests.
    -- ponytail: a placed squad that never reports population stalls the batch in `activating`.
    local queued,last_slot={},nil
    local held,current_source
    local region=assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local function save() record.write(context,key,schema,saved); context:set_variable(mask_key,mask) end
    local function block(reason)
        saved.status=3; context:set_variable(reason_key,reason); save()
        return false,reason
    end
    -- Request handles are scoped to their VM. Retained state cannot recreate a submitted batch.
    if saved.source or state:variable(mask_key)~=nil then block("retained_batch_requires_reconciliation") end
    local function current()
        local view=model.view()
        return view and view.source==saved.source and view.epoch==saved.epoch
            and view.phase==saved.phase and view.stage~="blocked"
    end
    local function slot(name,kind,index)
        local value=context:slot(assert(mission.Slot[name]))
        assert(value.object_tag==0x80F732CE and value.registry_key==0xC55749AB
            and value.slot_type==kind and value.slot_index==index,"Nokris phase slot binding mismatch")
        return value
    end
    local function prepare(phase)
        local definition=assert(phases[phase])
        assert(#definition.crystals==2 and #definition.crystal_symbols==2 and #definition.carriers==2
            and #definition.supports>0 and #definition.supports<=6,"Nokris phase roster bounds")
        local operations={}
        for index,name in ipairs(definition.crystal_symbols) do
            operations[#operations+1]={crystal=slot(name,4,definition.crystals[index])}
        end
        local function squad(row,carrier)
            slot(row.symbol,1,row.slot)
            local value=context:squad(assert(mission.Squad[row.symbol]))
            assert(value.member_count==#row.counts,"Nokris phase squad profile mismatch")
            local counts=value:counts()
            assert(counts.count==#row.counts,"Nokris phase count vector mismatch")
            for index,count in ipairs(row.counts) do
                assert(math.type(count)=="integer" and count>=0 and count<=0x7FFFFFFF)
                counts:set(index,count)
            end
            local rule=carrier and slot(row.rule_symbol,66,row.rule) or nil
            operations[#operations+1]={squad=value,counts=counts,rule=rule,slot=row.slot}
        end
        for _,row in ipairs(definition.supports) do squad(row,false) end
        -- Carriers are placed by phase_carriers once the support wave is thinned.
        return operations
    end
    local batch={}
    local function submit(operation)
        local request
        if operation.crystal then request=operation.crystal:set_object_active{active=true}
        else
            request=operation.squad:place{counts=operation.counts,spawn_rule=operation.rule}
            last_slot=operation.slot
        end
        requests[#requests+1]=assert(request,"Nokris phase effect did not return a request key")
    end
    -- Copy scalar admission data; request handles remain owned by this batch.
    function batch.population(index)
        if not saved.phase or saved.status==3 or not positive(index) then return nil end
        local definition=phases[saved.phase]
        local row=definition.supports[index]
        if not row then return nil end
        return {symbol=row.symbol,slot=row.slot,phase=saved.phase,source=saved.source,epoch=saved.epoch,
            transported=(mask & (1 << (index+1)))~=0}
    end
    function batch.view()
        local transported=0
        for index=1,#requests do if (mask & (1 << (index-1)))~=0 then transported=transported+1 end end
        return {status=statuses[saved.status],phase=saved.phase,source=saved.source,epoch=saved.epoch,
            transaction=saved.epoch and (tostring(saved.epoch)..":"..tostring(saved.serial)),
            requested=#requests,transported=transported,reason=state:variable(reason_key)}
    end
    function batch.sync()
        if saved.status==3 then return false,"blocked" end
        local view,command=model.view(),model.output()
        if saved.source and (view.source~=saved.source or view.epoch~=saved.epoch or view.stage=="blocked") then
            return block("model_identity_lost")
        end
        if not command or command.kind~="activate_phase" then return false,"no_activation_command" end
        if held~=region or current_source~=view.source then return false,"awaiting_held_source" end
        local epoch,serial=transaction(command.transaction)
        if not epoch or epoch~=command.epoch or epoch~=view.epoch or not decimal(view.source)
            or view.stage~="activating" or view.phase~=command.phase or not positive(command.phase)
            or command.phase>3 or command.definition~=phases[command.phase] then
            return block("invalid_activation_command")
        end
        if saved.serial==serial and saved.epoch==epoch then
            if saved.phase~=command.phase then return block("transaction_phase_conflict") end
            if command.transported and saved.status~=2 then return block("model_transport_without_batch") end
            return true
        end
        if command.transported then return block("model_transport_without_batch") end
        if saved.source then
            if saved.status~=2 or serial<=saved.serial or command.phase~=saved.phase+1 then
                return block("prior_batch_not_released")
            end
            -- Only the actual model can emit the next activation after accepting phase release.
        elseif command.phase~=1 then return block("missing_prior_phase") end
        local operations=prepare(command.phase) -- Validate the complete batch before its first effect.
        saved={source=view.source,epoch=epoch,serial=serial,phase=command.phase,status=1}
        requests={}; mask=0; queued={}; last_slot=nil; save()
        for _,operation in ipairs(operations) do
            if operation.crystal or last_slot==nil then submit(operation) else queued[#queued+1]=operation end
        end
        return true
    end
    function batch.squad_state(event)
        if saved.status~=1 or #queued==0 or last_slot==nil then return false end
        if event.object_tag~=0x80F732CE or event.registry_key~=0xC55749AB or event.slot_type~=1
            or event.slot_index~=last_slot or event.source_generation~=saved.source
            or event.population_available~=true then return false end
        submit(table.remove(queued,1))
        return true
    end
    function batch.effect_result(event)
        if saved.status==3 or not saved.source then return false end
        for index,request in ipairs(requests) do
            if event.request_key and event.request_key:matches(request) then
                if not current() or event.source_generation~=saved.source then return block("batch_source_lost") end
                if event.outcome~="transport_staged" then return block("batch_transport_refused") end
                mask=mask | (1 << (index-1))
                if mask==(1 << #requests)-1 and #queued==0 then saved.status=2 end
                save(); return true
            end
        end
        return false
    end
    function batch.client_state(event)
        if saved.source and (event.source_generation~=saved.source or event.held_region_index~=region) then
            return block("batch_held_or_source_lost")
        end
        held=event.held_region_index
        current_source=decimal(event.source_generation) and event.source_generation or nil
        return true
    end
    return batch
end
