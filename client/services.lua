RegisterNetEvent('qbphone:client:openServices',function()
    SetNuiFocus(true,true)
    QBPhone.SendNui('service:open',{})
end)
RegisterNetEvent('qbphone:client:serviceRequest',function(data)
    SetNuiFocus(true,true)
    QBPhone.SendNui('service:request',data)
end)
RegisterNetEvent('qbphone:client:serviceResult',function(data) QBPhone.SendNui('service:result',data) end)
CreateThread(function()
    for id,s in pairs(Config.PhoneServices.shops) do
        Kora.interact.addCircleZone('qbphone:shop:'..id,vector3(s.coords.x,s.coords.y,s.coords.z),s.distance,
            {options={{label=s.label,event='qbphone:client:openServices'}}},false)
    end
end)
