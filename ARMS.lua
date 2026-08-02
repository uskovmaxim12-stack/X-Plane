-- ============================================================
-- ARMS - Adaptive Recovery Management System
-- Полная версия для X-Plane 12 (FlyWithLua)
-- Версия: 10.0 (Final)
-- ============================================================

-- ============================================================
-- 1. НАСТРОЙКИ (изменяемые)
-- ============================================================
local CONFIG = {
    ALPHA_CRITICAL = 16.0,      -- Угол атаки > 16°
    YAW_RATE_CRITICAL = 0.4,    -- Вращение > 0.4 рад/с
    VVI_CRITICAL = -400.0,      -- Падение > 400 фут/мин
    ROLL_CRITICAL = 60.0,       -- Крен > 60°
    THR_ASYMM_CRITICAL = 30.0,  -- Разница тяги > 30%
    RISK_PREPARE = 20.0,        -- Риск > 20% → подготовка
    RISK_ACTIVE = 50.0,         -- Риск > 50% → вмешательство
    RISK_EMERGENCY = 80.0,      -- Риск > 80% → экстренный режим
    ACTIVATION_DELAY = 0.5,     -- Задержка 0.5 сек (защита от ложных)
    LOG_ENABLED = true,         -- Логирование в Log.txt
}

-- ============================================================
-- 2. ИНДИКАЦИЯ НА ЭКРАНЕ (HUD)
-- ============================================================
local show_hud = true
local hud_x = 20   -- позиция слева
local hud_y = 50   -- позиция снизу

-- ============================================================
-- 3. ПОЛУЧАЕМ DATAREF'Ы (все нужные)
-- ============================================================
local function get_ref(name)
    local ref = XPLMFindDataRef(name)
    if ref == nil and CONFIG.LOG_ENABLED then
        logMsg("[ARMS] WARNING: DataRef " .. name .. " not found!")
    end
    return ref
end

local alpha_ref = get_ref("sim/flightmodel/position/alpha")
local speed_ref = get_ref("sim/flightmodel/position/indicated_airspeed")
local roll_ref = get_ref("sim/flightmodel/position/phi")
local yaw_ref = get_ref("sim/flightmodel/position/Q")
local vvi_ref = get_ref("sim/flightmodel/position/vvi_fpm")
local g_load_ref = get_ref("sim/flightmodel/position/gload")
local throttle1_ref = get_ref("sim/flightmodel/engine/ENGN_throttle_use[0]")
local throttle2_ref = get_ref("sim/flightmodel/engine/ENGN_throttle_use[1]")
local flap_ref = get_ref("sim/flightmodel/controls/flaprat")

local override_ref = get_ref("sim/operation/override/override_control_surfaces")
local cmd_elevator_ref = get_ref("sim/flightmodel/controls/elevator_def")
local cmd_rudder_ref = get_ref("sim/flightmodel/controls/rudder_def")
local cmd_aileron_ref = get_ref("sim/flightmodel/controls/aileron_def")
local cmd_throttle1_ref = get_ref("sim/flightmodel/engine/ENGN_throttle_use[0]")
local cmd_throttle2_ref = get_ref("sim/flightmodel/engine/ENGN_throttle_use[1]")
local cmd_flap_ref = get_ref("sim/flightmodel/controls/flaprat")

-- ============================================================
-- 4. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================
local function readf(ref)
    if ref == nil then return 0 end
    return XPLMGetDataf(ref) or 0
end

local function writef(ref, val)
    if ref == nil then return end
    XPLMSetDataf(ref, val)
end

local function sign(v)
    if v > 0 then return 1.0 end
    if v < 0 then return -1.0 end
    return 0.0
end

local function clamp(v, mn, mx)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function calc_risk(value, min_val, max_val)
    if value <= min_val then return 0.0 end
    if value >= max_val then return 100.0 end
    local norm = (value - min_val) / (max_val - min_val)
    return norm * norm * 100.0
end

-- ============================================================
-- 5. ПЕРЕМЕННЫЕ СОСТОЯНИЯ
-- ============================================================
local arms_active = true          -- включена/выключена
local arms_status = "STANDBY"     -- STANDBY, PREPARE, ACTIVE, EMERGENCY
local current_risk = 0.0
local spin_detected = false
local spin_timer = 0.0

-- ============================================================
-- 6. ГЛАВНАЯ ЛОГИКА
-- ============================================================
function arms_loop()
    if not arms_active then
        -- Если выключена — снимаем вмешательство
        if readf(override_ref) == 1 then
            writef(override_ref, 0)
        end
        arms_status = "OFF"
        return
    end

    -- 6.1. Читаем данные
    local a = readf(alpha_ref) * 57.2958
    local spd = readf(speed_ref)
    local r = readf(roll_ref) * 57.2958
    local yr = readf(yaw_ref)
    local vv = readf(vvi_ref)
    local g = readf(g_load_ref)
    local t1 = readf(throttle1_ref) * 100
    local t2 = readf(throttle2_ref) * 100
    local flp = readf(flap_ref)

    -- 6.2. Расчёт рисков
    local r_alpha = calc_risk(a, 10.0, 22.0)
    local r_vvi = calc_risk(-vv, 200.0, 800.0)
    local r_yaw = calc_risk(math.abs(yr), 0.2, 1.5)
    local r_roll = calc_risk(math.abs(r), 10.0, 60.0)
    local r_thr = calc_risk(math.abs(t1 - t2), 5.0, 40.0)

    -- Общий риск (средневзвешенный)
    current_risk = (r_alpha * 2.0 + r_vvi * 1.5 + r_yaw * 1.5 + r_roll * 1.0 + r_thr * 1.0) / 7.0
    current_risk = clamp(current_risk, 0.0, 100.0)

    -- 6.3. Определение статуса
    if current_risk >= CONFIG.RISK_EMERGENCY then
        arms_status = "EMERGENCY"
    elseif current_risk >= CONFIG.RISK_ACTIVE then
        arms_status = "ACTIVE"
    elseif current_risk >= CONFIG.RISK_PREPARE then
        arms_status = "PREPARE"
    else
        arms_status = "STANDBY"
    end

    -- 6.4. Проверка штопора (жёсткие условия)
    local isSpin = (a > CONFIG.ALPHA_CRITICAL) and 
                   (vv < CONFIG.VVI_CRITICAL) and 
                   (math.abs(yr) > CONFIG.YAW_RATE_CRITICAL)

    -- 6.5. Защита от ложных срабатываний (задержка)
    if isSpin then
        spin_timer = spin_timer + 0.02   -- каждый кадр ~0.02 сек
    else
        spin_timer = 0.0
    end
    spin_detected = (spin_timer >= CONFIG.ACTIVATION_DELAY)

    -- 6.6. Принятие решения
    local should_intervene = false

    if spin_detected then
        should_intervene = true
        arms_status = "SPIN RECOVERY"
    elseif arms_status == "EMERGENCY" or arms_status == "ACTIVE" then
        should_intervene = true
    end

    -- 6.7. Вмешательство или отключение
    if should_intervene then
        -- Вычисляем команды
        local elevator = 0.0
        if r_alpha > 20.0 then
            local factor = (a - 10.0) / 12.0
            factor = clamp(factor, 0.0, 1.0)
            elevator = -0.5 - factor * 0.5
        end

        local rudder = 0.0
        if math.abs(yr) > 0.3 then
            rudder = -sign(yr) * clamp(math.abs(yr) / 1.5, 0.3, 1.0)
        end

        local cmd_t1, cmd_t2
        if current_risk > CONFIG.RISK_ACTIVE then
            cmd_t1 = 1.0
            cmd_t2 = 1.0
            if r_thr > 30.0 then
                local avg = (t1 + t2) / 2.0 / 100.0
                cmd_t1 = avg
                cmd_t2 = avg
                if current_risk > CONFIG.RISK_EMERGENCY then
                    cmd_t1 = 1.0
                    cmd_t2 = 1.0
                end
            end
        else
            cmd_t1 = t1 / 100.0
            cmd_t2 = t2 / 100.0
        end

        local flap = 0.0
        if r_alpha > 60.0 and r_roll < 20.0 and r_yaw < 30.0 then
            flap = 5.0
        end

        -- Отправка команд
        writef(override_ref, 1)
        writef(cmd_elevator_ref, clamp(elevator, -1.0, 1.0))
        writef(cmd_rudder_ref, clamp(rudder, -1.0, 1.0))
        writef(cmd_aileron_ref, 0.0)
        writef(cmd_throttle1_ref, clamp(cmd_t1, 0.0, 1.0))
        writef(cmd_throttle2_ref, clamp(cmd_t2, 0.0, 1.0))
        writef(cmd_flap_ref, clamp(flap, 0.0, 40.0))

        -- Логирование
        if CONFIG.LOG_ENABLED then
            logMsg(string.format("[ARMS] Risk: %.1f%% | Status: %s | Elev: %.2f | Rud: %.2f | Thr: %.2f/%.2f", 
                current_risk, arms_status, elevator, rudder, cmd_t1, cmd_t2))
        end
    else
        -- Отключаем вмешательство
        if readf(override_ref) == 1 then
            writef(override_ref, 0)
        end
    end
end

-- ============================================================
-- 7. ОТРИСОВКА HUD (ИНДИКАЦИЯ НА ЭКРАНЕ)
-- ============================================================
function draw_hud()
    if not show_hud then return end

    local color = "white"
    if arms_status == "EMERGENCY" or arms_status == "SPIN RECOVERY" then
        color = "red"
    elseif arms_status == "ACTIVE" then
        color = "orange"
    elseif arms_status == "PREPARE" then
        color = "yellow"
    elseif arms_status == "STANDBY" then
        color = "green"
    else
        color = "gray"
    end

    draw_string(hud_x, hud_y, "═══ ARMS SYSTEM ═══", "white", 24)
    draw_string(hud_x, hud_y - 30, "Status: " .. arms_status, color, 20)
    draw_string(hud_x, hud_y - 55, "Risk: " .. string.format("%.1f", current_risk) .. "%", "white", 18)
    
    if arms_active then
        draw_string(hud_x, hud_y - 80, "Active: YES", "lime", 16)
    else
        draw_string(hud_x, hud_y - 80, "Active: NO", "red", 16)
    end
end

-- ============================================================
-- 8. РЕГИСТРАЦИЯ
-- ============================================================
do_every_frame("arms_loop()")
do_every_draw("draw_hud()")

logMsg("========================================")
logMsg(" ARMS v10.0 LOADED (FULL VERSION)")
logMsg("========================================")
logMsg(" [HUD] На экране отображается статус системы")
logMsg(" [HOTKEY] Ctrl + A — включить/выключить ARMS")
logMsg("========================================")

-- ============================================================
-- 9. ГОРЯЧАЯ КЛАВИША ДЛЯ ВКЛ/ВЫКЛ
-- ============================================================
function toggle_arms()
    arms_active = not arms_active
    if arms_active then
        logMsg("[ARMS] SYSTEM ACTIVATED")
    else
        logMsg("[ARMS] SYSTEM DEACTIVATED")
        writef(override_ref, 0)
    end
end

add_keybinding("Ctrl + A", "Toggle ARMS", "toggle_arms()")
