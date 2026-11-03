-- Registers the shared and client settings (config/shared.lua, handsets.lua, client.lua) with kora_lib so the
-- owner can edit them in /config; edits are saved to config.local.lua, never to these files. The server-only
-- settings are registered at the end of config/server.lua so they never reach a client.
if Kora and Kora.config and Kora.config.adopt then
    Config = Kora.config.adopt(Config, { descriptions = {
        ['compat.koraPhoneExports.enabled'] = 'Also answer the legacy kora_phone exports (sendMailToOffline, sendMail, sendMessage, getNumber, getNumberByCitizenId, hasPhone and the client open, close and isOpen), so resources written for kora_phone keep working. Turn off only if nothing calls them. Restart this resource to apply. Never run it together with the legacy kora_phone resource.',
        ['RequirePhoneItem'] = 'Require a handset item in the inventory to use the phone.',
        ['Client.Command'] = 'Chat command that opens or closes the phone.',
        ['Client.Keybind'] = 'Default key that opens or closes the phone. Players can rebind it in FiveM settings.',
        ['Client.DisableWhileDead'] = 'Stop the phone opening, and put it away, while the player is dead or in last stand.',
        ['HomeScreen.allowReorder'] = 'Let players rearrange home screen app icons. When off the fixed default order is used.',
        ['Gallery.fullscreenViewer'] = 'Open photos and videos from the Gallery in a large full-screen viewer.',
        ['ConsumeSimOnInstall'] = 'Inserting a SIM moves its item into the phone, and removing it returns the same item. The phone re-checks the inventory result and corrects it when this is on.',
        ['SimSwap'] = 'Where SIM swapping is allowed: player, shop or both.',
    } })
end
