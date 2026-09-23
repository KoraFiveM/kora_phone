fx_version 'cerulean'
game 'gta5'

name 'qbphone'
author 'QBPhone Team'
description 'Server-authoritative QBCore phone'
version '0.3.6'

lua54 'yes'

shared_scripts {
    '@qblib/init.lua',
    '@qb-core/shared/locale.lua',
    'config/shared.lua',
    'shared/constants.lua',
    'shared/validation.lua',
    'shared/contracts.lua'
}

client_scripts {
    '@qbtheme/client/bridge.lua',
    'config/client.lua',
    'client/**/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'server/integrations/*.lua',
    'server/repositories/*.lua',
    'server/services/*.lua',
    'server/rate_limits.lua',
    'server/permissions.lua',
    'server/sessions.lua',
    'server/callbacks.lua',
    'server/modules/call_callbacks.lua',
    'server/modules/economy_callbacks.lua',
    'server/modules/media_callbacks.lua',
    'server/modules/community_callbacks.lua',
    'server/main.lua'
}

-- Applied in this order when the resource starts, once each (server/integrations/migrations.lua).
migration 'migrations/001_initial.sql'
migration 'migrations/002_indexes.sql'
migration 'migrations/003_calls.sql'
migration 'migrations/004_media.sql'
migration 'migrations/005_economy_audit.sql'
migration 'migrations/006_community.sql'
migration 'migrations/007_messaging.sql'
migration 'migrations/008_pin.sql'
migration 'migrations/009_items.sql'
migration 'migrations/010_mail.sql'
migration 'migrations/011_media_posts.sql'

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/assets/*',
    'web/dist/compat.js',
    'local-media/*'
}

dependencies {
    'qbtheme',
    'qblib',
    'qb-core',
    'oxmysql'
}

-- Lets this resource answer as each aliased phone (client/customapps.lua) for real: many
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
