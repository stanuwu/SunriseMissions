-- Reconstructed support-population handoff. Zero is not normal death or physical retirement.
local record=require("strike_nokris.state_record")
local pending_population=require("strike_nokris.pending_population")
local identity_schema=record.schema("J1",{{name="source",kind="string",limit=20},
    {name="epoch",kind="integer"},{name="phase",kind="integer"},
    {name="completed",kind="integer"},{name="frozen",kind="boolean"}})
local row_schema=record.schema("J2",{{name="spawn",kind="integer"},{name="counter",kind="integer"},
    {name="alive",kind="integer"},{name="revision",kind="integer"},{name="group",kind="integer"}})
local function positive(value) return math.type(value)=="integer" and value>0 end

return function(mission,model,activation,objective,context,state,prefix,phases)
    assert(type(prefix)=="string" and #prefix<=40 and #phases==3)
    local identity_key,reason_key=prefix..".identity",prefix..".reason"
    local identity=record.read(state,identity_key,identity_schema)
    local jobs,held,source,blocked={}
    local region=assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local function save() record.write(context,identity_key,identity_schema,identity) end
    local function save_row(index) record.write(context,prefix..".row"..index,row_schema,jobs[index].observed) end
    local function block(reason)
        blocked=true; context:set_variable(reason_key,reason); save(); return false,reason
    end
    if identity.source or state:variable(reason_key) then block("retained_jobs_require_reconciliation") end
    local function current()
        local view=model.view()
        return held==region and source==identity.source and view.source==identity.source
            and view.epoch==identity.epoch and view.stage~="blocked"
    end
    local function slot(symbol,kind,index)
        local value=context:slot(assert(mission.Slot[symbol]))
        assert(value.object_tag==0x80F732CE and value.registry_key==0xC55749AB
            and value.slot_type==kind and value.slot_index==index,"phase support binding mismatch")
        return value
    end
    local director
    local function clear()
        if blocked or not identity.phase or #jobs~=#phases[identity.phase].supports then return false end
        for _,job in ipairs(jobs) do
            if job.request or not job.observed or job.observed.alive~=0 then return false end
        end
        return true
    end
    -- Carrier Knights are released once the add wave is thinned to half of what was placed
    -- (retail shows them well after the adds engage; no timer). Suspended rows count as gone.
    local function thinned()
        if blocked or not identity.phase or #jobs~=#phases[identity.phase].supports then return false end
        local placed,alive=0,0
        for _,job in ipairs(jobs) do
            if not job.suspended then
                if not job.observed or not job.initial then return false end
                placed=placed+job.initial; alive=alive+job.observed.alive
            end
        end
        return placed>0 and alive*2<=placed
    end
    local function settled()
        if blocked or not identity.phase or #jobs~=#phases[identity.phase].supports then return false end
        for index,job in ipairs(jobs) do
            local admission=activation.population(index)
            if job.request or not admission or not admission.transported then return false end
        end
        return true
    end
    local function suspend(index,reason)
        local job=jobs[index]
        job.suspended=true; job.observed=nil; job.costs=nil; job.early=nil
        record.write(context,prefix..".row"..index,row_schema,{})
        context:set_variable(reason_key,reason)
        return false
    end
    local function assign(index,group,expected)
        local job=jobs[index]
        if identity.frozen or job.suspended or job.request or job.observed.alive<=0 then return end
        job.request=objective.assign(context,mission,assert(mission.Slot[job.definition.symbol]),director,group)
        assert(job.request,"objective assignment must return a request key")
        job.assigned=true
        job.observed.group=group; save_row(index)
    end
    local function choose(index)
        local job=jobs[index]
        if blocked or identity.frozen or job.suspended or job.request or not job.observed or job.observed.alive<=0 then return end
        local selected=objective.choose({objective_revision=job.observed.revision,task_costs=job.costs},5,job.observed.group,1)
        if selected~=nil and selected~=job.observed.group then assign(index,selected,1) end
    end
    local adapter={}
    function adapter.view()
        return {phase=identity.phase,source=identity.source,epoch=identity.epoch,frozen=identity.frozen==true,
            settled=settled(),thinned=thinned(),population_clear=clear(),blocked=blocked==true,
            completed=identity.completed or 0,reason=state:variable(reason_key)}
    end
    function adapter.sync()
        if blocked then return false end
        local batch,view=activation.view(),model.view()
        if identity.source and not current() then return block("support_identity_lost") end
        if batch.status=="blocked" then return block("activation_lost") end
        if not batch.phase or held~=region or source~=view.source then return false end
        if batch.source~=view.source or batch.epoch~=view.epoch or batch.phase~=view.phase then
            return block("activation_identity_mismatch")
        end
        if identity.phase==batch.phase then
            for index,job in ipairs(jobs) do
                local admission=activation.population(index)
                if job.early and admission and admission.transported then
                    local early=job.early; job.early=nil
                    for _,event in ipairs(early) do
                        adapter.squad_state(event)
                        if blocked then return false end
                    end
                end
            end
            return true
        end
        if identity.phase then
            if not identity.frozen or batch.phase~=identity.phase+1 then return block("support_handoff_not_retired") end
        elseif batch.phase~=1 then return block("missing_initial_support_phase") end
        local definition=assert(phases[batch.phase]); assert(#definition.supports>0 and #definition.supports<=6)
        local next_jobs={}
        director=slot("OBJ_NOKRIS_MAIN_LOOP",3,4) -- 0.5.0 slot handles carry no objective_count
        for index,row in ipairs(definition.supports) do
            slot(row.symbol,1,row.slot); assert(mission.Squad[row.symbol])
            next_jobs[index]={definition=row}
        end
        local completed=identity.completed or 0
        if identity.phase then completed=completed | (1 << (identity.phase-1)) end
        identity={source=view.source,epoch=view.epoch,phase=batch.phase,completed=completed,frozen=false}
        jobs=next_jobs; save()
        -- These are observer rows; Host retains every committed placement and Auth generation.
        for index=1,6 do record.write(context,prefix..".row"..index,row_schema,{}) end
        return true
    end
    function adapter.freeze()
        if not current() then return block("support_identity_lost") end
        -- Retire this phase's objective ownership. Ordinary adds do not own the crystal gate
        -- and may finish their already-observed combat lifetime after Nokris becomes damageable.
        if not settled() then return false,"support_population_not_settled" end
        identity.frozen=true; identity.completed=(identity.completed or 0) | (1 << (identity.phase-1)); save(); return true
    end
    function adapter.client_state(event)
        if blocked then return false end
        if identity.source and (event.source_generation~=identity.source or event.held_region_index~=region) then
            return block("support_held_or_source_lost")
        end
        held,source=event.held_region_index,event.source_generation; return true
    end
    function adapter.squad_state(event)
        if blocked or not identity.phase then return false end
        if event.object_tag~=0x80F732CE or event.registry_key~=0xC55749AB or event.slot_type~=1 then return false end
        for index,job in ipairs(jobs) do
            if event.slot_index==job.definition.slot then
                if not current() or event.source_generation~=identity.source then return block("support_source_lost") end
                local admission=activation.population(index)
                if not admission or admission.phase~=identity.phase or admission.source~=identity.source
                    or admission.epoch~=identity.epoch or admission.slot~=job.definition.slot then return block("support_admission_lost") end
                if not admission.transported then
                    job.early=job.early or {}
                    local ok,reason=pending_population.push(job.early,event)
                    if not ok then return block(reason) end
                    return false
                end
                if job.spawn and positive(event.spawn_generation) and event.spawn_generation~=job.spawn then
                    return block("support_spawn_changed")
                end
                if job.suspended then return false end
                local prior=job.observed
                -- A first reset may carry directly known population; no duplicate is guaranteed.
                if event.registration_reset and prior then
                    return suspend(index,"support_registration_lost")
                end
                if not positive(event.spawn_generation) or not positive(event.sense_generation)
                    or event.population_available~=true or math.type(event.alive_count)~="integer" or event.alive_count<0 then
                    if prior then return suspend(index,"support_population_unknown") end
                    return false
                end
                local costs={}
                for task=1,5 do costs[task]=event.task_costs and event.task_costs[task] end
                if prior then
                    if event.spawn_generation~=prior.spawn then return block("support_spawn_changed") end
                    if event.sense_generation==prior.counter then
                        local same=event.alive_count==prior.alive and event.objective_revision==prior.revision
                        for task=1,5 do same=same and costs[task]==job.costs[task] end
                        if not same then return block("support_duplicate_conflict") end
                        return true
                    end
                    -- Native unchanged levels do not dispatch callbacks. Actual lost reports
                    -- arrive with registration_reset above, not merely a skipped callback counter.
                    if event.sense_generation<prior.counter then return block("support_counter_reversed") end
                    if event.objective_revision~=nil and event.objective_revision~=0 and event.objective_revision~=1 then
                        return block("support_objective_revision_changed")
                    end
                    if prior.revision==1 and event.objective_revision~=1 then return block("support_objective_revision_lost") end
                    -- A retired wave refilling (geyser squads respawn natively, run 423F4B44 slot 119
                    -- after the first release) is observed, never fatal: frozen rows take no objective.
                elseif event.alive_count<=0 or (event.objective_revision~=nil and event.objective_revision~=0) then return false end
                job.spawn=event.spawn_generation
                if not prior then job.initial=event.alive_count end
                job.observed={spawn=event.spawn_generation,counter=event.sense_generation,alive=event.alive_count,
                    revision=event.objective_revision,group=prior and prior.group or -1}
                job.costs=costs; save_row(index)
                -- Third-phase multi-member waves can report positive population before their
                -- native spawn state settles. Require one unchanged follow-up before publishing.
                if identity.phase==3 then
                    if not prior then return true end
                    if prior.group==-1 then
                        if job.observed.revision==1 then choose(index)
                        elseif not job.assigned and prior.alive==event.alive_count then assign(index,-1,0) end
                        return true
                    end
                end
                if not prior then assign(index,-1,0) else choose(index) end
                return true
            end
        end
        return false
    end
    function adapter.effect_result(event)
        if blocked then return false end
        for index,job in ipairs(jobs) do
            if job.request and event.request_key and event.request_key:matches(job.request) then
                if not current() or event.source_generation~=identity.source then return block("support_receipt_source_lost") end
                if event.outcome~="transport_staged" then return block("support_objective_refused") end
                job.request=nil; choose(index); return true
            end
        end
        return false
    end
    return adapter
end
