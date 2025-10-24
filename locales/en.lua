Locales = Locales or {}

Locales['en'] = {
  -- HUD strings
  hud_label_prefix      = 'PIT Timer: ',
  hud_authorized_text   = 'PIT Maneuver Authorized',

  -- Chat/help strings
  cmd_start_desc        = 'Start the PIT timer',
  cmd_stop_desc         = 'Stop the PIT timer',
  hud_set_msg           = 'HUD set x=%.2f y=%.2f scale=%.2f',

  -- Errors & notifications
  err_must_be_on_duty   = 'You must be on-duty as Police.',
  err_insufficient      = 'Insufficient grade to control the PIT timer.',
  err_esx_not_inited    = 'ESX not initialized.',
}

-- Locale accessor. Use _L('key', args...)
function _L(key, ...)
  local lang = (Config and Config.Locale) or 'en'
  local pack = Locales[lang] or Locales['en'] or {}
  local str  = pack[key] or key
  local argc = select('#', ...)
  if argc > 0 then
    return str:format(...)
  end
  return str
end
