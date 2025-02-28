Engine_GlutXtd : CroneEngine {
    classvar nvoices = 15;

    var pg;
    var <delaySynth; // global delay effect synth
    var <buffersL;
    var <buffersR;
    var <voices;
    var mixBus;
    var <phases;
    var <levels;

    var <seek_tasks;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    // disk read
    readBuf { arg i, path;
        if(buffersL[i].notNil && buffersR[i].notNil, {
            if(File.exists(path), {
                var numChannels;
                var newbuf;

                numChannels = SoundFile.use(path.asString(), { |f| f.numChannels });

                newbuf = Buffer.readChannel(context.server, path, 0, -1, [0], { |b|
                    voices[i].set(\buf_l, b);
                    buffersL[i].free;
                    buffersL[i] = b;
                });

                if(numChannels > 1, {
                    newbuf = Buffer.readChannel(context.server, path, 0, -1, [1], { |b|
                        voices[i].set(\buf_r, b);
                        buffersR[i].free;
                        buffersR[i] = b;
                    });
                }, {
                    voices[i].set(\buf_r, newbuf);
                    buffersR[i].free;
                    buffersR[i] = newbuf;
                });
            });
        });
    }

    alloc {
        buffersL = Array.fill(nvoices, { arg i;
            Buffer.alloc(
                context.server,
                context.server.sampleRate * 1
            );
        });

        buffersR = Array.fill(nvoices, { arg i;
            Buffer.alloc(
                context.server,
                context.server.sampleRate * 1
            );
        });

        // Extended SynthDef with resonant filter parameters + PitchShift
        SynthDef(\synth, {
            arg out, phase_out, level_out,
                buf_l, buf_r,
                gate=0, pos=0, speed=1, jitter=0,
                size=0.1, density=20, pitch=1, pan=0, spread=0, gain=1, envscale=1,
                freeze=0, t_reset_pos=0,

                // per-voice resonant filter
                filterFreq=8000, filterRQ=0.5,

                // PitchShift arguments
                shiftWindow=0.1,
                shiftRatio=1.0,
                shiftPitchDispersion=0.0,
                shiftTimeDispersion=0.0,
                shiftMul=1.0,
                shiftAdd=0.0;

            var grain_trig, jitter_sig, buf_dur, pan_sig;
            var buf_pos, pos_sig, sig_l, sig_r, sig_mix, env, level;

            // Granular triggering
            grain_trig = Impulse.kr(density);
            buf_dur = BufDur.kr(buf_l);

            pan_sig = TRand.kr(
                trig: grain_trig,
                lo: spread.neg,
                hi: spread
            );

            jitter_sig = TRand.kr(
                trig: grain_trig,
                lo: buf_dur.reciprocal.neg * jitter,
                hi: buf_dur.reciprocal * jitter
            );

            // Phase tracking
            buf_pos = Phasor.kr(
                trig: t_reset_pos,
                rate: buf_dur.reciprocal / ControlRate.ir * speed,
                resetPos: pos
            );

            pos_sig = Wrap.kr(Select.kr(freeze, [buf_pos, pos]));

            // Granular voices
            sig_l = GrainBuf.ar(
                1, grain_trig, size, buf_l, pitch, pos_sig + jitter_sig, 2
            );
            sig_r = GrainBuf.ar(
                1, grain_trig, size, buf_r, pitch, pos_sig + jitter_sig, 2
            );

            // Combine L/R with per‐voice panning
            sig_mix = Balance2.ar(sig_l, sig_r, pan + pan_sig);

            // PitchShift inserted immediately after granular voices
            sig_mix = PitchShift.ar(
                sig_mix,
                shiftWindow,
                shiftRatio,
                shiftPitchDispersion,
                shiftTimeDispersion,
                shiftMul,
                shiftAdd
            );

            // Per-voice resonant filter
            sig_mix = RLPF.ar(sig_mix, filterFreq, filterRQ);

            // Per-voice envelope
            env = EnvGen.kr(Env.asr(1, 1, 1), gate: gate, timeScale: envscale);
            level = env;

            Out.ar(out, sig_mix * level * gain);
            Out.kr(phase_out, pos_sig);
            Out.kr(level_out, level);
        }).add;

        // Global delay effect + decimator
        SynthDef(\delay, {
            arg in, out,
                delayTime=0.5, feedback=0.5, mix=0.5, maxDelay=2.0,

                // Decimator parameters
                deciRate=44100.0, deciBits=24, deciMul=1.0, deciAdd=0.0;

            var dry, fb, delayed, wet, outSig;

            // read the dry signal from the input bus
            dry = In.ar(in, 2);

            // read feedback from the local loop
            fb = LocalIn.ar(2);

            // pass sum of dry + feedback into delay
            delayed = DelayL.ar(dry + (fb * feedback), maxDelay, delayTime);

            // decimate inside the feedback loop
            delayed = Decimator.ar(
                delayed,
                rate: deciRate,
                bits: deciBits,
                mul: deciMul,
                add: deciAdd
            );

            // store delayed (bit-reduced) signal back into local loop
            LocalOut.ar(delayed);

            // final wet/dry mix
            wet = delayed;
            outSig = (dry * (1 - mix)) + (wet * mix);

            Out.ar(out, outSig);
        }).add;

        context.server.sync;

        // mix bus for all synth outputs
        mixBus = Bus.audio(context.server, 2);

        // Instantiate the global delay (with integrated decimator)
        delaySynth = Synth.new(\delay, [
            \in, mixBus.index,
            \out, context.out_b.index
        ], target: context.xg);

        phases = Array.fill(nvoices, { arg i; Bus.control(context.server); });
        levels = Array.fill(nvoices, { arg i; Bus.control(context.server); });

        pg = ParGroup.head(context.xg);

        voices = Array.fill(nvoices, { arg i;
            Synth.new(\synth, [
                \out, mixBus.index,
                \phase_out, phases[i].index,
                \level_out, levels[i].index,
                \buf_l, buffersL[i],
                \buf_r, buffersR[i],
                \filterFreq, 8000,
                \filterRQ, 0.5
            ], target: pg);
        });

        context.server.sync;

        // File read command remains unchanged
        this.addCommand("read", "is", { arg msg;
            this.readBuf(msg[1] - 1, msg[2]);
        });

        this.addCommand("seek", "if", { arg msg;
            var voice = msg[1] - 1;
            var lvl, pos;
            var seek_rate = 1 / 750;

            seek_tasks[voice].stop;

            lvl = levels[voice].getSynchronous();

            if (false, { // placeholder for potential advanced seeking
                var step;
                var target_pos;
                pos = phases[voice].getSynchronous();
                voices[voice].set(\freeze, 1);

                target_pos = msg[2];
                step = (target_pos - pos) * seek_rate;

                seek_tasks[voice] = Routine {
                    while({ abs(target_pos - pos) > abs(step) }, {
                        pos = pos + step;
                        voices[voice].set(\pos, pos);
                        seek_rate.wait;
                    });
                    voices[voice].set(\pos, target_pos);
                    voices[voice].set(\freeze, 0);
                    voices[voice].set(\t_reset_pos, 1);
                };

                seek_tasks[voice].play();
            }, {
                pos = msg[2];
                voices[voice].set(\pos, pos);
                voices[voice].set(\t_reset_pos, 1);
                voices[voice].set(\freeze, 0);
            });
        });

        this.addCommand("gate", "ii", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\gate, msg[2]);
        });

        this.addCommand("speed", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\speed, msg[2]);
        });

        this.addCommand("jitter", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\jitter, msg[2]);
        });

        this.addCommand("size", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\size, msg[2]);
        });

        this.addCommand("density", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\density, msg[2]);
        });

        this.addCommand("pitch", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\pitch, msg[2]);
        });

        this.addCommand("pan", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\pan, msg[2]);
        });

        this.addCommand("spread", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\spread, msg[2]);
        });

        this.addCommand("volume", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\gain, msg[2]);
        });

        this.addCommand("envscale", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\envscale, msg[2]);
        });

        // New command handlers for resonant filter control
        this.addCommand("filterCutoff", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\filterFreq, msg[2]);
        });

        this.addCommand("filterRQ", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\filterRQ, msg[2]);
        });

        // Commands for the global delay parameters
        this.addCommand("delay_time", "f", { arg msg; delaySynth.set(\delayTime, msg[1]); });
        this.addCommand("delay_feedback", "f", { arg msg; delaySynth.set(\feedback, msg[1]); });
        this.addCommand("delay_mix", "f", { arg msg; delaySynth.set(\mix, msg[1]); });

        // Decimator command handlers
        this.addCommand("decimator_rate", "f", { arg msg; delaySynth.set(\deciRate, msg[1]); });
        this.addCommand("decimator_bits", "f", { arg msg; delaySynth.set(\deciBits, msg[1]); });
        this.addCommand("decimator_mul", "f", { arg msg; delaySynth.set(\deciMul, msg[1]); });
        this.addCommand("decimator_add", "f", { arg msg; delaySynth.set(\deciAdd, msg[1]); });

        // New commands for per‐voice PitchShift parameters
        this.addCommand("ps_windowSize", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\shiftWindow, msg[2]);
        });

        this.addCommand("ps_pitchRatio", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\shiftRatio, msg[2]);
        });

        this.addCommand("ps_pitchDispersion", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\shiftPitchDispersion, msg[2]);
        });

        this.addCommand("ps_timeDispersion", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\shiftTimeDispersion, msg[2]);
        });

        this.addCommand("ps_mul", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\shiftMul, msg[2]);
        });

        this.addCommand("ps_add", "if", { arg msg;
            var voice = msg[1] - 1;
            voices[voice].set(\shiftAdd, msg[2]);
        });

        // set up polled phase & level readings
        nvoices.do({ arg i;
            this.addPoll(("phase_" ++ (i+1)).asSymbol, {
                var val = phases[i].getSynchronous;
                val
            });

            this.addPoll(("level_" ++ (i+1)).asSymbol, {
                var val = levels[i].getSynchronous;
                val
            });
        });

        seek_tasks = Array.fill(nvoices, { arg i;
            Routine {}
        });
    }

    free {
        voices.do({ arg voice; voice.free; });
        phases.do({ arg bus; bus.free; });
        levels.do({ arg bus; bus.free; });
        buffersL.do({ arg b; b.free; });
        buffersR.do({ arg b; b.free; });
        delaySynth.free;
        mixBus.free;
    }
}
