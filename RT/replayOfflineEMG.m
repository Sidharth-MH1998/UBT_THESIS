function out = replayOfflineEMG(calibrationFile, recordingFile, recordingRows, realTime)
%REPLAYOFFLINEEMG Apply the online MU decoder to a separate EMG recording.
% Pass true for realTime to pace decoding at the original sampling rate.
arguments
    calibrationFile
    recordingFile
    recordingRows = []
    realTime (1,1) logical = false
end

root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, '07_onlineDecompositionV3', 'OnlineDecomposeSrc'));
setup_online_dependencies();

calibration = load_fields(calibrationFile, {'signal','parameters','edition'});
assert(all(isfield(calibration, {'signal','parameters'})), ...
    'Select a decomposition result containing signal and parameters.');
signal = calibration.signal;
assert(all(isfield(signal, {'data','fsamp','EMGmask'})), ...
    'Calibration signal must contain data, fsamp and EMGmask.');
if isfield(calibration, 'edition')
    assert(all(isfield(calibration.edition, {'Pulsetrain','Dischargetimes'})), ...
        'The edition structure must contain Pulsetrain and Dischargetimes.');
    signal.Pulsetrain = calibration.edition.Pulsetrain;
    signal.Dischargetimes = calibration.edition.Dischargetimes;
end
assert(all(isfield(signal, {'Pulsetrain','Dischargetimes'})), ...
    'Calibration must contain pulse trains and discharge times.');

recording = load_fields(recordingFile, ...
    {'signal','recordedEMG','fs_emg','emgValues','samplingFrequency'});
if isfield(recording, 'signal') && all(isfield(recording.signal, {'data','fsamp'}))
    emg = recording.signal.data;
    fs = recording.signal.fsamp;
elseif all(isfield(recording, {'recordedEMG','fs_emg'}))
    emg = recording.recordedEMG;
    fs = recording.fs_emg;
elseif all(isfield(recording, {'emgValues','samplingFrequency'}))
    emg = recording.emgValues;
    fs = recording.samplingFrequency;
else
    error('Select a MAT-file with signal.data/fsamp, recordedEMG/fs_emg, or emgValues/samplingFrequency.');
end
validateattributes(fs, {'numeric'}, {'scalar','real','finite','positive'});
assert(fs == signal.fsamp, ...
    'Recording sampling rate (%g Hz) must match calibration (%g Hz).', fs, signal.fsamp);
validateattributes(emg, {'numeric'}, {'2d','real','nonempty'});

channelCount = size(signal.data,1);
if isempty(recordingRows)
    assert(size(emg,1) == channelCount, ...
        'Recording has %d rows and calibration has %d. Set recordingRows in the launcher.', ...
        size(emg,1), channelCount);
    recordingRows = 1:channelCount;
end
validateattributes(recordingRows, {'numeric'}, ...
    {'vector','numel',channelCount,'integer','positive','<=',size(emg,1)});
emg = double(emg(recordingRows,:));
assert(all(isfinite(emg(:))), 'Selected recording channels contain NaN or Inf.');

cfg.calibChannels = 1:channelCount;
cfg.emgChannels = recordingRows;
nsamp = round(0.128 * fs);
[states, muMap] = prepare_online_grid_states(signal, calibration.parameters, cfg);
nMU = size(muMap,1);
minBlock = max(1, max(cellfun(@(state) state.extensionfactor, states)) - 1);
assert(nsamp >= minBlock, 'The online window is too short for the calibration extension.');
cfg.muLabels = arrayfun(@(mu) sprintf('G%d MU%d', muMap(mu,1), muMap(mu,2)), ...
    1:nMU, 'UniformOutput', false);

totalSamples = size(emg,2);
pulse = zeros(nMU,totalSamples);
spikes = false(totalSamples,nMU);
windowCount = 0;
sessionClock = tic;
for first = 1:nsamp:totalSamples
    last = min(first + nsamp - 1, totalSamples);
    if realTime
        pause(max(0, last/fs - toc(sessionClock)));
    end
    block = emg(:,first:last);
    n = size(block,2);
    if n < minBlock
        % The online decoder needs room for the previous window's extension.
        block(:,n+1:minBlock) = repmat(block(:,end),1,minBlock-n);
    end
    [blockPulse, blockSpikes, states] = decode_online_grid_window(block, states, fs);
    pulse(:,first:last) = blockPulse(:,1:n);
    spikes(first:last,:) = blockSpikes(1:n,:);
    windowCount = windowCount + 1;
end
discharges = arrayfun(@(mu) find(spikes(:,mu)), 1:nMU, 'UniformOutput', false);
rates = cellfun(@(samples) fs ./ diff(samples), discharges, 'UniformOutput', false);
force = recording_force(recording, totalSamples);
thresholds = recruitment_thresholds(force, discharges);

out.cfg = cfg;
out.fs = fs;
out.nsamp = nsamp;
out.windowSec = nsamp/fs;
out.nWin = windowCount;
out.elapsedSec = toc(sessionClock);
out.calibrationFile = calibrationFile;
out.recordingFile = recordingFile;
out.online.EMG = emg;
out.online.Pulsetrain = pulse;
out.online.Distime = spikes;
out.online.Dischargetimes = discharges;
out.online.fr = rates;
out.online.mean_fr = cellfun(@mean,rates).';
out.online.Time = (0:totalSamples-1)/fs;
out.online.ngrid = numel(states);
out.online.muMap = muMap;
out.online.muLabels = cfg.muLabels;
out.online.PulsetrainByGrid = cellfun(@(state) ...
    out.online.Pulsetrain(state.muIndices,:), states, 'UniformOutput', false);
out.online.DischargetimesByGrid = cell(numel(states), max(cellfun(@(state) state.nMU, states)));
out.online.MUfiltByGrid = cellfun(@(state) state.MUfilt, states, 'UniformOutput', false);
for grid = 1:numel(states)
    out.online.DischargetimesByGrid(grid,1:states{grid}.nMU) = discharges(states{grid}.muIndices);
end
out.online.recruitmentThreshold = thresholds;
out.online.force = force;
plot_replay_raster(discharges, cfg.muLabels, fs, totalSamples, thresholds, force);
fprintf('Decoded %d samples in %d windows.\n', totalSamples, windowCount);
end

function force = recording_force(recording, sampleCount)
force = [];
if ~isfield(recording,'signal')
    return;
end
signal = recording.signal;
if ~isfield(signal,'path') || ~isnumeric(signal.path) || ~isreal(signal.path) || ...
        ~isvector(signal.path) || numel(signal.path) ~= sampleCount || ...
        (isfield(signal,'recordedForce') && isempty(signal.recordedForce))
    return;
end
force = double(signal.path(:));
force(~isfinite(force)) = NaN;
end

function thresholds = recruitment_thresholds(force, discharges)
thresholds = nan(1,numel(discharges));
if isempty(force)
    return;
end
% Same definition as PlotMURecruitmentResults: force at the first discharge.
for mu = 1:numel(discharges)
    samples = discharges{mu};
    if ~isempty(samples)
        thresholds(mu) = force(samples(1));
    end
end
end

function plot_replay_raster(discharges, muLabels, fs, sampleCount, thresholds, force)
fig = figure('Name','Offline EMG Replay - Raster and Force','NumberTitle','off','Color','w');
ax = axes('Parent',fig,'Position',[0.16 0.18 0.72 0.74]);
hasForce = any(isfinite(force));
if hasForce
    yyaxis(ax,'right');
    plot(ax,(0:sampleCount-1)/fs,force,'k-','DisplayName','Recorded force');
    ylabel(ax,'Recorded force');
    ax.YColor = 'k';
    yyaxis(ax,'left');
end
hold(ax,'on');
nMU = numel(discharges);
colors = lines(nMU);
rasterLines = gobjects(nMU,1);
for mu = 1:nMU
    times = (discharges{mu}-1)/fs;
    rasterLines(mu) = plot(ax,nan,nan,'|','Color',colors(mu,:), ...
        'MarkerSize',10,'LineWidth',1.2);
    set(rasterLines(mu),'XData',times,'YData',mu*ones(size(times)));
    if isfinite(thresholds(mu))
        muLabels{mu} = sprintf('%s (RT %.2f)',muLabels{mu},thresholds(mu));
    else
        muLabels{mu} = sprintf('%s (RT N/A)',muLabels{mu});
    end
end
hold(ax,'off');
grid(ax,'on');
xlim(ax,[0 sampleCount/fs]);
ylim(ax,[0.5 nMU+0.5]);
set(ax,'YDir','reverse','YColor','k');
yticks(ax,1:nMU);
yticklabels(ax,muLabels);
xlabel(ax,'Time (s)');
ylabel(ax,'Grid / motor unit');
if hasForce
    title(ax,'Detected motor-unit discharges and recorded force');
else
    title(ax,'Detected motor-unit discharges');
end
sortControl = uicontrol(fig,'Style','checkbox','Units','normalized', ...
    'Position',[0.02 0.015 0.92 0.055],'BackgroundColor','w', ...
    'String','Sort MUs by increasing recruitment threshold', ...
    'TooltipString','Force at first detected discharge. Missing thresholds appear last.', ...
    'Callback',@(control,~) sort_raster(control.Value,ax,rasterLines,muLabels,thresholds));
if all(isnan(thresholds))
    set(sortControl,'Enable','off', ...
        'String','Recruitment threshold sorting unavailable (no valid force at first discharge)');
end
end

function sort_raster(enabled, ax, rasterLines, labels, thresholds)
order = 1:numel(rasterLines);
if enabled
    [~,order] = sort(thresholds,'ascend','MissingPlacement','last');
end
for row = 1:numel(order)
    line = rasterLines(order(row));
    line.YData = row*ones(size(line.XData));
end
yticklabels(ax,labels(order));
end

function data = load_fields(file, names)
% Optional MAT-file fields differ between recording formats.
variables = whos('-file',file);
present = intersect(names, {variables.name});
data = struct();
if ~isempty(present)
    data = load(file,present{:});
end
end
