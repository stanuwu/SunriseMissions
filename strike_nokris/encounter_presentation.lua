-- Completion presentation follows accepted mechanics. Unsafe boss cosmetics remain disabled.
local decimal=require("strike_nokris.identity_text").positive_decimal
local function positive(value) return math.type(value)=="integer" and value>0 end
return function(mission,controller)
    local region=mission.states.STATE_80F729E1_000B_0000_80F76DF7.region_index
    local source,held,identity,fenced
    local rows={}
    local retired=false
    local retirement_request
    -- complete_mission sets the activity-complete lifetime (MISSION COMPLETE); the client's own
    -- post-game chain runs from there. Sent once, after the chest object is transported.
    local lifetime={}
    local function status(context,key,value)
        -- One bounded Host key: latest transition followed by the owned row state.
        local parts={"P1",key,value}
        for _,row in ipairs(rows) do
            parts[#parts+1]=row.invalid and "i" or row.failed and "f" or row.request and "p"
                or row.submitted and (row.observed and "o" or row.staged and "t" or "s") or "-"
        end
        local value=table.concat(parts,"|")
        assert(#value<=127,"presentation diagnostic exceeds Host string capacity")
        context:set_variable("nokris.presentation",value)
    end
    local function add(symbol,kind,index,key,phase,member)
        local row={symbol=symbol,kind=kind,index=index,key=key,phase=phase,member=member,
            desired=false,submitted=false,staged=false}
        rows[#rows+1]=row; return row
    end
    local chest=add("STRIKE_CHEST_HIVE_O_CHEST",4,0,"chest")
    local function binding(context,row)
        local symbol=mission.Slot[row.symbol]
        if not symbol then return end
        local slot=context:slot(symbol)
        local object=row==chest and 0x80F7354E or 0x80F732CE
        if slot.object_tag~=object or slot.slot_type~=row.kind or slot.slot_index~=row.index
            or slot.registry_key~=(row==chest and 0x71A28D90 or 0xC55749AB) then return end
        return slot
    end
    local function submit(context,row)
        if row.request or row.invalid or row.desired==row.submitted then return end
        if row.failed and row.desired then return end
        local ok,request=pcall(function()
            local slot=binding(context,row)
            if not slot then return end
            return slot:set_object_active{active=row.desired}
        end)
        if not ok or not request then
            row.failed=true; status(context,row.key,"submission_refused"); return
        end
        row.request=request; row.submitted=row.desired; row.staged=false
        status(context,row.key,row.desired and "activation_pending" or "clear_pending")
    end
    local function observe(context,event)
        if event.source_generation~=source or event.slot_type~=4
            or not positive(event.generation) or not positive(event.sense_generation)
            or math.type(event.entry_index)~="integer" or event.entry_index<0
            or type(event.alive)~="boolean" or type(event.present)~="boolean" then return end
        for _,row in ipairs(rows) do
            local object=row==chest and 0x80F7354E or 0x80F732CE
            if row.kind==4 and row.submitted and event.object_tag==object and event.slot_index==row.index
                and event.registry_key==(row==chest and 0x71A28D90 or 0xC55749AB) then
                if row.activation and (row.entry~=event.entry_index or row.activation~=event.generation
                    or event.sense_generation<row.counter) then
                    row.invalid=true; status(context,row.key,"identity_lost")
                else
                    row.entry=event.entry_index; row.activation=event.generation; row.counter=event.sense_generation
                    row.observed=event.alive and event.present
                    if row.staged then status(context,row.key,row.observed and "observed" or "inactive") end
                end
            end
        end
    end
    local function advance(context,state)
        local view=controller.boss_status and controller.boss_status()
        local model=view and view.model
        if not model or not view.encounter_owned or held~=region or not decimal(source) then return end
        if identity and (model.source~=identity.source or model.epoch~=identity.epoch or model.boss~=identity.boss) then
            fenced=true; status(context,"presentation","identity_lost"); return
        end
        if not identity then
            identity={source=model.source,epoch=model.epoch,boss=model.boss}
            status(context,"presentation","completion_owned")
        end
        if model.source~=source then return end
        local running=not view.blocked and state:variable("route.invalidated")~=true
        chest.desired=running and model.stage=="complete"
        if running and (model.stage=="result" or model.stage=="complete") and not retired then
            retired=true
            local ok,request=pcall(function()
                return context:slot(mission.Slot.OBJ_NOKRIS_MAIN_LOOP):reset_objectives{}
            end)
            retirement_request=ok and request or nil
            status(context,"objectives",ok and request and "retirement_submitted" or "retirement_refused")
        end
        for _,row in ipairs(rows) do submit(context,row) end
        if running and model.stage=="complete" and chest.staged and not lifetime.submitted then
            lifetime.submitted=true
            local ok,request=pcall(function()
                return context:complete_mission{}
            end)
            if ok and request then lifetime.request=request; status(context,"lifetime","pending")
            else status(context,"lifetime","submission_refused") end
        end
    end
    for _,name in ipairs{"on_event_client_state_changed","on_event_squad_state",
        "on_event_object_state","on_event_effect_result","on_event_native_reaction","on_event_damage_state",
        "on_load"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            if previous then previous(context,state,event) end
            if name=="on_load" then
                if state:variable("nokris.presentation") then fenced=true; status(context,"presentation","interrupted") end
                return
            end
            if name=="on_event_client_state_changed" then
                if identity and (source~=event.source_generation or event.held_region_index~=region) then
                    -- The departed occurrence owns its cleanup. Never replay a clear into its replacement.
                    rows={}; identity=nil; fenced=true; status(context,"presentation","exited")
                end
                source,held=event.source_generation,event.held_region_index
            end
            if fenced or held~=region then return end
            if name=="on_event_effect_result" then
                if retirement_request and event.request_key and event.request_key:matches(retirement_request)
                    and event.source_generation==source then
                    retirement_request=nil
                    status(context,"objectives",event.outcome=="transport_staged" and "retired" or "retirement_refused")
                end
                if lifetime.request and event.request_key and event.request_key:matches(lifetime.request)
                    and event.source_generation==source then
                    lifetime.request=nil
                    status(context,"lifetime",event.outcome=="transport_staged" and "transport_staged" or "refused")
                end
                for _,row in ipairs(rows) do
                    if row.request and event.request_key and event.request_key:matches(row.request) then
                        if event.source_generation~=source then return end
                        row.request=nil
                        if event.outcome=="transport_staged" then
                            row.staged=true
                            status(context,row.key,row.submitted and (row.observed and "observed" or "transport_staged") or "cleared")
                        else row.failed=true; status(context,row.key,"transport_refused") end
                    end
                end
            elseif name=="on_event_object_state" then observe(context,event) end
            advance(context,state)
        end
    end
    return controller
end
