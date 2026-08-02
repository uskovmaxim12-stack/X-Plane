-- ============================================================
-- ARMS - Adaptive Recovery Management System
-- FlyWithLua для X-Plane 12 (исправленная версия)
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

-- ============================================================
-- 1. ПОРТИ
-- ============================================================

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

-- ============================================================
-- 2. DATAREF'Ы (старый способ)
-- ============================================================

local alpha_ref = XPLMFindDataRef("sim/flightmodel/position/alpha")
local speed_ref = XPLMFindDataRef("sim/flightmodel/position/indicated_airspeed")
local roll_ref = XPLMFindDataRef("sim/flightmodel/position/phi")
local yaw_ref = XPLMFindDataRef("sim/flightmodel/position/Q")
local vvi_ref = XPLMFindDataRef("sim/flightmodel/position/vvi_ftsec")
local throttle1_ref = XPLMFindDataRef("sim/flightmodel/engine/ENGN_thro_use[0]")
local throttle2_ref = XPLMFindDataRef("sim/flightmodel/engine/ENGN_thro_use[1]")

local override_ref = XPLMFindDataRef("sim/operation/override/override_control_surfaces")
local cmd_elevator_ref = XPLMFindDataRef("sim/flightmodel/controls/elevator")
local cmd_rudder_ref = XPLMFindDataRef("sim/flightmodel/controls/rudder")
local cmd_aileron_ref = XPLMFindDataRef("sim/flightmodel/controls/aileron")
local cmd_throttle1_ref = XPLMFindDataRef("sim/flightmodel/engine/ENGN_thro_use[0]")
local cmd_throttle2_ref = XPLMFindDataRef("sim/flightmodel/engine/ENGN_thro_use[1]")
local cmd_flap_ref = XPLMFindDataRef("sim/flightmodel/controls/flaprat")

-- ============================================================
-- 3. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ЧТЕНИЯ/ЗАПИСИ
-- ============================================================

function get_float(ref)
    return XPLMGetDataf(ref)
end

function set_float(ref, value)
    XPLMSetDataf(ref, value)
end

-- ============================================================
-- 4. ГЛАВНАЯ ЛОГИКА
-- ============================================================

function arms_loop()
    -- 4.1. Читаем данные
    local a = get_float(alpha_ref) * 57.2958
    local spd = get_float(speed_ref)
    local r = get_float(roll_ref) * 57.2958
    local yr = get_float(yaw_ref)
    local vv = get_float(vvi_ref)
    local t1 = get_float(throttle1_ref) * 100
    local t2 = get_float(throttle2_ref) * 100

    -- 4.2. Расчёт рисков
    local r_alpha = calc_risk(a, ALPHA_MIN, ALPHA_MAX)
    local r_vvi = calc_risk(-vv, 200.0, 800.0)
    local r_yaw = calc_risk(math.abs(yr), YAW_MIN, YAW_MAX)
    local r_roll = calc_risk(math.abs(r), ROLL_MIN, ROLL_MAX)
    local r_thr = calc_risk(math.abs(t1 - t2), THR_ASYMM_MIN, THR_ASYMM_MAX)

    -- 4.3. Общий риск
    local risk = (r_alpha * 2.0 + r_vvi * 1.5 + r_yaw * 1.5 + r_roll * 1.0 + r_thr * 1.0) / 7.0
    risk = clamp(risk, 0.0, 100.0)

    -- 4.4. Если риск мал — не вмешиваемся
    if risk < RISK_PREPARE then
        if get_float(override_ref) == 1 then
            set_float(override_ref, 0)
        end
        return
    end

    -- 4.5. Расчёт команд
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

    -- 4.6. Отправка команд
    set_float(override_ref, 1)
    set_float(cmd_elevator_ref, clamp(elevator, -1.0, 1.0))
    set_float(cmd_rudder_ref, clamp(rudder, -1.0, 1.0))
    set_float(cmd_aileron_ref, 0.0)
    set_float(cmd_throttle1_ref, clamp(cmd_t1, 0.0, 1.0))
    set_float(cmd_throttle2_ref, clamp(cmd_t2, 0.0, 1.0))
    set_float(cmd_flap_ref, 0.0)
end

-- ============================================================
-- 5. РЕГИСТРАЦИЯ
-- ============================================================

do_every_frame("arms_loop()")
logMsg("========================================")
logMsg(" ARMS v8.1 LOADED (FlyWithLua)")
logMsg("========================================")
