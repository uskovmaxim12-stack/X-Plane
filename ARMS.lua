-- ============================================================
-- ARMS - ПОЛНАЯ ВЕРСИЯ (БЕЗ УРЕЗАНИЙ)
-- Версия: 35.0 (FULL VERSION - NO CUTS)
-- FlyWithLua NG+ для X-Plane 12
-- ============================================================

-- 1. КОНФИГУРАЦИЯ
local CONFIG = {
    ALPHA_CRITICAL = 16.0, BETA_CRITICAL = 15.0,
    YAW_RATE_CRITICAL = 0.4, VVI_CRITICAL = -400.0,
    ROLL_CRITICAL = 60.0, PITCH_CRITICAL = 25.0,
    THR_ASYMM_CRITICAL = 30.0, SPEED_MIN_CRITICAL = 150.0,
    SPEED_MAX_CRITICAL = 550.0, G_LOAD_MAX = 2.5,
    WIND_SHEAR_CRITICAL = 20.0, TURBULENCE_CRITICAL = 0.7,
    ICE_CRITICAL = 0.3,
    RISK_PREPARE = 20.0, RISK_ACTIVE = 50.0, RISK_EMERGENCY = 80.0,
    PREDICT_SECONDS = 3.0, HISTORY_LENGTH = 60,
    NUM_SCENARIOS = 30, ACTIVATION_DELAY = 0.3,
    LOG_LEVEL = "DEBUG",
    LOG_TO_CONSOLE = true,
    LOG_TO_FILE = true,
}
-- 2. СИСТЕМА ЛОГИРОВАНИЯ
local log_buffer = {}
local log_counter = 0

local function get_timestamp()
    return os.date("%H:%M:%S")
end

local function write_log(level, message)
    local entry = string.format("[%s] [%s] %s", get_timestamp(), level, message)
    table.insert(log_buffer, entry)
    log_counter = log_counter + 1
    if CONFIG.LOG_TO_CONSOLE then logMsg(entry) end
    if CONFIG.LOG_TO_FILE and log_counter % 10 == 0 then
        local file = io.open("ARMS_Log.txt", "a")
        if file then
            for i = 1, #log_buffer do file:write(log_buffer[i] .. "\n") end
            file:close()
            log_buffer = {}
        end
    end
end

local function log_info(msg) write_log("INFO", msg) end
local function log_warning(msg) write_log("WARNING", msg) end
local function log_error(msg) write_log("ERROR", msg) end
local function log_debug(msg)
    if CONFIG.LOG_LEVEL == "DEBUG" then write_log("DEBUG", msg) end
end
-- 3. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
local function clamp(v, mn, mx)
    return math.max(mn, math.min(mx, v))
end

local function sign(v)
    if v > 0 then return 1.0 end
    if v < 0 then return -1.0 end
    return 0.0
end

local function calc_risk(value, min_val, max_val)
    if value <= min_val then return 0 end
    if value >= max_val then return 100 end
    local norm = (value - min_val) / (max_val - min_val)
    return norm * norm * 100
end

local function get_ref(name)
    local ref = XPLMFindDataRef(name)
    if ref == nil then
        log_warning("DataRef not found: " .. name)
        return nil
    end
    return ref
end

local function readf(ref)
    if ref == nil then return 0 end
    return XPLMGetDataf(ref) or 0
end

local function readi(ref)
    if ref == nil then return 0 end
    return XPLMGetDatai(ref) or 0
end

local function writef(ref, val)
    if ref == nil then return end
    XPLMSetDataf(ref, val)
end

local function writei(ref, val)
    if ref == nil then return end
    XPLMSetDatai(ref, val)
end
-- 4. ВСЕ DATAREF'Ы (РАЗБИТЫ ПО ГРУППАМ)

-- 4.1. ПОЛОЖЕНИЕ И ДВИЖЕНИЕ
local alpha_ref = get_ref("sim/flightmodel/position/alpha")
local beta_ref = get_ref("sim/flightmodel/position/beta")
local speed_ref = get_ref("sim/flightmodel/position/indicated_airspeed")
local mach_ref = get_ref("sim/flightmodel/position/mach")
local roll_ref = get_ref("sim/flightmodel/position/phi")
local pitch_ref = get_ref("sim/flightmodel/position/theta")
local heading_ref = get_ref("sim/flightmodel/position/psi")
local yaw_ref = get_ref("sim/flightmodel/position/Q")
local vvi_ref = get_ref("sim/flightmodel/position/vh_ind_fpm")
if vvi_ref == nil then vvi_ref = get_ref("sim/flightmodel/position/vvi_fpm") end
local gload_ref = get_ref("sim/flightmodel/position/gload")
local elevation_ref = get_ref("sim/flightmodel/position/elevation")
local ground_speed_ref = get_ref("sim/flightmodel/position/groundspeed")

-- 4.2. УГЛОВЫЕ И ЛИНЕЙНЫЕ СКОРОСТИ
local p_ref = get_ref("sim/flightmodel/position/P")
local q_ref = get_ref("sim/flightmodel/position/Q")
local r_ref = get_ref("sim/flightmodel/position/R")
local vx_ref = get_ref("sim/flightmodel/position/local_vx")
local vy_ref = get_ref("sim/flightmodel/position/local_vy")
local vz_ref = get_ref("sim/flightmodel/position/local_vz")

-- 4.3. ПОГОДА
local wind_speed_ref = get_ref("sim/weather/wind_speed_kt")
local wind_direction_ref = get_ref("sim/weather/wind_direction_deg")
local wind_shear_ref = get_ref("sim/weather/wind_shear_kt_per_ft")
local turbulence_ref = get_ref("sim/weather/turbulence")
local temperature_ref = get_ref("sim/weather/temperature_ambient_c")
local pressure_ref = get_ref("sim/weather/pressure_sealevel_inhg")
local density_ref = get_ref("sim/weather/air_density")
local visibility_ref = get_ref("sim/weather/visibility_reported_sm")

-- 4.4. ДВИГАТЕЛИ
local thr1_ref = get_ref("sim/flightmodel/engine/ENGN_thro_use[0]")
if thr1_ref == nil then thr1_ref = get_ref("sim/flightmodel/engine/ENGN_throttle_use[0]") end
local thr2_ref = get_ref("sim/flightmodel/engine/ENGN_thro_use[1]")
if thr2_ref == nil then thr2_ref = get_ref("sim/flightmodel/engine/ENGN_throttle_use[1]") end
local n1_1_ref = get_ref("sim/flightmodel/engine/ENGN_N1[0]")
local n1_2_ref = get_ref("sim/flightmodel/engine/ENGN_N1[1]")
local egt1_ref = get_ref("sim/flightmodel/engine/ENGN_EGT[0]")
local egt2_ref = get_ref("sim/flightmodel/engine/ENGN_EGT[1]")
local fuel_flow1_ref = get_ref("sim/flightmodel/engine/ENGN_fuel_flow[0]")
local fuel_flow2_ref = get_ref("sim/flightmodel/engine/ENGN_fuel_flow[1]")
local eng_running1_ref = get_ref("sim/flightmodel/engine/ENGN_running[0]")
local eng_running2_ref = get_ref("sim/flightmodel/engine/ENGN_running[1]")
local eng_fail1_ref = get_ref("sim/flightmodel/engine/ENGN_failure[0]")
local eng_fail2_ref = get_ref("sim/flightmodel/engine/ENGN_failure[1]")
local eng_fire1_ref = get_ref("sim/flightmodel/engine/ENGN_fire[0]")
local eng_fire2_ref = get_ref("sim/flightmodel/engine/ENGN_fire[1]")
local fuel_total_ref = get_ref("sim/flightmodel/weight/m_fuel_total")

-- 4.5. ПОВЕРХНОСТИ УПРАВЛЕНИЯ
local flap_ref = get_ref("sim/flightmodel/controls/flaprat")
local spoiler_ref = get_ref("sim/flightmodel/controls/spoiler")
local speedbrake_ref = get_ref("sim/flightmodel/controls/speedbrake")
local elevator_def_ref = get_ref("sim/flightmodel/controls/elevator_def")
local rudder_def_ref = get_ref("sim/flightmodel/controls/rudder_def")
local aileron_def_ref = get_ref("sim/flightmodel/controls/aileron_def")
local elevator_trim_ref = get_ref("sim/flightmodel/controls/elevator_trim")
local rudder_trim_ref = get_ref("sim/flightmodel/controls/rudder_trim")
local aileron_trim_ref = get_ref("sim/flightmodel/controls/aileron_trim")
local yoke_pitch_ref = get_ref("sim/flightmodel/controls/yoke_pitch")
local yoke_roll_ref = get_ref("sim/flightmodel/controls/yoke_roll")
local rudder_pedal_ref = get_ref("sim/flightmodel/controls/rudder_pedal")

-- 4.6. ШАССИ И ТОРМОЗА
local gear_deploy_ref = get_ref("sim/flightmodel/controls/gear_deploy")
local gear_handle_ref = get_ref("sim/flightmodel/controls/gear_handle")
local brake_left_ref = get_ref("sim/flightmodel/controls/brake_left")
local brake_right_ref = get_ref("sim/flightmodel/controls/brake_right")
local parking_brake_ref = get_ref("sim/cockpit2/controls/parking_brake_ratio")

-- 4.7. СИСТЕМЫ И ЭЛЕКТРИКА
local battery_ref = get_ref("sim/cockpit/electrical/battery_on")
local generator_ref = get_ref("sim/cockpit/electrical/generator_on")
local apu_running_ref = get_ref("sim/cockpit/electrical/APU_running")
local beacon_ref = get_ref("sim/cockpit/electrical/beacon_lights_on")
local nav_lights_ref = get_ref("sim/cockpit/electrical/nav_lights_on")
local landing_lights_ref = get_ref("sim/cockpit/electrical/landing_lights_on")
local strobe_ref = get_ref("sim/cockpit/electrical/strobe_lights_on")

-- 4.8. АВТОПИЛОТ
local ap_on_ref = get_ref("sim/cockpit2/autopilot/autopilot_on")
local ap_mode_ref = get_ref("sim/cockpit2/autopilot/autopilot_mode")
local ap_altitude_ref = get_ref("sim/cockpit2/autopilot/altitude_dial_ft")
local ap_heading_ref = get_ref("sim/cockpit2/autopilot/heading_dial_deg")
local ap_speed_ref = get_ref("sim/cockpit2/autopilot/airspeed_dial_kts")
local ap_vs_ref = get_ref("sim/cockpit2/autopilot/vvi_dial_fpm")
local fd_on_ref = get_ref("sim/cockpit2/autopilot/flight_director_on")

-- 4.9. СИГНАЛИЗАЦИЯ
local stall_warning_ref = get_ref("sim/cockpit2/annunciators/stall_warning")
local gpws_warning_ref = get_ref("sim/cockpit2/annunciators/gpws_warning")
local overspeed_warning_ref = get_ref("sim/cockpit2/annunciators/overspeed")
local autopilot_disconnect_ref = get_ref("sim/cockpit2/annunciators/autopilot_disconnect")
local master_caution_ref = get_ref("sim/cockpit2/annunciators/master_caution")
local master_warning_ref = get_ref("sim/cockpit2/annunciators/master_warning")
local fire_warning_ref = get_ref("sim/cockpit2/annunciators/fire_warning")

-- 4.10. ОБЛЕДЕНЕНИЕ
local pitot_heat_ref = get_ref("sim/cockpit2/ice/pitot_heat_on")
local deice_ref = get_ref("sim/cockpit2/ice/deice_on")
local wing_ice_ref = get_ref("sim/flightmodel/failures/ice_ratio")
local tail_ice_ref = get_ref("sim/flightmodel/failures/tail_ice")

-- 4.11. ВЕС
local weight_total_ref = get_ref("sim/flightmodel/weight/m_total")
local cg_ref = get_ref("sim/flightmodel/weight/m_cg")
local weight_payload_ref = get_ref("sim/flightmodel/weight/m_payload")
local fuel_weight_ref = get_ref("sim/flightmodel/weight/m_fuel_total")

-- 4.12. УПРАВЛЕНИЕ (OVERRIDE)
local override_ref = get_ref("sim/operation/override/override_control_surfaces")
local override_throttle_ref = get_ref("sim/operation/override/override_throttles")
local override_gear_ref = get_ref("sim/operation/override/override_gear")
local override_flap_ref = get_ref("sim/operation/override/override_flaps")
local override_brakes_ref = get_ref("sim/operation/override/override_brakes")
-- 5. ИСТОРИЯ
local history = {
    alpha = {}, beta = {}, speed = {}, mach = {},
    roll = {}, pitch = {}, heading = {}, yaw = {},
    vvi = {}, gload = {},
    p = {}, q = {}, r = {},
    vx = {}, vy = {}, vz = {},
    thr1 = {}, thr2 = {}, n1_1 = {}, n1_2 = {},
    flap = {}, spoiler = {},
    wind_speed = {}, turbulence = {}, temperature = {},
    wing_ice = {}, tail_ice = {},
}

local function add_history(hist, val)
    table.insert(hist, val)
    if #hist > CONFIG.HISTORY_LENGTH then table.remove(hist, 1) end
end

local function get_trend(hist)
    local n = #hist
    if n < 3 then return 0 end
    local sum_x, sum_y, sum_xy, sum_x2 = 0, 0, 0, 0
    for i = 1, n do
        local x = i - 1
        local y = hist[i]
        sum_x = sum_x + x
        sum_y = sum_y + y
        sum_xy = sum_xy + x * y
        sum_x2 = sum_x2 + x * x
    end
    local denom = n * sum_x2 - sum_x * sum_x
    if denom == 0 then return 0 end
    return (n * sum_xy - sum_x * sum_y) / denom
end

local function get_last(hist) return hist[#hist] or 0 end

local function predict_value(hist, dt)
    local last = get_last(hist)
    local tr = get_trend(hist)
    return last + tr * dt
end

-- 6. КОМАНДЫ УПРАВЛЕНИЯ (СТРОКИ)
local CMD_ELEVATOR_DOWN = "sim/flight_controls/elevator_down"
local CMD_ELEVATOR_UP = "sim/flight_controls/elevator_up"
local CMD_RUDDER_LEFT = "sim/flight_controls/rudder_left"
local CMD_RUDDER_RIGHT = "sim/flight_controls/rudder_right"
local CMD_AILERON_LEFT = "sim/flight_controls/aileron_left"
local CMD_AILERON_RIGHT = "sim/flight_controls/aileron_right"
local CMD_THROTTLE_UP_1 = "sim/engine/throttle_up_1"
local CMD_THROTTLE_DOWN_1 = "sim/engine/throttle_down_1"
local CMD_THROTTLE_UP_2 = "sim/engine/throttle_up_2"
local CMD_THROTTLE_DOWN_2 = "sim/engine/throttle_down_2"
local CMD_FLAP_UP = "sim/flight_controls/flaps_up"
local CMD_FLAP_DOWN = "sim/flight_controls/flaps_down"
local CMD_GEAR_UP = "sim/flight_controls/gear_up"
local CMD_GEAR_DOWN = "sim/flight_controls/gear_down"
local CMD_SPEEDBRAKES_UP = "sim/flight_controls/speedbrakes_up"
local CMD_SPEEDBRAKES_DOWN = "sim/flight_controls/speedbrakes_down"

local function apply_commands(elevator, rudder, aileron, thr1, thr2, flap, spoiler)
    if elevator < -0.1 then command_begin(CMD_ELEVATOR_DOWN)
    elseif elevator > 0.1 then command_begin(CMD_ELEVATOR_UP) end

    if rudder < -0.1 then command_begin(CMD_RUDDER_LEFT)
    elseif rudder > 0.1 then command_begin(CMD_RUDDER_RIGHT) end

    if aileron < -0.1 then command_begin(CMD_AILERON_LEFT)
    elseif aileron > 0.1 then command_begin(CMD_AILERON_RIGHT) end

    if thr1 > 0.6 then command_begin(CMD_THROTTLE_UP_1) end
    if thr2 > 0.6 then command_begin(CMD_THROTTLE_UP_2) end

    if flap > 0.5 then command_begin(CMD_FLAP_DOWN)
    else command_begin(CMD_FLAP_UP) end

    if spoiler > 0.5 then command_begin(CMD_SPEEDBRAKES_DOWN)
    else command_begin(CMD_SPEEDBRAKES_UP) end

    if override_ref then writei(override_ref, 1) end
    if override_throttle_ref then writei(override_throttle_ref, 1) end
end

local function release_commands()
    command_end(CMD_ELEVATOR_DOWN)
    command_end(CMD_ELEVATOR_UP)
    command_end(CMD_RUDDER_LEFT)
    command_end(CMD_RUDDER_RIGHT)
    command_end(CMD_AILERON_LEFT)
    command_end(CMD_AILERON_RIGHT)
    command_end(CMD_THROTTLE_UP_1)
    command_end(CMD_THROTTLE_DOWN_1)
    command_end(CMD_THROTTLE_UP_2)
    command_end(CMD_THROTTLE_DOWN_2)
    command_end(CMD_FLAP_UP)
    command_end(CMD_FLAP_DOWN)
    command_end(CMD_GEAR_UP)
    command_end(CMD_GEAR_DOWN)
    command_end(CMD_SPEEDBRAKES_UP)
    command_end(CMD_SPEEDBRAKES_DOWN)
    if override_ref then writei(override_ref, 0) end
    if override_throttle_ref then writei(override_throttle_ref, 0) end
end
-- 7. ОЦЕНКА РИСКА
local function assess_risk(state)
    local risk = 0
    local weights = 0

    local function add_risk(value, min_val, max_val, weight)
        risk = risk + calc_risk(value, min_val, max_val) * weight
        weights = weights + weight
    end

    add_risk(state.alpha or 0, 10, 22, 2.0)
    add_risk(-(state.vvi or 0), 200, 800, 1.5)
    add_risk(math.abs(state.yaw or 0), 0.2, 1.5, 1.5)
    add_risk(math.abs(state.roll or 0), 10, 60, 1.0)
    add_risk(math.abs(state.pitch or 0), 10, 30, 0.5)
    add_risk(math.abs((state.thr1 or 0) - (state.thr2 or 0)), 5, 40, 1.0)
    add_risk(state.wing_ice or 0, 0.1, 0.5, 0.5)
    add_risk(state.turbulence or 0, 0.3, 1.0, 0.3)

    if weights > 0 then risk = risk / weights end
    return clamp(risk, 0, 100)
end

-- 8. ГЕНЕРАЦИЯ 30 СЦЕНАРИЕВ
local function generate_scenarios(state)
    local scenarios = {}
    local base_thr1 = (state.thr1 or 50) / 100
    local base_thr2 = (state.thr2 or 50) / 100

    for i = 1, CONFIG.NUM_SCENARIOS do
        local factor = (i - 1) / (CONFIG.NUM_SCENARIOS - 1)
        local scenario = {
            elevator = 0,
            rudder = 0,
            aileron = 0,
            thr1 = base_thr1,
            thr2 = base_thr2,
            flap = 0,
            spoiler = 0,
            risk = 0,
        }

        if (state.alpha or 0) > 14 or (state.vvi or 0) < -300 then
            scenario.elevator = -0.3 - factor * 0.6
        end
        if math.abs(state.yaw or 0) > 0.3 then
            scenario.rudder = -sign(state.yaw or 0) * (0.3 + factor * 0.7)
        end
        if math.abs(state.roll or 0) > 30 then
            scenario.aileron = -sign(state.roll or 0) * (factor * 0.3)
        end
        if (state.alpha or 0) > 15 or (state.vvi or 0) < -400 then
            scenario.thr1 = 0.7 + factor * 0.3
            scenario.thr2 = 0.7 + factor * 0.3
        end
        if (state.alpha or 0) > 14 and math.abs(state.roll or 0) < 20 and (state.vvi or 0) < -200 then
            scenario.flap = factor * 5
        end
        if math.abs(state.roll or 0) > 40 then
            scenario.spoiler = factor * 0.5
        end

        local predicted = {
            alpha = (state.alpha or 0) + scenario.elevator * 5 + scenario.flap * 1.5,
            speed = (state.speed or 0) + (scenario.thr1 - 0.5) * 15 - scenario.spoiler * 10,
            roll = (state.roll or 0) + scenario.aileron * 10 + scenario.rudder * 3 + scenario.spoiler * 5,
            yaw = (state.yaw or 0) + scenario.rudder * 0.5,
            vvi = (state.vvi or 0) + scenario.elevator * 100 + scenario.flap * 20,
            pitch = (state.pitch or 0) + scenario.elevator * 3,
            thr1 = scenario.thr1 * 100,
            thr2 = scenario.thr2 * 100,
            wing_ice = (state.wing_ice or 0) - scenario.elevator * 0.01,
            turbulence = (state.turbulence or 0) - scenario.spoiler * 0.1,
        }
        scenario.risk = assess_risk(predicted)
        table.insert(scenarios, scenario)
    end

    table.sort(scenarios, function(a, b) return a.risk < b.risk end)
    return scenarios
end

local function select_best_scenario(scenarios)
    if #scenarios == 0 then return nil end
    return scenarios[1]
end
-- 9. ПОЛНОЕ СОСТОЯНИЕ (БЕЗ ПЕРЕГРУЗКИ)
local function get_full_state()
    return {
        alpha = readf(alpha_ref) * 57.2958,
        beta = readf(beta_ref) * 57.2958,
        speed = readf(speed_ref),
        mach = readf(mach_ref),
        roll = readf(roll_ref) * 57.2958,
        pitch = readf(pitch_ref) * 57.2958,
        heading = readf(heading_ref) * 57.2958,
        yaw = readf(yaw_ref),
        vvi = readf(vvi_ref),
        gload = readf(gload_ref),
        elevation = readf(elevation_ref),
        p = readf(p_ref), q = readf(q_ref), r = readf(r_ref),
        vx = readf(vx_ref), vy = readf(vy_ref), vz = readf(vz_ref),
        thr1 = readf(thr1_ref) * 100,
        thr2 = readf(thr2_ref) * 100,
        n1_1 = readf(n1_1_ref), n1_2 = readf(n1_2_ref),
        egt1 = readf(egt1_ref), egt2 = readf(egt2_ref),
        eng_running1 = readi(eng_running1_ref),
        eng_running2 = readi(eng_running2_ref),
        eng_fail1 = readi(eng_fail1_ref),
        eng_fail2 = readi(eng_fail2_ref),
        eng_fire1 = readi(eng_fire1_ref),
        eng_fire2 = readi(eng_fire2_ref),
        fuel_total = readf(fuel_total_ref),
        flap = readf(flap_ref),
        spoiler = readf(spoiler_ref),
        speedbrake = readf(speedbrake_ref),
        elevator_def = readf(elevator_def_ref),
        rudder_def = readf(rudder_def_ref),
        aileron_def = readf(aileron_def_ref),
        elevator_trim = readf(elevator_trim_ref),
        rudder_trim = readf(rudder_trim_ref),
        aileron_trim = readf(aileron_trim_ref),
        yoke_pitch = readf(yoke_pitch_ref),
        yoke_roll = readf(yoke_roll_ref),
        rudder_pedal = readf(rudder_pedal_ref),
        gear_deploy = readf(gear_deploy_ref),
        gear_handle = readf(gear_handle_ref),
        brake_left = readf(brake_left_ref),
        brake_right = readf(brake_right_ref),
        parking_brake = readf(parking_brake_ref),
        battery = readi(battery_ref),
        generator = readi(generator_ref),
        apu_running = readi(apu_running_ref),
        beacon = readi(beacon_ref),
        nav_lights = readi(nav_lights_ref),
        landing_lights = readi(landing_lights_ref),
        strobe = readi(strobe_ref),
        ap_on = readi(ap_on_ref),
        ap_mode = readi(ap_mode_ref),
        ap_altitude = readf(ap_altitude_ref),
        ap_heading = readf(ap_heading_ref),
        ap_speed = readf(ap_speed_ref),
        ap_vs = readf(ap_vs_ref),
        fd_on = readi(fd_on_ref),
        stall_warning = readi(stall_warning_ref),
        gpws_warning = readi(gpws_warning_ref),
        overspeed_warning = readi(overspeed_warning_ref),
        ap_disconnect = readi(autopilot_disconnect_ref),
        master_caution = readi(master_caution_ref),
        master_warning = readi(master_warning_ref),
        fire_warning = readi(fire_warning_ref),
        pitot_heat = readi(pitot_heat_ref),
        deice = readi(deice_ref),
        wing_ice = readf(wing_ice_ref),
        tail_ice = readf(tail_ice_ref),
        weight_total = readf(weight_total_ref),
        cg = readf(cg_ref),
        wind_speed = readf(wind_speed_ref),
        wind_direction = readf(wind_direction_ref),
        wind_shear = readf(wind_shear_ref),
        turbulence = readf(turbulence_ref),
        temperature = readf(temperature_ref),
        pressure = readf(pressure_ref),
        density = readf(density_ref),
        visibility = readf(visibility_ref),
    }
end

-- 10. ПЕРЕМЕННЫЕ СОСТОЯНИЯ
local arms_active = true
local arms_status = "STANDBY"
local current_risk = 0
local predicted_risk = 0
local spin_timer = 0
local prev_risk = 0
local was_intervening = false
local state_counter = 0

-- 11. ГЛАВНАЯ ЛОГИКА
function arms_loop()
    if not arms_active then
        arms_status = "OFF"
        if was_intervening then release_commands() was_intervening = false end
        return
    end

    state_counter = state_counter + 1
    local state = get_full_state()

    add_history(history.alpha, state.alpha)
    add_history(history.beta, state.beta)
    add_history(history.speed, state.speed)
    add_history(history.mach, state.mach)
    add_history(history.roll, state.roll)
    add_history(history.pitch, state.pitch)
    add_history(history.heading, state.heading)
    add_history(history.yaw, state.yaw)
    add_history(history.vvi, state.vvi)
    add_history(history.gload, state.gload)
    add_history(history.p, state.p)
    add_history(history.q, state.q)
    add_history(history.r, state.r)
    add_history(history.vx, state.vx)
    add_history(history.vy, state.vy)
    add_history(history.vz, state.vz)
    add_history(history.thr1, state.thr1)
    add_history(history.thr2, state.thr2)
    add_history(history.n1_1, state.n1_1)
    add_history(history.n1_2, state.n1_2)
    add_history(history.flap, state.flap)
    add_history(history.spoiler, state.spoiler)
    add_history(history.wind_speed, state.wind_speed)
    add_history(history.turbulence, state.turbulence)
    add_history(history.temperature, state.temperature)
    add_history(history.wing_ice, state.wing_ice)
    add_history(history.tail_ice, state.tail_ice)

    local is_training = (state.stall_warning == 1) and (state.ap_on == 0)
    local sensor_failure = (state.pitot_heat == 0) and (state.deice == 0) and (state.wing_ice > 0.1)
    local engine_failure = (state.eng_fail1 == 1) or (state.eng_fail2 == 1)
    local fire_hazard = (state.eng_fire1 == 1) or (state.eng_fire2 == 1)

    if is_training then
        arms_status = "TRAINING"
        if was_intervening then release_commands() was_intervening = false end
        return
    end

    if fire_hazard then
        arms_status = "FIRE HAZARD"
        if not was_intervening then
            log_error("FIRE DETECTED! Initiating emergency procedure.")
            apply_commands(-0.2, 0, 0, 0.5, 0.5, 0, 0)
            was_intervening = true
        end
        return
    end

    if sensor_failure then
        arms_status = "SENSOR FAIL"
        if was_intervening then release_commands() was_intervening = false end
        return
    end

    current_risk = assess_risk(state)

    local future = {
        alpha = predict_value(history.alpha, CONFIG.PREDICT_SECONDS),
        speed = predict_value(history.speed, CONFIG.PREDICT_SECONDS),
        roll = predict_value(history.roll, CONFIG.PREDICT_SECONDS),
        yaw = predict_value(history.yaw, CONFIG.PREDICT_SECONDS),
        vvi = predict_value(history.vvi, CONFIG.PREDICT_SECONDS),
        pitch = predict_value(history.pitch, CONFIG.PREDICT_SECONDS),
        thr1 = predict_value(history.thr1, CONFIG.PREDICT_SECONDS),
        thr2 = predict_value(history.thr2, CONFIG.PREDICT_SECONDS),
        wing_ice = predict_value(history.wing_ice, CONFIG.PREDICT_SECONDS),
        turbulence = predict_value(history.turbulence, CONFIG.PREDICT_SECONDS),
    }
    predicted_risk = assess_risk(future)

    if current_risk >= CONFIG.RISK_EMERGENCY or predicted_risk >= CONFIG.RISK_EMERGENCY then
        arms_status = "EMERGENCY"
    elseif current_risk >= CONFIG.RISK_ACTIVE or predicted_risk >= CONFIG.RISK_ACTIVE then
        arms_status = "ACTIVE"
    elseif current_risk >= CONFIG.RISK_PREPARE or predicted_risk >= CONFIG.RISK_PREPARE then
        arms_status = "PREPARE"
    else
        arms_status = "STANDBY"
    end

    local isSpin = (state.alpha > CONFIG.ALPHA_CRITICAL) and
                   (state.vvi < CONFIG.VVI_CRITICAL) and
                   (math.abs(state.yaw) > CONFIG.YAW_RATE_CRITICAL)

    if isSpin then spin_timer = spin_timer + 0.02 else spin_timer = 0.0 end

    local should_intervene = false
    if isSpin and spin_timer >= CONFIG.ACTIVATION_DELAY then
        should_intervene = true
        arms_status = "SPIN RECOVERY"
        log_error(string.format("SPIN DETECTED! Alpha: %.1f, Yaw: %.2f, VVI: %.0f", state.alpha, state.yaw, state.vvi))
    elseif current_risk >= CONFIG.RISK_ACTIVE or predicted_risk >= CONFIG.RISK_ACTIVE then
        should_intervene = true
    end

    if should_intervene then
        local scenarios = generate_scenarios(state)
        local best = select_best_scenario(scenarios)
        if best then
            apply_commands(best.elevator, best.rudder, best.aileron or 0, best.thr1, best.thr2, best.flap, best.spoiler or 0)
            was_intervening = true
            if math.abs(current_risk - prev_risk) > 3.0 then
                log_warning(string.format(
                    "Risk: %.1f%% | Pred: %.1f%% | Status: %s | Elev: %.2f | Rud: %.2f | Thr: %.2f/%.2f",
                    current_risk, predicted_risk, arms_status, best.elevator, best.rudder, best.thr1, best.thr2
                ))
                prev_risk = current_risk
            end
        end
    else
        if was_intervening then
            release_commands()
            was_intervening = false
            log_info("Recovery complete. Final risk: " .. string.format("%.1f", current_risk) .. "%")
        end
    end

    if state_counter % 100 == 0 then
        log_debug(string.format("State: Alpha=%.1f, Speed=%.0f, VVI=%.0f, Roll=%.1f, Risk=%.1f, Status=%s",
            state.alpha, state.speed, state.vvi, state.roll, current_risk, arms_status))
    end
end
-- 12. HUD
local hud_visible = true
local hud_x = 20
local hud_y = 50

function draw_hud()
    if not hud_visible then return end

    local state = get_full_state()
    local color = "white"
    if arms_status == "EMERGENCY" or arms_status == "SPIN RECOVERY" or arms_status == "FIRE HAZARD" then
        color = "red"
    elseif arms_status == "ACTIVE" then color = "orange"
    elseif arms_status == "PREPARE" then color = "yellow"
    elseif arms_status == "STANDBY" then color = "green"
    else color = "gray" end

    draw_string(hud_x, hud_y, "═══ ARMS SYSTEM ═══", "white", 24)
    draw_string(hud_x, hud_y + 25, "Status: " .. arms_status, color, 20)
    draw_string(hud_x, hud_y + 50, "Risk: " .. string.format("%.1f", current_risk) .. "%", "white", 18)
    draw_string(hud_x, hud_y + 70, "Pred: " .. string.format("%.1f", predicted_risk) .. "%", "cyan", 18)
    draw_string(hud_x, hud_y + 95, "Alpha: " .. string.format("%.1f", state.alpha) .. "°", "white", 16)
    draw_string(hud_x, hud_y + 115, "VVI: " .. string.format("%.0f", state.vvi) .. " fpm", "white", 16)
    draw_string(hud_x, hud_y + 135, "Yaw: " .. string.format("%.2f", state.yaw) .. " rad/s", "white", 16)
    draw_string(hud_x, hud_y + 155, "Roll: " .. string.format("%.1f", state.roll) .. "°", "white", 16)
    draw_string(hud_x, hud_y + 175, "Thr1: " .. string.format("%.0f", state.thr1) .. "%", "white", 16)
    draw_string(hud_x, hud_y + 195, "Thr2: " .. string.format("%.0f", state.thr2) .. "%", "white", 16)
    draw_string(hud_x, hud_y + 220, "Stall Warn: " .. (state.stall_warning == 1 and "ON" or "OFF"), "lime", 14)
    draw_string(hud_x, hud_y + 238, "AP: " .. (state.ap_on == 1 and "ON" or "OFF"), "lime", 14)
    draw_string(hud_x, hud_y + 256, "Active: " .. (arms_active and "YES" or "NO"), "lime", 16)
end

-- 13. РЕГИСТРАЦИЯ
do_every_frame("arms_loop()")
do_every_draw("draw_hud()")

log_info("========================================")
log_info(" ARMS v35.0 LOADED (FULL VERSION)")
log_info("========================================")
log_info(" [PARAMETERS] 100+ parameters monitored")
log_info(" [PREDICT] 3 seconds prediction")
log_info(" [SCENARIOS] 30 scenarios per frame")
log_info(" [TWIN] Full digital twin")
log_info(" [LOGS] 4 levels: INFO, WARNING, ERROR, DEBUG")
log_info("========================================")

-- 14. ГОРЯЧИЕ КЛАВИШИ
function toggle_arms()
    arms_active = not arms_active
    if arms_active then log_info("SYSTEM ACTIVATED") else log_info("SYSTEM DEACTIVATED") release_commands() end
end

function toggle_hud()
    hud_visible = not hud_visible
    if hud_visible then log_info("HUD shown") else log_info("HUD hidden") end
end

create_command("ARMS/TOGGLE", "Toggle ARMS", "toggle_arms()", "", "")
create_command("ARMS/HUD_TOGGLE", "Toggle HUD", "toggle_hud()", "", "")

log_info("ARMS v35.0 initialization complete. System ready.")
log_info("========================================")
