-- Normal-solo health-gate authority and continuous crystal observations; no shield-child dependency.
local phases=require("strike_nokris.phase_plan")
local decimal=require("strike_nokris.identity_text").positive_decimal
local function positive(value) return math.type(value)=="integer" and value>0 end
local function after(a,b) return #a>#b or (#a==#b and a>b) end

return function()
    local phase,crystals=0,{}
    local consumption_candidates,emitted_consumption={},{}
    local emitted_link,emitted_remove=false,false
    local pending_phase,pending_death
    local last_capture="0"
    local capabilities={phase_onset=true,shield_ready=true,crystal_consumed=true,phase_released=true,
        boss_defeated=true,publish_result=true,result_accepted=true}
    local provider={encounter_owned=true,supports=function(kind) return capabilities[kind]==true end}
    function provider.read(event,status,callback)
        local model=status and status.model
        if not model or not event then return {} end
        local function input(kind,fields)
            local value={kind=kind,source=model.source,epoch=model.epoch,boss=model.boss,phase=phase}
            if fields then
                value.transaction=fields.transaction
                value.member=fields.member
                value.generation=fields.generation
                value.crystal=fields.crystal
                value.support_retired=fields.support_retired
                value.immunity_removed=fields.immunity_removed
                value.cause=fields.cause
                value.success=fields.success
            end
            return value
        end
        local function onset(next_phase)
            phase=next_phase; crystals={}; pending_phase=nil
            consumption_candidates,emitted_consumption={},{}
            emitted_link,emitted_remove=false,false
            return input("phase_onset")
        end
        if callback=="on_event_native_reaction" then
            if event.source_generation~=model.source or event.spawn_generation~=model.boss
                or not decimal(event.capture_sequence) or not after(event.capture_sequence,last_capture) then
                return nil,"native_phase_identity_or_sequence_lost"
            end
            last_capture=event.capture_sequence
            if event.native_admission=="reaction" then
                -- Legacy raw toggles carry no synchronous floor admission and cannot start mechanics.
                if event.health_phase==0 then return {} end
                local expected=model.phase+1
                if event.health_phase~=expected or expected>3 or pending_phase then
                    return nil,"native_health_phase_order"
                end
                if model.stage=="releasing" and status.attachment and status.attachment.active==false then
                    -- Native damage can resume before Lua receives the completed release operation.
                    pending_phase=expected
                elseif model.stage=="opening_damage" and status.boss_population_available==false then
                    -- Retain the authenticated onset, not a timer or a manufactured phase.
                    pending_phase=expected
                elseif model.stage=="opening_damage" or model.stage=="damage" then
                    return {onset(expected)}
                else return nil,"native_health_phase_order" end
            elseif event.native_admission=="boss_defeated" then
                if model.stage=="complete" then return {} end
                if model.stage=="releasing" and model.phase==3 and event.health_phase==3
                    and status.attachment and status.attachment.active==false then
                    pending_death=true; return {}
                end
                if model.stage~="final_damage" or event.health_phase~=3 then return nil,"native_death_before_final_phase" end
                return {input("boss_defeated",{cause="normal_death"})}
            else return nil,"unknown_native_phase_admission" end
        end
        if pending_phase and (model.stage=="damage" or (model.stage=="opening_damage"
            and status.boss_population_available==true)) then return {onset(pending_phase)} end
        if pending_death and model.stage=="final_damage" then
            pending_death=nil
            return {input("boss_defeated",{cause="normal_death"})}
        end
        if phase==0 or model.phase~=phase then return {} end
        if callback=="on_event_object_state" and event.object_tag==0x80F732CE
            and event.registry_key==0xC55749AB and event.slot_type==4 then
            for member,slot in ipairs(phases[phase].crystals) do
                if event.slot_index==slot then
                    local prior=crystals[member]
                    if event.source_generation~=model.source or not positive(event.sense_generation)
                        or math.type(event.entry_index)~="integer" or event.entry_index<0
                        or not positive(event.generation) or type(event.alive)~="boolean"
                        or type(event.present)~="boolean" then return nil,"native_phase_crystal_identity" end
                    if not prior and (not event.alive or not event.present) then return {} end
                    if prior and (event.entry_index~=prior.entry or event.generation~=prior.activation
                        or event.sense_generation<prior.counter
                        or (event.sense_generation==prior.counter and (event.alive~=prior.live or event.present~=prior.spawned))
                        or (prior.inactive and (event.alive or event.present))) then
                        return nil,"native_phase_crystal_lifetime_lost"
                    end
                    local inactive=not event.alive and not event.present
                    local active=(prior and prior.active==true) or (event.alive and event.present)
                    crystals[member]={entry=event.entry_index,activation=event.generation,
                        counter=event.sense_generation,live=event.alive,spawned=event.present,
                        active=active,inactive=inactive}
                    if active and inactive and (not prior or not prior.inactive) then
                        local carrier=member==1 and status.carrier_one or status.carrier_two
                        if type(carrier)~="table" or not positive(carrier.generation)
                            or math.type(carrier.alive)~="integer" or carrier.alive<0 then
                            return nil,"native_phase_crystal_carrier_identity"
                        end
                        consumption_candidates[member]={generation=carrier.generation,crystal=slot}
                    end
                end
            end
        end
        if model.stage=="shield" then
            local consumed={}
            for member=1,2 do
                local candidate=consumption_candidates[member]
                local carrier=member==1 and status.carrier_one or status.carrier_two
                if candidate and not emitted_consumption[member] and type(carrier)=="table" then
                    if carrier.generation~=candidate.generation then
                        return nil,"native_phase_crystal_carrier_lifetime_lost"
                    end
                    if carrier.alive==0 then
                        emitted_consumption[member]=true
                        consumed[#consumed+1]=input("crystal_consumed",{member=member,
                            generation=candidate.generation,crystal=candidate.crystal})
                    end
                end
            end
            if #consumed>0 then return consumed end
        end
        local command=status.command
        if model.stage=="result" and command and command.transported then
            return {input("result_accepted",{transaction=command.transaction,success=true})}
        end
        if model.stage=="activating" and not emitted_link and command and command.transported then
            emitted_link=true
            return {input("shield_ready",{transaction=command.transaction})}
        end
        -- This receipt means the native gate operation completed, not just that a packet was sent.
        if model.stage=="releasing" and status.attachment and status.attachment.native_accepted
            and not emitted_remove and command and command.transported
            and status.support and status.support.frozen and status.support.settled
            and status.carriers and status.carriers.frozen and not status.carriers.pending then
            emitted_remove=true
            local release=input("phase_released",{transaction=command.transaction,support_retired=true,immunity_removed=true})
            if pending_phase then return {release,onset(pending_phase)} end
            return {release}
        end
        return {}
    end
    return provider
end
