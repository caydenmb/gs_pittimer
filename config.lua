-- Pure Lua config
Config = {}

-- How long the timer runs when started (in seconds)
Config.TimerDuration = 120

-- Jobs that should SEE the timer (any grade)
Config.AllowedJobs = {
    police  = true,
    sheriff = true
}

-- Who can CONTROL (inclusive grade ranges)
-- police: 3–8 ; sheriff: 3–6
Config.ControlGrades = {
    police  = { min = 3, max = 8 },
    sheriff = { min = 3, max = 6 }
}
