function varargout = online_live_display(action, varargin)
%ONLINE_LIVE_DISPLAY Shared live/simulation raster and firing-rate interface.
switch lower(action)
    case 'init'
        [varargout{1}, varargout{2}] = init_live_figure(varargin{:});
    case 'update'
        update_live_plot(varargin{:});
    otherwise
        error('Unknown display action: %s', action);
end
end

%% Plot initialization and live update helpers
function [fig, plotState] = init_live_figure(nMU, cfg, sharedUI)
colors = lines(nMU);

fig = figure( ...
    'Color', 'w', ...
    'Position', [180 100 1050 650], ...
    'Name', 'Real-Time Discharge Rate', ...
    'CloseRequestFcn', @stop_figure);
setappdata(fig, 'stopRequested', false);

axRaster = sharedUI.axRaster;
cla(axRaster);
hold(axRaster, 'on');
grid(axRaster, 'on');
title(axRaster, 'Live Spike Trains', 'FontSize', 11);
xlabel(axRaster, 'Time (s)');
ylabel(axRaster, 'Motor Unit');
ylim(axRaster, [0 nMU + 1]);
yticks(axRaster, 1:nMU);
yticklabels(axRaster, arrayfun(@(x) sprintf('%s  (0 spikes)', cfg.muLabels{x}), 1:nMU, 'UniformOutput', false));

axFr = axes('Parent',fig,'Units','normalized', ...
    'Position',[0.08 0.12 0.82 0.80]);
hold(axFr, 'on');
grid(axFr, 'on');
title(axFr, 'Instantaneous Firing Rate (Hz)', 'FontSize', 11);
xlabel(axFr, 'Time (s)');
ylabel(axFr, 'Firing Rate (Hz)');
ylim(axFr, [0 cfg.frYLim]);

hRaster = gobjects(nMU, 1);
hFr = gobjects(nMU, 1);
for mu = 1:nMU
    hRaster(mu) = plot(axRaster, nan, nan, '|', ...
        'Color', colors(mu,:), 'MarkerSize', 10, 'LineWidth', 1.4);
    hFr(mu) = plot(axFr, nan, nan, '.', ...
        'Color', colors(mu,:), 'MarkerSize', 5, ...
        'DisplayName', cfg.muLabels{mu});
end

if cfg.showLegend
    legend(axFr, 'Location', 'eastoutside', 'FontSize', 7);
end

tlineRaster = xline(axRaster, 0, 'r--', 'LineWidth', 1.2);
tlineFr = xline(axFr, 0, 'r--', 'LineWidth', 1.2);

uicontrol(fig, 'Style', 'pushbutton', ...
    'String', 'Stop', ...
    'Units', 'pixels', ...
    'Position', [20 20 80 28], ...
    'Callback', @(~,~) request_stop(fig));

plotState = struct();
plotState.axRaster = axRaster;
plotState.axFr = axFr;
plotState.hRaster = hRaster;
plotState.hFr = hFr;
plotState.tlineRaster = tlineRaster;
plotState.tlineFr = tlineFr;
end

function update_live_plot(fig, plotState, Dischargetimes_online, fr_online, currentTime, cfg, fs_online)
if ~ishandle(fig)
    return;
end

nMU = numel(Dischargetimes_online);
for mu = 1:nMU
    spikes = Dischargetimes_online{mu};
    if ~isempty(spikes)
        spikeTimes = (spikes-1) / fs_online;
        set(plotState.hRaster(mu), 'XData', spikeTimes, 'YData', mu * ones(size(spikeTimes)));
    end

    if numel(spikes) > 1
        frTimes = (spikes(2:end)-1) / fs_online;
        set(plotState.hFr(mu), 'XData', frTimes, 'YData', fr_online{mu});
    end
end

set(plotState.tlineRaster, 'Value', currentTime);
set(plotState.tlineFr, 'Value', currentTime);

xMin = max(0, currentTime - cfg.visibleWindowSec);
xMax = max(cfg.visibleWindowSec, currentTime);
xlim(plotState.axRaster, [xMin xMax]);
xlim(plotState.axFr, [xMin xMax]);

yticklabels(plotState.axRaster, arrayfun(@(mu) ...
    sprintf('%s  (%d spikes)', cfg.muLabels{mu}, numel(Dischargetimes_online{mu})), ...
    1:nMU, 'UniformOutput', false));

title(plotState.axRaster, sprintf('Live Spike Trains  |  t = %.2f s', currentTime), 'FontSize', 11);

drawnow limitrate;
end

function request_stop(fig)
if ishghandle(fig)
    setappdata(fig, 'stopRequested', true);
end
end

function stop_figure(fig, ~)
setappdata(fig, 'stopRequested', true);
delete(fig);
end

