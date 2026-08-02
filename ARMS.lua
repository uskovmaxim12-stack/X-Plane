-- ============================================================
-- ARMS - Adaptive Recovery Management System
-- Полная прогнозирующая версия для X-Plane 12
-- Версия: 13.0 (FULL PREDICTIVE)
-- Полностью соответствует концепции проекта
-- ============================================================

-- ============================================================
-- 1. НАСТРОЙКИ
-- ============================================================
local CONFIG = {
    -- Критические пороги (из раздела 1.1 проекта)
    ALPHA_CRITICAL = 16.0,      -- Угол атаки > 16° (сваливание)
    YAW_RATE_CRITICAL = 0.4,    -- Вращение > 0.4 рад/с (штопор)
    VVI_CRITICAL = -400.0,      -- Падение > 400 фут/мин
    ROLL_CRITICAL = 60.0,       -- Крен > 60° (из раздела 1.1)
    SPEED_CRITICAL_LOW = 150.0,
    SPEED_CRITICAL_HIGH = 550.0,
    THR_ASYMM_CRITICAL = 30.0,  -- Разница тяги > 30%
    G_LOAD_MAX = 2.5,
    
    -- Уровни риска (из раздела 4.3)
    RISK_PREPARE = 20.0,        -- Подготовка
    RISK_ACTIVE = 50.0,         -- Активное вмешательство
    RISK_EMERGENCY = 80.0,      -- Экстренный режим
    
    -- Прогнозирование (из раздела 3.2)
    PREDICT_SECONDS = 3.0,      -- Прогноз на 3 секунды
    HISTORY_LENGTH = 30,        -- История для тренда
    SIMULATION_STEPS = 10,      -- 10 сценариев
    
    -- Защита от ложных (из раздела 4.4)
    ACTIVATION_DELAY = 0.3,
}

-- ============================================================
-- 2. DATAREF'Ы (из раздела 4.1)
-- ============================================================
local function get_ref(name)
    local ref = XPLMFindDataRef(name)
    if ref == nil then
        logMsg("[ARMS] DataRef not found: " .. name)
    end
    return ref
end

local refs = {
    -- Входные параметры (из раздела 4.1)
    alpha = get_ref("sim/flightmodel/position/alpha"),
    speed = get_ref("sim/flightmodel/position/indicated_airspeed"),
    roll = get_ref("sim/flightmodel/position/phi"),
    pitch = get_ref("sim/flightmodel/position/theta"),
    yaw = get_ref("sim/flightmodel/position/Q"),
    vvi = get_ref("sim/flightmodel/position/vvi_fpm") or get_ref("sim/flightmodel/position/vvi_ftsec"),
    gload = get_ref("sim/flightmodel/position/gload"),
    flap = get_ref("sim/flightmodel/controls/flaprat"),
    thr1 = get_ref("sim/flightmodel/engine/ENGN_thro_use[0]") or get_ref("sim/flightmodel/engine/ENGN_throttle_use[0]"),
    thr2 = get_ref("sim/flightmodel/engine/ENGN_thro_use[1]") or get_ref("sim/flightmodel/engine/ENGN_throttle_use[1]"),
    
    -- Управление (из раздела 4.1)
    override = get_ref("sim/operation/override/override_control_surfaces"),
    cmd_elevator = get_ref("sim/flightmodel/controls/elevator"),
    cmd_rudder = get_ref("sim/flightmodel/controls/rudder"),
    cmd_aileron = get_ref("sim/flightmodel/controls/aileron"),
    cmd_thr1 = get_ref("sim/flightmodel/engine/ENGN_thro_use[0]") or get_ref("sim/flightmodel/engine/ENGN_throttle_use[0]"),
    cmd_thr2 = get_ref("sim/flightmodel/engine/ENGN_thro_use[1]") or get_ref("sim/flightmodel/engine/ENGN_throttle_use[1]"),
    cmd_flap = get_ref("sim/flightmodel/controls/flaprat"),
}

-- ============================================================
-- 3. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================
local function readf(ref) if ref == nil then return 0 end return XPLMGetDataf(ref) or 0 end
local function writef(ref, val) if ref == nil then return end XPLMSetDataf(ref, val) end
local function sign(v) return (v > 0) and 1 or (v < 0) and -1 or 0 end
local function clamp(v, mn, mx) return math.max(mn, math.min(mx, v)) end

-- Функция расчёта риска (из раздела 3.1)
local function calc_risk(value, min_val, max_val)
    if value <= min_val then return 0 end
    if value >= max_val then return 100 end
    local norm = (value - min_val) / (max_val - min_val)
    return norm * norm * 100
end

-- Среднее значение
local function average(arr)
    local sum = 0
    for i = 1, #arr do sum = sum + arr[i] end
    return sum / #arr
end

-- Линейный тренд (из раздела 3.2)
local function trend(arr)
    local n = #arr
    if n < 2 then return 0 end
    local sum_x, sum_y, sum_xy, sum_x2 = 0, 0, 0, 0
    for i = 1, n do
        local x = i - 1
        local y = arr[i]
        sum_x = sum_x + x
        sum_y = sum_y + y
        sum_xy = sum_xy + x * y
        sum_x2 = sum_x2 + x * x
    end
    local denom = n * sum_x2 - sum_x * sum_x
    if denom == 0 then return 0 end
    return (n * sum_xy - sum_x * sum_y) / denom
end

-- ============================================================
-- 4. ХРАНИЛИЩЕ ИСТОРИИ (из раздела 3.2)
-- ============================================================
local history = {
    alpha = {}, speed = {}, roll = {}, yaw = {}, vvi = {}, thr1 = {}, thr2 = {},
}

local function add_history(hist, val)
    table.insert(hist, val)
    if #hist > CONFIG.HISTORY_LENGTH then
        table.remove(hist, 1)
    end
end

local function get_trend(hist)
    if #hist < 3 then return 0 end
    return trend(hist)
end

local function get_last(hist)
    return hist[#hist] or 0
end

-- ============================================================
-- 5. ПРОГНОЗИРОВАНИЕ (из раздела 3.2)
-- ============================================================
local function predict_value(hist, dt)
    local last = get_last(hist)
    local tr = get_trend(hist)
    return last + tr * dt
end

local function predict_state(dt)
    return {
        alpha = predict_value(history.alpha, dt),
        speed = predict_value(history.speed, dt),
        roll = predict_value(history.roll, dt),
        yaw = predict_value(history.yaw, dt),
        vvi = predict_value(history.vvi, dt),
        thr1 = predict_value(history.thr1, dt),
        thr2 = predict_value(history.thr2, dt),
    }
end

-- ============================================================
-- 6. ОЦЕНКА РИСКА (из раздела 3.1 и 4.2)
-- ============================================================
local function assess_risk(state)
    local a = state.alpha or 0
    local spd = state.speed or 0
    local r = state.roll or 0
    local yr = state.yaw or 0
    local vv = state.vvi or 0
    local t1 = state.thr1 or 0
    local t2 = state.thr2 or 0

    -- Расчёт рисков по каждому параметру
    local r_alpha = calc_risk(a, 10, 22)          -- Угол атаки
    local r_vvi = calc_risk(-vv, 200, 800)        -- Вертикальная скорость
    local r_yaw = calc_risk(math.abs(yr), 0.2, 1.5) -- Вращение
    local r_roll = calc_risk(math.abs(r), 10, 60)   -- Крен
    local r_thr = calc_risk(math.abs(t1 - t2), 5, 40) -- Асимметрия тяги
    local r_speed_low = calc_risk(150 - spd, 0, 50)   -- Потеря скорости
    if spd > 150 then r_speed_low = 0 end
    local r_speed_high = calc_risk(spd, 500, 600)     -- Перегон

    -- Общий риск (средневзвешенный)
    local risk = (r_alpha * 2.0 + r_vvi * 1.5 + r_yaw * 1.5 + 
                  r_roll * 1.0 + r_thr * 1.0 + r_speed_low * 1.0 + r_speed_high * 0.5) / 8.5
    return clamp(risk, 0, 100)
end

-- ============================================================
-- 7. ГЕНЕРАЦИЯ СЦЕНАРИЕВ (из раздела 4.2)
-- ============================================================
local function generate_scenarios(current_state, dt)
    local scenarios = {}
    local base_elevator = 0
    local base_rudder = 0
    local base_thr1 = current_state.thr1 or 0
    local base_thr2 = current_state.thr2 or 0
    local base_flap = 0

    for i = 1, 10 do
        local factor = (i - 1) / 9
        local scenario = {
            elevator = 0,
            rudder = 0,
            thr1 = base_thr1,
            thr2 = base_thr2,
            flap = base_flap,
            risk = 0,
        }
        
        -- Варианты действий
        if (current_state.alpha or 0) > 14 or (current_state.vvi or 0) < -300 then
            scenario.elevator = -0.3 - factor * 0.6
        end
        if math.abs(current_state.yaw or 0) > 0.3 then
            scenario.rudder = -sign(current_state.yaw or 0) * (0.3 + factor * 0.7)
        end
        
        -- Симуляция результата (цифровой двойник, упрощённо)
        local predicted = {
            alpha = current_state.alpha + scenario.elevator * 5,
            speed = current_state.speed + (scenario.thr1 - 0.5) * 10,
            roll = current_state.roll + scenario.rudder * 5,
            yaw = current_state.yaw + scenario.rudder * 0.5,
            vvi = current_state.vvi + scenario.elevator * 100,
            thr1 = scenario.thr1 * 100,
            thr2 = scenario.thr2 * 100,
        }
        scenario.risk = assess_risk(predicted)
        table.insert(scenarios, scenario)
    end
    return scenarios
end

-- ============================================================
-- 8. ВЫБОР ЛУЧШЕГО СЦЕНАРИЯ (из раздела 4.2)
-- ============================================================
local function select_best_scenario(scenarios)
    local best = scenarios[1]
    for i = 2, #scenarios do
        if scenarios[i].risk < best.risk then
            best = scenarios[i]
        end
    end
    return best
end

-- ============================================================
-- 9. ГЛАВНАЯ ЛОГИКА
-- ============================================================
local arms_active = true
local arms_status = "STANDBY"
local current_risk = 0
local predicted_risk = 0
local spin_timer = 0

function arms_loop()
    if not arms_active then
        if readf(refs.override) == 1 then writef(refs.override, 0) end
        arms_status = "OFF"
        return
    end

    -- 9.1. Чтение данных (из раздела 4.1)
    local a = readf(refs.alpha) * 57.2958
    local spd = readf(refs.speed)
    local r = readf(refs.roll) * 57.2958
    local pitch = readf(refs.pitch) * 57.2958
    local yr = readf(refs.yaw)
    local vv = readf(refs.vvi)
    local gl = readf(refs.gload)
    local t1 = readf(refs.thr1) * 100
    local t2 = readf(refs.thr2) * 100
    local flap = readf(refs.flap)

    -- 9.2. Сохранение в историю (из раздела 3.2)
    add_history(history.alpha, a)
    add_history(history.speed, spd)
    add_history(history.roll, r)
    add_history(history.yaw, yr)
    add_history(history.vvi, vv)
    add_history(history.thr1, t1)
    add_history(history.thr2, t2)

    -- 9.3. Текущее состояние
    local current_state = {
        alpha = a, speed = spd, roll = r, pitch = pitch,
        yaw = yr, vvi = vv, gload = gl, thr1 = t1, thr2 = t2, flap = flap,
    }

    -- 9.4. Текущий риск
    current_risk = assess_risk(current_state)

    -- 9.5. Прогнозируемый риск (из раздела 3.2)
    local future = predict_state(CONFIG.PREDICT_SECONDS)
    predicted_risk = assess_risk(future)

    -- 9.6. Статус системы (из раздела 4.3)
    if current_risk >= CONFIG.RISK_EMERGENCY or predicted_risk >= CONFIG.RISK_EMERGENCY then
        arms_status = "EMERGENCY"
    elseif current_risk >= CONFIG.RISK_ACTIVE or predicted_risk >= CONFIG.RISK_ACTIVE then
        arms_status = "ACTIVE"
    elseif current_risk >= CONFIG.RISK_PREPARE or predicted_risk >= CONFIG.RISK_PREPARE then
        arms_status = "PREPARE"
    else
        arms_status = "STANDBY"
    end

    -- 9.7. Обнаружение штопора (из раздела 1.1)
    local isSpin = (a > CONFIG.ALPHA_CRITICAL) and 
                   (vv < CONFIG.VVI_CRITICAL) and 
                   (math.abs(yr) > CONFIG.YAW_RATE_CRITICAL)
    if isSpin then
        spin_timer = spin_timer + 0.02
    else
        spin_timer = 0.0
    end

    -- 9.8. Принятие решения (из раздела 4.2)
    local should_intervene = false
    if isSpin and spin_timer >= CONFIG.ACTIVATION_DELAY then
        should_intervene = true
        arms_status = "SPIN RECOVERY"
    elseif current_risk >= CONFIG.RISK_ACTIVE or predicted_risk >= CONFIG.RISK_ACTIVE then
        should_intervene = true
    end

    -- 9.9. Выбор и выполнение сценария (из раздела 4.2)
    if should_intervene then
        local scenarios = generate_scenarios(current_state, CONFIG.PREDICT_SECONDS)
        local best = select_best_scenario(scenarios)

        writef(refs.override, 1)
        writef(refs.cmd_elevator, clamp(best.elevator, -1, 1))
        writef(refs.cmd_rudder, clamp(best.rudder, -1, 1))
        writef(refs.cmd_aileron, 0)
        writef(refs.cmd_thr1, clamp(best.thr1, 0, 1))
        writef(refs.cmd_thr2, clamp(best.thr2, 0, 1))
        writef(refs.cmd_flap, clamp(best.flap, 0, 40))
    else
        if readf(refs.override) == 1 then
            writef(refs.override, 0)
        end
    end
end

-- ============================================================
-- 10. ИНТЕРФЕЙС С ПИЛОТОМ (из раздела 4.1)
-- ============================================================
local hud_show = true
local hud_x = 20
local hud_y = 50

function draw_hud()
    if not hud_show then return end

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
    draw_string(hud_x, hud_y - 80, "Predicted: " .. string.format("%.1f", predicted_risk) .. "%", "cyan", 18)
    draw_string(hud_x, hud_y - 105, "Active: " .. (arms_active and "YES" or "NO"), "lime", 16)
end

-- ============================================================
-- 11. РЕГИСТРАЦИЯ
-- ============================================================
do_every_frame("arms_loop()")
do_every_draw("draw_hud()")

logMsg("========================================")
logMsg(" ARMS v13.0 LOADED (FULL PREDICTIVE)")
logMsg("========================================")
logMsg(" [HUD] Статус, риск и прогноз отображаются")
logMsg(" [HOTKEY] Ctrl + A — включить/выключить")
logMsg("========================================")

-- ============================================================
-- 12. ГОРЯЧАЯ КЛАВИША (из раздела 4.3)
-- ============================================================
local toggle_cmd = create_command("ARMS/TOGGLE", "Toggle ARMS", function()
    arms_active = not arms_active
    if arms_active then
        logMsg("[ARMS] SYSTEM ACTIVATED")
    else
        logMsg("[ARMS] SYSTEM DEACTIVATED")
        writef(refs.override, 0)
    end
end)
toggle_cmd:set_key_binding("Ctrl + A")
