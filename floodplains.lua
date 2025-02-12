-- Floodplains
-- v. 20250212
-- by @nzimas
-- 
-- 7~voice granular synthesizer 
-- Press K2 to randomize all voices
-- Extensive config options in EDIT menu

engine.name = "Glut"

-- We use 5 main voices (indices 1–5) plus 2 auxiliary voices (6 and 7) for polyphony.
local num_voices = 5

-- Tables for the main voices (1–5)
local voice_active = {}       -- whether the main voice is active
local active_notes = {}       -- per‑voice note stack (for MIDI key stacking)
local pingpong_metros = {}    -- for playhead direction toggling
local pingpong_sign = {}
local random_seek_metros = {}

for i = 1, num_voices do
  voice_active[i] = false
  active_notes[i] = {}
  pingpong_metros[i] = nil
  pingpong_sign[i] = 1
  random_seek_metros[i] = nil
end

-- Initialize auxiliary voices (indices 6 and 7)
voice_active[6] = false
voice_active[7] = false

local ui_metro

local g_transition_time_options = {}
for t = 100, 1000, 100 do table.insert(g_transition_time_options, t) end
for t = 1500, 90000, 500 do table.insert(g_transition_time_options, t) end

local g_morph_time_options = {}
for t = 0, 90000, 500 do table.insert(g_morph_time_options, t) end

local key2_hold = false
local key2_timer = 0

-- Envelope globals per voice (we extend these for auxiliary voices too)
local envelope_threads = {}
local current_env = {}
for i = 1, num_voices do
  envelope_threads[i] = nil
  current_env[i] = -60  -- in dB
end
for i = 6,7 do
  envelope_threads[i] = nil
  current_env[i] = -60
end

-- UI squares: main voices (1–5) are displayed in 2 rows.
local square_size = 20
local positions = {}
-- Top row: voices 1–3
local top_y = 10
local top_margin = math.floor((128 - (3 * square_size)) / 4)
positions[1] = { x = top_margin, y = top_y }
positions[2] = { x = top_margin*2 + square_size, y = top_y }
positions[3] = { x = top_margin*3 + square_size*2, y = top_y }
-- Bottom row: voices 4–5
local bottom_y = 40
local bottom_margin = math.floor((128 - (2 * square_size)) / 3)
positions[4] = { x = bottom_margin, y = bottom_y }
positions[5] = { x = bottom_margin*2 + square_size, y = bottom_y }
-- (Auxiliary voices 6 and 7 are not shown in the UI.)

local function random_float(l, h)
  return l + math.random() * (h - l)
end

local function smooth_transition(param_name, new_val, duration)
  clock.run(function()
    local start_val = params:get(param_name)
    local steps = 60
    local dt = duration / steps
    for i = 1, steps do
      local t = i / steps
      params:set(param_name, start_val + (new_val - start_val) * t)
      clock.sleep(dt)
    end
    params:set(param_name, new_val)
  end)
end

local function update_playhead(i)
  local rate = params:get(i.."playhead_rate")
  local dir = params:get(i.."playhead_direction")
  if pingpong_metros[i] then
    pingpong_metros[i]:stop()
    pingpong_metros[i] = nil
    pingpong_sign[i] = 1
  end
  if dir == 1 then
    engine.speed(i, rate)
  elseif dir == 2 then
    engine.speed(i, -rate)
  else
    pingpong_metros[i] = metro.init()
    pingpong_metros[i].time = 2.0
    pingpong_metros[i].event = function()
      pingpong_sign[i] = -pingpong_sign[i]
      engine.speed(i, pingpong_sign[i]*rate)
    end
    pingpong_metros[i]:start()
    engine.speed(i, rate)
  end
end

local function randomize_voice(i)
  local transition_ms = g_transition_time_options[ params:get("transition_time") ]
  local morph_ms = g_morph_time_options[ params:get("morph_time") ]
  local actual_ms = math.min(morph_ms, transition_ms)
  local morph_duration = actual_ms/1000

  local new_jitter  = random_float(params:get("min_jitter"),  params:get("max_jitter"))
  local new_size    = random_float(params:get("min_size"),    params:get("max_size"))
  local new_density = random_float(params:get("min_density"), params:get("max_density"))
  local new_spread  = random_float(params:get("min_spread"),  params:get("max_spread"))

  smooth_transition(i.."jitter",  new_jitter,  morph_duration)
  smooth_transition(i.."size",    new_size,    morph_duration)
  smooth_transition(i.."density", new_density, morph_duration)
  smooth_transition(i.."spread",  new_spread,  morph_duration)
end

local function randomize_all()
  for i = 1, num_voices do
    randomize_voice(i)
  end
end

local function setup_ui_metro()
  ui_metro = metro.init()
  ui_metro.time = 1/15
  ui_metro.event = function() redraw() end
  ui_metro:start()
end

local function setup_params()
  params:add_separator("Samples & Voices")
  for i = 1, num_voices do
    params:add_file(i.."sample", i.." sample")
    params:set_action(i.."sample", function(file) engine.read(i, file) end)
    params:add_control(i.."playhead_rate", i.." playhead rate",
      controlspec.new(0, 4, "lin", 0.01, 1.0, "", 0.01/4))
    params:set_action(i.."playhead_rate", function(v) update_playhead(i) end)
    params:add_option(i.."playhead_direction", i.." playhead direction", {">>","<<","<->"}, 1)
    params:set_action(i.."playhead_direction", function(d) update_playhead(i) end)
    params:add_taper(i.."volume", i.." volume", -60, 20, 0, 0, "dB")
    params:set_action(i.."volume", function(v) engine.volume(i, math.pow(10, v/20)) end)
    params:add_taper(i.."jitter", i.." jitter", 0, 2000, 0, 5, "ms")
    params:set_action(i.."jitter", function(val) engine.jitter(i, val/1000) end)
    params:add_taper(i.."size", i.." size", 1, 500, 100, 5, "ms")
    params:set_action(i.."size", function(val) engine.size(i, val/1000) end)
    params:add_taper(i.."density", i.." density", 0, 512, 20, 6, "hz")
    params:set_action(i.."density", function(val) engine.density(i, val) end)
    params:add_taper(i.."spread", i.." spread", 0, 100, 0, 0, "%")
    params:set_action(i.."spread", function(val) engine.spread(i, val/100) end)
    params:add_taper(i.."fade", i.." att/dec", 1, 9000, 1000, 3, "ms")
    params:set_action(i.."fade", function(val) engine.envscale(i, val/1000) end)
    params:add_control(i.."seek", i.." seek",
      controlspec.new(0, 100, "lin", 0.1, 0, "%", 0.1/100))
    params:set_action(i.."seek", function(val) engine.seek(i, val/100) end)
    params:add_option(i.."random_seek", i.." randomize seek", {"off","on"}, 1)
    params:add_control(i.."random_seek_freq_min", i.." rnd seek freq min",
      controlspec.new(100, 30000, "lin", 100, 500, "ms", 0.00333))
    params:add_control(i.."random_seek_freq_max", i.." rnd seek freq max",
      controlspec.new(100, 30000, "lin", 100, 2000, "ms", 0.00333))
    params:set_action(i.."random_seek_freq_min", function(val)
      local max_val = params:get(i.."random_seek_freq_max")
      if val > max_val then return max_val else return val end
    end)
    params:set_action(i.."random_seek_freq_max", function(val)
      local min_val = params:get(i.."random_seek_freq_min")
      if val < min_val then return min_val else return val end
    end)
    params:set_action(i.."random_seek", function(val)
      if val == 2 then
        if random_seek_metros[i] == nil then
          random_seek_metros[i] = metro.init()
          random_seek_metros[i].event = function()
            params:set(i.."seek", math.random()*100)
            local tmin = params:get(i.."random_seek_freq_min")
            local tmax = params:get(i.."random_seek_freq_max")
            if tmax < tmin then tmin, tmax = tmax, tmin end
            local next_interval = math.random(tmin, tmax)
            random_seek_metros[i].time = next_interval/1000
            random_seek_metros[i]:start()
          end
        end
        random_seek_metros[i].time = 0.1
        random_seek_metros[i]:start()
      else
        if random_seek_metros[i] ~= nil then
          random_seek_metros[i]:stop()
        end
      end
    end)
    params:add_number("midi_channel_"..i, "MIDI channel "..i, 1, 16, i)
    -- Attack and Release parameters (in ms)
    params:add_taper(i.."attack", i.." attack (ms)", 0, 5000, 10, 0, "ms")
    params:add_taper(i.."release", i.." release (ms)", 0, 5000, 1000, 0, "ms")
  end

  params:add_separator("Polyphony")
  params:add_option("polyphonic_voice", "polyphonic voice", {"1","2","3","4","5"}, 1)

  params:add_separator("Transition")
  params:add_option("transition_time", "transition time (ms)",
    g_transition_time_options, 10)
  params:add_option("morph_time", "morph time (ms)",
    g_morph_time_options, 1)
  params:set_action("morph_time", function(idx)
    local morph = g_morph_time_options[idx]
    local trans = g_transition_time_options[params:get("transition_time")]
    if morph > trans then
      local best_index = 1
      for i = 1, #g_morph_time_options do
        if g_morph_time_options[i] <= trans then best_index = i end
      end
      params:set("morph_time", best_index)
    end
  end)

  params:add_separator("Randomizer")
  params:add_taper("min_jitter", "jitter (min)", 0, 2000, 0, 5, "ms")
  params:add_taper("max_jitter", "jitter (max)", 0, 2000, 500, 5, "ms")
  params:add_taper("min_size", "size (min)", 1, 500, 1, 5, "ms")
  params:add_taper("max_size", "size (max)", 1, 500, 500, 5, "ms")
  params:add_taper("min_density", "density (min)", 0, 512, 0, 6, "hz")
  params:add_taper("max_density", "density (max)", 0, 512, 40, 6, "hz")
  params:add_taper("min_spread", "spread (min)", 0, 100, 0, 0, "%")
  params:add_taper("max_spread", "spread (max)", 0, 100, 100, 0, "%")

  params:add_separator("Reverb")
  params:add_taper("reverb_mix", "* mix", 0, 100, 50, 0, "%")
  params:set_action("reverb_mix", function(v) engine.reverb_mix(v/100) end)
  params:add_taper("reverb_room", "* room", 0, 100, 50, 0, "%")
  params:set_action("reverb_room", function(v) engine.reverb_room(v/100) end)
  params:add_taper("reverb_damp", "* damp", 0, 100, 50, 0, "%")
  params:set_action("reverb_damp", function(v) engine.reverb_damp(v/100) end)

  params:add_separator("MIDI")
  params:add{ type = "number", id = "midi_device", name = "MIDI Device", min = 1, max = 4, default = 1,
    action = function(value)
      if midi_in then midi_in.event = nil end
      midi_in = midi.connect(value)
      midi_in.event = midi_event
    end }

  params:bang()
end

local function setup_engine()
  for i = 1, num_voices do
    engine.seek(i, 0)
    engine.gate(i, 0)
    update_playhead(i)
  end
  -- Ensure auxiliary voices are initially gated off:
  engine.gate(6, 0)
  engine.gate(7, 0)
end

local midi_in

-- The envelope routines now use the polyphonic voice's envelope times for auxiliary voices.
local function get_attack_time(i)
  if i > num_voices then
    local poly = params:get("polyphonic_voice")
    return params:get(poly.."attack")
  else
    return params:get(i.."attack")
  end
end

local function get_release_time(i)
  if i > num_voices then
    local poly = params:get("polyphonic_voice")
    return params:get(poly.."release")
  else
    return params:get(i.."release")
  end
end

local function envelope_attack(i)
  if envelope_threads[i] then clock.cancel(envelope_threads[i]) end
  current_env[i] = -60
  envelope_threads[i] = clock.run(function()
    local att_ms = get_attack_time(i)
    local steps = math.max(1, math.floor(att_ms / 10))
    local dt = att_ms / steps / 1000
    local start_vol = current_env[i]
    local target_vol = params:get((i > num_voices) and params:get("polyphonic_voice").."volume" or (i.."volume"))
    for step = 1, steps do
      local t = step / steps
      local new_vol = start_vol + (target_vol - start_vol) * t
      current_env[i] = new_vol
      engine.volume(i, math.pow(10, new_vol/20))
      clock.sleep(dt)
    end
    current_env[i] = target_vol
    engine.volume(i, math.pow(10, target_vol/20))
  end)
end

local function envelope_release(i)
  if envelope_threads[i] then clock.cancel(envelope_threads[i]) end
  envelope_threads[i] = clock.run(function()
    local rel_ms = get_release_time(i)
    local steps = math.max(1, math.floor(rel_ms / 10))
    local dt = rel_ms / steps / 1000
    local start_vol = current_env[i]
    local target_vol = -60
    for step = 1, steps do
      local t = step / steps
      local new_vol = start_vol + (target_vol - start_vol) * t
      current_env[i] = new_vol
      engine.volume(i, math.pow(10, new_vol/20))
      clock.sleep(dt)
    end
    current_env[i] = target_vol
    engine.volume(i, math.pow(10, target_vol/20))
    engine.gate(i, 0)
  end)
end

-- MIDI event handler
function midi_event(data)
  local msg = midi.to_msg(data)
  if msg.type == "note_on" then
    if msg.vel == 0 then
      -- treat note_on with vel==0 as note_off
      for i = 1, num_voices do
        if msg.ch == params:get("midi_channel_"..i) then
          if i == params:get("polyphonic_voice") then
            local chord = active_notes[i]
            for j, n in ipairs(chord) do
              if n == msg.note then table.remove(chord, j) break end
            end
            if #chord == 0 then
              voice_active[i] = false
              envelope_release(i)
              engine.gate(6, 0)
              engine.gate(7, 0)
            else
              if msg.note == chord[1] then
                engine.pitch(i, math.pow(2, (chord[1]-60)/12))
                engine.seek(i, 0)
                engine.gate(i, 1)
                envelope_attack(i)
              else
                engine.pitch(i, math.pow(2, (chord[1]-60)/12))
              end
              if #chord >= 2 then
                if #chord == 2 then
                  engine.pitch(6, math.pow(2, (chord[2]-60)/12))
                  engine.seek(6, 0)
                  engine.gate(6, 1)
                  envelope_attack(6)
                else
                  engine.pitch(6, math.pow(2, (chord[2]-60)/12))
                end
              else
                engine.gate(6, 0)
              end
              if #chord >= 3 then
                if #chord == 3 then
                  engine.pitch(7, math.pow(2, (chord[3]-60)/12))
                  engine.seek(7, 0)
                  engine.gate(7, 1)
                  envelope_attack(7)
                else
                  engine.pitch(7, math.pow(2, (chord[3]-60)/12))
                end
              else
                engine.gate(7, 0)
              end
            end
          else
            for j, n in ipairs(active_notes[i]) do
              if n == msg.note then table.remove(active_notes[i], j) break end
            end
            if #active_notes[i] == 0 then
              voice_active[i] = false
              envelope_release(i)
            else
              local last_note = active_notes[i][#active_notes[i]]
              engine.pitch(i, math.pow(2, (last_note-60)/12))
            end
          end
        end
      end
    else
      for i = 1, num_voices do
        if msg.ch == params:get("midi_channel_"..i) then
          if i == params:get("polyphonic_voice") then
            local chord = active_notes[i]
            table.insert(chord, msg.note)
            voice_active[i] = true
            local file = params:get(i.."sample")
            if file and file ~= "" then
              engine.read(6, file)
              engine.read(7, file)
            end
            if #chord == 1 then
              engine.pitch(i, math.pow(2, (chord[1]-60)/12))
              engine.seek(i, 0)
              engine.gate(i, 1)
              envelope_attack(i)
            else
              -- Do not re-trigger main envelope; main voice remains on chord[1]
              engine.pitch(i, math.pow(2, (chord[1]-60)/12))
            end
            if #chord >= 2 then
              if #chord == 2 then
                engine.pitch(6, math.pow(2, (chord[2]-60)/12))
                engine.seek(6, 0)
                engine.gate(6, 1)
                envelope_attack(6)
              else
                engine.pitch(6, math.pow(2, (chord[2]-60)/12))
              end
            else
              engine.gate(6, 0)
            end
            if #chord >= 3 then
              if #chord == 3 then
                engine.pitch(7, math.pow(2, (chord[3]-60)/12))
                engine.seek(7, 0)
                engine.gate(7, 1)
                envelope_attack(7)
              else
                engine.pitch(7, math.pow(2, (chord[3]-60)/12))
              end
            else
              engine.gate(7, 0)
            end
            if #chord >= 2 then
              if math.random() < 0.5 then
                engine.pan(6, -1)
                engine.pan(7, 1)
              else
                engine.pan(6, 1)
                engine.pan(7, -1)
              end
            end
            if #chord >= 2 then randomize_voice(6) end
            if #chord >= 3 then randomize_voice(7) end
          else
            voice_active[i] = true
            table.insert(active_notes[i], msg.note)
            engine.pitch(i, math.pow(2, (msg.note-60)/12))
            engine.seek(i, 0)
            engine.gate(i, 1)
            envelope_attack(i)
          end
        end
      end
    end
  elseif msg.type == "note_off" then
    for i = 1, num_voices do
      if msg.ch == params:get("midi_channel_"..i) then
        if i == params:get("polyphonic_voice") then
          local chord = active_notes[i]
          for j, n in ipairs(chord) do
            if n == msg.note then table.remove(chord, j) break end
          end
          if #chord == 0 then
            voice_active[i] = false
            envelope_release(i)
            engine.gate(6, 0)
            engine.gate(7, 0)
          else
            if msg.note == chord[1] then
              engine.pitch(i, math.pow(2, (chord[1]-60)/12))
              engine.seek(i, 0)
              engine.gate(i, 1)
              envelope_attack(i)
            else
              engine.pitch(i, math.pow(2, (chord[1]-60)/12))
            end
            if #chord >= 2 then
              if #chord == 2 then
                engine.pitch(6, math.pow(2, (chord[2]-60)/12))
                engine.seek(6, 0)
                engine.gate(6, 1)
                envelope_attack(6)
              else
                engine.pitch(6, math.pow(2, (chord[2]-60)/12))
              end
            else
              engine.gate(6, 0)
            end
            if #chord >= 3 then
              if #chord == 3 then
                engine.pitch(7, math.pow(2, (chord[3]-60)/12))
                engine.seek(7, 0)
                engine.gate(7, 1)
                envelope_attack(7)
              else
                engine.pitch(7, math.pow(2, (chord[3]-60)/12))
              end
            else
              engine.gate(7, 0)
            end
          end
        else
          for j, n in ipairs(active_notes[i]) do
            if n == msg.note then table.remove(active_notes[i], j) break end
          end
          if #active_notes[i] == 0 then
            voice_active[i] = false
            envelope_release(i)
          else
            local last_note = active_notes[i][#active_notes[i]]
            engine.pitch(i, math.pow(2, (last_note-60)/12))
          end
        end
      end
    end
  end
end

function key(n, z)
  if n == 2 then
    if z == 1 then
      key2_hold = true
      key2_timer = util.time()
    else
      if key2_hold then
        key2_hold = false
        if util.time() - key2_timer < 1 then
          randomize_all()
        end
      end
    end
  end
end

function enc(n, d)
  -- No encoder-specific functions defined.
end

function redraw()
  screen.clear()
  for i = 1, num_voices do
    local pos = positions[i]
    screen.level(15)
    screen.rect(pos.x, pos.y, square_size, square_size)
    screen.stroke()
    if voice_active[i] then
      screen.level(10)
      screen.rect(pos.x, pos.y, square_size, square_size)
      screen.fill()
    end
  end
  screen.update()
end

function init()
  setup_ui_metro()
  setup_params()
  setup_engine()
  midi_in = midi.connect(params:get("midi_device"))
  midi_in.event = midi_event
end
