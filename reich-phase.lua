-- Steve Reich Phasing Technique for Monome Norns
-- KEY2 : resync
-- KEY3 : play/pause
-- ENC1 : master rate
-- ENC2 : drift
-- ENC3 : mix
-- PARAMS > select sample : file browser

local fileselect = require "fileselect"

local sample_loaded = false
local running       = true
local rate_base     = 1.0
local drift         = 0.005
local mix           = 0.5
local buf_len       = 30.0
local phase         = {0.0, 0.0}

local CX1, CX2, CY, R, DOT_R = 32, 96, 25, 13, 2

-- -------------------------
-- SOFTCUT
-- -------------------------
local function sc_levels()
  softcut.level(1, 1.0 - mix)
  softcut.level(2, mix)
end

local function sc_rates()
  softcut.rate(1, rate_base)
  softcut.rate(2, rate_base + drift)
end

local function sc_setup()
  for v = 1, 2 do
    softcut.enable(v, 1)
    softcut.buffer(v, 1)
    softcut.loop(v, 1)
    softcut.loop_start(v, 0)
    softcut.loop_end(v, buf_len)
    softcut.position(v, 0)
    softcut.fade_time(v, 0.02)
    softcut.level_slew_time(v, 0.05)
    softcut.pan(v, v == 1 and -0.3 or 0.3)
    softcut.play(v, 1)
  end
  sc_levels()
  sc_rates()
  running = true
  sample_loaded = true
end

local function load_sample(path)
  softcut.buffer_clear()
  softcut.buffer_read_mono(path, 0, 0, -1, 1, 1)
  -- wait 1.5s for buffer read, then setup
  metro.init(function(m)
    local f = io.popen('soxi -D "' .. path .. '" 2>/dev/null')
    if f then
      local d = tonumber(f:read("*l"))
      f:close()
      if d and d > 0.1 then buf_len = d end
    end
    sc_setup()
    metro.free(m.id)
  end, 1.5, 1):start()
end

local function open_file_browser()
  fileselect.enter(_path.audio, function(file)
    if file ~= "cancel" then
      load_sample(file)
    end
  end)
end

-- -------------------------
-- SCREEN
-- -------------------------
function redraw()
  screen.clear()

  if not sample_loaded then
    screen.level(5)
    screen.move(24, 18)
    screen.text("REICH PHASE")
    screen.level(3)
    screen.move(2, 32)
    screen.text("PARAMS > select sample")
    screen.move(10, 44)
    screen.text("to load audio file")
    screen.update()
    return
  end

  screen.level(3)
  screen.move(44, 6)
  screen.text("REICH PHASE")

  if not running then
    screen.level(4)
    screen.move(57, 14)
    screen.text("||")
  end

  -- draw ring using many small pixels around circumference (avoids Cairo path issues)
  local function draw_ring_pixels(cx, cy, r, lv)
    screen.level(lv)
    local steps = 80
    for i = 0, steps - 1 do
      local a = (i / steps) * 2 * math.pi
      local px = math.floor(cx + r * math.cos(a) + 0.5)
      local py = math.floor(cy + r * math.sin(a) + 0.5)
      screen.pixel(px, py)
    end
    screen.fill()
  end

  local function draw_dot_pixels(cx, cy, lv)
    screen.level(lv)
    for dx = -DOT_R, DOT_R do
      for dy = -DOT_R, DOT_R do
        if dx*dx + dy*dy <= DOT_R*DOT_R then
          screen.pixel(cx + dx, cy + dy)
        end
      end
    end
    screen.fill()
  end

  -- V1
  draw_ring_pixels(CX1, CY, R, 6)
  local a1 = phase[1] * 2 * math.pi - math.pi / 2
  draw_dot_pixels(
    math.floor(CX1 + R * math.cos(a1) + 0.5),
    math.floor(CY  + R * math.sin(a1) + 0.5),
    15)
  screen.level(4)
  screen.move(CX1 - 3, CY + R + 8)
  screen.text("V1")

  -- V2
  draw_ring_pixels(CX2, CY, R, 3)
  local a2 = phase[2] * 2 * math.pi - math.pi / 2
  draw_dot_pixels(
    math.floor(CX2 + R * math.cos(a2) + 0.5),
    math.floor(CY  + R * math.sin(a2) + 0.5),
    9)
  screen.level(4)
  screen.move(CX2 - 3, CY + R + 8)
  screen.text("V2")

  screen.level(2)
  screen.move(1, 63)
  screen.text("SPD:" .. string.format("%.2f", rate_base) ..
              " DRF:" .. string.format("%.3f", drift) ..
              " MIX:" .. string.format("%.2f", mix))
  screen.update()
end

-- -------------------------
-- PARAMS
-- -------------------------
local function add_params()
  params:add_separator("REICH PHASE")

  -- file selector via params
  params:add_file("sample_file", "select sample", _path.audio)
  params:set_action("sample_file", function(path)
    if path and path ~= "" then
      load_sample(path)
    end
  end)

  params:add_control("rate_base", "master rate",
    controlspec.new(0.25, 2.0, "lin", 0.01, 1.0, "x"))
  params:set_action("rate_base", function(v)
    rate_base = v
    if sample_loaded then sc_rates() end
  end)

  params:add_control("drift", "drift",
    controlspec.new(0.0, 0.1, "lin", 0.001, 0.005, ""))
  params:set_action("drift", function(v)
    drift = v
    if sample_loaded then sc_rates() end
  end)

  params:add_control("mix", "mix v1/v2",
    controlspec.new(0.0, 1.0, "lin", 0.01, 0.5, ""))
  params:set_action("mix", function(v)
    mix = v
    if sample_loaded then sc_levels() end
  end)
end

-- -------------------------
-- INIT
-- -------------------------
function init()
  add_params()
  params:read()
  params:bang()

  softcut.event_phase(function(v, pos)
    phase[v] = (pos / buf_len) % 1.0
  end)
  softcut.phase_quant(1, 1/30)
  softcut.phase_quant(2, 1/30)
  softcut.poll_start_phase()

  metro.init(function() redraw() end, 1/30):start()
end

-- -------------------------
-- ENCODERS
-- -------------------------
function enc(n, d)
  if     n == 1 then params:delta("rate_base", d)
  elseif n == 2 then params:delta("drift", d)
  elseif n == 3 then params:delta("mix", d)
  end
end

-- -------------------------
-- KEYS
-- -------------------------
function key(n, z)
  if n == 2 and z == 1 then
    if sample_loaded then
      softcut.position(1, 0)
      softcut.position(2, 0)
      phase = {0.0, 0.0}
    end
  elseif n == 3 and z == 1 then
    running = not running
    if sample_loaded then
      softcut.play(1, running and 1 or 0)
      softcut.play(2, running and 1 or 0)
    end
  end
end

-- -------------------------
-- CLEANUP
-- -------------------------
function cleanup()
  softcut.poll_stop_phase()
  softcut.buffer_clear()
end
