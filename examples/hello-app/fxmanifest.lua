fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'hello-app'
description 'Example kora_phone SDK app'
version '1.0.0'

dependency 'kora_phone'

kora_phone_app 'app.json'

server_script 'server/main.lua'

files {
    'app.json',
    'ui/dist/index.html',
    'ui/dist/assets/*',
}
