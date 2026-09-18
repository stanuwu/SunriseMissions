-- Reconstructed replacement transport requires the model's positive-loss command and a prior
-- carrier not known alive.
local record=require("strike_nokris.state_record")
local pending_population=require("strike_nokris.pending_population")
local identity_schema=record.schema("K1",{{name="source",kind="string",limit=20},
    {name="epoch",kind="integer"},{name="phase",kind="integer"}})
local flow_schema=record.schema("K2",{{name="serial",kind="integer"},{name="member",kind="integer"},
    {name="status",kind="integer"},{name="frozen",kind="boolean"}})
local row_schema=record.schema("K3",{{name="spawn",kind="integer"},{name="counter",kind="integer"},
    {name="alive",kind="integer"},{name="revision",kind="integer"},{name="group",kind="integer"}})
local function positive(value) return math.type(value)=="integer" and value>0 end
local identity_text=require("strike_nokris.identity_text")
local function serial_of(value,epoch)
    local first,last=identity_text.transaction_parts(value)
    if first~=tostring(epoch) then return nil end
    local serial=tonumber(last)
    return positive(serial) and tostring(serial)==last and serial or nil
end

return function(mission,model,activation,support,objective,context,state,prefix,phases)
    assert(type(prefix)=="string" and #prefix<=40 and #phases==3)
    local identity_key,flow_key,reason_key=prefix..".identity",prefix..".flow",prefix..".reason"
    local identity=record.read(state,identity_key,identity_schema)
    local flow=record.read(state,flow_key,flow_schema)
    local jobs,held,source,blocked,placement,director={}
    local region=assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local function save()
        record.write(context,identity_key,identity_schema,identity); record.write(context,flow_key,flow_schema,flow)
    end
    local function save_row(member) record.write(context,prefix..".row"..member,row_schema,jobs[member].observed) end
    local function block(reason) blocked=true; context:set_variable(reason_key,reason); save(); return false,reason end
    if identity.source or state:variable(reason_key) then block("retained_carriers_require_reconciliation") end
    local function current()
        local view=model.view()
        return held==region and source==identity.source and view.source==identity.source
            and view.epoch==identity.epoch and view.stage~="blocked"
    end
    local function slot(symbol,kind,index)
        local value=context:slot(assert(mission.Slot[symbol]))
        assert(value.object_tag==0x80F732CE and value.registry_key==0xC55749AB
            and value.slot_type==kind and value.slot_index==index,"phase carrier binding mismatch")
        return value
    end
    local function pending()
        if placement or flow.status==1 or flow.status==2 then return true end
        for _,job in ipairs(jobs) do if job.request or job.placement or not job.admitted then return true end end
        return false
    end
    local function place(job)
        local row=job.definition
        local rule=slot(row.rule_symbol,66,row.rule)
        slot(row.symbol,1,row.slot)
        local squad=context:squad(assert(mission.Squad[row.symbol]))
        assert(squad.member_count==#row.counts)
        local counts=squad:counts(); assert(counts.count==#row.counts)
        for index,count in ipairs(row.counts) do assert(math.type(count)=="integer" and count>=0); counts:set(index,count) end
        return assert(squad:place{counts=counts,spawn_rule=rule})
    end
    local function assign(member,group,expected)
        local job=jobs[member]
        job.request=assert(objective.assign(context,mission,mission.Slot[job.definition.symbol],director,group))
        job.observed.group=group; save_row(member)
    end
    local function choose(member)
        local job=jobs[member]
        if flow.frozen or job.request or not job.observed or job.observed.alive<=0 then return end
        local group=objective.choose({objective_revision=job.observed.revision,task_costs=job.costs},5,job.observed.group,1)
        if group~=nil and group~=job.observed.group then assign(member,group,1) end
    end
    local adapter={}
    function adapter.view()
        return {source=identity.source,epoch=identity.epoch,phase=identity.phase,blocked=blocked==true,
            frozen=flow.frozen==true,pending=pending(),member=flow.member,
            transaction=flow.serial and (tostring(identity.epoch)..":"..tostring(flow.serial)),
            transported=flow.status==2 or flow.status==3,reason=state:variable(reason_key)}
    end
    function adapter.carrier(member)
        local job=jobs[member]
        if blocked or not job or not job.observed then return nil end
        return {generation=job.observed.spawn,alive=job.observed.alive,
            ready=job.observed.alive~=0 and job.assigned==true and not job.replacing}
    end
    function adapter.client_state(event)
        if blocked then return false end
        if identity.source and (event.source_generation~=identity.source or event.held_region_index~=region) then
            return block("carrier_held_or_source_lost")
        end
        held,source=event.held_region_index,event.source_generation; return true
    end
    function adapter.sync()
        if blocked then return false end
        local view,batch=model.view(),activation.view()
        if identity.source and not current() then return block("carrier_identity_lost") end
        if batch.status=="blocked" then return block("carrier_activation_lost") end
        if not batch.phase or held~=region or source~=view.source then return false end
        if batch.source~=view.source or batch.epoch~=view.epoch or batch.phase~=view.phase then return block("carrier_activation_mismatch") end
        if identity.phase~=batch.phase then
            if identity.phase then
                if not flow.frozen or pending() or batch.phase~=identity.phase+1 then return block("carrier_phase_not_settled") end
            elseif batch.phase~=1 then return block("missing_initial_carrier_phase") end
            local definition=assert(phases[batch.phase]); assert(#definition.carriers==2)
            director=slot("OBJ_NOKRIS_MAIN_LOOP",3,4) -- 0.5.0 slot handles carry no objective_count
            local next_jobs={}
            for member,row in ipairs(definition.carriers) do
                slot(row.symbol,1,row.slot); slot(row.rule_symbol,66,row.rule)
                next_jobs[member]={definition=row}
            end
            jobs=next_jobs; flow={frozen=false}
            identity={source=view.source,epoch=view.epoch,phase=batch.phase}; save()
            for member=1,2 do record.write(context,prefix..".row"..member,row_schema,{}) end
        end
        -- Initial placement waits for the add wave to thin (support view), never for a timer.
        if view.stage=="shield" and support.view().thinned then
            for _,job in ipairs(jobs) do
                if not job.admitted and not job.placement then job.placement=place(job) end
            end
        end
        for _,job in ipairs(jobs) do
            if job.early and job.admitted and not (job.replacing and flow.status==1) then
                local early=job.early; job.early=nil
                for _,event in ipairs(early) do
                    adapter.squad_state(event)
                    if blocked then return false end
                end
            end
        end
        local command=model.output()
        if not command or command.kind~="replace_carrier" then return true end
        local serial=serial_of(command.transaction,identity.epoch)
        local member=command.member
        if not serial or (member~=1 and member~=2) or command.epoch~=identity.epoch
            or command.phase~=identity.phase or view.stage~="shield" or flow.frozen then return block("invalid_carrier_replacement") end
        if flow.serial==serial then
            if flow.member~=member then return block("replacement_transaction_conflict") end
            if command.transported and flow.status==1 then return block("model_transport_without_carrier") end
            return true
        end
        if command.transported or (flow.serial and serial<=flow.serial) then return block("replacement_transaction_reversed") end
        local job=jobs[member]
        if pending() or not job.observed or job.observed.alive>0 then return false,"awaiting_prior_carrier_zero" end
        flow.serial,flow.member,flow.status=serial,member,1
        job.replacing=true; job.assigned=false; save()
        placement=place(job); return true
    end
    function adapter.freeze()
        if blocked or not current() then return false end
        local view=model.view()
        if view.phase~=identity.phase or view.stage~="releasing" or view.consumed~=3 or pending() then return false end
        flow.frozen=true; save(); return true
    end
    function adapter.squad_state(event)
        if blocked or not identity.phase then return false end
        if event.object_tag~=0x80F732CE or event.registry_key~=0xC55749AB or event.slot_type~=1 then return false end
        for member,job in ipairs(jobs) do
            if event.slot_index==job.definition.slot then
                if not current() or event.source_generation~=identity.source then return block("carrier_source_lost") end
                -- The member's own placement receipt is its admission.
                if not job.admitted or (job.replacing and flow.status==1) then
                    job.early=job.early or {}
                    local ok,reason=pending_population.push(job.early,event)
                    if not ok then return block(reason) end
                    return false
                end
                local prior=job.observed
                local replacing=job.replacing and flow.member==member and flow.status==2
                local new_spawn=replacing and positive(event.spawn_generation) and event.spawn_generation>prior.spawn
                -- Preserve explicit replacement adoption; an initial reset has no lifetime to lose.
                if event.registration_reset and prior and not new_spawn then
                    return block("carrier_registration_lost")
                end
                if not positive(event.spawn_generation) or not positive(event.sense_generation)
                    or event.population_available~=true or math.type(event.alive_count)~="integer" or event.alive_count<0 then
                    -- On 0.5 a re-placed slot's new lifetime never reports its alive count, so its
                    -- spawn generation alone admits the replacement; its population stays unknown (-1).
                    if new_spawn and positive(event.sense_generation) then
                        job.replacing=false; flow.status=3; save()
                        job.observed={spawn=event.spawn_generation,counter=event.sense_generation,alive=-1,
                            revision=event.objective_revision,group=-1}
                        job.costs={}; save_row(member); assign(member,-1,0)
                        return true
                    end
                    if prior and prior.alive>=0 then return block("carrier_population_unknown") end
                    return false
                end
                if new_spawn then
                    -- The reused slot keeps the objective revision of its previous carrier.
                    if event.alive_count<=0 or (event.objective_revision~=nil
                        and event.objective_revision~=0 and event.objective_revision~=1) then return false end
                    prior=nil; job.replacing=false; flow.status=3; save()
                elseif prior and event.spawn_generation~=prior.spawn then return block("unexpected_carrier_spawn") end
                local costs={}; for task=1,5 do costs[task]=event.task_costs and event.task_costs[task] end
                if prior then
                    if event.sense_generation==prior.counter then
                        local same=event.alive_count==prior.alive and event.objective_revision==prior.revision
                        for task=1,5 do same=same and costs[task]==job.costs[task] end
                        if not same then return block("carrier_duplicate_conflict") end
                        return true
                    end
                    -- The reducer suppresses unchanged levels and marks actual gaps as resets.
                    if event.sense_generation<prior.counter then return block("carrier_counter_reversed") end
                    if (flow.frozen or job.replacing) and event.alive_count>0 then return block("retired_carrier_resurged") end
                    if (prior.revision==1 and event.objective_revision~=1)
                        or (event.objective_revision~=nil and event.objective_revision~=0 and event.objective_revision~=1) then
                        return block("carrier_objective_revision_lost")
                    end
                elseif event.alive_count<=0 or (event.objective_revision~=nil and event.objective_revision~=0) then return false end
                job.observed={spawn=event.spawn_generation,counter=event.sense_generation,alive=event.alive_count,
                    revision=event.objective_revision,group=prior and prior.group or -1}
                job.costs=costs; save_row(member)
                if not prior then assign(member,-1,0) else choose(member) end
                return true
            end
        end
        return false
    end
    function adapter.effect_result(event)
        if blocked then return false end
        for _,job in ipairs(jobs) do
            if job.placement and event.request_key and event.request_key:matches(job.placement) then
                if not current() or event.source_generation~=identity.source then return block("carrier_placement_source_lost") end
                if event.outcome~="transport_staged" then return block("carrier_placement_refused") end
                job.placement=nil; job.admitted=true
                local early=job.early; job.early=nil
                for _,early_event in ipairs(early or {}) do
                    adapter.squad_state(early_event)
                    if blocked then return false end
                end
                return true
            end
        end
        if placement and event.request_key and event.request_key:matches(placement) then
            if not current() or event.source_generation~=identity.source then return block("replacement_receipt_source_lost") end
            if event.outcome~="transport_staged" then return block("replacement_transport_refused") end
            placement=nil; flow.status=2; save(); return true
        end
        for member,job in ipairs(jobs) do
            if job.request and event.request_key and event.request_key:matches(job.request) then
                if not current() or event.source_generation~=identity.source then return block("carrier_receipt_source_lost") end
                if event.outcome~="transport_staged" then return block("carrier_objective_refused") end
                job.request=nil; job.assigned=true; choose(member); return true
            end
        end
        return false
    end
    return adapter
end
