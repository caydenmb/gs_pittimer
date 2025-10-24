lua54 'yes'
fx_version 'cerulean'
game 'gta5'

name 'PT'
author 'Gingr Snaps'
description 'On-screen PIT timer with ESX + Qbox support'

shared_script 'config.lua'

client_scripts {
  'pt_timer.lua'
}

server_scripts {
  'server.lua'
}

-- No hard dependencies. This resource detects ESX or Qbox at runtime.