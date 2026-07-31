-- ============================================================
-- ARMS - Automatic Recovery Management System
-- Версия: 1.0 (полная интеграция с X‑Plane 12)
-- Плагин: FlyWithLua NG+
-- ============================================================

-- ============================================================
-- 1. ПОДКЛЮЧЕНИЕ DATAREF (чтение параметров самолёта)
-- ============================================================

-- Угол атаки (градусы)
dataref("alpha", "sim/flightmodel/position/alpha", "readonly")
-- Воздушная скорость (узлы)
dataref("speed", "sim/flightmodel/position/indicated_airspeed", "readonly")
-- Крен (градусы)
dataref("roll", "sim/flightmodel/position/roll", "readonly")
-- Тангаж (градусы)
dataref("pitch", "sim/flightmodel/position/pitch", "readonly")
-- Угловая скорость рыскания (рад/с)
dataref("yawRate", "sim/flightmodel/position/yaw_rate", "readonly")
-- Вертикальная скорость (фут/мин)
dataref("vvi", "sim/flightmodel/position/vh_ind", "readonly")
-- Перегрузка (g)
dataref("gLoad", "sim/flightmodel/position/g_force", "readonly")
-- Положение закрылков (градусы)
dataref("flapPos", "sim/flightmodel/controls/flaprat", "readonly")
-- Тяга двигателя 1 (%)
dataref("throttle1", "sim/flightmodel/engine/ENGN_thro_use[0]", "readonly")
-- Тяга двигателя 2 (%)
dataref("throttle2", "sim/flightmodel/engine/ENGN_thro_use[1]", "readonly")

-- ============================================================
-- 2. ПОДКЛЮЧЕНИЕ DATAREF (запись команд управления)
-- ============================================================

-- Переопределение управления (1 = разрешено управление извне)
dataref("override_controls", "sim/operation/override/override_control_surfaces", "writable")
-- Переопределение тяги
dataref("override_throttles", "sim/operation/override/override_throttles", "writable")

-- Руль высоты (-1..1, где -1 = от себя)
dataref("cmdElevator", "sim/flightmodel/controls/elevator", "writable")
-- Руль направления (-1..1)
dataref("cmdRudder", "sim/flightmodel/controls/rudder", "writable")
-- Элероны (-1..1)
dataref("cmdAileron", "sim/flightmodel/controls/aileron", "writable")
-- Тяга двигателя 1 (0..1)
dataref("cmdThrottle1", "sim/flightmodel/engine/ENGN_thro[0]", "writable")
-- Тяга двигателя 2 (0..1)
dataref("cmdThrottle2", "sim/flightmodel/engine/ENGN_thro[1]", "writable")
-- Закрылки (градусы)
dataref("cmdFlap", "sim/flightmodel/controls/flaprat", "writable")

-- ============================================================
-- 3. КОНСТАНТЫ И ПОРОГИ
-- ============================================================

local ALPHA_CRITICAL = 16.0      -- критический угол атаки
local VVI_CRITICAL = -500.0      -- критическая вертикальная скорость (фут/мин)
local YAW_RATE_CRITICAL = 0.5    -- критическая угловая скорость (рад/с)
local ROLL_CRITICAL = 60.0       -- критический крен (градусы)
local SPEED_MAX_CRITICAL = 550.0 -- максимальная скорость (узлы)
local THROTTLE_ASYMMETRY = 30.0  -- допустимая разница тяги (%)

-- ============================================================
-- 4. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================

function sign(value)
    if value > 0 then return 1.0 end
    if value < 0 then return -1.0 end
    return 0.0
end

function clamp(value, minVal, maxVal)
    if value < minVal then return minVal end
    if value > maxVal then return maxVal end
    return value
end

function abs(value)
    if value < 0 then return -value end
    return value
end

-- ============================================================
-- 5. ДИАГНОСТИКА
-- ============================================================

function diagnose(a, vv, yr, r, spd, t1, t2)
    -- 1. Проверка сваливания (угол атаки + падение)
    local stall = (a > ALPHA_CRITICAL) and (vv < VVI_CRITICAL)
    
    -- 2. Проверка штопора (сваливание + вращение)
    local spin = stall and (abs(yr) > YAW_RATE_CRITICAL)
    
    -- 3. Проверка критического крена
    local rollCritical = (abs(r) > ROLL_CRITICAL)
    
    -- 4. Проверка асимметрии тяги
    local thrustAsymmetry = (abs(t1 - t2) > THROTTLE_ASYMMETRY)
    
    -- 5. Проверка превышения скорости
    local speedCritical = (spd > SPEED_MAX_CRITICAL)
    
    -- Приоритет: ШТОПОР → СВАЛИВАНИЕ → АСИММЕТРИЯ
    if spin then
        return "SPIN", 2
    elseif stall or rollCritical or speedCritical then
        return "STALL", 2
    elseif thrustAsymmetry then
        return "ASYMMETRY", 3
    else
        return "NORMAL", 0
    end
end

-- ============================================================
-- 6. СЦЕНАРИИ
-- ============================================================

function executeScenarioA(yawRate)
    override_controls = 1
    override_throttles = 1
    cmdElevator = -0.8
    cmdRudder = -sign(yawRate) * 1.0
    cmdAileron = 0.0
    cmdThrottle1 = 1.0
    cmdThrottle2 = 1.0
    cmdFlap = 5.0
end

function executeScenarioB(yawRate)
    override_controls = 1
    override_throttles = 1
    cmdElevator = -0.8
    cmdRudder = -sign(yawRate) * 1.0
    cmdAileron = 0.0
    cmdThrottle1 = 1.0
    cmdThrottle2 = 0.0
    cmdFlap = 0.0
end

function executeScenarioC(t1, t2, flapPos)
    override_controls = 0
    override_throttles = 1
    local avg = (t1 + t2) / 2.0
    cmdThrottle1 = avg / 100.0
    cmdThrottle2 = avg / 100.0
    cmdFlap = flapPos
end

function resetControls()
    override_controls = 0
    override_throttles = 0
    cmdElevator = 0.0
    cmdRudder = 0.0
    cmdAileron = 0.0
    cmdThrottle1 = throttle1 / 100.0
    cmdThrottle2 = throttle2 / 100.0
    cmdFlap = flapPos
end

-- ============================================================
-- 7. ВЫВОД В КОНСОЛЬ
-- ============================================================

function printStatus(status, scenario)
    local statusText = ""
    local scenarioText = ""
    
    if status == "NORMAL" then
        statusText = "✅ НОРМАЛЬНЫЙ РЕЖИМ"
        scenarioText = "❌ Сценарий не выбран"
    elseif status == "STALL" then
        statusText = "⚠️ СВАЛИВАНИЕ"
        scenarioText = "СЦЕНАРИЙ Б (разнотяг, закрылки убраны)"
    elseif status == "SPIN" then
        statusText = "🚨 ШТОПОР"
        scenarioText = "СЦЕНАРИЙ Б (разнотяг, закрылки убраны)"
    elseif status == "ASYMMETRY" then
        statusText = "🔄 АСИММЕТРИЯ ТЯГИ"
        scenarioText = "СЦЕНАРИЙ В (выравнивание тяги)"
    end
    
    print("═══════════════════════════════════════════════")
    print("              ARMS - СТАТУС СИСТЕМЫ           ")
    print("═══════════════════════════════════════════════")
    print("📌 СОСТОЯНИЕ САМОЛЁТА: " .. statusText)
    print("📊 Угол атаки: " .. string.format("%.1f", alpha) .. "°")
    print("📊 Скорость: " .. string.format("%.0f", speed) .. " узлов")
    print("📊 Крен: " .. string.format("%.1f", roll) .. "°")
    print("📊 Вращение: " .. string.format("%.2f", yawRate) .. " рад/с")
    print("📊 Вертикальная скорость: " .. string.format("%.0f", vvi) .. " фут/мин")
    print("📊 Тяга 1/2: " .. string.format("%.0f", throttle1) .. "% / " .. string.format("%.0f", throttle2) .. "%")
    print("🎯 СЦЕНАРИЙ: " .. scenarioText)
    print("🛠️ Руль высоты: " .. string.format("%.0f", cmdElevator * 100) .. "%")
    print("🛠️ Руль направления: " .. string.format("%.0f", cmdRudder * 100) .. "%")
    print("🛠️ Тяга левый: " .. string.format("%.0f", cmdThrottle1 * 100) .. "%")
    print("🛠️ Тяга правый: " .. string.format("%.0f", cmdThrottle2 * 100) .. "%")
    print("🛠️ Закрылки: " .. string.format("%.1f", cmdFlap) .. "°")
    print("═══════════════════════════════════════════════")
end

-- ============================================================
-- 8. ГЛАВНЫЙ ЦИКЛ (выполняется каждый кадр)
-- ============================================================

function flight_start()
    print("🛩️ ARMS загружена и готова к работе!")
    print("Ожидание данных от X‑Plane...")
end

do_every_draw(function()
    -- 8.1. Диагностика
    local status, scenario = diagnose(alpha, vvi, yawRate, roll, speed, throttle1, throttle2)
    
    -- 8.2. Выполнение сценария
    if scenario == 1 then
        executeScenarioA(yawRate)
    elseif scenario == 2 then
        executeScenarioB(yawRate)
    elseif scenario == 3 then
        executeScenarioC(throttle1, throttle2, flapPos)
    else
        resetControls()
    end
    
    -- 8.3. Вывод статуса (каждые 2 секунды)
    local currentTime = os.clock()
    if not lastPrintTime or (currentTime - lastPrintTime) > 2.0 then
        printStatus(status, scenario)
        lastPrintTime = currentTime
    end
end)
