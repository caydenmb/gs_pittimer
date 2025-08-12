lua54 "yes"
fx_version 'cerulean'
game 'gta5'

name 'PT'
author 'Mr.kujo934'
description 'On-screen PIT timer (police/sheriff, clocked-in only, optimized)'

client_scripts {
    'config.lua',     -- optional legacy file; safe to remove if unused
    'pt_timer.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'es_extended'     -- ESX is required
}
