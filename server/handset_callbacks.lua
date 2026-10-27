QBPhone.registerCallback('handsetAction','mutation',function(src,p)
    return QBPhone.Handsets.locked(src,QBPhone.Handsets.action,p)
end)
QBPhone.registerCallback('calls:videoControl','mutation',QBPhone.Services.Calling.videoControl)
