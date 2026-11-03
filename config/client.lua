Config.Client = {
    Command = 'phone',
    Keybind = 'M',
    DisableWhileDead = true,
    NotificationSound = true, -- the game's own text-message tone when the phone is closed
    -- Player state bag that keeps the phone shut while it is true. Another resource sets it while its own camera or
    -- editor is up (kora_emotemenu's Emote Maker freecam does); the phone then refuses to open (key, item, export,
    -- camera app) and closes if it was open. kora_inventory honours the same bag. false or '' turns this off.
    -- Read once at resource start.
    UiBlockBag = 'koraUiBlocked',
}

-- Camera app. The live preview needs the mouse for the phone UI, so aiming works through a key:
-- lookMode 'hold' aims while lookKey is held, 'toggle' switches aiming on and off with it, 'off' keeps the
-- camera fixed to where the player faces. lookKey is a default players can rebind in their key settings.
-- hint shows the on-screen help line while the camera is open.
-- zoom: the mouse wheel zooms the rear and selfie cameras, both with the phone cursor up and while aiming.
-- Values are the field of view in degrees (lower is closer). The camera opens at defaultFov and goes back to it
-- when it closes or flips between rear and selfie. smooth eases to each step (smoothSpeed: higher is quicker)
-- instead of jumping. selfie overrides minFov / maxFov / defaultFov for the selfie camera held at arm's length.
Config.Camera = {
    lookMode = 'hold', -- hold | toggle | off
    lookKey = 'LMENU', -- keyboard key name (LMENU = left Alt)
    hint = true,
    zoom = {
        enabled = true,
        minFov = 10.0,
        maxFov = 60.0,
        defaultFov = 60.0,
        step = 5.0, -- degrees per wheel notch
        smooth = true,
        smoothSpeed = 10.0,
        selfie = { minFov = 30.0, maxFov = 60.0 },
    },
}

-- Phone prop and animation while the phone is open. The player holds a phone and plays the texting pose
-- (the in-car pose when seated, the call pose during a call). The prop and pose go away when the phone
-- closes or the player dies, is cuffed, ragdolls or swims, and come back when that clears.
Config.Animation = {
    enabled = true, -- false: no prop and no animation, the phone just opens
    model = 'prop_npc_phone_02', -- prop held in the hand
    bone = 28422, -- bone index (28422 = PH_R_Hand) or a bone name
    offset = { x = 0.0, y = 0.0, z = 0.0 },
    rotation = { x = 0.0, y = 0.0, z = 0.0 },
    cancelOnRagdoll = true, -- drop the pose while ragdolling or falling over
    cancelOnWater = true, -- drop the pose while swimming
    -- flag defaults to 50 (upper body only, so the player can still move)
    anims = {
        text = { dict = 'cellphone@', clip = 'cellphone_text_read_base' },
        call = { dict = 'cellphone@', clip = 'cellphone_call_listen_base' },
        vehicleText = { dict = 'anim@cellphone@in_car@ps', clip = 'cellphone_text_read_base' },
        vehicleCall = { dict = 'anim@cellphone@in_car@ps', clip = 'cellphone_call_listen_base' },
    },
}
