%% Novecento+ EMG acquisition and quality check.
% The recorded channels x samples matrix is stored in emgValues.
% record the emg and find bad channels, baseline noise and inspect the frequency spectrum.
% Combined live inspection and stream diagnostics. Run this script alone.
% Outputs: emgValues, samplingFrequency, gridHeatmapResult,
% diagnosticReport (latest raw-window metrics per input), badchan,
% badChannelReport (whole-recording raw-data candidates; not auto-removed).
scriptDirectory = fileparts(mfilename('fullpath'));
repositoryDirectory = fileparts(scriptDirectory);
addpath(scriptDirectory, fullfile(repositoryDirectory,'01_DataRecording','srcNovecento'));

%% 1. EMG quality-check settings

cfg.activeInputs = [1 2];             % Novecento inputs used for recording.
cfg.emgChannels = [1:64 71:134];      % Channels retained from the stacked inputs.
cfg.previewChannels = 1:8:128;         % Retained-channel indices shown in the plot.
cfg.blockDurationSec = 0.05;          % Read/update every 50 ms for live heatmaps.
cfg.visibleWindowSec = 1;            % Duration shown in the moving plot, in seconds.
cfg.recordDurationSec = 60;           % USER SETTING: total recording time in seconds.
cfg.spectrumMaximumHz = 700;          % Highest frequency displayed in the PSD plots.
cfg.lineFrequencyHz = 50;             % Power-line frequency used for harmonic markers.
cfg.diagnostics.windowSec = 5;        % Analyze raw EMG, before heatmap filtering.
cfg.diagnostics.updateSec = 0.5;      % Slower diagnostics keep acquisition responsive.
cfg.diagnostics.minimumSec = 1;
cfg.diagnostics.finalBadChannelCheck = true;

% Live heatmaps share the acquisition and figure with the raw EMG preview.
cfg.heatmap.enabled = true;
cfg.heatmap.windowSec = 0.25;
cfg.heatmap.bandHz = [20 500];
cfg.heatmap.gridTypes = {'GR08MM1305'}; % One type reused, or one per active input.
% Types: GR/HD08MM1305, GR/HD04MM1305, GR/HD10MM0808.
cfg.heatmap.badChannels = {[]}; % Electrode numbers 1:64; one cell per input.
cfg.heatmap.colorLimits = []; % Shared peak-hold scale, or fixed [0 upperLimit].
% One grid uses the first 64 physical channels of each active input. All
% must be included in cfg.emgChannels; their retained order can be arbitrary.
% Heatmap units follow the decoder's GainFactor; verify units with hardware.

%% 2. Device settings

cfg.socketTimeoutSec = 100;       % Maximum TCP read/write wait time in seconds.
cfg.GainFactor = 0.2861;          % Scale factor used to convert decoded EMG to mV.
cfg.FSelAux = 2;                  % AUX rate: 1=500, 2=2000, 3=4000, 4=8000 Hz.
cfg.AnOutINSource = 0;            % Analog-output source: 0 selects Novecento input 1.
cfg.AnOutChan = 1;                % Channel number routed to the analog output.
cfg.AnOutGain = bin2dec('00000000'); % Analog-output gain code: 0 means gain of 1.
cfg.hardwareQueryRetries = 3;     % Number of hardware-query attempts before failure.
cfg.hardwareQueryPauseSec = 0.2;  % Delay before each hardware query, in seconds.

activeInputs = cfg.activeInputs;
numBlocks = ceil(cfg.recordDurationSec / cfg.blockDurationSec);

%% 3. Novecento input configuration

cfg.IN_Active = zeros(10, 1); % Enable flag for each input: 0=off, 1=on.
cfg.Mode = zeros(10, 1);      % Acquisition mode code for each input; 0=standard mode.
cfg.Gain = zeros(10, 1);      % Hardware gain code for each input.
cfg.HRES = zeros(10, 1);      % Resolution flag for each input: 0=16-bit, 1=32-bit.
cfg.HPF = zeros(10, 1);       % High-pass filter flag for each input: 0=off, 1=on.
cfg.FsampCode = zeros(10, 1); % Sampling-rate code: 0=500, 1=2000, 2=4000, 3=8000 Hz.

cfg.IN_Active(activeInputs) = 1; % Enable all inputs listed in activeInputs.
cfg.Gain(activeInputs) = 1;      % Apply hardware gain code 1 to active inputs.
cfg.HRES(activeInputs) = 0;      % Acquire active inputs using 16-bit resolution.
cfg.HPF(activeInputs) = 1;       % Enable the hardware high-pass filter.
cfg.FsampCode(activeInputs) = 1; % Sample active inputs at 2000 Hz.

%% 4. Connect to the Novecento+

dev = connectNovecento(cfg);
disconnectDevice = onCleanup(@() disconnectNovecento(dev));

%% 5. Read and store EMG data

try
samplesPerBlock = round(dev.fsInput(activeInputs(1)) * cfg.blockDurationSec);
samplingFrequency = dev.fsInput(activeInputs(1));
assert(all(dev.fsInput(activeInputs) == samplingFrequency) && samplingFrequency > 0, ...
    'All active inputs must have the same valid sampling rate.');
assert(samplesPerBlock >= 1 && mod(samplesPerBlock*500/samplingFrequency,1) == 0, ...
    'blockDurationSec must align with Novecento packet columns.');
assert(isfinite(cfg.recordDurationSec) && cfg.recordDurationSec > 0, ...
    'recordDurationSec must be finite and positive.');
assert(~isempty(cfg.emgChannels) && numel(unique(cfg.emgChannels)) == numel(cfg.emgChannels) && ...
    all(ismember(cfg.emgChannels,1:sum(dev.NumChan(activeInputs)))), ...
    'emgChannels must contain unique valid stacked-channel indices.');
assert(~isempty(cfg.previewChannels) && all(ismember(cfg.previewChannels,1:numel(cfg.emgChannels))), ...
    'previewChannels must select retained-channel rows.');
assert(cfg.diagnostics.windowSec >= cfg.diagnostics.minimumSec && ...
    cfg.diagnostics.minimumSec > 0 && cfg.diagnostics.updateSec > 0, ...
    'Diagnostic windows and update interval must be positive.');
targetSamples = round(cfg.recordDurationSec*samplingFrequency);
emgValues = zeros(numel(cfg.emgChannels),targetSamples);
recordedSamples = 0;

qualityFigure = figure('Name', 'Novecento EMG quality check', ...
    'NumberTitle', 'off', 'Color', 'w','Position',[40 40 1600 900]);
previewPanel = uipanel(qualityFigure,'Units','normalized','Position',[0 0.01 0.64 0.98], ...
    'BorderType','none');
if cfg.heatmap.enabled
    qualityLayout = tiledlayout(previewPanel,2,numel(activeInputs), ...
        'TileSpacing','compact','Padding','compact');
    qualityAxes = nexttile(qualityLayout,1,[1 numel(activeInputs)]);
    heatmapState = initializeGridHeatmaps(cfg,dev,samplingFrequency,qualityLayout);
else
    qualityAxes = axes('Parent', previewPanel);
end
diagnostics = initializeDiagnostics(cfg,dev,samplingFrequency,qualityFigure);
diagnosticReport = struct([]);
nextDiagnosticSample = max(2,round(cfg.diagnostics.minimumSec*samplingFrequency));
acquisitionError = '';
catch ME
    clear disconnectDevice dev;
    rethrow(ME);
end

try
for blockIdx = 1:numBlocks
    if ~isgraphics(qualityFigure), break; end
    allInputChannels = readEmgBlock(dev, activeInputs, samplesPerBlock);

    if max(cfg.emgChannels) > size(allInputChannels, 1)
        error(['cfg.emgChannels requests channel %d, but the active inputs ' ...
            'provide only %d stacked channels.'], ...
            max(cfg.emgChannels), size(allInputChannels, 1));
    end

    keptSamples = min(size(allInputChannels,2),targetSamples-recordedSamples);
    emgBlock = allInputChannels(cfg.emgChannels, 1:keptSamples);
    emgValues(:,recordedSamples+(1:keptSamples)) = emgBlock;
    recordedSamples = recordedSamples+keptSamples;
    diagnostics = trackDiagnosticBlocks(diagnostics,emgBlock);
    if cfg.heatmap.enabled
        % Preserve invalid raw samples for reporting, but do not poison filter state.
        heatmapBlock = emgBlock;
        heatmapBlock(~isfinite(heatmapBlock)) = 0;
        heatmapState = updateGridHeatmaps(heatmapState,heatmapBlock);
    end
    if recordedSamples >= nextDiagnosticSample
        diagnosticReport = analyzeDiagnosticWindow(diagnostics,emgValues,recordedSamples, ...
            samplingFrequency,cfg);
        updateDiagnosticDisplay(diagnostics,diagnosticReport,cfg);
        nextDiagnosticSample = recordedSamples+max(1,round(cfg.diagnostics.updateSec*samplingFrequency));
    end

    if max(cfg.previewChannels) > size(emgValues, 1)
        error(['cfg.previewChannels requests retained-channel index %d, ' ...
            'but emgValues contains only %d channels.'], ...
            max(cfg.previewChannels), size(emgValues, 1));
    end

    if isgraphics(qualityFigure)
        previewLabels = cfg.emgChannels(cfg.previewChannels);
        plotQualityPreview(qualityAxes, ...
            emgValues(cfg.previewChannels, max(1,recordedSamples- ...
            round(cfg.visibleWindowSec*samplingFrequency)+1):recordedSamples), previewLabels, ...
            samplingFrequency, cfg.visibleWindowSec, recordedSamples);
        title(qualityAxes, sprintf('EMG quality check: %.2f / %.2f seconds', ...
            recordedSamples / samplingFrequency, cfg.recordDurationSec));
        drawnow limitrate;
    end
end
catch ME
    acquisitionError = ME.message;
    warning('LiveEmgInspect:AcquisitionStopped','Acquisition stopped: %s',ME.message);
end
emgValues = emgValues(:,1:recordedSamples);
% Final live RMS values are 64 x number-of-inputs, in physical electrode order.
if cfg.heatmap.enabled
    gridHeatmapResult = struct('rmsByElectrode',heatmapState.rms, ...
        'maps',{heatmapState.maps},'retainedRows',heatmapState.rows, ...
        'settings',cfg.heatmap,'sampleTimeSec',recordedSamples/samplingFrequency, ...
        'rmsReady',heatmapState.filled == heatmapState.windowN);
end

%% 6. Stop streaming and disconnect

clear disconnectDevice dev;
if recordedSamples >= 2
    diagnosticReport = analyzeDiagnosticWindow(diagnostics,emgValues,recordedSamples, ...
        samplingFrequency,cfg);
    for g = 1:numel(diagnosticReport)
        diagnosticReport(g).acquisitionError = acquisitionError;
    end
    updateDiagnosticDisplay(diagnostics,diagnosticReport,cfg);
    fprintf('\nLatest raw-window diagnostics (not the full recording):\n');
    for g = 1:numel(diagnosticReport)
        fprintf('Input %d: %s\n',diagnosticReport(g).input,diagnosticReport(g).warnings);
    end
end

fprintf('Recording complete: %d channels, %.1f seconds, %.0f Hz.\n', ...
    size(emgValues, 1), size(emgValues, 2) / samplingFrequency, ...
    samplingFrequency);

%% 7. Calculate and plot RMS for every recorded EMG channel

if isempty(emgValues)
    warning('No EMG samples were recorded.');
    return;
end
channelRMS = sqrt(mean(double(emgValues).^2, 2));
plotChannelRMS(channelRMS,cfg.emgChannels);
badchan = [];
badChannelReport = table;
if cfg.diagnostics.finalBadChannelCheck
    % Check each input separately so one muscle/grid does not set another's RMS baseline.
    for g = 1:numel(diagnostics.rows)
        rows = diagnostics.rows{g};
        data = emgValues(rows,:);
        if numel(rows)<2 || size(data,2)<numel(rows) || any(~isfinite(data(:)))
            fprintf('Input %d: final bad-channel check skipped (short/invalid data).\n',activeInputs(g));
            continue;
        end
        [localBad,report] = FindBadchan(data,samplingFrequency,cfg.lineFrequencyHz);
        badchan = [badchan rows(localBad)]; %#ok<AGROW>
        if ~isempty(report)
            report.Channel = reshape(rows(report.Channel),[],1);
            report.StreamChannel = reshape(cfg.emgChannels(report.Channel),[],1);
            report.Input = repmat(activeInputs(g),height(report),1);
            badChannelReport = [badChannelReport;report]; %#ok<AGROW>
        end
    end
    fprintf('Combined badchan (retained row indices): %s\n',mat2str(badchan));
end

%% 8. Close the live plot, then show the power spectra

if isgraphics(qualityFigure)
    title(qualityAxes, ...
        'Recording complete - close this window to show the power spectra');
    drawnow;
    waitfor(qualityFigure);
end

previewLabels = cfg.emgChannels(cfg.previewChannels);
plotPowerSpectrum(emgValues(cfg.previewChannels, :), ...
    previewLabels, samplingFrequency, cfg.spectrumMaximumHz, ...
    cfg.lineFrequencyHz);


%% Local functions: raw-stream diagnostics (one report per physical input)
function state = initializeDiagnostics(cfg,dev,fs,fig)
ng = numel(cfg.activeInputs);
counts = dev.NumChan(cfg.activeInputs);
offsets = [0 cumsum(counts(:).')];
state.rows = cell(1,ng);
state.labels = cell(1,ng);
state.previous = cell(1,ng);
state.repeated = zeros(1,ng);
state.totalBlocks = 0;
state.jumpPosition = 0;
state.jumps = nan(ng,max(1,ceil(cfg.diagnostics.windowSec/cfg.blockDurationSec)));
for g = 1:ng
    state.rows{g} = find(cfg.emgChannels>offsets(g) & cfg.emgChannels<=offsets(g+1));
    assert(~isempty(state.rows{g}),'No retained channels for input %d.',cfg.activeInputs(g));
    state.labels{g} = cfg.emgChannels(state.rows{g});
end
state.fs = fs;
panel = uipanel(fig,'Units','normalized','Position',[0.65 0.01 0.34 0.98], ...
    'Title','Raw EMG diagnostics');
state.spectrumAxes = axes(panel,'Position',[0.12 0.73 0.83 0.22]);
hold(state.spectrumAxes,'on');
state.spectrumLines = gobjects(1,ng);
for g = 1:ng
    state.spectrumLines(g) = plot(state.spectrumAxes,NaN,NaN, ...
        'DisplayName',sprintf('Input %d',cfg.activeInputs(g)));
end
xline(state.spectrumAxes,50,'--r','HandleVisibility','off');
xline(state.spectrumAxes,60,'--m','HandleVisibility','off');
grid(state.spectrumAxes,'on');
xlim(state.spectrumAxes,[0 min(cfg.spectrumMaximumHz,fs/2)]);
xlabel(state.spectrumAxes,'Frequency (Hz)'); ylabel(state.spectrumAxes,'PSD (dB/Hz)');
title(state.spectrumAxes,'Median channel spectrum per input');
legend(state.spectrumAxes,'show','Location','best');
names = arrayfun(@(k)sprintf('Input %d',k),cfg.activeInputs,'UniformOutput',false);
rowNames = {'Window (s)','Dominant frequency (Hz)','50 Hz / EMG power', ...
    '60 Hz / EMG power','Consecutive-channel corr.','Common-mode fraction', ...
    'Zero samples (%)','Nonfinite samples (%)','Repeated blocks (%)', ...
    'Block-jump ratio','Flat stream channels'};
state.table = uitable(panel,'Units','normalized','Position',[0.02 0.31 0.96 0.34], ...
    'ColumnName',names,'RowName',rowNames,'Data',cell(numel(rowNames),ng), ...
    'ColumnWidth',repmat({110},1,ng),'ColumnEditable',false);
state.status = uicontrol(panel,'Style','edit','Units','normalized', ...
    'Position',[0.02 0.02 0.96 0.26],'Max',2,'Min',0,'Enable','inactive', ...
    'HorizontalAlignment','left','BackgroundColor','w','FontSize',10, ...
    'String','Collecting raw EMG...');
end

function state = trackDiagnosticBlocks(state,block)
state.totalBlocks = state.totalBlocks+1;
state.jumpPosition = mod(state.jumpPosition,size(state.jumps,2))+1;
for g = 1:numel(state.rows)
    x = double(block(state.rows{g},:));
    previous = state.previous{g};
    if ~isempty(previous)
        state.jumps(g,state.jumpPosition) = median(abs(x(:,1)-previous(:,end)),'omitnan');
        if isequaln(x,previous), state.repeated(g) = state.repeated(g)+1; end
    end
    state.previous{g} = x;
end
end

function report = analyzeDiagnosticWindow(state,data,lastSample,fs,cfg)
firstSample = max(1,lastSample-round(cfg.diagnostics.windowSec*fs)+1);
reports = cell(1,numel(state.rows));
for g = 1:numel(state.rows)
    x = data(state.rows{g},firstSample:lastSample);
    jumps = state.jumps(g,isfinite(state.jumps(g,:)));
    metrics = calculateLiveMetrics(x,fs,jumps,state.repeated(g),state.totalBlocks-1);
    metrics.input = cfg.activeInputs(g);
    metrics.streamChannels = state.labels{g};
    metrics.retainedRows = state.rows{g};
    metrics.windowSec = size(x,2)/fs;
    metrics.sampleTimeSec = lastSample/fs;
    metrics.warnings = liveWarnings(metrics,state.labels{g});
    reports{g} = metrics;
end
report = [reports{:}];
end

function updateDiagnosticDisplay(state,report,cfg)
if ~isgraphics(state.table), return; end
values = cell(11,numel(report));
messages = cell(1,numel(report));
for g = 1:numel(report)
    m = report(g);
    set(state.spectrumLines(g),'XData',m.frequency,'YData',10*log10(m.medianPSD+eps));
    values(:,g) = {sprintf('%.2f',m.windowSec);sprintf('%.2f',m.dominantFrequency); ...
        sprintf('%.4g',m.mains50Ratio);sprintf('%.4g',m.mains60Ratio); ...
        sprintf('%.3f',m.adjacentCorrelation);sprintf('%.3f',m.commonModeFraction); ...
        sprintf('%.3f',100*m.zeroFraction);sprintf('%.3f',100*m.nonfiniteFraction); ...
        sprintf('%.3f',100*m.repeatedBlockFraction);sprintf('%.3f',m.boundaryJumpRatio); ...
        formatLiveChannels(m.flatRows,m.streamChannels)};
    messages{g} = sprintf('Input %d: %s',m.input,m.warnings);
end
set(state.table,'Data',values);
note = sprintf(['Raw window: up to %g s; repeated-block count: whole session.\n' ...
    'Correlation uses consecutive retained channels, not physical grid neighbors.\n' ...
    'Warnings require visual confirmation.\n\n'],cfg.diagnostics.windowSec);
message = [note strjoin(messages,sprintf('\n\n'))];
if isfield(report,'acquisitionError') && ~isempty(report(1).acquisitionError)
    message = [message sprintf('\nAcquisition stopped: %s',report(1).acquisitionError)];
end
color = [0 0.4 0];
if contains(message,'WARNING') || contains(message,'Acquisition stopped'), color = [0.75 0 0]; end
set(state.status,'String',message,'ForegroundColor',color);
end

%% Local function: plot whole-recording RMS

function plotChannelRMS(channelRMS,channelLabels)

figure('Name', 'Recorded-channel RMS', ...
    'NumberTitle', 'off', 'Color', 'w');

bar(1:numel(channelRMS), channelRMS);
grid on;
xlabel('Retained channel index');
ylabel('RMS');
title('Whole-recording raw RMS (including DC/noise)');
xlim([0.5 numel(channelRMS)+0.5]);
ticks = 1:8:numel(channelRMS);
xticks(ticks); xticklabels(string(channelLabels(ticks)));
xlabel('Stacked channel number');

end


%% Local function: plot all preview-channel power spectra

function state = initializeGridHeatmaps(cfg,dev,fs,layout)
% Map physical input channels to retained rows using detected probe sizes.
opt = cfg.heatmap;
ng = numel(cfg.activeInputs);
assert(isscalar(opt.windowSec) && isfinite(opt.windowSec) && opt.windowSec > 0, ...
    'Heatmap windowSec must be finite and positive.');
assert(numel(opt.bandHz)==2 && all(isfinite(opt.bandHz)) && ...
    opt.bandHz(1)>0 && opt.bandHz(2)>opt.bandHz(1) && opt.bandHz(2)<fs/2, ...
    'Heatmap bandHz must lie between zero and Nyquist.');
assert(isscalar(opt.gridTypes) || numel(opt.gridTypes)==ng, ...
    'Specify one grid type or one per active input.');
assert(isscalar(opt.badChannels) || numel(opt.badChannels)==ng, ...
    'Specify one badChannels cell or one per active input.');
assert(isempty(opt.colorLimits) || (numel(opt.colorLimits)==2 && ...
    all(isfinite(opt.colorLimits)) && opt.colorLimits(1)==0 && opt.colorLimits(2)>0), ...
    'Heatmap colorLimits must be [] or [0 positiveValue].');
offsets = [0 cumsum(dev.NumChan(cfg.activeInputs).')];
state.rows = zeros(64,ng);
state.maps = cell(1,ng);
state.bad = cell(1,ng);
state.images = gobjects(1,ng);
state.axes = gobjects(1,ng);
state.titles = gobjects(1,ng);
for g = 1:ng
    inputIdx = cfg.activeInputs(g);
    assert(dev.NumChan(inputIdx)>=64,'Heatmaps require 64 electrodes per input.');
    [present,rows] = ismember(offsets(g)+(1:64),cfg.emgChannels);
    assert(all(present),'Include the first 64 channels of input %d in emgChannels.',inputIdx);
    state.rows(:,g) = rows(:);
    type = upper(string(opt.gridTypes{min(g,numel(opt.gridTypes))}));
    switch type
        case {"GR08MM1305","HD08MM1305"}
            % Match the printed electrode numbering in the existing GR orientation.
            map = [[NaN; (1:12).'] (13:25).' (26:38).' (39:51).' (52:64).'];
        case {"GR04MM1305","HD04MM1305"}
            % formatsignalHDEMG repository convention, absent corner as NaN.
            map = [NaN 25 26 51 52; (1:12).' (24:-1:13).' ...
                (27:38).' (50:-1:39).' (53:64).'];
        case {"GR10MM0808","HD10MM0808"}
            map = flipud(reshape(1:64,8,8));
        otherwise
            error('Unsupported heatmap grid type: %s.',type);
    end
    if startsWith(type,"HD"), map = fliplr(map); end
    state.maps{g} = map;
    state.bad{g} = opt.badChannels{min(g,numel(opt.badChannels))};
    assert(all(ismember(state.bad{g},1:64)),'Invalid badChannels electrode number.');
    ax = nexttile(layout,ng+g);
    state.axes(g) = ax;
    state.images(g) = imagesc(ax,nan(size(map)),'AlphaData',zeros(size(map)));
    axis(ax,'image'); set(ax,'Color',[0.8 0.8 0.8],'CLim',[0 1]);
    xlabel(ax,'Grid column'); ylabel(ax,'Grid row');
    state.titles(g) = title(ax,sprintf('Input %d | %s | warming up',inputIdx,type), ...
        'Interpreter','none');
    cb = colorbar(ax); cb.Label.String = 'Filtered RMS (decoder amplitude units)';
    [r,c] = find(isfinite(map));
    for k = 1:numel(r)
        text(ax,c(k),r(k),num2str(map(r(k),c(k))), ...
            'HorizontalAlignment','center','FontSize',8);
    end
end
colormap(ancestor(layout.Parent,'figure'),parula(256));
[state.bh,state.ah] = butter(2,opt.bandHz(1)/(fs/2),'high');
[state.bl,state.al] = butter(2,opt.bandHz(2)/(fs/2),'low');
state.zh = zeros(2,64*ng); state.zl = zeros(2,64*ng);
state.windowN = max(1,round(opt.windowSec*fs));
state.ring = zeros(64*ng,state.windowN);
state.powerSum = zeros(64*ng,1);
state.position = 1; state.filled = 0; state.total = 0;
state.warmupN = round(0.5*fs);
state.rms = nan(64,ng);
state.upper = eps;
state.options = opt;
state.inputs = cfg.activeInputs;
end

function state = updateGridHeatmaps(state,emgBlock)
% Stateful causal filtering, followed by an exact sliding RMS power buffer.
x = double(emgBlock(state.rows(:),:)).';
assert(all(isfinite(x(:))),'Nonfinite EMG received.');
[x,state.zh] = filter(state.bh,state.ah,x,state.zh,1);
[x,state.zl] = filter(state.bl,state.al,x,state.zl,1);
keep = (state.total+(1:size(x,1)))>state.warmupN;
state.total = state.total+size(x,1);
p = x(keep,:).'.^2;
n = size(p,2);
if n >= state.windowN
    % Also works if the user chooses acquisition blocks longer than the RMS window.
    state.ring = p(:,end-state.windowN+1:end);
    state.powerSum = sum(state.ring,2);
    state.position = 1;
    state.filled = state.windowN;
elseif n > 0
    slots = mod(state.position-1+(0:n-1),state.windowN)+1;
    state.powerSum = state.powerSum+sum(p-state.ring(:,slots),2);
    state.ring(:,slots) = p;
    state.position = mod(state.position-1+n,state.windowN)+1;
    state.filled = min(state.windowN,state.filled+n);
end
if state.filled < state.windowN, return; end
state.rms = reshape(sqrt(max(state.powerSum,0)/state.windowN),64,[]);
for g = 1:size(state.rms,2), state.rms(state.bad{g},g) = NaN; end
valid = state.rms(isfinite(state.rms));
if ~isempty(valid), state.upper = max(state.upper,1.05*max(valid)); end
limits = state.options.colorLimits;
if isempty(limits), limits = [0 state.upper]; end
for g = 1:numel(state.images)
    if ~isgraphics(state.images(g)), continue; end
    map = state.maps{g};
    mask = isfinite(map);
    values = nan(size(map));
    values(mask) = state.rms(map(mask),g);
    set(state.images(g),'CData',values,'AlphaData',isfinite(values));
    set(state.axes(g),'CLim',limits);
    set(state.titles(g),'String',sprintf('Input %d | %g ms RMS | %g-%g Hz', ...
        state.inputs(g),1000*state.options.windowSec,state.options.bandHz));
end
end

%% Local function: plot all preview-channel power spectra

function plotPowerSpectrum(previewData, channelLabels, fs, maximumHz, lineHz)

% Remove DC offsets before estimating the spectra.
spectrumData = double(previewData);
if any(~isfinite(spectrumData(:)))
    warning('LiveEmgInspect:InvalidSpectrumSamples', ...
        'Invalid samples replaced with zero for spectrum display only; recorded data are unchanged.');
    spectrumData(~isfinite(spectrumData)) = 0;
end
spectrumData = spectrumData - mean(spectrumData, 2);

% Welch settings from freq_spectrum.m: one-second Hann windows and 50% overlap.
nSamples = size(spectrumData, 2);
welchWindowSamples = min(nSamples, max(8, round(fs)));
welchWindow = hann(welchWindowSamples, 'periodic');
welchOverlap = floor(welchWindowSamples / 2);
nFft = max(2048, 2^nextpow2(welchWindowSamples));

nChannels = size(spectrumData, 1);
powerDensity = zeros(nFft / 2 + 1, nChannels);
for channelIdx = 1:nChannels
    [powerDensity(:, channelIdx), frequencyHz] = pwelch( ...
        spectrumData(channelIdx, :), welchWindow, welchOverlap, ...
        nFft, fs, 'onesided');
end

powerDb = 10 * log10(powerDensity + eps);
plotMaximumHz = min(maximumHz, fs / 2);

% Plot every previewed channel separately in one tiled figure.
spectrumFigure = figure('Name', 'Preview-channel EMG power spectra', ...
    'NumberTitle', 'off', 'Color', 'w');
numberOfColumns = min(4, nChannels);
numberOfRows = ceil(nChannels / numberOfColumns);
spectrumLayout = tiledlayout(spectrumFigure, numberOfRows, numberOfColumns, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

for channelIdx = 1:nChannels
    spectrumAxes = nexttile(spectrumLayout);
    plot(spectrumAxes, frequencyHz, powerDb(:, channelIdx), ...
        'Color', [0.05 0.35 0.75], 'LineWidth', 1);
    hold(spectrumAxes, 'on');
    addLineFrequencyMarkers(spectrumAxes, lineHz, plotMaximumHz);
    hold(spectrumAxes, 'off');
    grid(spectrumAxes, 'on');
    xlim(spectrumAxes, [0 plotMaximumHz]);
    title(spectrumAxes, sprintf('Channel %d', channelLabels(channelIdx)));
    xlabel(spectrumAxes, 'Frequency (Hz)');
    ylabel(spectrumAxes, 'Power (dB/Hz)');
end

title(spectrumLayout, 'EMG power spectra');

end


%% Local function: add power-line harmonic markers

function addLineFrequencyMarkers(ax, lineHz, maximumHz)

if isempty(lineHz) || ~isscalar(lineHz) || lineHz <= 0
    return;
end

for frequency = lineHz:lineHz:maximumHz
    xline(ax, frequency, ':', 'Color', [0.55 0.55 0.55], ...
        'HandleVisibility', 'off');
end

end


%% Local function: plot the most recent EMG window

function plotQualityPreview(ax, previewData, channelLabels, fs, windowSec, lastSample)

windowSamples = round(windowSec * fs);
firstSample = max(1, size(previewData, 2) - windowSamples + 1);
visibleData = double(previewData(:, firstSample:end));
timeSec = (lastSample-size(visibleData,2):lastSample-1) / fs;

visibleData(~isfinite(visibleData)) = NaN;
channelSpread = std(visibleData, 0, 2,'omitnan');
positiveSpread = channelSpread(isfinite(channelSpread) & channelSpread > 0);
traceOffset = 1;
if ~isempty(positiveSpread), traceOffset = max(6*median(positiveSpread),1); end
offsets = (0:size(visibleData, 1) - 1)' * traceOffset;

traces = getappdata(ax,'emgPreviewLines');
if numel(traces) ~= size(visibleData,1) || ~all(isgraphics(traces))
    traces = plot(ax, timeSec, visibleData + offsets, 'LineWidth', 0.7);
    setappdata(ax,'emgPreviewLines',traces);
else
    shifted = visibleData+offsets;
    for k = 1:numel(traces)
        set(traces(k),'XData',timeSec,'YData',shifted(k,:));
    end
end
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Recorded channel');
yticks(ax, offsets);
yticklabels(ax, string(channelLabels));
ylim(ax, [-traceOffset, traceOffset * size(visibleData, 1)]);
xlim(ax, [max(0, timeSec(end) - windowSec), max(windowSec, timeSec(end))]);

end


%% Local function: connect and configure the Novecento+

function dev = connectNovecento(cfg)

% Device constants
auxFsamp = [0 16 32 48];
fsampVal = [500 2000 4000 8000];
sizeAux = [16 64 128 256];
channelsByProbeType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];

% Build the 15-byte configuration command
confString = zeros(1, 15, 'uint8');
confString(1) = uint8(128 + auxFsamp(cfg.FSelAux) + ...
    cfg.IN_Active(10) * 2 + cfg.IN_Active(9));

for inputIdx = 1:8
    confString(2) = uint8(double(confString(2)) + ...
        cfg.IN_Active(inputIdx) * 2^(inputIdx - 1));
end

confString(3) = uint8(cfg.AnOutGain + cfg.AnOutINSource);
confString(4) = uint8(cfg.AnOutChan);

for inputIdx = 1:10
    confString(4 + inputIdx) = uint8( ...
        cfg.Mode(inputIdx) * 64 + cfg.Gain(inputIdx) * 16 + ...
        cfg.HPF(inputIdx) * 8 + cfg.HRES(inputIdx) * 4 + ...
        cfg.FsampCode(inputIdx));
end
confString(15) = uint8(crc8(double(confString), 14));

% Open the TCP connection
tcpSocket = tcpclient('169.254.1.10', 23456);
tcpSocket.ByteOrder = "little-endian";
tcpSocket.Timeout = cfg.socketTimeoutSec;

% Request the connected probe configuration
settings = [];
lastError = [];
for attempt = 1:cfg.hardwareQueryRetries
    try
        flush(tcpSocket);
    catch
    end
    pause(cfg.hardwareQueryPauseSec);

    command = uint8([1 0]);
    command(2) = uint8(crc8(double(command(1)), 1));
    write(tcpSocket, command, 'uint8');

    try
        settings = read(tcpSocket, 20, 'uint8')';
        break;
    catch ME
        lastError = ME;
    end
end

if isempty(settings)
    clear tcpSocket;
    error('Hardware settings read failed: %s', lastError.message);
end
if settings(20) == 255
    clear tcpSocket;
    error('Hardware configuration request returned a CRC error.');
end

% Start streaming using the selected configuration
write(tcpSocket, confString, 'uint8');

% Calculate the packet layout for every input
numChan = zeros(10, 1);
ptrIn = ones(11, 1);
sizeIn = zeros(10, 1);
fsInput = zeros(10, 1);

for inputIdx = 1:10
    probeType = double(settings(inputIdx + 1));
    if probeType + 1 <= numel(channelsByProbeType)
        numChan(inputIdx) = channelsByProbeType(probeType + 1);
    end

    if numChan(inputIdx) == 0
        cfg.IN_Active(inputIdx) = 0;
    end

    if cfg.IN_Active(inputIdx) == 1
        fsInput(inputIdx) = fsampVal(cfg.FsampCode(inputIdx) + 1);
        sizeIn(inputIdx) = (cfg.HRES(inputIdx) + 1) * ...
            fsInput(inputIdx) / 500 * numChan(inputIdx);
    end
    ptrIn(inputIdx + 1) = ptrIn(inputIdx) + sizeIn(inputIdx);
end

% Set the TCP receive buffer
packetSize = ptrIn(11) - 1 + sizeAux(cfg.FSelAux) + 128;
try
    tcpSocket.InputBufferSize = max(packetSize * 500 * 4, 1e6);
catch
end

% Store connection information needed while reading
dev.tcpSocket = tcpSocket;
dev.cfg = cfg;
dev.ConfString = confString;
dev.PacketSize1Block = packetSize;
dev.NumChan = numChan;
dev.Ptr_IN = ptrIn;
dev.fsInput = fsInput;

end


%% Local function: read and decode one EMG block

function emg = readEmgBlock(dev, inputIdxList, samplesPerBlock)

% Determine how many complete packet columns to read
fsActive = dev.fsInput(inputIdxList(1));
nBaseCols = samplesPerBlock * 500 / fsActive;
if mod(nBaseCols, 1) ~= 0
    error('The block length does not map to complete Novecento packets.');
end
nBaseCols = round(nBaseCols);

% Read one raw block from the TCP connection
nRead = dev.PacketSize1Block * nBaseCols;
rawValues = read(dev.tcpSocket, nRead, 'int16')';
if numel(rawValues) ~= nRead
    error('Short read: expected %d values, received %d.', ...
    nRead, numel(rawValues));
end

% Extract and decode each selected input
packet = reshape(rawValues, dev.PacketSize1Block, nBaseCols);
blocks = cell(1, numel(inputIdxList));

for listIdx = 1:numel(inputIdxList)
    inputIdx = inputIdxList(listIdx);
    inputRows = dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx + 1) - 1;
    linearValues = reshape(packet(inputRows, :), 1, []);
    nSamples = dev.fsInput(inputIdx) * nBaseCols / 500;

    if dev.cfg.HRES(inputIdx) == 0
        decoded = reshape(linearValues, dev.NumChan(inputIdx), nSamples);
        blocks{listIdx} = dev.cfg.GainFactor * double(decoded);
    else
        % The probe sends [highWord, lowWord], but MATLAB typecast on this
        % little-endian system expects [lowWord, highWord].
        wordPairs = reshape(linearValues, 2, []);
        reorderedWords = reshape(flipud(wordPairs), 1, []);
        decoded = reshape(typecast(reorderedWords, 'int32'), ...
            dev.NumChan(inputIdx), nSamples);

        % HRES uses a conversion step four times smaller than 16-bit mode.
        blocks{listIdx} = (dev.cfg.GainFactor / 4) * double(decoded);
    end
end

% Store all selected inputs in one channels-by-samples matrix
emg = vertcat(blocks{:});

end


%% Local function: stop streaming

function disconnectNovecento(dev)

try
    stopString = dev.ConfString;
    stopString(1) = uint8(0);
    stopString(15) = uint8(crc8(double(stopString), 14));
    write(dev.tcpSocket, stopString, 'uint8');
    pause(0.5);
catch
end

end


%% Local function: calculate CRC-8

function crc = crc8(vector, len)

crc = 0;
for byteIdx = 1:len
    extract = vector(byteIdx);
    for bitIdx = 1:8
        bitSum = xor(mod(crc, 2), mod(extract, 2));
        crc = floor(crc / 2);
        if bitSum > 0
            crc = bitxor(crc, 140);
        end
        extract = floor(extract / 2);
    end
end

end

function metrics = calculateLiveMetrics(emg, fs, boundaryJumps, ...
        repeatedBlocks, totalBlocks)
    metrics.nonfiniteFraction = mean(~isfinite(emg(:)));
    metrics.zeroFraction = mean(emg(:) == 0);
    emg(~isfinite(emg)) = 0;
    centered = emg - mean(emg, 2);
    channelStd = std(centered, 0, 2);
    flatThreshold = max(eps(max(abs(emg(:)))), eps);
    metrics.flatRows = find(channelStd <= flatThreshold).';
    metrics.repeatedBlockFraction = repeatedBlocks / max(totalBlocks, 1);

    [metrics.frequency, metrics.medianPSD] = liveMedianPSD(centered, fs);
    emgBand = metrics.frequency >= 20 & ...
        metrics.frequency <= min(450, fs / 2);
    bandPower = sum(metrics.medianPSD(emgBand));
    bandPower = max(bandPower, eps);
    metrics.mains50Ratio = sum(metrics.medianPSD( ...
        metrics.frequency >= 49 & metrics.frequency <= 51)) / bandPower;
    metrics.mains60Ratio = sum(metrics.medianPSD( ...
        metrics.frequency >= 59 & metrics.frequency <= 61)) / bandPower;
    positiveFrequency = metrics.frequency(metrics.frequency >= 1);
    positivePower = metrics.medianPSD(metrics.frequency >= 1);
    metrics.dominantFrequency = NaN;
    if any(positivePower > 0)
        [~, peakIndex] = max(positivePower);
        metrics.dominantFrequency = positiveFrequency(peakIndex);
    end

    correlationInput = centered(:, 1:max(1, round(fs / 500)):end);
    correlationMatrix = corrcoef(correlationInput.');
    adjacent = diag(correlationMatrix, 1);
    metrics.adjacentCorrelation = median(adjacent, 'omitnan');

    commonMode = median(centered, 1);
    channelVariance = var(centered, 0, 2);
    residualVariance = var(centered - commonMode, 0, 2);
    valid = channelVariance > 0;
    metrics.commonModeFraction = median(max(0, 1 - ...
        residualVariance(valid) ./ channelVariance(valid)), 'omitnan');

    typicalJump = median(abs(diff(centered, 1, 2)), 'all', 'omitnan');
    if isempty(boundaryJumps) || typicalJump == 0
        metrics.boundaryJumpRatio = NaN;
    else
        metrics.boundaryJumpRatio = median(boundaryJumps, 'omitnan') / typicalJump;
    end
end

function [frequency, medianPSD] = liveMedianPSD(emg, fs)
    nFFT = min(size(emg, 2), max(512, round(2 * fs)));
    segment = emg(:, end - nFFT + 1:end);
    window = 0.5 - 0.5 * cos(2 * pi * (0:nFFT - 1) / (nFFT - 1));
    spectrum = fft(segment .* window, [], 2);
    positiveBins = 1:(floor(nFFT / 2) + 1);
    psd = abs(spectrum(:, positiveBins)).^2 / (fs * sum(window.^2));
    if mod(nFFT,2)==0
        psd(:, 2:end - 1) = 2 * psd(:, 2:end - 1);
    else
        psd(:, 2:end) = 2 * psd(:, 2:end);
    end
    medianPSD = median(psd, 1).';
    frequency = (positiveBins - 1).' * fs / nFFT;
end

function text = liveWarnings(metrics, channelLabels)
    messages = {};
    if metrics.nonfiniteFraction > 0
        messages{end + 1} = 'WARNING: NaN/Inf samples in raw stream';
    end
    if metrics.zeroFraction > 0.5
        messages{end + 1} = 'WARNING: more than half of raw samples are zero';
    end
    if metrics.repeatedBlockFraction > 0
        messages{end + 1} = 'WARNING: identical consecutive read blocks (also possible with flat signals)';
    end
    if ~isempty(metrics.flatRows)
        messages{end + 1} = ['WARNING: flat channel(s): ' ...
            formatLiveChannels(metrics.flatRows, channelLabels)];
    end
    if metrics.mains50Ratio > 0.1
        messages{end + 1} = 'WARNING: strong 50-Hz interference';
    end
    if metrics.mains60Ratio > 0.1
        messages{end + 1} = 'WARNING: strong 60-Hz interference';
    end
    if abs(metrics.adjacentCorrelation) > 0.9 || metrics.commonModeFraction > 0.8
        messages{end + 1} = 'WARNING: strong common-mode signal';
    end
    if isfinite(metrics.boundaryJumpRatio) && metrics.boundaryJumpRatio > 3
        messages{end + 1} = 'WARNING: discontinuities at read boundaries';
    end
    if isempty(messages)
        text = 'No major automated warning.';
    else
        text = strjoin(messages, newline);
    end
end

function text = formatLiveChannels(rows, labels)
    if isempty(rows)
        text = 'none';
    else
        text = mat2str(labels(rows));
    end
end


