%% Raster, force and instantaneous firing rate for all grids
% signal.data defines EMG length; signal.path supplies force.
% Prefer edition discharge times when available, otherwise use signal.
[fileName, fileFolder] = uigetfile('*.mat','Select decomposition results');
if isequal(fileName,0), return; end
session = load(fullfile(fileFolder,fileName),'signal','edition');
assert(isfield(session,'signal'),'The selected file must contain signal.');
signal = session.signal;
assert(all(isfield(signal,{'data','fsamp','path','Pulsetrain','Dischargetimes'})), ...
    'Required signal fields: data, fsamp, path, Pulsetrain, Dischargetimes.');
fs = signal.fsamp;
validateattributes(fs,{'numeric'},{'scalar','positive','finite'});
nSamples = size(signal.data,2);
assert(nSamples > 0,'signal.data is empty.');
assert(isnumeric(signal.path) && isvector(signal.path) && ...
    numel(signal.path) == nSamples,'signal.path must match the EMG sample count.');
assert(iscell(signal.Pulsetrain) && iscell(signal.Dischargetimes), ...
    'Pulsetrain and Dischargetimes must be cell arrays.');
nGrids = numel(signal.Pulsetrain);
time = (0:nSamples-1)/fs;

%% Collect spikes in grid order, then saved MU-number order
spikeTimes = {};
muLabels = {};
for gridIdx = 1:nGrids
    results = signal;
    source = 'signal';
    if isfield(session,'edition') && isstruct(session.edition) && ...
            all(isfield(session.edition,{'Pulsetrain','Dischargetimes'})) && ...
            iscell(session.edition.Pulsetrain) && ...
            iscell(session.edition.Dischargetimes) && ...
            numel(session.edition.Pulsetrain) >= gridIdx && ...
            size(session.edition.Dischargetimes,1) >= gridIdx
        results = session.edition;
        source = 'edition';
    end
    % Pulsetrain rows give the MU count; discharge cells can have empty padding.
    nGridMUs = size(results.Pulsetrain{gridIdx},1);
    assert(size(results.Dischargetimes,1) >= gridIdx && ...
        size(results.Dischargetimes,2) >= nGridMUs, ...
        'Discharge cells are missing for grid %d.',gridIdx);
    fprintf('Grid %d: %d MUs from %s.\n',gridIdx,nGridMUs,source);
    for mu = 1:nGridMUs
        samples = results.Dischargetimes{gridIdx,mu};
        assert(isnumeric(samples) && all(isfinite(samples(:))) && ...
            all(samples(:) == round(samples(:))) && ...
            all(samples(:) >= 1 & samples(:) <= nSamples), ...
            'Invalid discharge samples in grid %d MU %d.',gridIdx,mu);
        spikeTimes{end+1} = (unique(samples(:).')-1)/fs;
        muLabels{end+1} = sprintf('G%d MU%d',gridIdx,mu);
    end
end

%% Raster with force on the right axis
nMUs = numel(spikeTimes);
colors = lines(max(nMUs,1));
figure('Color','w','Name','MU raster and firing rate', ...
    'Position',[80 80 1350 800]);
axRaster = subplot(2,1,1);
yyaxis(axRaster,'left');
hold(axRaster,'on');
for mu = 1:nMUs
    plot(axRaster,spikeTimes{mu},mu*ones(size(spikeTimes{mu})), ...
        '|','Color',colors(mu,:),'MarkerSize',10,'LineWidth',1.2);
end
hold(axRaster,'off');
ylim(axRaster,[0.5 max(nMUs,1)+0.5]);
yticks(axRaster,1:nMUs);
yticklabels(axRaster,muLabels);
set(axRaster,'YDir','reverse','YColor','k','TickLabelInterpreter','none');
ylabel(axRaster,'Grid / motor unit');
if nMUs == 0
    text(axRaster,0.5,0.5,'No motor units retained', ...
        'Units','normalized','HorizontalAlignment','center');
end
yyaxis(axRaster,'right');
plot(axRaster,time,signal.path(:),'k-','LineWidth',1.4);
set(axRaster,'YDir','normal','YColor','k');
ylabel(axRaster,'Force (% MVC)');
xlabel(axRaster,'Time (s)');
title(axRaster,'Motor-unit raster with force');
grid(axRaster,'on');

%% Instantaneous firing rate: 1 / interspike interval, at its midpoint
axFR = subplot(2,1,2);
hold(axFR,'on');
for mu = 1:nMUs
    t = spikeTimes{mu};
    if numel(t) < 2, continue; end
    rate = 1./diff(t);
    rateTime = (t(1:end-1)+t(2:end))/2;
    plot(axFR,rateTime,rate,'.-','Color',colors(mu,:), ...
        'MarkerSize',7,'LineWidth',0.5,'DisplayName',muLabels{mu});
end
hold(axFR,'off');
xlabel(axFR,'Time (s)');
ylabel(axFR,'Firing rate (Hz)');
title(axFR,'Instantaneous firing rate');
grid(axFR,'on');
if any(cellfun(@numel,spikeTimes) >= 2)
    legend(axFR,'Location','eastoutside','Interpreter','none','FontSize',8);
end
linkaxes([axRaster axFR],'x');
xlim(axRaster,[0 max(time(end),1/fs)]);
sgtitle(sprintf('%s | %d grids | %d MUs',fileName,nGrids,nMUs), ...
    'Interpreter','none');
