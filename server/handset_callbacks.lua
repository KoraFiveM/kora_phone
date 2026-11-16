-- The handset action route locks itself (it may change which handset is selected), so the gateway
-- does not wrap it in Handsets.locked.
KoraPhone.Routes.handle('handsetAction', function(src, payload)
    return KoraPhone.Handsets.locked(src, KoraPhone.Handsets.action, payload)
end)
