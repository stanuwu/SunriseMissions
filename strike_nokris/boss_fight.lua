-- Intro admits the model; an explicitly supplied native provider owns mechanical admissions.
local record=require("strike_nokris.state_record")
local flow_schema=record.schema("B1",{{name="ordinal",kind="integer"},{name="host_sequence",kind="string",limit=20}})
local phases=require("strike_nokris.phase_plan")
local function positive(value) return math.type(value)=="integer" and value>0 end
local decimal=require("strike_nokris.identity_text").positive_decimal
local function after(value,prior) return #value>#prior or (#value==#prior and value>prior) end
local semantic_fields={"actors_retired","cause","checkpoint","crystal","generation","immunity_removed",
    "intro_staged","member","new_boss","new_epoch","new_source","outcome","phase","relics_retired",
    "scenes_retired","success","support_retired","transaction"}

-- An optional provider consumes authenticated native ingress; SDK metadata cannot enable phases.
return function(mission,objective,controller,provider)
    local region=assert(mission.states.STATE_80F729E1_000B_0000_80F76DF7).region_index
    local flow_key,status_key="nokris.control","nokris.capability"
    local initialized,model,activation,attachment,support,carriers,held,source,boss,fenced,terminal
    local captured_boss_recovery,captured_observed_recovery
    -- This only closes combat callbacks. It cannot grant death/terminal authority. Retained
    -- model keys already fence reload, so this incarnation-local latch needs no additional key.
    local combat_closed=false
    local opening_population_pending=false
    local control={ordinal=0,host_sequence="0"}
    local function status(context,value) context:set_variable(status_key,value) end
    local function stop(context,reason)
        fenced=true; boss=nil
        if model then model.invalidate(reason) end
        context:set_variable("route.invalidated",true)
        status(context,reason); return false
    end
    local function available(kind) return provider and provider.supports(kind)==true end
    local function emit(context,kind,fields,external)
        if fenced then return false end
        if control.ordinal==math.maxinteger then return stop(context,"semantic_sequence_exhausted") end
        local view=model.view()
        local event={kind=kind,source=view.source,epoch=view.epoch,boss=view.boss}
        for _,key in ipairs(semantic_fields) do
            if fields and fields[key]~=nil then event[key]=fields[key] end
        end
        if external and (not fields or fields.source~=view.source or fields.epoch~=view.epoch or fields.boss~=view.boss) then
            return stop(context,"foreign_native_semantic_identity")
        end
        control.ordinal=control.ordinal+1
        event.sequence=tostring(control.ordinal) -- Local semantic ordinal, never represented as a Host sequence.
        record.write(context,flow_key,flow_schema,control)
        local accepted,reason=model.observe(event)
        if not accepted then return stop(context,"semantic_"..tostring(reason)) end
        return true
    end
    local function adapters_ok(context)
        if model.view().stage=="blocked" then return stop(context,model.view().reason or "model_invalidated") end
        if activation then
            for _,adapter in ipairs{activation,attachment,support,carriers} do
                local view=adapter.view()
                if view.blocked or view.status=="blocked" then return stop(context,view.reason or "phase_adapter_invalidated") end
            end
        end
        return true
    end
    local function construct_adapters(context,state)
        if activation then return end
        activation=require("strike_nokris.phase_activation")(mission,model,context,state,"activate",phases)
        local attachment_module=provider and provider.encounter_owned and "strike_nokris.phase_gate"
            or "strike_nokris.phase_attachment"
        attachment=require(attachment_module)(mission,model,context,state,"phase_attachment")
        support=require("strike_nokris.phase_support")(mission,model,activation,objective,context,state,"phase_support",phases)
        carriers=require("strike_nokris.phase_carriers")(mission,model,activation,support,objective,context,state,"phase_carriers",phases)
        local event={source_generation=source,held_region_index=held}
        for _,adapter in ipairs{activation,attachment,support,carriers} do adapter.client_state(event) end
        attachment.squad_state(boss)
    end
    local function advance(context,state)
        if fenced or not model or not adapters_ok(context) then return end
        if opening_population_pending then status(context,"awaiting_boss_population"); return end
        local command=model.output()
        if terminal and (not command or terminal.transaction~=command.transaction) then
            if not terminal.staged then stop(context,"terminal_output_not_settled"); return end
            terminal=nil
        end
        if command then
            if command.kind=="activate_phase" then
                for _,capability in ipairs{"phase_onset","shield_ready","phase_released"} do
                    if not available(capability) then stop(context,"unsupported_"..capability); return end
                end
                if command.phase>1 then
                    local old=support and support.view()
                    local prior=carriers and carriers.view()
                    if not old or (old.phase~=command.phase and not old.frozen)
                        or not prior or (prior.phase~=command.phase and (not prior.frozen or prior.pending)) then
                        stop(context,"prior_phase_not_settled"); return
                    end
                end
                construct_adapters(context,state)
                if not adapters_ok(context) then return end
                activation.sync(); if not adapters_ok(context) then return end
                attachment.sync(); if not adapters_ok(context) then return end
                support.sync(); carriers.sync()
            elseif command.kind=="release_phase" then
                if not available("phase_released") then stop(context,"unsupported_phase_released"); return end
                if not support.freeze() or not carriers.freeze() then status(context,"awaiting_phase_settlement"); return end
                attachment.sync()
            elseif command.kind=="replace_carrier" then
                if not available("relic_lost") then stop(context,"unsupported_relic_lost"); return end
                carriers.sync()
            else
                -- Local completion is validated by the native defeat owner. Other providers must
                -- return an owned request handle; delivery remains separate from acceptance.
                local terminal_kind=command.kind=="publish_result"
                local local_result=provider and provider.encounter_owned and command.kind=="publish_result"
                if not terminal_kind or not available(command.kind) or (not local_result and type(provider.submit)~="function") then
                    stop(context,"unsupported_"..command.kind); return
                end
                if not terminal then
                    local copy={kind=command.kind,transaction=command.transaction,phase=command.phase,
                        checkpoint=command.checkpoint,source=model.view().source,epoch=command.epoch,
                        host_sequence=control.host_sequence}
                    local request=local_result and context:complete_native_encounter{spawn_generation=model.view().boss}
                        or provider.submit(copy)
                    if not request then stop(context,"terminal_command_not_submitted"); return end
                    terminal={request=request,transaction=command.transaction,source=copy.source,epoch=copy.epoch,staged=false}
                end
                status(context,"awaiting_"..command.kind.."_acceptance"); return
            end
            if not adapters_ok(context) then return end
            local transported=false
            local function receipt(view)
                return view.source==model.view().source and view.epoch==command.epoch and view.phase==command.phase
                    and view.transaction==command.transaction
            end
            if command.kind=="activate_phase" then
                local batch,shield=activation.view(),attachment.view()
                transported=receipt(batch) and receipt(shield) and batch.status=="transport_staged" and shield.status=="transport_staged"
            elseif command.kind=="release_phase" then
                local shield=attachment.view()
                transported=receipt(shield) and shield.active==false and shield.status=="transport_staged"
                    and support.view().frozen and support.view().settled and carriers.view().frozen and not carriers.view().pending
            else
                local replacement=carriers.view(); transported=receipt(replacement) and replacement.transported
            end
            if transported and not command.transported then
                if not emit(context,"transport",{transaction=command.transaction,outcome="transport_staged"}) then return end
            end
        end
        if carriers and model.view().stage=="shield" then
            -- Carrier placement is deferred past activation; give the adapter its chance each event.
            carriers.sync(); if not adapters_ok(context) then return end
            for member=1,2 do
                local ready=carriers.carrier(member)
                -- A Knight killed before its objective receipt still owns the relic; register its
                -- generation so the crystal consumption is not refused as a foreign lifetime.
                local observed=ready and (ready.ready or ready.alive==0) and ready.generation
                -- The model itself deduplicates a matching generation. A local cache avoids extra semantic events.
                local key="ready"..member
                if observed and control[key]~=observed then
                    local pending=model.output()
                    if not emit(context,"carrier_ready",{phase=model.view().phase,member=member,generation=observed,
                        transaction=pending and pending.transaction}) then return end
                    control[key]=observed
                end
            end
        end
        if model.view().stage=="opening_damage" or model.view().stage=="damage" then
            status(context,available("phase_onset") and "awaiting_phase_input" or "awaiting_native_phase_input")
        elseif model.view().stage=="shield" and not available("crystal_consumed") then
            status(context,"awaiting_native_crystal_consumption")
        elseif model.view().stage=="complete" then status(context,"model_complete")
        elseif provider and provider.encounter_owned and model.view().stage=="shield" then
            local consumed=model.view().consumed
            status(context,consumed==0 and "awaiting_both_crystals" or consumed==1 and "awaiting_crystal_two" or "awaiting_crystal_one")
        elseif provider and provider.encounter_owned and model.view().stage=="releasing" then
            status(context,"awaiting_native_gate_release")
        elseif not fenced then status(context,"awaiting_"..model.view().stage.."_input") end
    end
    local function semantic(context,state,event,callback)
        if not provider or not model or fenced then return end
        for pass=1,8 do
            local inputs,reason=provider.read(pass==1 and event or {},controller.boss_status(),pass==1 and callback or "settle")
            if reason then stop(context,reason); return end
            inputs=inputs or {}
            assert(type(inputs)=="table" and #inputs<=8,"bounded semantic provider batch required")
            if #inputs==0 then return end
            for _,input in ipairs(inputs) do
                local authority={phase_onset=true,shield_ready=true,crystal_consumed=true,relic_lost=true,
                    phase_released=true,boss_defeated=true,wipe=true,retirement_accepted=true,reset_accepted=true,
                    checkpoint_ready=true,boss_ready=true,result_accepted=true}
                if type(input)~="table" or not authority[input.kind] then stop(context,"unexpected_native_input"); return end
                if not available(input.kind) then stop(context,"unsupported_"..tostring(input.kind)); return end
                if input.kind=="phase_released" and (not support or not support.view().frozen
                    or not support.view().settled or not carriers.view().frozen or carriers.view().pending) then
                    stop(context,"native_release_before_settlement"); return
                end
                if input.kind=="phase_onset" then control.ready1,control.ready2=nil,nil end
                if not emit(context,input.kind,input,true) then return end
                if input.kind=="boss_defeated" then combat_closed=true end
                advance(context,state)
                if fenced then return end
            end
            if not provider.encounter_owned then return end
        end
        stop(context,"semantic_settlement_did_not_quiesce")
    end
    local function qualified_boss(event)
        return event.object_tag==0x80F732CE and event.registry_key==0xC55749AB and event.slot_type==1 and event.slot_index==0
    end
    controller.boss_status=function()
        local pending=model and model.output()
        return {initialized=model~=nil,blocked=fenced==true,model=model and model.view(),
            boss_population_available=boss~=nil and positive(boss.alive_count),
            encounter_owned=provider and provider.encounter_owned==true,
            command=pending and {kind=pending.kind,transaction=pending.transaction,phase=pending.phase,
                member=pending.member,transported=pending.transported},
            activation=activation and activation.view(),attachment=attachment and attachment.view(),
            support=support and support.view(),carriers=carriers and carriers.view(),
            carrier_one=carriers and carriers.carrier(1),carrier_two=carriers and carriers.carrier(2),
            ready_one=control.ready1,ready_two=control.ready2}
    end
    for _,name in ipairs{"on_start","on_load","on_event_client_state_changed","on_event_squad_state",
        "on_event_object_state","on_event_effect_result","on_event_player_trigger",
        "on_event_trigger_entered","on_event_trigger_exited","on_event_trigger_state",
        "on_event_native_reaction"} do
        local previous=controller[name]
        controller[name]=function(context,state,event)
            if not initialized then
                initialized=true
                local recovery_flow=state:variable("directive.flow")
                local retained={flow_key,status_key,"finish.identity","finish.flow","finish.pending","finish.carriers","finish.reason",
                    "activate.batch","activate.mask","activate.reason","phase_attachment.identity","phase_attachment.flow","phase_attachment.reason",
                    "phase_support.identity","phase_support.reason","phase_carriers.identity","phase_carriers.flow","phase_carriers.reason"}
                for index=1,6 do retained[#retained+1]="phase_support.row"..index end
                for index=1,2 do retained[#retained+1]="phase_carriers.row"..index end
                local recovery_sequence=type(recovery_flow)=="string"
                    and string.sub(recovery_flow,1,15)=="D2|8|none|88|2|"
                    and string.sub(recovery_flow,-18)=="|127|active|0|none"
                    and string.sub(recovery_flow,16,#recovery_flow-18)
                local unarmed_sequence=type(recovery_flow)=="string"
                    and string.sub(recovery_flow,1,15)=="D2|9|none|88|2|"
                    and string.sub(recovery_flow,-18)=="|511|active|0|none"
                    and string.sub(recovery_flow,16,#recovery_flow-18)
                local captured_unarmed_recovery=name=="on_load" and decimal(unarmed_sequence)
                    and after(unarmed_sequence,"6255")
                    and state:variable("nokris.recovery")=="awaiting_client_state"
                    and state:variable("prefight.entry")=="arrived"
                    and state:variable("later.prefight.reason")=="clearance_observed"
                    and state:variable("later.boss_entry.status")=="running"
                    and state:variable("nokris.chant")=="transport_staged"
                    and state:variable("nokris.intro")=="transport_staged"
                    and (state:variable(status_key)==nil
                        or state:variable(status_key)=="awaiting_phase_input"
                        or state:variable(status_key)=="retained_boss_requires_reconciliation")
                    and (state:variable(flow_key)~=nil or state:variable(status_key)==nil)
                local portal_suffix="|255|active|0|none"
                local portal_sequence=type(recovery_flow)=="string"
                    and string.sub(recovery_flow,1,15)=="D2|8|none|88|2|"
                    and string.sub(recovery_flow,-#portal_suffix)==portal_suffix
                    and string.sub(recovery_flow,16,#recovery_flow-#portal_suffix)
                local portal_observed_recovery=name=="on_load" and decimal(portal_sequence)
                    and after(portal_sequence,"4236")
                    and state:variable("prefight.entry")=="blocked"
                    and state:variable("later.prefight.status")=="blocked"
                    and state:variable("later.prefight.reason")=="clearance_observed"
                    and state:variable("later.boss_entry.entered")==true
                    and state:variable("later.boss_entry.status")=="running"
                    and state:variable("nokris.chant")=="transport_staged"
                    and state:variable("nokris.intro")=="transport_staged"
                    and state:variable("nokris.capability")==nil and state:variable("nokris.control")==nil
                    and state:variable("route.invalidated")==true
                captured_observed_recovery=portal_observed_recovery or (name=="on_load" and type(recovery_flow)=="string"
                    and string.sub(recovery_flow,1,15)=="D2|9|none|88|2|"
                    and string.sub(recovery_flow,-18)=="|511|active|0|none"
                    and decimal(string.sub(recovery_flow,16,#recovery_flow-18))
                    and after(string.sub(recovery_flow,16,#recovery_flow-18),"7969")
                    and state:variable("nokris.recovery")=="reattach_observed_boss"
                    and state:variable(flow_key)==nil and state:variable(status_key)==nil)
                captured_boss_recovery=captured_observed_recovery or captured_unarmed_recovery or (name=="on_load"
                    and decimal(recovery_sequence) and after(recovery_sequence,"5471")
                    and state:variable("prefight.entry")=="blocked"
                    and state:variable("later.prefight.status")=="blocked"
                    and state:variable("later.prefight.reason")=="clearance_observed"
                    and state:variable("later.boss_entry.entered")==true
                    and state:variable("later.boss_entry.status")=="running"
                    and state:variable("nokris.chant")=="transport_staged"
                    and state:variable("route.invalidated")==true
                    and state:variable(flow_key)==nil and state:variable(status_key)==nil)
                if captured_unarmed_recovery then
                    for _,key in ipairs(retained) do context:clear_variable(key) end
                    context:clear_variable("nokris.intro")
                    context:set_variable("nokris.recovery","awaiting_client_state")
                    -- Prevent inner entry owners from placing before the replacement VM has
                    -- received the client-state event that arms native observation ownership.
                    context:set_variable("later.prefight.status","blocked")
                end
                if captured_boss_recovery then held,source=region,"2" end
                for _,key in ipairs(retained) do
                    if state:variable(key)~=nil then stop(context,"retained_boss_requires_reconciliation"); break end
                end
            end
            if model and (name=="on_start" or name=="on_load") then stop(context,"retained_boss_requires_reconciliation") end
            if event and name=="on_event_client_state_changed" then
                if model and (event.source_generation~=source or event.held_region_index~=region) then stop(context,"boss_held_or_source_lost") end
                if event.source_generation~=source or event.held_region_index~=held then boss=nil end
                held,source=event.held_region_index,event.source_generation
            end
            if event and name=="on_event_squad_state" and qualified_boss(event) then
                local valid=held==region and event.source_generation==source and decimal(source)
                    and positive(event.spawn_generation) and positive(event.sense_generation)
                    and event.population_available==true and math.type(event.alive_count)=="integer" and event.alive_count>=0
                    and not (event.registration_reset and (boss or model))
                local stage=model and model.view().stage
                -- Initial task selection can transiently empty this same squad. Keep the
                -- opening model, but require fresh living evidence before native onset emits.
                local opening_wait=boss and provider and provider.encounter_owned
                    and stage=="opening_damage" and model.view().phase==0 and not activation
                local final=stage=="final_damage" or stage=="result" or stage=="complete"
                    or (provider and provider.encounter_owned and stage=="releasing" and model.view().phase==3
                        and attachment and attachment.view().active==false)
                -- The third gate can be released before its receipt reaches Lua. Retain a zero
                -- population in that window; only the exact native death event can award success.
                if event.alive_count==0 and (not boss or (not final and not opening_wait)) then valid=false end
                if boss and (event.spawn_generation~=boss.spawn_generation or event.sense_generation<boss.sense_generation
                    or (event.sense_generation==boss.sense_generation and event.alive_count~=boss.alive_count)
                    or (boss.alive_count==0 and event.alive_count~=0 and not opening_population_pending)) then valid=false end
                if not valid then
                    boss=nil; if model then stop(context,"boss_lifetime_unavailable") end
                else
                    opening_population_pending=opening_wait and event.alive_count==0 or false
                    if event.alive_count==0 and final then combat_closed=true end
                    boss={object_tag=event.object_tag,registry_key=event.registry_key,slot_type=1,slot_index=0,
                        source_generation=source,spawn_generation=event.spawn_generation,sense_generation=event.sense_generation,
                        population_available=true,alive_count=event.alive_count}
                end
            end
            if previous and not combat_closed and not fenced
                and not (opening_population_pending and name=="on_event_squad_state" and qualified_boss(event)) then
                previous(context,state,event)
            end
            if captured_boss_recovery and not fenced then
                -- Earlier controllers deliberately fence retained reloads. This exact diagnostic
                -- restores only the captured boss prerequisites after they run; a new living
                -- boss observation and native phase semantics still own progression.
                context:clear_variable("route.invalidated")
                context:set_variable("prefight.entry","arrived")
                context:set_variable("later.prefight.status","population_zero")
                context:set_variable("later.prefight.reason","clearance_observed")
                if captured_observed_recovery then
                    context:set_variable("nokris.intro","transport_staged")
                    context:set_variable("later.boss_entry.status","running")
                elseif boss then context:set_variable("later.boss_entry.status","running") end
            end
            if fenced then return end
            if model and (state:variable("route.invalidated")==true or state:variable("later.boss_entry.status")=="blocked") then
                stop(context,"boss_route_invalidated"); return
            end
            if not model then
                if not boss or state:variable("nokris.intro")~="transport_staged"
                    or state:variable("later.boss_entry.status")~="running" or state:variable("route.invalidated")==true then return end
                -- Epoch1 identifies this local model incarnation, not a native checkpoint reset.
                model=require("strike_nokris.finish_model")(context,state,"finish",
                    {source=source,epoch=1,boss=boss.spawn_generation,local_completion=provider and provider.encounter_owned},phases)
            end
            if not event or not decimal(event.mission_sequence) then stop(context,"missing_causal_host_sequence"); return end
            -- A causal Host watermark is not a producer replay fence. Native capture/attachment
            -- counters and squad/object generations below own observation admission, including
            -- sibling events and delayed observations from independent producers. Receipts are
            -- admitted by their owned requests and must never move the observation watermark.
            local newer=after(event.mission_sequence,control.host_sequence)
            if event.source_generation~=source then stop(context,"foreign_causal_host_source"); return end
            if newer and name~="on_event_effect_result" then
                control.host_sequence=event.mission_sequence
                record.write(context,flow_key,flow_schema,control)
            end
            if terminal and name=="on_event_effect_result" and event.request_key and event.request_key:matches(terminal.request) then
                local command=model.output()
                if not command or command.transaction~=terminal.transaction or model.view().source~=terminal.source
                    or model.view().epoch~=terminal.epoch then stop(context,"terminal_receipt_identity_lost"); return end
                if event.outcome~="transport_staged" then stop(context,"terminal_transport_refused"); return end
                if not terminal.staged then
                    if not emit(context,"transport",{transaction=terminal.transaction,outcome="transport_staged"}) then return end
                    terminal.staged=true
                end
            end
            if activation then
                local method=name=="on_event_client_state_changed" and "client_state"
                    or (name=="on_event_squad_state" and "squad_state") or (name=="on_event_effect_result" and "effect_result")
                if method then
                    for _,adapter in ipairs{activation,attachment,support,carriers} do
                        if adapter[method] then adapter[method](event) end
                        if not adapters_ok(context) then return end
                    end
                end
            end
            advance(context,state)
            semantic(context,state,event,name)
        end
    end
    return controller
end
