function session = novecento_live_plot(cfg)
%NOVECENTO_LIVE_PLOT Read Novecento+ EMG blocks and plot them live.
%
% Outputs are also written to the MATLAB base workspace:
%   recordedEMG
%   recordedDurationSec
%   recordStartSample
%   recordEndSample
%   trimmedEMG

if nargin < 1 || ~isstruct(cfg)
    error('novecento_live_plot requires a complete cfg structure.');
end

dev = novecento_connect(cfg);
cleanupObj = onCleanup(@() novecento_disconnect(dev)); %#ok<NASGU>

[fs, samplesPerBlock] = validate_stream_settings(dev, cfg);
[fig, ui] = build_plot_window();
app = create_app_state(cfg, fs);

assign_session_to_base(app);
setappdata(fig, 'novecentoApp', app);
set(fig, 'WindowKeyPressFcn', @(src, event) handle_marker_keypress(src, event));

fprintf('\n=== Novecento live plot ===\n');
fprintf('Connected to %s. Close the figure to stop safely.\n', dev.ip);
fprintf('Press r to mark start, q to mark stop and create trimmedEMG.\n\n');

while ishandle(fig)
    rawAll = novecento_read_emg_block(dev, cfg.activeInputs, samplesPerBlock);
    if ~ishandle(fig)
        break;
    end

    rawBlock = double(rawAll(cfg.emgChannels, :));

    app = getappdata(fig, 'novecentoApp');
    app.blockCounter = app.blockCounter + 1;
    app.lastRawBlock = rawBlock;
    app.recordedEMG = [app.recordedEMG rawBlock]; %#ok<AGROW>
    app.recordedDurationSec = size(app.recordedEMG, 2) / app.fs;

    assign_session_to_base(app);
    setappdata(fig, 'novecentoApp', app);
    update_plot_window(fig, ui);
    drawnow limitrate;
end

session = getappdata_safe(fig, app);

end

function [fs, samplesPerBlock] = validate_stream_settings(dev, cfg)

if isempty(cfg.activeInputs) || isempty(cfg.emgChannels)
    error('cfg.activeInputs and cfg.emgChannels must not be empty.');
end

fsVals = dev.fsInput(cfg.activeInputs);
if any(fsVals <= 0)
    error('No valid sampling rate detected for one or more active inputs.');
end

if numel(unique(fsVals)) ~= 1
    error('All active inputs must use the same sampling frequency.');
end

fs = fsVals(1);
samplesPerBlock = fs * cfg.blockDurationSec;
if mod(samplesPerBlock, 1) ~= 0
    error('cfg.blockDurationSec must produce an integer number of samples.');
end
samplesPerBlock = round(samplesPerBlock);

totalChannels = sum(dev.NumChan(cfg.activeInputs));
if any(cfg.emgChannels < 1) || any(mod(cfg.emgChannels, 1) ~= 0) || max(cfg.emgChannels) > totalChannels
    error('cfg.emgChannels must contain integer channel indices between 1 and %d.', totalChannels);
end

previewRows = get_preview_rows(cfg.previewChannels, numel(cfg.emgChannels));
if isempty(previewRows)
    error('cfg.previewChannels does not select any available EMG channels.');
end

end

function [fig, ui] = build_plot_window()

fig = figure( ...
    'Color', 'w', ...
    'Position', [80 60 1450 780], ...
    'Name', 'Novecento Live EMG Plot');

ui.axRaw = axes('Parent', fig, 'Position', [0.06 0.11 0.90 0.80]);
title(ui.axRaw, 'Live EMG Preview');
xlabel(ui.axRaw, 'Time (s)');
ylabel(ui.axRaw, 'Channel');
grid(ui.axRaw, 'on');

ui.statusText = uicontrol(fig, 'Style', 'text', ...
    'String', 'Waiting for data...', ...
    'Units', 'pixels', ...
    'Position', [20 738 1380 28], ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w');


end

function app = create_app_state(cfg, fs)

app = struct();
app.cfg = cfg;
app.fs = fs;
app.blockCounter = 0;
app.lastRawBlock = [];
app.recordedEMG = [];
app.recordedDurationSec = 0;
app.recordStartSample = [];
app.recordEndSample = [];
app.trimmedEMG = [];
app.recordStateText = 'Idle';

end

function update_plot_window(fig, ui)

if ~ishandle(fig)
    return;
end

app = getappdata(fig, 'novecentoApp');
if isempty(app.recordedEMG)
    return;
end

previewRows = get_preview_rows(app.cfg.previewChannels, size(app.recordedEMG, 1));
channelLabels = app.cfg.emgChannels(previewRows);
nVisible = get_visible_sample_count(app.cfg.visibleWindowSec, app.fs, size(app.recordedEMG, 2));

visibleEMG = app.recordedEMG(previewRows, end - nVisible + 1:end);
firstSample = size(app.recordedEMG, 2) - nVisible + 1;

novecento_plot_stacked(ui.axRaw, visibleEMG, channelLabels, app.fs, firstSample, app.cfg.visibleWindowSec);
title(ui.axRaw, sprintf('Raw EMG Preview | showing %d channel(s)', numel(previewRows)));

set(ui.statusText, 'String', sprintf( ...
    'Blocks: %d | Duration: %.2f s | Marker: %s', ...
    app.blockCounter, app.recordedDurationSec, app.recordStateText));



end

function handle_marker_keypress(fig, event)

if ~ishandle(fig)
    return;
end

app = getappdata(fig, 'novecentoApp');
currentSample = size(app.recordedEMG, 2);

switch lower(event.Key)
    case 'r'
        app.recordStartSample = currentSample + 1;
        app.recordEndSample = [];
        app.trimmedEMG = [];
        app.recordStateText = sprintf('START at sample %d', app.recordStartSample);

    case 'q'
        app.recordEndSample = currentSample;

        if isempty(app.recordStartSample)
            app.recordStateText = 'Press r before q';
        else
            startSample = max(1, min(app.recordStartSample, currentSample));
            endSample = max(startSample, min(app.recordEndSample, currentSample));
            app.recordStartSample = startSample;
            app.recordEndSample = endSample;
            app.trimmedEMG = app.recordedEMG(:, startSample:endSample);
            app.recordStateText = sprintf('STOP at sample %d | trimmedEMG ready', endSample);
        end

    otherwise
        return;
end

assign_session_to_base(app);
setappdata(fig, 'novecentoApp', app);

end

function previewRows = get_preview_rows(previewCfg, nAvailableRows)

if isscalar(previewCfg)
    previewRows = 1:min(previewCfg, nAvailableRows);
else
    previewRows = previewCfg(:)';
    previewRows = previewRows(previewRows >= 1 & previewRows <= nAvailableRows);
end

end

function nVisible = get_visible_sample_count(visibleWindowSec, fs, nRecordedSamples)

if isinf(visibleWindowSec)
    nVisible = nRecordedSamples;
else
    nVisible = min(nRecordedSamples, max(1, round(visibleWindowSec * fs)));
end


end

function assign_session_to_base(app)

assignin('base', 'recordedEMG', app.recordedEMG);
assignin('base', 'recordedDurationSec', app.recordedDurationSec);
assignin('base', 'recordStartSample', app.recordStartSample);
assignin('base', 'recordEndSample', app.recordEndSample);
assignin('base', 'trimmedEMG', app.trimmedEMG);

end

function session = getappdata_safe(fig, fallback)

if ishandle(fig)
    session = getappdata(fig, 'novecentoApp');
else
    session = fallback;
end

end
