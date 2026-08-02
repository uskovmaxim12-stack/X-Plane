-- ============================================================
-- ARMS - Adaptive Recovery Management System
-- FlyWithLua для X-Plane 12
-- Версия: 8.0
-- ============================================================

function clamp(v, mn, mx)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

function sign(v)
    if v > 0 then return 1.0 end
    if v < 0 then return -1.0 end
    return 0.0
end

function calc_risk(value, min_val, max_val)
    if value <= min_val then return 0.0 end
    if value >= max_val then return 100.0 end
    local norm = (value - min_val) / (max_val - min_val)
    return norm * norm * 100.0
end

local ALPHA_MIN = 10.0
local ALPHA_MAX = 22.0
local VVI_MIN = -200.0
local VVI_MAX = -800.0
local YAW_MIN = 0.2
local YAW_MAX = 1.5
local ROLL_MIN = 10.0
local ROLL_MAX = 60.0
local THR_ASYMM_MIN = 5.0
local THR_ASYMM_MAX = 40.0

local RISK_PREPARE = 20.0
local RISK_ACTIVE = 50.0
local RISK_EMERGENCY = 80.0

local alpha = dataref_table("sim/flightmodel/position/alpha")
local speed = dataref_table("sim/flightmodel/position/indicated_airspeed")
local roll = dataref_table("sim/flightmodel/position/phi")
local yaw = dataref_table("sim/flightmodel/position/Q")
local vvi = dataref_table("sim/flightmodel/position/vvi_ftsec")
local throttle1 = dataref_table("sim/flightmodel/engine/ENGN_thro_use[0]")
local throttle2 = dataref_table("sim/flightmodel/engine/ENGN_thro_use[1]")

local override = dataref_table("sim/operation/override/override_control_surfaces")
local cmd_elevator = dataref_table("sim/flightmodel/controls/elevator")
local cmd_rudder = dataref_table("sim/flightmodel/controls/rudder")
local cmd_aileron = dataref_table("sim/flightmodel/controls/aileron")
local cmd_throttle1 = dataref_table("sim/flightmodel/engine/ENGN_thro_use[0]")
local cmd_throttle2 = dataref_table("sim/flightmodel/engine/ENGN_thro_use[1]")
local cmd_flap = dataref_table("sim/flightmodel/controls/flaprat")

function arms_loop()
    local a = alpha[0] * 57.2958
    local r = roll[0] * 57.2958
    local yr = yaw[0]
    local vv = vvi[0]
    local t1 = throttle1[0] * 100
    local t2 = throttle2[0] * 100

    local r_alpha = calc_risk(a, ALPHA_MIN, ALPHA_MAX)
    local r_vvi = calc_risk(-vv, 200.0, 800.0)
    local r_yaw = calc_risk(math.abs(yr), YAW_MIN, YAW_MAX)
    local r_roll = calc_risk(math.abs(r), ROLL_MIN, ROLL_MAX)
    local r_thr = calc_risk(math.abs(t1 - t2), THR_ASYMM_MIN, THR_ASYMM_MAX)

    local risk = (r_alpha * 2.0 + r_vvi * 1.5 + r_yaw * 1.5 + r_roll * 1.0 + r_thr * 1.0) / 7.0
    risk = clamp(risk, 0.0, 100.0)

    if risk < RISK_PREPARE then
        if override[0] == 1 then
            override[0] = 0
        end
        return
    end

    local elevator = 0.0
    if r_alpha > 20.0 then
        local factor = (a - ALPHA_MIN) / (ALPHA_MAX - ALPHA_MIN)
        factor = clamp(factor, 0.0, 1.0)
        elevator = -0.5 - factor * 0.5
    end

    local rudder = 0.0
    if math.abs(yr) > 0.3 then
        rudder = -sign(yr) * clamp(math.abs(yr) / 1.5, 0.3, 1.0)
    end

    local cmd_t1, cmd_t2
    if risk > RISK_ACTIVE then
        cmd_t1 = 1.0
        cmd_t2 = 1.0
        if r_thr > 30.0 then
            local avg = (t1 + t2) / 2.0 / 100.0
            cmd_t1 = avg
            cmd_t2 = avg
            if risk > RISK_EMERGENCY then
                cmd_t1 = 1.0
                cmd_t2 = 1.0
            end
        end
    else
        cmd_t1 = t1 / 100.0
        cmd_t2 = t2 / 100.0
    end

    override[0] = 1
    cmd_elevator[0] = clamp(elevator, -1.0, 1.0)
    cmd_rudder[0] = clamp(rudder, -1.0, 1.0)
    cmd_aileron[0] = 0.0
    cmd_throttle1[0] = clamp(cmd_t1, 0.0, 1.0)
    cmd_throttle2[0] = clamp(cmd_t2, 0.0, 1.0)
    cmd_flap[0] = 0.0
end

do_every_frame("arms_loop()")
logMsg("========================================")
logMsg(" ARMS v8.0 LOADED (FlyWithLua)")
logMsg("========================================")
