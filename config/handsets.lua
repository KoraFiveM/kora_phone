Config.Handsets = {
    phone = 'standard', -- legacy item: converted once, never stacked
    phone_standard = 'standard', phone_flip = 'flip', phone_fold = 'fold'
}
Config.SimItem = 'phone_sim'
Config.SimSwap = 'both' -- player | shop | both
-- Inserting a SIM moves its item into the phone (exactly one item leaves the inventory); removing it returns the
-- same item with its number. The inventory gateway does this; the phone re-checks it. Set false to skip the re-check.
Config.ConsumeSimOnInstall = true
Config.LaunchApps = { phone=true, contacts=true, messages=true, camera=true, gallery=true, gps=true,
    settings=true, mail=true, notes=true, calculator=true, clock=true, weather=true, music=true }
Config.PhoneServices = {
    -- Replace coordinates and business job names for your server.
    shops = {
        legion = { label='Circuit Mobile', coords={x=149.7,y=-1040.2,z=29.4}, distance=3.0,
            bucket=0, recoveryFee=500, replacementFee=100, resalePercent=50,
            prices={phone_standard=1200,phone_flip=1800,phone_fold=2400,phone_sim=100} },
        technician = { label='Mobile Workshop', coords={x=-40.1,y=-1090.7,z=26.4}, distance=3.0,
            bucket=0, job='mechanic', grade=0, recoveryFee=500, replacementFee=100, resalePercent=50,
            prices={phone_standard=1200,phone_flip=1800,phone_fold=2400,phone_sim=100} }
    },
    wifi = {
        legion = { label='Legion Public Wi-Fi', coords={x=215.8,y=-810.1,z=30.7}, radius=70, bucket=0 },
        workshop = { label='Workshop Private', coords={x=-40.1,y=-1090.7,z=26.4}, radius=25, bucket=0,
            passwordConvar='qbphone_workshop_wifi_password', ownerJob='mechanic' }
    }
}
