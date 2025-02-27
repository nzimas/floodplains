-- Floodplains
-- v. 20250227
-- by @nzimas
--
-- Multitimbral granular synthesizer
-- Extensive conf options in the EDIT menu

engine.name = "GlutXtd"

local num_voices = 5  -- main voices 1..5
local num_aux = 10    -- aux voices 6..15 (2 per main voice)

-- Tables for the main voices (1–5)
local voice_active = {}
local active_notes = {}
local random_seek_metros = {}

for i = 1, num_voices do
  voice_active[i] = false
  active_notes[i] = {}
  random_seek_metros[i] = nil
end

-- Initialize aux voices (voices 6..15)
for i = num_voices+1, num_voices+num_aux do
  voice_active[i] = false
end

local ui_metro

local g_morph_time_options = {}
for t = 0, 90000, 500 do table.insert(g_morph_time_options, t) end

-- Key timing variables for K1, K2, K3:
local key1_hold = false
local key1_timer = 0
local key2_hold = false
local key2_timer = 0
local key3_hold = false
local key3_timer = 0

-- Envelope globals (main + aux)
local envelope_threads = {}
local current_env = {}
for i = 1, num_voices+num_aux do
  envelope_threads[i] = nil
  current_env[i] = -60
end

-- UI squares: main voices (1–5) in 2 rows
local square_size = 20
local positions = {}
-- Top row: voices 1–3
local top_y = 10
local top_margin = math.floor((128 - (3 * square_size)) / 4)
positions[1] = { x = top_margin, y = top_y }
positions[2] = { x = top_margin * 2 + square_size, y = top_y }
positions[3] = { x = top_margin * 3 + square_size * 2, y = top_y }
-- Bottom row: voices 4–5
local bottom_y = 40
local bottom_margin = math.floor((128 - (2 * square_size)) / 3)
positions[4] = { x = bottom_margin, y = bottom_y }
positions[5] = { x = bottom_margin * 2 + square_size, y = bottom_y }
-- (Aux voices 6–15 have no UI squares)

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

-- Randomize one voice (plus its 2 aux voices)
local function randomize_voice(i)
  local morph_ms = g_morph_time_options[params:get("morph_time")]
  local morph_duration = morph_ms / 1000

  local new_jitter  = random_float(params:get("min_jitter"),  params:get("max_jitter"))
  local new_size    = random_float(params:get("min_size"),    params:get("max_size"))
  local new_density = random_float(params:get("min_density"), params:get("max_density"))
  local new_spread  = random_float(params:get("min_spread"),  params:get("max_spread"))

  smooth_transition(i.."jitter",  new_jitter,  morph_duration)
  smooth_transition(i.."size",    new_size,    morph_duration)
  smooth_transition(i.."density", new_density, morph_duration)
  smooth_transition(i.."spread",  new_spread,  morph_duration)

  clock.run(function()
    local aux1 = 2 * i + 4
    local aux2 = 2 * i + 5
    local steps = 60
    local dt = morph_duration / steps
    for step = 1, steps do
      local cur_j = params:get(i.."jitter")
      local cur_s = params:get(i.."size")
      local cur_d = params:get(i.."density")
      local cur_sp = params:get(i.."spread")
      engine.jitter(aux1, cur_j / 1000)
      engine.jitter(aux2, cur_j / 1000)
      engine.size(aux1, cur_s / 1000)
      engine.size(aux2, cur_s / 1000)
      engine.density(aux1, cur_d)
      engine.density(aux2, cur_d)
      engine.spread(aux1, cur_sp / 100)
      engine.spread(aux2, cur_sp / 100)
      clock.sleep(dt)
    end
  end)
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
  params:add_separator("MIDI")
  params:add{
    type = "number", id = "midi_device", name = "MIDI Device",
    min = 1, max = 16, default = 1,
    action = function(value)
      if midi_in then midi_in.event = nil end
      midi_in = midi.connect(value)
      midi_in.event = midi_event
    end
  }

  params:add_separator("Parts")
  for i = 1, num_voices do
    params:add_separator("PART " .. i)

    -- Sample + MIDI channel
    params:add_file(i.."sample", i.." sample")
    params:set_action(i.."sample", function(file)
      engine.read(i, file)
      local aux1 = 2 * i + 4
      local aux2 = 2 * i + 5
      engine.read(aux1, file)
      engine.read(aux2, file)
    end)
    params:add_number("midi_channel_"..i, "MIDI channel "..i, 1, 16, i)

    -- Granular params
    params:add_taper(i.."volume", i.." volume", -60, 20, 0, 0, "dB")
    params:set_action(i.."volume", function(v)
      local vol = math.pow(10, v / 20)
      engine.volume(i, vol)
      local aux1 = 2 * i + 4
      local aux2 = 2 * i + 5
      engine.volume(aux1, vol)
      engine.volume(aux2, vol)
    end)
    params:add_taper(i.."pan", i.." pan", -1, 1, 0, 0, "")
    params:set_action(i.."pan", function(v) engine.pan(i, v) end)
    params:add_taper(i.."jitter", i.." jitter", 0, 2000, 0, 5, "ms")
    params:set_action(i.."jitter", function(val) engine.jitter(i, val / 1000) end)
    params:add_taper(i.."size", i.." size", 1, 500, 100, 5, "ms")
    params:set_action(i.."size", function(val) engine.size(i, val / 1000) end)
    params:add_taper(i.."density", i.." density", 0, 512, 20, 6, "hz")
    params:set_action(i.."density", function(val) engine.density(i, val) end)
    params:add_taper(i.."spread", i.." spread", 0, 100, 0, 0, "%")
    params:set_action(i.."spread", function(val) engine.spread(i, val / 100) end)
    params:add_taper(i.."fade", i.." att/dec", 1, 9000, 1000, 3, "ms")
    params:set_action(i.."fade", function(val) engine.envscale(i, val / 1000) end)

    -- Seek + random seek
    params:add_control(i.."seek", i.." seek",
      controlspec.new(0, 100, "lin", 0.1, 0, "%", 0.1/100))
    params:set_action(i.."seek", function(val) engine.seek(i, val / 100) end)

    params:add_option(i.."random_seek", i.." randomize seek", {"off", "on"}, 1)
    params:add_control(i.."random_seek_freq_min", i.." rnd seek freq min",
      controlspec.new(100, 30000, "lin", 100, 500, "ms", 0.00333))
    params:add_control(i.."random_seek_freq_max", i.." rnd seek freq max",
      controlspec.new(100, 30000, "lin", 100, 2000, "ms", 0.00333))

    -- keep min < max
    params:set_action(i.."random_seek_freq_min", function(val)
      local mx = params:get(i.."random_seek_freq_max")
      if val > mx then return mx else return val end
    end)
    params:set_action(i.."random_seek_freq_max", function(val)
      local mn = params:get(i.."random_seek_freq_min")
      if val < mn then return mn else return val end
    end)

    params:set_action(i.."random_seek", function(val)
      if val == 2 then
        if random_seek_metros[i] == nil then
          random_seek_metros[i] = metro.init()
          random_seek_metros[i].event = function()
            params:set(i.."seek", math.random() * 100)
            local tmin = params:get(i.."random_seek_freq_min")
            local tmax = params:get(i.."random_seek_freq_max")
            if tmax < tmin then tmin,tmax = tmax,tmin end
            local next_interval = math.random(tmin, tmax)
            random_seek_metros[i].time = next_interval / 1000
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

    -- Envelope
    params:add_taper(i.."attack",  i.." attack (ms)",  0, 5000, 200,  0, "ms")
    params:add_taper(i.."release", i.." release (ms)", 0, 5000, 1000, 0, "ms")

    -- Poly panning
    params:add_option(i.."random_poly_pan", i.." random poly pan", {"off", "on"}, 2)

    -- Filter
    params:add_separator("Voice "..i.." Filter")
    params:add_control(i.."filterCutoff", i.." filter cutoff",
      controlspec.new(20, 20000, "lin", 0.1, 8000, "Hz"))
    params:set_action(i.."filterCutoff", function(val)
      engine.filterCutoff(i, val)
      local aux1 = 2*i + 4
      local aux2 = 2*i + 5
      engine.filterCutoff(aux1, val)
      engine.filterCutoff(aux2, val)
    end)
    params:add_taper(i.."filterRQ", i.." filter resonance", 0.1, 2, 0.5, 0.01, "Q")
    params:set_action(i.."filterRQ", function(val)
      engine.filterRQ(i, val)
      local aux1 = 2*i + 4
      local aux2 = 2*i + 5
      engine.filterRQ(aux1, val)
      engine.filterRQ(aux2, val)
    end)

    params:add_separator("") -- blank line
  end

  params:add_separator("Transition")
  params:add_option("morph_time", "morph time (ms)", g_morph_time_options, 1)

  params:add_separator("Randomizer")
  params:add_taper("min_jitter",   "jitter (min)",   0, 2000, 0,   5, "ms")
  params:add_taper("max_jitter",   "jitter (max)",   0, 2000, 500, 5, "ms")
  params:add_taper("min_size",     "size (min)",     1, 500,   1,   5, "ms")
  params:add_taper("max_size",     "size (max)",     1, 500,   500, 5, "ms")
  params:add_taper("min_density",  "density (min)",  0, 512,   0,   6, "hz")
  params:add_taper("max_density",  "density (max)",  0, 512,   40,  6, "hz")
  params:add_taper("min_spread",   "spread (min)",   0, 100,   0,   0, "%")
  params:add_taper("max_spread",   "spread (max)",   0, 100,   100, 0, "%")

  ----------------------------------------------------------------
  -- Decimator (above Delay)
  ----------------------------------------------------------------
  params:add_separator("Decimator")

  params:add_control("decimator_rate", "decimator rate",
    controlspec.new(1000, 48000, "exp", 0, 44100, "Hz"))
  params:set_action("decimator_rate", function(v) engine.decimator_rate(v) end)

  params:add_number("decimator_bits", "decimator bits", 1, 32, 24)
  params:set_action("decimator_bits", function(v) engine.decimator_bits(v) end)

  params:add_control("decimator_mul", "decimator mul",
    controlspec.new(0, 5, "lin", 0, 1, ""))
  params:set_action("decimator_mul", function(v) engine.decimator_mul(v) end)

  params:add_control("decimator_add", "decimator add",
    controlspec.new(0, 5, "lin", 0, 0, ""))
  params:set_action("decimator_add", function(v) engine.decimator_add(v) end)

  ----------------------------------------------------------------
  -- Delay
  ----------------------------------------------------------------
  params:add_separator("Delay")
  params:add_control("delay_time", "Delay Time",
    controlspec.new(0.1, 2.0, "lin", 0.01, 0.5, "s"))
  params:set_action("delay_time", function(v) engine.delay_time(v) end)

  params:add_taper("delay_feedback", "Delay Feedback", 0, 100, 50, 0, "%")
  params:set_action("delay_feedback", function(v) engine.delay_feedback(v/100) end)

  params:add_taper("delay_mix", "Delay Mix", 0, 100, 50, 0, "%")
  params:set_action("delay_mix", function(v) engine.delay_mix(v/100) end)

  ----------------------------------------------------------------
  -- LFO Section
  ----------------------------------------------------------------
  params:add_separator("LFOs")

  local lfo_target_names = {
    "filter cutoff","filter res","jitter","density","size",
    "pan","volume"
  }
  local lfo_shape_names = { "sine", "triangle" }

  for lfo_index = 1, 3 do
    params:add_separator("LFO " .. lfo_index)

    params:add_number("lfo"..lfo_index.."_voice", "Voice", 1, 5, 1)
    params:add_option("lfo"..lfo_index.."_target", "Target", lfo_target_names, 1)
    params:add_taper("lfo"..lfo_index.."_depth", "Depth", 0, 100, 0, 0, "%")
    params:add_control("lfo"..lfo_index.."_rate", "Rate",
      controlspec.new(0.01, 20, "exp", 0, 1, "Hz"))
    params:add_option("lfo"..lfo_index.."_shape", "Shape", lfo_shape_names, 1)
  end

  params:bang()
end

local function setup_engine()
  for i = 1, num_voices do
    engine.gate(i, 0)
    engine.speed(i, 0)
  end
  for i = num_voices+1, num_voices+num_aux do
    engine.gate(i, 0)
    engine.speed(i, 0)
  end
end

local midi_in

-- For aux, use envelope times from their main
local function get_attack_time(i)
  if i > num_voices then
    local main = math.floor((i - 4) / 2)
    return params:get(main.."attack")
  else
    return params:get(i.."attack")
  end
end

local function get_release_time(i)
  if i > num_voices then
    local main = math.floor((i - 4) / 2)
    return params:get(main.."release")
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
    local target_vol = (i > num_voices)
      and params:get(math.floor((i - 4) / 2).."volume")
      or  params:get(i.."volume")
    local target_pan = (i > num_voices)
      and params:get(math.floor((i - 4) / 2).."pan")
      or  params:get(i.."pan")

    engine.pan(i, target_pan)
    for step = 1, steps do
      local t = step / steps
      local new_vol = start_vol + (target_vol - start_vol)*t
      current_env[i] = new_vol
      engine.volume(i, math.pow(10, new_vol / 20))
      clock.sleep(dt)
    end
    current_env[i] = target_vol
    engine.volume(i, math.pow(10, target_vol / 20))
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
      local new_vol = start_vol + (target_vol - start_vol)*t
      current_env[i] = new_vol
      engine.volume(i, math.pow(10, new_vol / 20))
      clock.sleep(dt)
    end
    current_env[i] = target_vol
    engine.volume(i, math.pow(10, target_vol / 20))
    engine.gate(i, 0)
  end)
end

-- Quick voice reset
local function retrigger_voice(i)
  engine.gate(i, 0)
  clock.run(function()
    clock.sleep(0.01)
    engine.gate(i, 1)
    envelope_attack(i)
  end)
end

----------------------------------------------------------------
-- MIDI / Poly
----------------------------------------------------------------
function midi_event(data)
  local msg = midi.to_msg(data)
  if msg.type == "note_on" then
    if msg.vel == 0 then
      -- treat note_on with vel=0 as note_off
      for i = 1, num_voices do
        if msg.ch == params:get("midi_channel_"..i) then
          local chord = active_notes[i]
          for j, n in ipairs(chord) do
            if n == msg.note then
              table.remove(chord, j)
              break
            end
          end
          if #chord == 0 then
            voice_active[i] = false
            envelope_release(i)
            local aux1 = 2*i + 4
            local aux2 = 2*i + 5
            engine.gate(aux1, 0)
            engine.gate(aux2, 0)
          else
            if msg.note == chord[1] then
              engine.pitch(i, math.pow(2,(chord[1]-60)/12))
              retrigger_voice(i)
              engine.pan(i, params:get(i.."pan"))
            else
              engine.pitch(i, math.pow(2,(chord[1]-60)/12))
            end
            -- handle aux
            local aux1 = 2*i + 4
            if #chord >= 2 then
              if #chord == 2 then
                engine.pitch(aux1, math.pow(2,(chord[2]-60)/12))
                engine.gate(aux1, 1)
                envelope_attack(aux1)
                engine.jitter(aux1,   params:get(i.."jitter")/1000)
                engine.size(aux1,     params:get(i.."size")/1000)
                engine.density(aux1,  params:get(i.."density"))
                engine.spread(aux1,   params:get(i.."spread")/100)
                engine.envscale(aux1, params:get(i.."fade")/1000)
                engine.seek(aux1,     params:get(i.."seek")/100)
                engine.pan(aux1,      params:get(i.."pan"))
              else
                engine.pitch(aux1, math.pow(2,(chord[2]-60)/12))
              end
            else
              engine.gate(aux1, 0)
            end

            local aux2 = 2*i + 5
            if #chord >= 3 then
              if #chord == 3 then
                engine.pitch(aux2, math.pow(2,(chord[3]-60)/12))
                engine.gate(aux2, 1)
                envelope_attack(aux2)
                engine.jitter(aux2,   params:get(i.."jitter")/1000)
                engine.size(aux2,     params:get(i.."size")/1000)
                engine.density(aux2,  params:get(i.."density"))
                engine.spread(aux2,   params:get(i.."spread")/100)
                engine.envscale(aux2, params:get(i.."fade")/1000)
                engine.seek(aux2,     params:get(i.."seek")/100)
                engine.pan(aux2,      params:get(i.."pan"))
              else
                engine.pitch(aux2, math.pow(2,(chord[3]-60)/12))
              end
            else
              engine.gate(aux2, 0)
            end

            if #chord >= 2 then
              if params:get(i.."random_poly_pan") == 2 then
                if math.random() < 0.5 then
                  engine.pan(aux1, -1)
                  engine.pan(aux2,  1)
                else
                  engine.pan(aux1,  1)
                  engine.pan(aux2, -1)
                end
              else
                local mainPan = params:get(i.."pan")
                engine.pan(aux1, mainPan)
                engine.pan(aux2, mainPan)
              end
            end
          end
        end
      end
    else
      -- note_on normal
      for i = 1, num_voices do
        if msg.ch == params:get("midi_channel_"..i) then
          local chord = active_notes[i]
          table.insert(chord, msg.note)
          voice_active[i] = true

          if #chord == 1 then
            engine.pitch(i, math.pow(2,(chord[1]-60)/12))
            retrigger_voice(i)
          else
            engine.pitch(i, math.pow(2,(chord[1]-60)/12))
          end
          engine.pan(i, params:get(i.."pan"))

          local aux1 = 2*i + 4
          if #chord >= 2 then
            if #chord == 2 then
              engine.pitch(aux1, math.pow(2,(chord[2]-60)/12))
              engine.gate(aux1, 1)
              envelope_attack(aux1)
              engine.jitter(aux1,   params:get(i.."jitter")/1000)
              engine.size(aux1,     params:get(i.."size")/1000)
              engine.density(aux1,  params:get(i.."density"))
              engine.spread(aux1,   params:get(i.."spread")/100)
              engine.envscale(aux1, params:get(i.."fade")/1000)
              engine.seek(aux1,     params:get(i.."seek")/100)
              engine.pan(aux1,      params:get(i.."pan"))
            else
              engine.pitch(aux1, math.pow(2,(chord[2]-60)/12))
            end
          else
            engine.gate(aux1, 0)
          end

          local aux2 = 2*i + 5
          if #chord >= 3 then
            if #chord == 3 then
              engine.pitch(aux2, math.pow(2,(chord[3]-60)/12))
              engine.gate(aux2, 1)
              envelope_attack(aux2)
              engine.jitter(aux2,   params:get(i.."jitter")/1000)
              engine.size(aux2,     params:get(i.."size")/1000)
              engine.density(aux2,  params:get(i.."density"))
              engine.spread(aux2,   params:get(i.."spread")/100)
              engine.envscale(aux2, params:get(i.."fade")/1000)
              engine.seek(aux2,     params:get(i.."seek")/100)
              engine.pan(aux2,      params:get(i.."pan"))
            else
              engine.pitch(aux2, math.pow(2,(chord[3]-60)/12))
            end
          else
            engine.gate(aux2, 0)
          end

          if #chord >= 2 then
            if params:get(i.."random_poly_pan") == 2 then
              if math.random() < 0.5 then
                engine.pan(aux1, -1)
                engine.pan(aux2,  1)
              else
                engine.pan(aux1,  1)
                engine.pan(aux2, -1)
              end
            else
              local mainPan = params:get(i.."pan")
              engine.pan(aux1, mainPan)
              engine.pan(aux2, mainPan)
            end
          end
        end
      end
    end
  elseif msg.type == "note_off" then
    for i = 1, num_voices do
      if msg.ch == params:get("midi_channel_"..i) then
        local chord = active_notes[i]
        for j, n in ipairs(chord) do
          if n == msg.note then
            table.remove(chord, j)
            break
          end
        end
        if #chord == 0 then
          voice_active[i] = false
          envelope_release(i)
          local aux1 = 2*i + 4
          local aux2 = 2*i + 5
          engine.gate(aux1, 0)
          engine.gate(aux2, 0)
        else
          if msg.note == chord[1] then
            engine.pitch(i, math.pow(2,(chord[1]-60)/12))
            retrigger_voice(i)
            engine.pan(i, params:get(i.."pan"))
          else
            engine.pitch(i, math.pow(2,(chord[1]-60)/12))
          end

          local aux1 = 2*i + 4
          if #chord >= 2 then
            if #chord == 2 then
              engine.pitch(aux1, math.pow(2,(chord[2]-60)/12))
              engine.gate(aux1, 1)
              envelope_attack(aux1)
              engine.jitter(aux1,   params:get(i.."jitter")/1000)
              engine.size(aux1,     params:get(i.."size")/1000)
              engine.density(aux1,  params:get(i.."density"))
              engine.spread(aux1,   params:get(i.."spread")/100)
              engine.envscale(aux1, params:get(i.."fade")/1000)
              engine.seek(aux1,     params:get(i.."seek")/100)
              engine.pan(aux1,      params:get(i.."pan"))
            else
              engine.pitch(aux1, math.pow(2,(chord[2]-60)/12))
            end
          else
            engine.gate(aux1, 0)
          end

          local aux2 = 2*i + 5
          if #chord >= 3 then
            if #chord == 3 then
              engine.pitch(aux2, math.pow(2,(chord[3]-60)/12))
              engine.gate(aux2, 1)
              envelope_attack(aux2)
              engine.jitter(aux2,   params:get(i.."jitter")/1000)
              engine.size(aux2,     params:get(i.."size")/1000)
              engine.density(aux2,  params:get(i.."density"))
              engine.spread(aux2,   params:get(i.."spread")/100)
              engine.envscale(aux2, params:get(i.."fade")/1000)
              engine.seek(aux2,     params:get(i.."seek")/100)
              engine.pan(aux2,      params:get(i.."pan"))
            else
              engine.pitch(aux2, math.pow(2,(chord[3]-60)/12))
            end
          else
            engine.gate(aux2, 0)
          end

          if #chord >= 2 then
            if params:get(i.."random_poly_pan") == 2 then
              if math.random() < 0.5 then
                engine.pan(aux1, -1)
                engine.pan(aux2,  1)
              else
                engine.pan(aux1,  1)
                engine.pan(aux2, -1)
              end
            else
              local mainPan = params:get(i.."pan")
              engine.pan(aux1, mainPan)
              engine.pan(aux2, mainPan)
            end
          end
        end
      end
    end
  end
end

----------------------------------------------------------------
-- K1/K2/K3 for randomizing voices
----------------------------------------------------------------
function key(n, z)
  if n == 1 then
    if z == 1 then
      key1_hold = true
      key1_timer = util.time()
    else
      if key1_hold then
        key1_hold = false
        local dt = util.time() - key1_timer
        if dt >= 1 then
          randomize_voice(1)
          params:set("1seek", math.random()*100)
        end
      end
    end
  elseif n == 2 then
    if z == 1 then
      key2_hold = true
      key2_timer = util.time()
    else
      if key2_hold then
        key2_hold = false
        local dt = util.time() - key2_timer
        if dt >= 1 then
          randomize_voice(4)
          params:set("4seek", math.random()*100)
        else
          randomize_voice(2)
          params:set("2seek", math.random()*100)
        end
      end
    end
  elseif n == 3 then
    if z == 1 then
      key3_hold = true
      key3_timer = util.time()
    else
      if key3_hold then
        key3_hold = false
        local dt = util.time() - key3_timer
        if dt >= 1 then
          randomize_voice(5)
          params:set("5seek", math.random()*100)
        else
          randomize_voice(3)
          params:set("3seek", math.random()*100)
        end
      end
    end
  end
end

function enc(n, d)
  -- no encoder usage
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

----------------------------------------------------------------
-- LFO Processing
----------------------------------------------------------------
local lfo_metro
local lfo_phases = {0, 0, 0}

-- Triangular wave
local function tri_wave(phase)
  if phase < 0.25 then
    return phase*4
  elseif phase < 0.75 then
    return 2 - (phase*4)
  else
    return (phase*4) - 4
  end
end

local function lfo_update()
  for i = 1, 3 do
    local depth = params:get("lfo"..i.."_depth")
    if depth > 0.001 then
      local voice     = params:get("lfo"..i.."_voice")
      local target_idx= params:get("lfo"..i.."_target")
      local shape_idx = params:get("lfo"..i.."_shape")
      local rate      = params:get("lfo"..i.."_rate")

      local target_name = ({
        "filter cutoff","filter res","jitter","density","size",
        "pan","volume"
      })[target_idx]

      -- We get the base param from the standard param set:
      local base_param_id
      if     target_name == "filter cutoff" then base_param_id = voice.."filterCutoff"
      elseif target_name == "filter res"    then base_param_id = voice.."filterRQ"
      elseif target_name == "jitter"        then base_param_id = voice.."jitter"
      elseif target_name == "density"       then base_param_id = voice.."density"
      elseif target_name == "size"          then base_param_id = voice.."size"
      elseif target_name == "pan"           then base_param_id = voice.."pan"
      elseif target_name == "volume"        then base_param_id = voice.."volume"
      end

      local base_val = params:get(base_param_id)

      local p = lfo_phases[i]
      local wave
      if shape_idx == 1 then
        wave = math.sin(2*math.pi * p)  -- sine
      else
        wave = tri_wave(p)              -- triangle
      end

      -- For most parameters, we simply revolve around the base_val ± an offset
      -- scaled by depth, then clamp to a safe range:
      local new_val

      if target_name == "pan" then
        -- Depth from 0..100 -> how wide we can swing around base_val
        -- wave in [-1..1], so offset = wave*(depth/100).
        -- Then clamp final to [-1..1].
        local offset = wave * (depth/100)
        new_val = base_val + offset
        if new_val < -1 then new_val = -1 end
        if new_val >  1 then new_val =  1 end

        local aux1 = 2*voice+4
        local aux2 = 2*voice+5
        engine.pan(voice, new_val)
        engine.pan(aux1, new_val)
        engine.pan(aux2, new_val)

      elseif target_name == "volume" then
        ----------------------------------------------------------------
        -- Volume must never exceed 0 dB if the base is near 0.
        -- We'll treat wave as in [–1..1], but **only** move volume downward
        -- from the base if that base is above -60. So:
        --   1) Map wave to [0..1] by (wave*0.5 + 0.5). That ensures no upward push.
        --   2) Depth picks how far we go downward from the base.
        --   3) We clamp the final volume between -60 and the base (if base < 0),
        --      or -60..0 if the base is >= 0.
        ----------------------------------------------------------------

        -- Convert wave [-1..1] => [0..1]
        local wave_pos = (wave * 0.5) + 0.5   -- wave=-1 => 0, wave=1 => 1

        -- If base_val >= 0, we do not allow going above 0 => clamp top to 0
        -- If base_val < 0, clamp top to that base_val, meaning no going above base
        local clamp_top = (base_val >= 0) and 0 or base_val
        local clamp_bot = -60

        -- The difference from top to -60
        local span = math.abs(clamp_bot - clamp_top)

        -- offset is wave_pos * (Depth% of that span). E.g. if depth=100 => up to the full span
        local offset_db = wave_pos * (span * (depth/100))

        -- Then new_val = top minus that offset
        -- so it starts at top, goes downward
        new_val = clamp_top - offset_db

        -- final clamp for safety
        if new_val < -60 then new_val = -60 end
        if new_val > 0 then new_val = 0 end

        local aux1 = 2*voice + 4
        local aux2 = 2*voice + 5

        local amp = math.pow(10, new_val/20)
        engine.volume(voice, amp)
        engine.volume(aux1, amp)
        engine.volume(aux2, amp)

      else
        -- For filter cutoff, res, jitter, density, size, do the old approach
        local ranges = {
          ["filter cutoff"] = {20, 20000},
          ["filter res"]    = {0.1, 2},
          ["jitter"]        = {0, 2000},
          ["density"]       = {0, 512},
          ["size"]          = {1, 500},
        }
        local minv, maxv = table.unpack(ranges[target_name])

        local offset = wave * (depth/100) * base_val
        new_val = base_val + offset
        if new_val < minv then new_val = minv end
        if new_val > maxv then new_val = maxv end

        local aux1 = 2*voice + 4
        local aux2 = 2*voice + 5

        if target_name == "filter cutoff" then
          engine.filterCutoff(voice, new_val)
          engine.filterCutoff(aux1, new_val)
          engine.filterCutoff(aux2, new_val)

        elseif target_name == "filter res" then
          engine.filterRQ(voice, new_val)
          engine.filterRQ(aux1, new_val)
          engine.filterRQ(aux2, new_val)

        elseif target_name == "jitter" then
          engine.jitter(voice, new_val/1000)
          engine.jitter(aux1, new_val/1000)
          engine.jitter(aux2, new_val/1000)

        elseif target_name == "density" then
          engine.density(voice, new_val)
          engine.density(aux1, new_val)
          engine.density(aux2, new_val)

        elseif target_name == "size" then
          engine.size(voice, new_val/1000)
          engine.size(aux1, new_val/1000)
          engine.size(aux2, new_val/1000)
        end
      end

      -- Advance LFO phase
      lfo_phases[i] = (p + rate/30) % 1
    end
  end
end

local function setup_lfo_metro()
  lfo_metro = metro.init()
  lfo_metro.time = 1/30 -- update ~30 times/s
  lfo_metro.event = lfo_update
  lfo_metro:start()
end

----------------------------------------------------------------

function init()
  setup_ui_metro()
  setup_params()
  setup_engine()
  midi_in = midi.connect(params:get("midi_device"))
  midi_in.event = midi_event

  -- Start LFO clock
  setup_lfo_metro()

  -- Randomize all voices at init
  randomize_all()
end
