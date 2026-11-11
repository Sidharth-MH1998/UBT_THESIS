classdef OnlineAcquisitionSession < handle
    %ONLINEACQUISITIONSESSION Device/replay acquisition and recording; no graphics.
    % UI callbacks receive updates, completed recordings, errors and status.
    properties (SetAccess = private)
        Config
        GridStates
        MuMap
        Labels
        Running = false
        Recording = false
        LastRecording = struct()
        ExperimentalTask = []
        SampleCursor = 0
    end
    properties
        OnUpdate = []
        OnStatus = []
        OnRecording = []
        OnError = []
        OnTaskUpdate = []
    end
    properties (Access = private)
        Signal
        Parameters
        Device = []
        Serial = []
        PollTimer = []
        Clock
        Random
        SerialBuffer = ''
        ForceCursor = 0
        LastRaw = []
        LastForce = []
        LastSpike
        SimulationCalibration
        Chunks
        RecordedForce
        RecordMetadata
        RecordStartSample
        RecordStartTime
        ReplayForce = zeros(0,3)
        DemoSpikePhase = [0 0]
        PollSuspended = false
    end
    methods
        function obj = OnlineAcquisitionSession(cfg,signal,parameters)
            setup_online_dependencies();
            obj.Config = cfg;
            for name = {'calibrationFactors','zeroValues','reverseStates'}
                obj.Config.forceCalibration.(name{1}) = ...
                    reshape(cfg.forceCalibration.(name{1}),1,[]);
            end
            obj.SimulationCalibration = obj.Config.forceCalibration;
            obj.Signal = signal;
            obj.Parameters = parameters;
            obj.Random = RandStream('mt19937ar','Seed',17);
        end

        function start(obj,useTimer)
            if nargin < 2, useTimer = true; end
            assert(~obj.Running,'Acquisition is already running.');
            try
                obj.status('Preparing grid decoders...');
                if strcmp(obj.Config.acquisitionMode,'Simulation')
                    obj.prepareSimulation();
                    obj.Config.fs = 2000;
                    obj.Config.quadrantReferenceRates = 12+2*(0:size(obj.MuMap,1)-1);
                else
                    assert(~isempty(fieldnames(obj.Signal)), ...
                        'Import an edited decomposition before hardware acquisition or replay.');
                    [obj.GridStates,obj.MuMap] = prepare_online_grid_states( ...
                        obj.Signal,obj.Parameters,obj.Config);
                    obj.Config.fs = obj.Signal.fsamp;
                    obj.Config.quadrantReferenceRates = get_mu_reference_rates(obj.Signal);
                end
                obj.Config.forceSource = 'simulated';
                if strcmp(obj.Config.acquisitionMode,'Hardware')
                    obj.Config.forceSource = 'hardware';
                elseif strcmp(obj.Config.acquisitionMode,'Replay calibration') && ...
                        isfield(obj.Signal,'recordedForce') && ~isempty(obj.Signal.recordedForce)
                    validateattributes(obj.Signal.recordedForce,{'numeric'}, ...
                        {'2d','ncols',3,'real','finite'});
                    obj.ReplayForce = double(obj.Signal.recordedForce);
                    if isfield(obj.Signal,'fs_force') && ~isempty(obj.Signal.fs_force)
                        obj.Config.forceFs = obj.Signal.fs_force;
                    end
                    validateattributes(obj.Config.forceFs,{'numeric'}, ...
                        {'scalar','real','positive','finite'});
                    obj.Config.forceSource = 'recorded';
                end
                obj.Config.nsamp = round(obj.Config.fs*obj.Config.blockDurationSec);
                assert(obj.Config.nsamp > 0 && ...
                    abs(obj.Config.nsamp-obj.Config.fs*obj.Config.blockDurationSec)<1e-9, ...
                    'EMG window must contain a whole number of samples.');
                obj.Labels = arrayfun(@(mu) sprintf('G%d MU%d', ...
                    obj.MuMap(mu,1),obj.MuMap(mu,2)),1:size(obj.MuMap,1), ...
                    'UniformOutput',false);
                if obj.Config.showQuadrant
                    assert(max(obj.Config.quadrantXMU,obj.Config.quadrantYMU) <= ...
                        size(obj.MuMap,1), 'Quadrant MU index exceeds retained MU count.');
                end
                for g = 1:numel(obj.GridStates)
                    state = obj.GridStates{g};
                    assert(state.nMU == 0 || obj.Config.nsamp >= state.extensionfactor-1, ...
                        'Increase the EMG window: it is too short for grid %d.',g);
                end
                if strcmp(obj.Config.acquisitionMode,'Hardware')
                    obj.status('Connecting Arduino and Novecento...');
                    obj.Serial = initializeArduinoForceStream(obj.Config.forcePort);
                    obj.Device = novecento_connect(obj.Config);
                    rates = obj.Device.fsInput(obj.Config.activeInputs);
                    assert(all(rates == obj.Config.fs), ...
                        'Every hardware input must match calibration sampling frequency.');
                    assert(max(obj.Config.emgChannels) <= ...
                        sum(obj.Device.NumChan(obj.Config.activeInputs)), ...
                        'Stream channel mapping exceeds connected input channels.');
                    flush(obj.Device.tcpSocket);
                    flush(obj.Serial,'input');
                end
                obj.SampleCursor = 0;
                obj.ForceCursor = 0;
                obj.LastSpike = -inf(1,size(obj.MuMap,1));
                obj.LastRaw = [];
                obj.LastForce = [];
                obj.SerialBuffer = '';
                obj.Clock = tic;
                obj.Running = true;
                if useTimer, obj.beginPolling(); end
                if strcmp(obj.Config.acquisitionMode,'Replay calibration')
                    obj.status(sprintf('Replay running: %s force at %g Hz. Press Start recording to retain a segment.', ...
                        obj.Config.forceSource,obj.Config.forceFs));
                else
                    obj.status('Acquisition running. Press Start recording to retain a segment.');
                end
            catch exception
                obj.Running = false;
                obj.releaseDevices();
                rethrow(exception);
            end
        end

        function beginPolling(obj)
            assert(obj.Running,'Start the session before polling.');
            assert(isempty(obj.PollTimer),'The polling timer is already active.');
            obj.PollTimer = timer('ExecutionMode','fixedSpacing', ...
                'Period',0.02,'BusyMode','drop', ...
                'TimerFcn',@(~,~) obj.poll(), ...
                'ErrorFcn',@(~,event) obj.fail(event.Data));
            start(obj.PollTimer);
        end

        function startExperimentalTask(obj,settings,metadata)
            assert(obj.Running && ~obj.Recording,'Start acquisition and stop any active recording first.');
            assert(all(settings.mu <= numel(obj.Labels)),'Selected MUs are unavailable.');
            settings.muMap = obj.MuMap(settings.mu,:);
            settings.simulatedGuidance = strcmp(obj.Config.acquisitionMode,'Simulation');
            settings.originalMUIds = zeros(1,2);
            for k = 1:2
                g = settings.muMap(k,1);
                settings.originalMUIds(k) = obj.GridStates{g}.originalIDs(settings.muMap(k,2));
            end
            task = MotorUnitTargetTask(settings,obj.Config.fs);
            guard = obj.suspendPolling(); %#ok<NASGU>
            obj.startRecording(metadata);
            obj.ExperimentalTask = task;
            obj.DemoSpikePhase = [0 0];
            obj.publishTask();
        end

        function startRecording(obj,metadata)
            guard = obj.suspendPolling(); %#ok<NASGU>
            assert(obj.Running && ~obj.Recording,'Start acquisition before recording.');
            obj.RecordMetadata = metadata;
            obj.RecordStartSample = obj.SampleCursor;
            obj.RecordStartTime = toc(obj.Clock);
            if ~strcmp(obj.Config.acquisitionMode,'Hardware')
                obj.RecordStartTime = obj.SampleCursor/obj.Config.fs;
            end
            obj.Chunks = struct('pulse',{{}},'spikes',{{}},'emg',{{}});
            obj.RecordedForce = obj.emptyForce();
            obj.Recording = true;
            obj.status('Recording');
        end

        function result = stopRecording(obj)
            guard = obj.suspendPolling(); %#ok<NASGU>
            assert(obj.Recording,'There is no active recording.');
            obj.Recording = false;
            cfg = obj.Config;
            obj.LastRecording = collect_app_recording(obj.Chunks,obj.RecordedForce, ...
                obj.GridStates,cfg,obj.RecordMetadata, ...
                obj.RecordStartSample,obj.RecordStartTime);
            if ~isempty(obj.ExperimentalTask)
                obj.ExperimentalTask.abort('stopped');
                obj.LastRecording.task = obj.ExperimentalTask.export();
                obj.LastRecording.fulltask_data = obj.LastRecording.online;
                obj.LastRecording = rmfield(obj.LastRecording,'online');
                obj.publishTask();
                obj.ExperimentalTask = [];
            end
            result = obj.LastRecording;
            % Release recording buffers after the completed result takes ownership.
            obj.Chunks = [];
            obj.RecordedForce = [];
            obj.status('Recording stopped. Acquisition continues.');
            if ~isempty(obj.OnRecording), obj.OnRecording(result); end
        end

        function stop(obj)
            obj.Running = false;
            cleanup = onCleanup(@() obj.releaseDevices());
            if obj.Recording, obj.stopRecording(); end
            obj.status('Acquisition stopped.');
        end

        function zeroForce(obj)
            assert(~strcmp(obj.Config.forceSource,'recorded'), ...
                'Recorded replay force is already calibrated; its stored baseline is preserved.');
            assert(obj.Running && ~obj.Recording, ...
                'Zero force while acquisition is running and recording is stopped.');
            assert(~isempty(obj.LastRaw),'No force samples received yet.');
            obj.Config.forceCalibration.zeroValues = obj.LastRaw;
            obj.LastForce = [];
            obj.status('Force zero updated.');
        end

        function setQuadrantSettings(obj,settings)
            assert(~obj.Recording,'Stop recording before changing quadrant settings.');
            names = fieldnames(settings);
            for idx = 1:numel(names)
                obj.Config.(names{idx}) = settings.(names{idx});
            end
        end

        function poll(obj)
            if ~obj.Running || obj.PollSuspended, return; end
            try
                if toc(obj.Clock) >= obj.Config.onlineDurationSec
                    obj.stop(); return;
                end
                if strcmp(obj.Config.acquisitionMode,'Hardware')
                    force = obj.readForce();
                    obj.appendForce(force);
                    bytes = obj.Device.PacketSize1Block*obj.Config.windowBaseCols*2;
                    for window = 1:4
                        if ~obj.Running || obj.Device.tcpSocket.NumBytesAvailable < bytes
                            break;
                        end
                        raw = novecento_read_emg_block(obj.Device, ...
                            obj.Config.activeInputs,obj.Config.nsamp);
                        emg = raw(obj.Config.emgChannels,:);
                        obj.processWindow(emg,force);
                        force = obj.emptyForce();
                    end
                    if ~isempty(force.data), obj.publishForce(force); end
                    obj.checkRecordingLimit();
                else
                    due = floor(toc(obj.Clock)/obj.Config.blockDurationSec);
                    if due > obj.SampleCursor/obj.Config.nsamp
                        obj.advanceSimulation();
                    end
                end
            catch exception
                obj.fail(exception);
            end
        end

        function advanceSimulation(obj)
            % Deterministic single-window step also used by hardware-free tests.
            assert(obj.Running && ~strcmp(obj.Config.acquisitionMode,'Hardware'), ...
                'Simulation must be running.');
            n = obj.Config.nsamp;
            if strcmp(obj.Config.acquisitionMode,'Replay calibration')
                if obj.SampleCursor+n > size(obj.Signal.data,2)
                    obj.stop(); return;
                end
                rows = obj.Config.calibChannels;
                emg = double(obj.Signal.data(rows,obj.SampleCursor+(1:n)));
            else
                emg = randn(obj.Random,numel(obj.Config.emgChannels),n);
            end
            endTime = (obj.SampleCursor+n)/obj.Config.fs;
            if strcmp(obj.Config.forceSource,'recorded')
                % Native-rate samples in [previous EMG time, endTime), starting at t=0.
                finalForceIndex = min(size(obj.ReplayForce,1),ceil(endTime*obj.Config.forceFs-1e-9));
                indices = (obj.ForceCursor+1:finalForceIndex)';
                obj.ForceCursor = finalForceIndex;
                force = obj.emptyForce();
                force.data = obj.ReplayForce(indices,:);
                force.sessionTime = (indices-1)/obj.Config.forceFs;
                force.arduinoTime = nan(numel(indices),1); % Original device timestamps are unavailable.
                obj.appendForce(force);
                obj.processWindow(emg,force);
                obj.checkRecordingLimit();
                return;
            end
            finalForceIndex = floor(endTime*obj.Config.forceFs);
            indices = (obj.ForceCursor+1:finalForceIndex)';
            obj.ForceCursor = finalForceIndex;
            force = obj.emptyForce();
            for idx = 1:numel(indices)
                t = indices(idx)/obj.Config.forceFs;
                syntheticForce = 35+25*sin(2*pi*t./[8 9 10]+[1 2 3]);
                reverse = logical(obj.Config.forceCalibration.reverseStates(:).');
                raw = syntheticForce.*obj.SimulationCalibration.calibrationFactors/100 + ...
                    obj.SimulationCalibration.zeroValues;
                raw(reverse) = -raw(reverse);
                if obj.Config.extensionPositive, raw = -raw; end
                force = obj.addForceSample(force,raw,indices(idx),t);
            end
            obj.appendForce(force);
            obj.processWindow(emg,force);
            obj.checkRecordingLimit();
        end

        function delete(obj)
            obj.Running = false;
            obj.releaseDevices();
        end
    end

    methods (Access = private)
        function guard = suspendPolling(obj)
            wasSuspended = obj.PollSuspended;
            obj.PollSuspended = true;
            guard = onCleanup(@() obj.restorePolling(wasSuspended));
        end

        function restorePolling(obj,wasSuspended)
            obj.PollSuspended = wasSuspended;
        end

        function processWindow(obj,emg,force)
            if strcmp(obj.Config.acquisitionMode,'Simulation')
                [pulse,spikes] = obj.syntheticSpikes();
            else
                [pulse,spikes,obj.GridStates] = ...
                    decode_online_grid_window(emg,obj.GridStates,obj.Config.fs);
            end
            obj.SampleCursor = obj.SampleCursor+obj.Config.nsamp;
            if obj.Recording
                idx = numel(obj.Chunks.pulse)+1;
                obj.Chunks.pulse{idx} = pulse;
                obj.Chunks.spikes{idx} = spikes;
                if obj.Config.recordEMG, obj.Chunks.emg{idx} = emg; end
            end
            if ~isempty(obj.ExperimentalTask)
                obj.ExperimentalTask.step(spikes,(obj.SampleCursor-obj.RecordStartSample)/obj.Config.fs);
                if isempty(obj.ExperimentalTask.Completion)
                    obj.publishTask();
                else
                    obj.stopRecording();
                end
            end
            if ~isempty(obj.OnUpdate)
                obj.OnUpdate(struct('time',obj.SampleCursor/obj.Config.fs, ...
                    'pulse',pulse,'spikes',spikes,'force',force,'emg',emg, ...
                    'sampleCursor',obj.SampleCursor));
            end
            every = obj.Config.printEveryNWindows;
            if every > 0 && mod(obj.SampleCursor/obj.Config.nsamp,every) == 0
                fprintf('t = %.2f s | spikes = %s\n', ...
                    obj.SampleCursor/obj.Config.fs,mat2str(sum(spikes,1)));
            end
        end

        function publishTask(obj)
            if ~isempty(obj.OnTaskUpdate)
                obj.OnTaskUpdate(obj.ExperimentalTask.snapshot(),obj.ExperimentalTask.Settings);
            end
        end

        function [pulse,spikes] = syntheticSpikes(obj)
            n = obj.Config.nsamp;
            nMU = size(obj.MuMap,1);
            spikes = false(n,nMU);
            rates = 12+6*sin(2*pi*obj.SampleCursor/obj.Config.fs/8+(0:nMU-1));
            for sample = 1:n
                globalSample = obj.SampleCursor+sample;
                fired = rand(obj.Random,1,nMU) < rates/obj.Config.fs & ...
                    globalSample-obj.LastSpike >= round(0.02*obj.Config.fs);
                spikes(sample,:) = fired;
                obj.LastSpike(fired) = globalSample;
            end
            if ~isempty(obj.ExperimentalTask)
                task = obj.ExperimentalTask;
                demoRate = [0 0];
                if strcmp(task.Phase,'attempt')
                    point = task.Targets(task.Schedule(task.Trial),:);
                    demoRate = point.*task.Settings.referencePPS./task.Settings.gain;
                end
                step = min(1,demoRate/obj.Config.fs);
                phase = obj.DemoSpikePhase + (0:n)'*step;
                spikes(:,task.Settings.mu) = diff(floor(phase+1e-9),1,1)>0;
                obj.DemoSpikePhase = mod(phase(end,:),1);
            end
            pulse = 0.03*randn(obj.Random,nMU,n)+double(spikes');
        end

        function prepareSimulation(obj)
            nGrids = obj.Config.numberOfGrids;
            obj.GridStates = cell(1,nGrids);
            obj.MuMap = zeros(3*nGrids,2);
            for g = 1:nGrids
                ids = (g-1)*3+(1:3);
                channels = (g-1)*64+(1:64);
                [~,channelRows] = ismember(channels,obj.Config.calibChannels);
                obj.GridStates{g} = struct('nMU',3,'muIndices',ids, ...
                    'originalIDs',1:3,'calibChannels',channels, ...
                    'channelRows',channelRows,'mask',false(64,1), ...
                    'MUfilt',zeros(3,0),'extensionfactor',0, ...
                    'normval',ones(1,3),'centroid',repmat([0 1],3,1));
                obj.MuMap(ids,:) = [repmat(g,3,1) (1:3)'];
            end
        end

        function force = readForce(obj)
            force = obj.emptyForce();
            count = obj.Serial.NumBytesAvailable;
            if count == 0, return; end
            bytes = read(obj.Serial,count,'uint8');
            obj.SerialBuffer = [obj.SerialBuffer char(bytes(:).')];
            ends = find(obj.SerialBuffer == newline);
            offset = 1;
            for idx = 1:numel(ends)
                line = obj.SerialBuffer(offset:ends(idx)-1);
                offset = ends(idx)+1;
                sample = sscanf(line,'%f,%f,%f,%f');
                if numel(sample) == 4 && all(isfinite(sample))
                    force = obj.addForceSample(force,sample(2:4)',sample(1),toc(obj.Clock));
                end
            end
            obj.SerialBuffer = obj.SerialBuffer(offset:end);
            assert(numel(obj.SerialBuffer)<65536, ...
                'Arduino is not sending complete newline-terminated force samples.');
        end

        function force = addForceSample(obj,force,raw,arduinoTime,time)
            raw(logical(obj.Config.forceCalibration.reverseStates)) = ...
                -raw(logical(obj.Config.forceCalibration.reverseStates));
            if obj.Config.extensionPositive, raw = -raw; end
            obj.LastRaw = raw;
            calibrated = (raw-obj.Config.forceCalibration.zeroValues)./ ...
                obj.Config.forceCalibration.calibrationFactors*100;
            if ~isempty(obj.LastForce), calibrated = 0.3*calibrated+0.7*obj.LastForce; end
            obj.LastForce = calibrated;
            force.data(end+1,:) = calibrated;
            force.arduinoTime(end+1,1) = arduinoTime;
            force.sessionTime(end+1,1) = time;
        end

        function appendForce(obj,force)
            if ~obj.Recording || isempty(force.data), return; end
            remaining = max(0,floor(obj.Config.forceFs*obj.Config.forceMaxDurationSec) - ...
                size(obj.RecordedForce.data,1));
            names = fieldnames(force);
            for idx = 1:numel(names)
                obj.RecordedForce.(names{idx}) = ...
                    [obj.RecordedForce.(names{idx}); force.(names{idx})(1:min(remaining,end),:)];
            end
        end

        function checkRecordingLimit(obj)
            if ~obj.Recording, return; end
            if size(obj.RecordedForce.data,1) >= floor(obj.Config.forceFs*obj.Config.forceMaxDurationSec)
                obj.stopRecording();
                obj.status('Force recording capacity reached; acquisition continues.');
            end
        end

        function publishForce(obj,force)
            if ~isempty(obj.OnUpdate)
                nMU = size(obj.MuMap,1);
                obj.OnUpdate(struct('time',obj.SampleCursor/obj.Config.fs, ...
                    'pulse',zeros(nMU,0),'spikes',false(0,nMU), ...
                    'force',force,'emg',zeros(numel(obj.Config.emgChannels),0), ...
                    'sampleCursor',obj.SampleCursor));
            end
        end

        function fail(obj,exception)
            if ~isa(exception,'MException')
                if isstruct(exception) && isfield(exception,'Message')
                    message = exception.Message;
                elseif isstruct(exception) && isfield(exception,'message')
                    message = exception.message;
                else
                    message = 'Acquisition timer failed.';
                end
                exception = MException('OnlineApp:TimerError','%s',message);
            end
            try
                obj.stop();
            catch
                obj.releaseDevices();
            end
            if ~isempty(obj.OnError), obj.OnError(exception); end
        end

        function status(obj,message)
            if ~isempty(obj.OnStatus), obj.OnStatus(message); end
        end

        function releaseDevices(obj)
            if ~isempty(obj.PollTimer)
                try
                    stop(obj.PollTimer);
                    delete(obj.PollTimer);
                catch
                end
                obj.PollTimer = [];
            end
            if ~isempty(obj.Device)
                try
                    novecento_disconnect(obj.Device);
                catch
                end
                obj.Device = [];
            end
            if ~isempty(obj.Serial)
                try
                    delete(obj.Serial);
                catch
                end
                obj.Serial = [];
            end
        end
    end
    methods (Static, Access = private)
        function force = emptyForce()
            force = struct('data',zeros(0,3),'arduinoTime',zeros(0,1), ...
                'sessionTime',zeros(0,1));
        end
    end
end
