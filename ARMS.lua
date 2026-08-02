-- ============================================================
-- ARMS - Adaptive Recovery Management System
-- FlyWithLua для X-Plane 12
-- Версия: 9.0 (Ультимативная, без лишней логики)
-- ============================================================

-- ============================================================
-- 1. ПОРОГИ (жёсткие, проверенные)
-- ============================================================

local ALPHA_CRITICAL = 16.0      -- Угол атаки > 16° (сваливание)
local YAW_RATE_CRITICAL = 0.4    -- Вращение > 0.4 рад/с (штопор)
local VVI_CRITICAL = -400.0      -- Вертикальная скорость падения

-- ============================================================
-- 2. DATAREF'Ы (ТОЛЬКО ТЕ, ЧТО НУЖНЫ)
-- ============================================================

local alpha = globalPropertyf("sim/flightmodel/position/alpha")
local yaw = globalPropertyf("sim/flightmodel/position/Q")
local vvi = globalPropertyf("sim/flightmodel/position/vvi_fpm")
local throttle1 = globalPropertyf("sim/flightmodel/engine/ENGN_throttle_use[0]")
local throttle2 = globalPropertyf("sim/flightmodel/engine/ENGN_throttle_use[1]")

local override = globalPropertyf("sim/operation/override/override_control_surfaces")
local cmd_elevator = globalPropertyf("sim/flightmodel/controls/elevator_def")
local cmd_rudder = globalPropertyf("sim/flightmodel/controls/rudder_def")
local cmd_throttle1 = globalPropertyf("sim/flightmodel/engine/ENGN_throttle_use[0]")
local cmd_throttle2 = globalPropertyf("sim/flightmodel/engine/ENGN_throttle_use[1]")
local cmd_flap = globalPropertyf("sim/flightmodel/controls/flaprat")

-- ============================================================
-- 3. ГЛАВНАЯ ЛОГИКА (ПРОСТАЯ КАК ДВАЖДЫ ДВА)
-- ============================================================

function arms_loop()
    -- Читаем данные
    local a = (alpha() or 0) * 57.2958
    local yr = yaw() or 0
    local vv = vvi() or 0
    local t1 = (throttle1() or 0) * 100
    local t2 = (throttle2() or 0) * 100

    -- Проверяем штопор
    local isSpin = (a > ALPHA_CRITICAL) and (vv < VVI_CRITICAL) and (math.abs(yr) > YAW_RATE_CRITICAL)

    if isSpin then
        -- Вмешиваемся
        override(1)
        cmd_elevator(-0.8)                         -- Штурвал от себя (опустить нос)
        cmd_rudder(-math.sign(yr) * 1.0)           -- Педаль против вращения
        cmd_throttle1(1.0)                         -- Левый двигатель — полная тяга
        cmd_throttle2(1.0)                         -- Правый двигатель — полная тяга
        cmd_flap(0.0)                              -- Закрылки убраны
    else
        -- Не вмешиваемся
        if override() == 1 then
            override(0)
        end
    end
end

-- ============================================================
-- 4. РЕГИСТРАЦИЯ
-- ============================================================

do_every_frame("arms_loop()")
logMsg("========================================")
logMsg(" ARMS v9.0 LOADED (Ultimate Edition)")
logMsg("========================================")
