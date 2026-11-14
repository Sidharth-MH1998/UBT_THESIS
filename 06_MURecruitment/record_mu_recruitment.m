function out = record_mu_recruitment(calibration, parameters, cfg)
%RECORD_MU_RECRUITMENT Live force/raster feedback and trial recording.
% Uses the existing recorder UI, hardware drivers and multigrid decoder.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'07_onlineDecompositionV3'));
setup_online_dependencies();
assert(cfg.recordEMG, 'Recruitment recording requires cfg.recordEMG = true.');
if ~exist(cfg.outputFolder,'dir'), mkdir(cfg.outputFolder); end
simulation = isfield(cfg,'simulation') && cfg.simulation;
if simulation
    states = {};
    muMap = [repelem((1:numel(cfg.activeInputs))',4) repmat((1:4)',numel(cfg.activeInputs),1)];
else
    [states, muMap] = prepare_online_grid_states(calibration, parameters, cfg);
end
nMU = size(muMap,1);
assert(nMU > 0, 'Calibration contains no motor units.');
[factors, zerosForce, reverse, cfg.forceCalibrationFile] = force_calibration(cfg);
[fig, ax, raster, closeBtn, zeroBtn, recordBtn, trackBtn, channelBox, ...
    traceBox, waitBox, slopeBox, plateauBox, targetBox, signLabel, ...
    signBox, participantBox, trialBox, sessionBox] = setupRecordingFigure(true,0);
fig.Name = 'Motor Unit Recruitment - Force and Raster';
if simulation
    fig.Name = [fig.Name ' [SIMULATION]'];
    participantBox.String = 'DEMO';
end
fig.CloseRequestFcn = @(~,~) set(closeBtn,'Value',1);
figCleanup = onCleanup(@() delete_figure(fig));
traceBox.String = {'Trapezium','Triangular'}; traceBox.Value = 1;
targetBox.String = '20';
plateauBox.String = '10';
slopeBox.String = '10';
traceBox.Callback = @(~,~) update_trace_controls();
plateauBox.TooltipString = 'Hold duration for Trapezium; ignored for Triangular.';
% Make room for the repetition setting within this recorder only.
controlPanel = targetBox.Parent;
rowLabels = {'Participant','Session','Trial','Digit/Channel','Trace', ...
    'Wait (s)','Slope (s)','Plateau (s)','Target (%)'};
rowFields = [participantBox sessionBox trialBox channelBox traceBox ...
    waitBox slopeBox plateauBox targetBox];
rowY = linspace(0.91,0.35,numel(rowFields));
for row = 1:numel(rowFields)
    pos = rowFields(row).Position; pos(2) = rowY(row);
    rowFields(row).Position = pos;
    label = findobj(controlPanel,'Style','text','String',rowLabels{row});
    pos = label.Position; pos(2) = rowY(row); label.Position = pos;
end
uicontrol(controlPanel,'Style','text','String','Repetitions', ...
    'Units','normalized','Position',[0.08 0.28 0.42 0.045], ...
    'HorizontalAlignment','left','BackgroundColor',controlPanel.BackgroundColor);
repeatBox = uicontrol(controlPanel,'Style','edit','String','3', ...
    'Units','normalized','Position',[0.53 0.28 0.39 0.05], ...
    'TooltipString','Positive integer: repeat the entire tracking task N times.');
title(raster,'Live Motor Unit Raster'); ylabel(raster,'Motor unit');
ylim(raster,[0 nMU+1]); yticks(raster,1:nMU);
labels = arrayfun(@(k) sprintf('G%d MU%d',muMap(k,1),muMap(k,2)), ...
    1:nMU,'UniformOutput',false);
yticklabels(raster,labels);
colors = lines(nMU); marks = gobjects(nMU,1);
for k = 1:nMU
    marks(k) = plot(raster,nan,nan,'|','Color',colors(k,:),'MarkerSize',10);
end
forceLines = initializeStreamForcePlot(ax,3);
targetLine = plot(ax,nan,nan,'k-','LineWidth',1.5);
if simulation
    fs = 2000;
    simStream = RandStream('mt19937ar','Seed',42);
    simNextForce = 0;
else
    serial = initializeArduinoForceStream(cfg.forcePort);
    serialCleanup = onCleanup(@() delete_serial(serial));
    dev = novecento_connect(cfg);
    emgCleanup = onCleanup(@() novecento_disconnect(dev));
    rates = dev.fsInput(cfg.activeInputs);
    assert(all(rates > 0) && numel(unique(rates)) == 1, ...
        'Active inputs must have the same positive sampling rate.');
    fs = rates(1);
    assert(fs == calibration.fsamp,'Online and calibration sampling rates must match.');
    assert(max(cfg.emgChannels) <= sum(dev.NumChan(cfg.activeInputs)), ...
        'EMG channels exceed the available stream channels.');
end
nsamp = fs * cfg.windowBaseCols / 500;
validateattributes(nsamp,{'numeric'},{'scalar','integer','positive'});
for g = 1:numel(states)
    assert(states{g}.nMU == 0 || nsamp >= states{g}.extensionfactor-1, ...
        'Processing window is too short for the calibration extension.');
end
forceData = zeros(0,3); forceTime = zeros(0,1); arduinoTime = zeros(0,1);
emgChunks = {}; pulseChunks = {}; spikeChunks = {};
spikes = cell(1,nMU); cursor = 0; raw = []; previous = [];
recording = false; tracking = false; savedFiles = {}; trialInfo = struct();
clock = tic; lastPlot = -inf;
if ~simulation
    try, flush(dev.tcpSocket); catch, end
end
while isgraphics(fig) && ~closeBtn.Value && toc(clock) < min(cfg.onlineDurationSec,cfg.forceMaxDurationSec)
    % Service UI before reading the next hardware block.
    drawnow;
    if closeBtn.Value, break; end
    requested = logical(recordBtn.Value || trackBtn.Value);
    if requested && ~recording
        [trialInfo, valid, message] = read_trial();
        if ~valid
            warning('Recruitment:TrialSettings','%s',message);
            recordBtn.Value = 0; trackBtn.Value = 0;
        else
            tracking = logical(trackBtn.Value);
            recording = true;
            zeroBtn.Enable = 'off'; signBox.Enable = 'off';
            startForce = size(forceData,1)+1; startSample = cursor+1;
            startClock = toc(clock);
            trialInfo.tracking = tracking;
            if tracking
                recordBtn.Value = 0; recordBtn.Enable = 'off';
                t = [0 trialInfo.wait trialInfo.wait+trialInfo.slope ...
                    trialInfo.wait+trialInfo.slope+trialInfo.plateau ...
                    trialInfo.wait+2*trialInfo.slope+trialInfo.plateau ...
                    2*trialInfo.wait+2*trialInfo.slope+trialInfo.plateau];
                t = reshape(t(:)+(0:trialInfo.repetitions-1)*trialInfo.cycleDuration,1,[]);
                set(targetLine,'XData',startClock+t, ...
                    'YData',repmat(trialInfo.target*[0 0 1 1 0 0],1,trialInfo.repetitions));
                ax.Color = [0.9 1 0.9];
            else
                trackBtn.Enable = 'off'; ax.Color = [1 0.95 0.9];
            end
        end
    end
    if recording && ((tracking && (~trackBtn.Value || toc(clock)-startClock >= trialInfo.duration)) ...
            || (~tracking && ~recordBtn.Value))
        save_trial();
    end
    if simulation
        % Pace synthetic blocks in real time while keeping the UI responsive.
        pause(max(0,(cursor+nsamp)/fs-toc(clock)));
        simTimes = (simNextForce:floor(toc(clock)*cfg.forceFs))'/cfg.forceFs;
        if ~isempty(simTimes)
            simNextForce = round(simTimes(end)*cfg.forceFs)+1;
            level = simulated_level(simTimes);
            for j = 1:numel(simTimes)
                raw = (level(j)*[0.7 1 0.4]+0.5*randn(simStream,1,3)).*factors/100;
                raw(logical(reverse)) = -raw(logical(reverse));
                if signBox.Value, raw = -raw; end
                value = (raw-zerosForce)./factors*100;
                if ~isempty(previous), value = 0.3*value+0.7*previous; end
                previous = value;
                forceData(end+1,:) = value; %#ok<AGROW>
                forceTime(end+1,1) = simTimes(j); %#ok<AGROW>
                arduinoTime(end+1,1) = simTimes(j)*1000; %#ok<AGROW>
            end
        end
    else
    while serial.NumBytesAvailable > 0
        sample = sscanf(char(readline(serial)),'%f,%f,%f,%f');
        if numel(sample) < 4 || any(~isfinite(sample(1:4))), continue; end
        raw = reshape(sample(2:4),1,3);
        raw(logical(reverse)) = -raw(logical(reverse));
        if signBox.Value, raw = -raw; end
        value = (raw-zerosForce)./factors*100;
        if ~isempty(previous), value = 0.3*value+0.7*previous; end
        previous = value;
        forceData(end+1,:) = value; %#ok<AGROW>
        forceTime(end+1,1) = toc(clock); %#ok<AGROW>
        arduinoTime(end+1,1) = sample(1); %#ok<AGROW>
    end
    end % hardware/simulation force source
    if zeroBtn.Value && ~isempty(raw)
        zerosForce = raw; previous = []; zeroBtn.Value = 0;
    end
    if signBox.Value
        signLabel.String = sprintf('(+): Extension\n(-): Flexion');
    else
        signLabel.String = sprintf('(+): Flexion\n(-): Extension');
    end
    if simulation
        sampleTimes = (cursor+(0:nsamp-1))/fs;
        level = simulated_level(sampleTimes);
        thresholds = repmat(linspace(3,24,4),1,numel(cfg.activeInputs));
        rate = (8+0.3*level(:)).*(level(:) >= thresholds);
        dist = rand(simStream,nsamp,nMU) < rate/fs;
        pulse = 0.05*randn(simStream,nMU,nsamp)+4*double(dist');
        emg = randn(simStream,numel(cfg.emgChannels),nsamp).*(0.02+0.004*level);
    else
        block = novecento_read_emg_block(dev,cfg.activeInputs,nsamp);
        emg = double(block(cfg.emgChannels,:));
        [pulse, dist, states] = decode_online_grid_window(emg,states,fs);
    end
    emgChunks{end+1} = emg; %#ok<AGROW>
    pulseChunks{end+1} = pulse; %#ok<AGROW>
    spikeChunks{end+1} = logical(dist); %#ok<AGROW>
    for k = 1:nMU
        spikes{k} = [spikes{k}; find(dist(:,k))+cursor];
    end
    cursor = cursor+size(emg,2);
    now = toc(clock);
    if now-lastPlot >= 1/cfg.forcePlotRateHz
        % Use measured receipt times for force instead of assuming no dropped samples.
        for k = 1:3
            keep = forceTime >= now-cfg.forceDisplayTimeSec;
            clearpoints(forceLines(k));
            addpoints(forceLines(k),forceTime(keep),forceData(keep,k));
        end
        for k = 1:nMU
            times = (spikes{k}-1)/fs;
            times = times(times >= cursor/fs-cfg.visibleWindowSec);
            set(marks(k),'XData',times,'YData',k*ones(size(times)));
        end
        xlim(ax,[max(0,now-cfg.forceDisplayTimeSec) max(cfg.forceDisplayTimeSec,now+cfg.forceBufferTimeSec)]);
        xlim(raster,[max(0,cursor/fs-cfg.visibleWindowSec) max(cfg.visibleWindowSec,cursor/fs)]);
        ylim(ax,[-10 max(110,1.15*str2double(targetBox.String))]);
        lastPlot = now;
    end
end
% Closing or reaching the duration limit saves an active partial trial.
if recording, trialInfo.interrupted = true; save_trial(); end
out = struct('savedFiles',{savedFiles},'nSamples',cursor,'fs',fs,'muMap',muMap);

    function update_trace_controls()
        if traceBox.Value == 2
            plateauBox.Enable = 'off';
        else
            plateauBox.Enable = 'on';
        end
    end

    function level = simulated_level(times)
        if recording && tracking
            level = task_level(times-startClock);
        else
            level = 20+15*sin(2*pi*times/12);
        end
    end

    function level = task_level(times)
        % One shared waveform for simulation and the saved target trace.
        phase = mod(times,trialInfo.cycleDuration);
        level = trialInfo.target*max(0,min(1,min( ...
            (phase-trialInfo.wait)/trialInfo.slope, ...
            (trialInfo.wait+2*trialInfo.slope+trialInfo.plateau-phase)/trialInfo.slope)));
        level(times < 0 | times >= trialInfo.duration) = 0;
    end

    function [info, valid, message] = read_trial()
        info = struct('participant',strtrim(participantBox.String), ...
            'session',str2double(sessionBox.String),'trial',str2double(trialBox.String), ...
            'channel',channelBox.Value,'target',str2double(targetBox.String), ...
            'wait',str2double(waitBox.String),'slope',str2double(slopeBox.String), ...
            'plateau',str2double(plateauBox.String),'interrupted',false);
        info.repetitions = str2double(repeatBox.String);
        info.traceType = traceBox.String{traceBox.Value};
        if strcmp(info.traceType,'Triangular')
            info.plateau = 0;
        end
        values = [info.session info.trial info.target info.wait info.slope info.plateau info.repetitions];
        valid = ~isempty(regexp(info.participant,'^[A-Za-z0-9_-]+$','once')) ...
            && all(isfinite(values)) && all(values >= 0) ...
            && info.slope > 0 && info.session >= 1 && info.trial >= 1 ...
            && all(fix(values(1:2)) == values(1:2)) ...
            && info.repetitions >= 1 && fix(info.repetitions) == info.repetitions;
        info.cycleDuration = 2*info.wait+2*info.slope+info.plateau;
        info.duration = info.repetitions*info.cycleDuration;
        valid = valid && isfinite(info.duration);
        message = 'Use a participant ID containing letters/numbers/_/-, positive integer session/trial/repetitions, nonnegative task values and a positive slope.';
    end

    function save_trial()
        % Freeze trial settings at start; edits apply to the next trial.
        allEMG = horzcat(emgChunks{:});
        allPulse = horzcat(pulseChunks{:});
        allDist = vertcat(spikeChunks{:});
        if cursor < startSample || size(forceData,1) < startForce
            warning('Recruitment:EmptyTrial','Trial contains no EMG or force samples; nothing saved.');
        else
            indices = startSample:cursor;
            forceIndices = startForce:size(forceData,1);
            signal = buildMUeditSignal(allEMG(:,indices),fs,forceData(forceIndices,:), ...
                trialInfo.channel,trialInfo.target,cfg.activeInputs, ...
                cfg.muEditGridName,cfg.muEditMuscle,cfg.forceFs);
            [~,name,ext] = fileparts(cfg.forceCalibrationFile);
            signal.calibrationFileName = [name ext];
            signal.simulated = simulation;
            signal.forceTime = forceTime(forceIndices)-startClock;
            signal.arduinoTime = arduinoTime(forceIndices);
            signal.emgTime = (indices-1)/fs;
            signal.emgTime = signal.emgTime-signal.emgTime(1);
            signal.forceCalibration = struct('factors',factors,'zeroValues',zerosForce, ...
                'reverseStates',reverse,'extensionPositive',logical(signBox.Value));
            recruitment = struct('muMap',muMap,'muLabels',{labels}, ...
                'Pulsetrain',allPulse(:,indices),'Distime',allDist(indices,:), ...
                'Dischargetimes',{cell(1,nMU)},'trial',trialInfo,'cfg',cfg, ...
                'startSessionTime',startClock,'startEMGSample',startSample, ...
                'simulated',simulation);
            for mu = 1:nMU
                recruitment.Dischargetimes{mu} = find(recruitment.Distime(:,mu));
            end
            if tracking
                signal.target = task_level(signal.emgTime);
            end
            filename = fullfile(cfg.outputFolder,sprintf('S%s_ss%d_dig%d_f%g_t%d.mat', ...
                trialInfo.participant,trialInfo.session,trialInfo.channel,trialInfo.target,trialInfo.trial));
            % Preserve existing trials, including repeated participant/trial settings.
            if exist(filename,'file')
                [folder,base,ext] = fileparts(filename); suffix = 1;
                while exist(filename,'file')
                    filename = fullfile(folder,sprintf('%s_repeat%d%s',base,suffix,ext)); suffix = suffix+1;
                end
            end
            save(filename,'signal','recruitment','-v7.3');
            savedFiles{end+1} = filename;
            fprintf('Recruitment trial saved: %s\n',filename);
            trialBox.String = num2str(trialInfo.trial+1);
        end
        recording = false; tracking = false;
        recordBtn.Value = 0; trackBtn.Value = 0;
        recordBtn.Enable = 'on'; trackBtn.Enable = 'on';
        zeroBtn.Enable = 'on'; signBox.Enable = 'on';
        ax.Color = [1 1 1]; set(targetLine,'XData',nan,'YData',nan);
    end
end

function [factors, zeroValues, reverse, file] = force_calibration(cfg)
factors = cfg.forceDefaultCalibrationFactors;
zeroValues = cfg.forceDefaultZeroValues; reverse = cfg.forceDefaultReverseStates;
file = cfg.forceCalibrationFile;
if isempty(file) && cfg.forcePromptCalibration
    [name,folder] = uigetfile('*.mat','Select force calibration (Cancel uses defaults)');
    if ~isequal(name,0), file = fullfile(folder,name); end
end
if ~isempty(file)
    data = load(file,'calibrationFactors','zeroValues','reverseStates');
    factors = data.calibrationFactors; zeroValues = data.zeroValues; reverse = data.reverseStates;
end
validateattributes(factors,{'numeric'},{'numel',3,'finite','nonzero'});
validateattributes(zeroValues,{'numeric'},{'numel',3,'finite'});
validateattributes(reverse,{'numeric','logical'},{'numel',3,'binary'});
factors = reshape(factors,1,3); zeroValues = reshape(zeroValues,1,3); reverse = reshape(reverse,1,3);
end

function delete_serial(serial)
if ~isempty(serial) && isvalid(serial), delete(serial); end
end

function delete_figure(fig)
if isgraphics(fig), delete(fig); end
end
