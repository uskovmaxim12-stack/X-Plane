-- ============================================================
-- ARMS (Automatic Recovery Management System) - X-Plane 12
-- Версия: 5.0 Lua (полный аналог Arduino-кода)
-- Совместим с любым самолётом
-- ============================================================

-- ============================================================
-- 1. НАСТРОЙКИ (пороги)
-- ============================================================

local ALPHA_CRITICAL = 16.0        -- Критический угол атаки (градусы)
local VVI_CRITICAL = -500.0        -- Критическая вертикальная скорость (фут/мин)
local YAW_RATE_CRITICAL = 0.5      -- Критическое вращение (рад/с)
local ROLL_CRITICAL = 60.0         -- Критический крен (градусы)
local SPEED_MAX_CRITICAL = 550.0   -- Максимальная скорость (узлы)
local THROTTLE_ASYMMETRY = 30.0    -- Допустимая разница тяги (%)
local DELTA_P_THRESHOLD = 5.0      -- Порог асимметрии обдува

-- ============================================================
-- 2. ПЕРЕМЕННЫЕ СОСТОЯНИЯ
-- ============================================================

local status = "NORMAL"   -- NORMAL, STALL, SPIN, ASYMMETRY
local scenario = 0        -- 0-нет, 1-А, 2-Б, 3-В

local cmdElevator = 0.0
local cmdRudder = 0.0
local cmdAileron = 0.0
local cmdThrottle1 = 0.0
local cmdThrottle2 = 0.0
local cmdFlap = 0.0

local armsActive = true   -- Система включена по умолчанию

-- ============================================================
-- 3. ДОСТУП К ДАННЫМ X‑PLANE (Dataref'ы)
-- ============================================================

-- Входные данные (читаем из симулятора)
local alpha = dataref_table("sim/flightmodel/position/alpha")
local speed = dataref_table("sim/flightmodel/position/indicated_airspeed")
local roll = dataref_table("sim/flightmodel/position/phi")
local pitch = dataref_table("sim/flightmodel/position/theta")
local yawRate = dataref_table("sim/flightmodel/position/Q")
local vvi = dataref_table("sim/flightmodel/position/vvi_ftsec")
local gLoad = dataref_table("sim/flightmodel/position/gload")
local flapPos = dataref_table("sim/flightmodel/controls/flaprat")
local throttle1 = dataref_table("sim/flightmodel/engine/ENGN_thro_use[0]")
local throttle2 = dataref_table("sim/flightmodel/engine/ENGN_thro_use[1]")

-- Выходные команды (пишем в симулятор)
local overrideControl = dataref_table("sim/operation/override/override_control_surfaces")
local cmdElevatorDref = dataref_table("sim/flightmodel/controls/elevator")
local cmdRudderDref = dataref_table("sim/flightmodel/controls/rudder")
local cmdAileronDref = dataref_table("sim/flightmodel/controls/aileron")
local cmdThrottle1Dref = dataref_table("sim/flightmodel/engine/ENGN_thro_use[0]")
local cmdThrottle2Dref = dataref_table("sim/flightmodel/engine/ENGN_thro_use[1]")
local cmdFlapDref = dataref_table("sim/flightmodel/controls/flaprat")

-- ============================================================
-- 4. ЯДРО АЛГОРИТМА (точно как в Arduino-коде)
-- ============================================================

function clamp(value, minVal, maxVal)
    if value < minVal then return minVal end
    if value > maxVal then return maxVal end
    return value
end

function sign(value)
    if value > 0 then return 1.0 end
    if value < 0 then return -1.0 end
    return 0.0
end

function diagnose(alpha, vvi, yawRate, roll, speed, throttle1, throttle2)
    local stall = (alpha > ALPHA_CRITICAL) and (vvi < VVI_CRITICAL)
    local spin = stall and (math.abs(yawRate) > YAW_RATE_CRITICAL)
    local rollCritical = (math.abs(roll) > ROLL_CRITICAL)
    local thrustAsymmetry = (math.abs(throttle1 - throttle2) * 100 > THROTTLE_ASYMMETRY)
    local speedCritical = (speed > SPEED_MAX_CRITICAL)

    if spin then return "SPIN" end
    if stall or rollCritical or speedCritical then return "STALL" end
    if thrustAsymmetry then return "ASYMMETRY" end
    return "NORMAL"
end

function selectScenario(status, deltaP)
    if status == "NORMAL" then return 0 end
    if status == "SPIN" then return 2 end
    if status == "STALL" then
        if deltaP < DELTA_P_THRESHOLD then return 1 else return 2 end
    end
    if status == "ASYMMETRY" then return 3 end
    return 0
end

function executeScenarioA()
    cmdElevator = clamp(-0.8, -1, 1)
    cmdRudder = clamp(-sign(yawRate[0]) * 1.0, -1, 1)
    cmdAileron = 0.0
    cmdThrottle1 = 1.0
    cmdThrottle2 = 1.0
    cmdFlap = clamp(5.0, 0, 40)
end

function executeScenarioB()
    cmdElevator = clamp(-0.8, -1, 1)
    cmdRudder = clamp(-sign(yawRate[0]) * 1.0, -1, 1)
    cmdAileron = 0.0
    cmdThrottle1 = 1.0
    cmdThrottle2 = 0.0
    cmdFlap = 0.0
end

function executeScenarioC()
    cmdElevator = 0.0
    cmdRudder = clamp(-sign(yawRate[0]) * 0.5, -1, 1)
    cmdAileron = 0.0
    local avg = (throttle1[0] + throttle2[0]) / 2.0
    cmdThrottle1 = avg
    cmdThrottle2 = avg
    cmdFlap = flapPos[0]
end

function resetCommands()
    cmdElevator = 0.0
    cmdRudder = 0.0
    cmdAileron = 0.0
    cmdThrottle1 = throttle1[0]
    cmdThrottle2 = throttle2[0]
    cmdFlap = flapPos[0]
end

-- ============================================================
-- 5. ГЛАВНАЯ ФУНКЦИЯ (ВЫЗЫВАЕТСЯ КАЖДЫЙ КАДР)
-- ============================================================

function updateARMS()
    if not armsActive then return end

    -- 5.1. Читаем данные из X‑Plane
    local a = alpha[0] or 0
    local spd = speed[0] or 0
    local r = roll[0] or 0
    local yr = yawRate[0] or 0
    local vv = vvi[0] or 0
    local t1 = (throttle1[0] or 0) * 100
    local t2 = (throttle2[0] or 0) * 100

    -- 5.2. Диагностика
    status = diagnose(a, vv, yr, r, spd, t1, t2)

    -- 5.3. Расчёт асимметрии
    local deltaP = math.abs(r) * 0.5 + math.abs(yr) * 10.0

    -- 5.4. Выбор сценария
    scenario = selectScenario(status, deltaP)

    -- 5.5. Выполнение сценария
    if scenario == 1 then
        executeScenarioA()
    elseif scenario == 2 then
        executeScenarioB()
    elseif scenario == 3 then
        executeScenarioC()
    else
        resetCommands()
    end

    -- 5.6. Отправка команд в симулятор
    if scenario ~= 0 then
        overrideControl[0] = 1  -- Включаем приоритет команд
        cmdElevatorDref[0] = cmdElevator
        cmdRudderDref[0] = cmdRudder
        cmdAileronDref[0] = cmdAileron
        cmdThrottle1Dref[0] = cmdThrottle1
        cmdThrottle2Dref[0] = cmdThrottle2
        cmdFlapDref[0] = cmdFlap
    else
        overrideControl[0] = 0  -- Отключаем приоритет
    end

    -- 5.7. Логирование (опционально)
    -- logStatus(status, scenario)
end

-- ============================================================
-- 6. ПОДКЛЮЧЕНИЕ К FLYWITHLUA
-- ============================================================

-- Вызов функции каждый кадр (30 раз в секунду)
do_every_frame("updateARMS()")

-- Сообщение в консоль X‑Plane
logMsg("========================================")
logMsg(" ARMS SYSTEM v5.0 LOADED")
logMsg(" Status: ACTIVE")
logMsg(" Aircraft: " .. PLANE_ICAO)
logMsg("========================================")

-- Кнопка для ручной активации/деактивации (Ctrl+A)
function toggleARMS()
    armsActive = not armsActive
    if armsActive then
        logMsg("ARMS: ACTIVATED")
    else
        logMsg("ARMS: DEACTIVATED")
        overrideControl[0] = 0
    end
end

add_keybinding("Ctrl + A", "Toggle ARMS", "toggleARMS()")
