RegisterNetEvent('kora_phone:client:openServices',function()
    SetNuiFocus(true,true)
    KoraPhone.SendNui('service:open',{})
end)
RegisterNetEvent('kora_phone:client:serviceRequest',function(data)
    SetNuiFocus(true,true)
    KoraPhone.SendNui('service:request',data)
end)
RegisterNetEvent('kora_phone:client:serviceResult',function(data) KoraPhone.SendNui('service:result',data) end)
CreateThread(function()
    for id,s in pairs(Config.PhoneServices.shops) do
        Kora.interact.addCircleZone('kora_phone:shop:'..id,vector3(s.coords.x,s.coords.y,s.coords.z),s.distance,
            {options={{label=s.label,event='kora_phone:client:openServices'}}},false)
    end
end)