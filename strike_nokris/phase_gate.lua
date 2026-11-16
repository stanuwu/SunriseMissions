-- The native health onset holds damage. Release receipts acknowledge the local gate operation.
return function(mission,model,context,state,prefix)
    local current,request,blocked,reason
    local region=mission.states.STATE_80F729E1_000B_0000_80F76DF7.region_index
    local function block(value) blocked,reason=true,value; return false end
    local adapter={}
    function adapter.view()
        local view=model.view()
        return {source=view.source,epoch=view.epoch,boss=view.boss,phase=current and current.phase,
            transaction=current and current.transaction,active=current and current.active,
            status=blocked and "blocked" or current and current.status,reason=reason,
            native_accepted=current and current.native_accepted}
    end
    function adapter.sync()
        if blocked then return false end
        local view,command=model.view(),model.output()
        if not command or (command.kind~="activate_phase" and command.kind~="release_phase") then return false end
        local active=command.kind=="activate_phase"
        if current and current.transaction==command.transaction then return true end
        if current and (current.status~="transport_staged" or current.active==active
            or command.phase~=(active and current.phase+1 or current.phase)) then return block("gate_command_order") end
        if not current and (not active or command.phase~=1) then return block("gate_initial_phase") end
        current={transaction=command.transaction,phase=command.phase,active=active,
            status=active and "transport_staged" or "pending",native_accepted=false}
        request=nil
        if not active then
            request=assert(context:release_native_phase{phase=command.phase,spawn_generation=view.boss},
                "native phase release requires an owned request")
        end
        return true
    end
    function adapter.client_state(event)
        local view=model.view()
        if event.source_generation~=view.source or event.held_region_index~=region then
            return block("gate_held_or_source_lost")
        end
        return true
    end
    function adapter.squad_state() return true end -- The enclosing controller owns boss continuity.
    function adapter.effect_result(event)
        if blocked or not request or not event.request_key or not event.request_key:matches(request) then return false end
        if event.source_generation~=model.view().source then return block("gate_receipt_source_lost") end
        if event.outcome~="transport_staged" then return block("native_gate_release_refused") end
        -- This action emits its receipt only after the native owner accepts Gate::release.
        current.status="transport_staged"; current.native_accepted=true
        return true
    end
    return adapter
end
