lua54 "yes" -- needed for Reaper

shared_script "@ReaperV4/bypass.lua"
lua54 "yes"

fx_version 'cerulean'
game 'gta5'

name 'PT'
author 'Gingr Snaps'
description 'On-screen PIT timer (police/sheriff)'

client_scripts {
    'config.lua',
    'pt_timer.lua'
}

-- IMPORTANT: keep this exact filename path
server_scripts {
    'server.lua'
}

dependencies {
    'es_extended'
}
