lua54 'yes'
fx_version 'cerulean'
game 'gta5'

name 'PT'
author 'Gingr Snaps'
description 'On-screen PIT timer with ESX + Qbox support (police only)'

-- Load config + locales on both sides first
shared_scripts {
  'config.lua',
  'locales/en.lua',        -- add more locales as needed (e.g., locales/es.lua)
}

client_scripts {
  'pt_timer.lua'
}

server_scripts {
  'server.lua'
}
