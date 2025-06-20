fx_version 'cerulean'
game 'gta5'

author 'Zaki'
description 'Bet64 - Sports Betting App for lb-phone'
version '1.0.0'
lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    '@es_extended/imports.lua',
    'client/main.lua',
    'client/app.lua',
    'client/admin.lua',
    'client/utils.lua'
}

server_scripts {
    'server/logs.lua',
    '@oxmysql/lib/MySQL.lua',
    '@es_extended/imports.lua',
    'server/main.lua',
    'server/database.lua',
    'server/callbacks.lua',
    'server/events.lua'
}

file 'ui/dist/**/*'

ui_page 'ui/dist/index.html'
-- ui_page 'http://localhost:3000'

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
    'lb-phone'
}

