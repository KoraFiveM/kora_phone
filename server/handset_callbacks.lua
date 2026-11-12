KoraPhone.registerCallback('handsetAction','mutation',function(src,p)
    return KoraPhone.Handsets.locked(src,KoraPhone.Handsets.action,p)
end)
KoraPhone.registerCallback('calls:videoControl','mutation',KoraPhone.Services.Calling.videoControl)