lua54 'yes'
fx_version 'cerulean'
game 'gta5'

name 'PT'
author 'Gingr Snaps'
description 'On-screen PIT timer (ESX + Qbox)'

-- Load config on both sides
shared_script 'config.lua'

client_scripts {
  'pt_timer.lua'
}

server_scripts {
  'server.lua'
}

-- If using ESX path, you need es_extended + (optionally) wasabi_multijob.
-- If using Qbox path, you need qbx_core and (optionally) randol_multijob.
