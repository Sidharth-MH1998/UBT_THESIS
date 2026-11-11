function varargout = ispin_quadrant_feedback(action, varargin)
%ISPIN_QUADRANT_FEEDBACK I-Spin-style two-MU discharge-rate feedback.
%
% state = ispin_quadrant_feedback('init', nMU, fs, windowSec, cfg)
% state = ispin_quadrant_feedback('update', state, distChunk, timeSec)
% data  = ispin_quadrant_feedback('export', state)
%
% distChunk must be samples-by-motor-units and contain nonzero values at
% detected discharges. The displayed rate is the spike count in a moving
% rate window, followed by an optional moving average. This matches the
% windowed-rate approach used by I-Spin more closely than instantaneous
% inter-spike-interval firing rate.

switch lower(action)
    case 'init'
        varargout{1} = initialize_quadrant(varargin{:});
    case 'update'
        varargout{1} = update_quadrant(varargin{:});
    case 'export'
        varargout{1} = export_quadrant(varargin{:});
    otherwise
        error('Unknown quadrant-feedback action: %s', action);
end
end

function state = initialize_quadrant(nMU, fs, streamWindowSec, cfg, ax)
state = struct('enabled', false);
if nMU < 2
    warning('Quadrant feedback requires at least two motor units.');
    return;
end

xMU = read_cfg(cfg, 'quadrantXMU', 1);
yMU = read_cfg(cfg, 'quadrantYMU', 2);
rateWindowSec = read_cfg(cfg, 'quadrantRateWindowSec', 1.0);
smoothingWindows = read_cfg(cfg, 'quadrantSmoothingWindows', 4);
historySec = read_cfg(cfg, 'quadrantHistorySec', 7.5);
axisMax = read_cfg(cfg, 'quadrantAxisMax', []);
referenceRates = read_cfg(cfg,'quadrantReferenceRates',[]);
axisScale = read_cfg(cfg,'quadrantAxisScale',1.5);

validateattributes(xMU, {'numeric'}, {'scalar','integer','>=',1,'<=',nMU});
validateattributes(yMU, {'numeric'}, {'scalar','integer','>=',1,'<=',nMU});
if xMU == yMU
    error('cfg.quadrantXMU and cfg.quadrantYMU must select different MUs.');
end
validateattributes(rateWindowSec, {'numeric'}, {'scalar','positive','finite'});
validateattributes(smoothingWindows, {'numeric'}, {'scalar','integer','>=',1});
validateattributes(historySec, {'numeric'}, {'scalar','positive','finite'});
if ~isempty(axisMax)
    validateattributes(axisMax, {'numeric'}, {'scalar','positive','finite'});
end
useReferences = ~isempty(referenceRates);
if useReferences
    validateattributes(referenceRates,{'numeric'},{'vector','numel',nMU,'real'});
    selectedReferences = referenceRates([xMU yMU]);
    assert(all(isfinite(selectedReferences) & selectedReferences > 0), ...
        'Selected MUs need positive reference firing rates. Check edition.mean_fr or edited discharge times.');
    validateattributes(axisScale,{'numeric'},{'scalar','real','positive','finite'});
else
    selectedReferences = [];
end

rateWindowCount = max(1, round(rateWindowSec / streamWindowSec));
historyCount = max(2, round(historySec / streamWindowSec));

backgroundColor = [1 1 1];
textColor = [0.15 0.15 0.15];
if nargin < 5
    fig = figure('Name','I-Spin Quadrant Feedback', ...
        'NumberTitle','off','Color',backgroundColor,'Position',[220 90 820 760]);
    ax = axes('Parent',fig,'Units','normalized','Position',[0.12 0.12 0.82 0.80], ...
        'Color',backgroundColor,'XColor',textColor,'YColor',textColor, ...
        'FontName','Poppins','FontSize',18,'LineWidth',1.2);
else
    fig = ancestor(ax,'figure');
    cla(ax);
    textColor = ax.XColor;
end
hold(ax,'on');
% Participant labels identify the two selected units; controls retain grid/MU IDs.
xlabel(ax,'Motor unit 1 activity (pulses/second)','Color',textColor);
ylabel(ax,'Motor unit 2 activity (pulses/second)','Color',textColor);
title(ax,{'Increase motor unit 1 activity to move right.'; ...
    'Increase motor unit 2 activity to move up.'}, ...
    'Color',textColor,'FontWeight','bold','FontSize',11);

if useReferences
    axisMaxima = axisScale*selectedReferences;
else
    if isempty(axisMax), axisMax = 30; end
    axisMaxima = [axisMax axisMax];
end
xlim(ax,[0 axisMaxima(1)]);
ylim(ax,[0 axisMaxima(2)]);
axis(ax,'square');
grid(ax,'off');

% I-Spin's 30/60-degree rays are defined relative to each axis's own maximum.
sectorColor = [0.40 0.45 0.70];
referenceVisibility = 'on';
if ~read_cfg(cfg,'quadrantShowReferenceLines',true)
    referenceVisibility = 'off';
end
lowerRay = plot(ax,[0 axisMaxima(1)],[0 axisMaxima(2)*tan(pi/6)], ...
    'Color',sectorColor,'LineWidth',4, ...
    'Tag','quadrantReferenceLine','Visible',referenceVisibility);
upperRay = plot(ax,[0 axisMaxima(1)*tan(pi/6)],[0 axisMaxima(2)], ...
    'Color',sectorColor,'LineWidth',4, ...
    'Tag','quadrantReferenceLine','Visible',referenceVisibility);
trajectory = plot(ax,nan,nan,'-','Color',[0 0.45 0.65], ...
    'LineWidth',4,'Tag','quadrantTrajectory');
cursor = plot(ax,nan,nan,'o','MarkerSize',20,'LineWidth',4, ...
    'MarkerEdgeColor',[1 0.25 0.25],'MarkerFaceColor',[1 0.25 0.25], ...
    'Tag','quadrantCursor');
status = text(ax,0.02,0.98,'Waiting for decoded data ...','Units','normalized', ...
    'VerticalAlignment','top','Color',textColor,'FontName','Poppins','FontSize',13);

state.enabled = true;
state.embedded = nargin >= 5;
state.fig = fig;
state.ax = ax;
state.trajectory = trajectory;
state.cursor = cursor;
state.lowerRay = lowerRay;
state.upperRay = upperRay;
state.status = status;
state.xMU = xMU;
state.yMU = yMU;
state.fs = fs;
state.streamWindowSec = streamWindowSec;
state.rateWindowSec = rateWindowSec;
state.rateWindowCount = rateWindowCount;
state.smoothingWindows = smoothingWindows;
state.historyCount = historyCount;
state.autoAxis = ~useReferences && (~isfield(cfg,'quadrantAxisMax') || isempty(cfg.quadrantAxisMax));
state.axisMax = max(axisMaxima);
state.axisMaxima = axisMaxima;
state.referenceRates = selectedReferences;
state.axisScale = axisScale;
state.spikeCounts = zeros(0,2);
state.rawRates = zeros(0,2);
state.rates = zeros(0,2);
state.time = zeros(0,1);
end

function state = update_quadrant(state, distChunk, timeSec)
if ~state.enabled || ~isfield(state,'fig') || ~ishandle(state.fig)
    return;
end
if size(distChunk,2) < max(state.xMU,state.yMU)
    error('distChunk does not contain the selected quadrant motor units.');
end

counts = [nnz(distChunk(:,state.xMU)), ...
          nnz(distChunk(:,state.yMU))];
state.spikeCounts(end+1,:) = counts;
rateStart = max(1,size(state.spikeCounts,1)-state.rateWindowCount+1);
coveredSec = (size(state.spikeCounts,1)-rateStart+1)*state.streamWindowSec;
rawRate = sum(state.spikeCounts(rateStart:end,:),1)/coveredSec;
state.rawRates(end+1,:) = rawRate;

smoothStart = max(1,size(state.rawRates,1)-state.smoothingWindows+1);
rate = mean(state.rawRates(smoothStart:end,:),1);
state.rates(end+1,:) = rate;
state.time(end+1,1) = timeSec;

if state.autoAxis
    requiredMax = max([30; state.rates(:)*1.25]);
    newMax = ceil(requiredMax/5)*5;
    if newMax > state.axisMax
        state.axisMax = newMax;
        state.axisMaxima = [newMax newMax];
        xlim(state.ax,[0 newMax]);
        ylim(state.ax,[0 newMax]);
        set(state.lowerRay,'XData',[0 newMax], ...
            'YData',[0 newMax*tan(pi/6)]);
        set(state.upperRay,'XData',[0 newMax/tan(pi/3)], ...
            'YData',[0 newMax]);
    end
end

i0 = max(1,size(state.rates,1)-state.historyCount+1);
set(state.trajectory,'XData',state.rates(i0:end,1), ...
    'YData',state.rates(i0:end,2));
set(state.cursor,'XData',rate(1),'YData',rate(2));
set(state.status,'String',sprintf( ...
    't = %.2f s     X: MU%d = %.1f pps     Y: MU%d = %.1f pps', ...
    timeSec,state.xMU,rate(1),state.yMU,rate(2)));
if ~state.embedded, drawnow limitrate; end
end

function data = export_quadrant(state)
data = struct('enabled',state.enabled);
if ~state.enabled
    return;
end
data.xMU = state.xMU;
data.yMU = state.yMU;
data.time = state.time;
data.rate = state.rates;
data.rawRate = state.rawRates;
data.spikeCounts = state.spikeCounts;
data.rateWindowSec = state.rateWindowSec;
data.smoothingWindows = state.smoothingWindows;
data.referenceRates = state.referenceRates;
data.axisScale = state.axisScale;
data.axisMaxima = state.axisMaxima;
end

function value = read_cfg(cfg, fieldName, defaultValue)
if isfield(cfg,fieldName) && ~isempty(cfg.(fieldName))
    value = cfg.(fieldName);
else
    value = defaultValue;
end
end
