lua54 'yes'
fx_version 'cerulean'
game 'gta5'

name 'PT'
author 'Gingr Snaps'
description 'On-screen PIT timer'

-- Load config for both sides
shared_script 'config.lua'

client_scripts {
  'pt_timer.lua'
}

server_scripts {
  'server.lua'
}

dependencies {
  'es_extended'
  -- wasabi_multijob is strongly recommended; set hardRequire=true in config if you want it mandatory
}
