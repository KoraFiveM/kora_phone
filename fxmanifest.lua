fx_version 'cerulean'
game 'gta5'
dependency 'kora_lib'

name 'kora_phone'
author 'Kora Team'
description 'Server-authoritative Kora phone'
version '0.0.1-dev.3'

lua54 'yes'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_core/init.lua',
    '@kora_core/shared/locale.lua',
    'config/shared.lua',
    'config/handsets.lua',
    'shared/constants.lua',
    'shared/validation.lua',
    'shared/contracts.lua'
}

client_scripts {
    '@kora_theme/client/bridge.lua',
    'config/client.lua',
    -- Explicit order: the SDK registry must exist before client/customapps.lua (the alias exports feed it),
    -- and client/nui.lua (route table loop) must load before client/video.lua.
    'client/animations.lua',
    'client/calls.lua',
    'client/camera.lua',
    'client/sdk/registry.lua',
    'client/sdk/events.lua',
    'client/customapps.lua',
    'client/integrations/voice.lua',
    'client/main.lua',
    'client/map.lua',
    'client/notifications.lua',
    'client/nui.lua',
    'client/phone_state.lua',
    'client/services.lua',
    'client/share.lua',
    'client/video.lua'
}

server_scripts {
    '@kora_sql/init.lua',
    'server/crypto.js',
    'config/server.lua',
    'server/schema.lua',
    'server/sdk/schema.lua',
    'server/integrations/*.lua',
    'server/repositories/*.lua',
    'server/services/*.lua',
    'server/rate_limits.lua',
    'server/permissions.lua',
    'server/sessions.lua',
    'server/handsets/core.lua',
    'server/handsets/location.lua',
    'server/handsets/sim.lua',
    'server/handsets/identity.lua',
    'server/handsets/cloud.lua',
    'server/handsets/actions.lua',
    'server/handsets/lifecycle.lua',
    'server/mailboxes.lua',
    'server/mail/system.lua',
    'server/phone_commerce.lua',
    -- App SDK: needs server/permissions.lua, rate_limits.lua and shared/constants.lua above.
    'server/sdk/manifest.lua',
    'server/sdk/registry.lua',
    'server/sdk/permissions.lua',
    'server/sdk/install.lua',
    'server/sdk/storage_repository.lua',
    'server/sdk/storage.lua',
    'server/sdk/callbacks.lua',
    'server/sdk/routes.lua',
    'server/sdk/discovery.lua',
    'server/sdk/exports.lua',
    -- Gateway: registers every callback from shared/routes.json; handlers bind lazily.
    'server/callbacks.lua',
    'server/modules/call_callbacks.lua',
    'server/modules/economy_callbacks.lua',
    'server/modules/media_callbacks.lua',
    'server/modules/community_callbacks.lua',
    'server/handset_callbacks.lua',
    'server/main.lua'
}

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/assets/*',
    'web/dist/compat.js',
    'web/dist/map.jpg',
    'shared/routes.json',
    'locales/*.lua',
    'local-media/*',
    'stream/kora_phone_props.ytyp'
}

-- In-hand handset props (copies of the kora_phoneshop display models under kora_phone names). Restarting this
-- resource while a player holds a phone unloads these archetypes under a live prop and crashes that client:
-- restart it with the phone put away, or move stream/ into a resource that does not restart.
data_file 'DLC_ITYP_REQUEST' 'stream/kora_phone_props.ytyp'

dependencies {
    'kora_theme',
    'kora_lib',
    'kora_core',
    'kora_sql',
    'kora_inventory',
    'kora_voice',
}

-- Custom-app compatibility only (no qb-phone): lets this resource answer as each aliased phone (client/customapps.lua) for real: many
-- custom apps gate their AddCustomApp-style call behind GetResourceState('lb-phone') (etc)
-- being 'started' before ever attempting the export, which the export-event trick alone
-- can't satisfy. `provide` makes GetResourceState and dependency resolution treat this
-- resource as if it were that one too. Don't also run the real lb-phone/sd-phone/etc
-- alongside this -- same warning sky_phone documents for the same trick: two active
-- providers of the same name race for the same registrations.
provide 'lb-phone'
provide 'sd-phone'
provide '17mov_Phone'
provide 'yseries'
provide 'high-phone'

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'

server_script 'kora_versioncheck.lua'
