Config.Client = {
    Command = 'phone',
    Keybind = 'M',
    DisableWhileDead = true,
    NotificationSound = true -- the game's own text-message tone when the phone is closed
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
