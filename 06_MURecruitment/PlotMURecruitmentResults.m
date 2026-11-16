% Select and inspect a hardware or demo recruitment recording.
% Force uses saved receipt timestamps; raster uses the EMG sample clock.
plotDir = fileparts(mfilename('fullpath'));
startFolder = fullfile(plotDir,'recordings');
if ~isfolder(startFolder), startFolder = plotDir; end
[fileName, folder] = uigetfile(fullfile(startFolder,'*.mat'), ...
    'Select a recruitment recording (signal and recruitment)');
if isequal(fileName,0)
    disp('No recording selected.');
    return;
end
recordingFile = fullfile(folder,fileName);
saved = load(recordingFile,'signal','recruitment');
assert(isfield(saved,'signal') && isfield(saved,'recruitment'), ...
    'Select a saved recruitment trial containing signal and recruitment.');
sig = saved.signal;
rec = saved.recruitment;
assert(isfield(sig,'fsamp') && isfield(sig,'data') && ...
    isfield(sig,'recordedForce') && isfield(rec,'Distime'), ...
    'Recording is missing EMG, force, sampling rate or raster data.');
validateattributes(sig.fsamp,{'numeric'},{'scalar','finite','positive'});
nSamples = size(sig.data,2);
nMU = size(rec.Distime,2);
assert(size(rec.Distime,1) == nSamples, ...
    'Raster sample count does not match the recorded EMG.');
emgTime = (0:nSamples-1)/sig.fsamp;
if isfield(sig,'emgTime') && numel(sig.emgTime) == nSamples
    emgTime = reshape(sig.emgTime,1,[]);
end
nForce = size(sig.recordedForce,1);
if isfield(sig,'forceTime') && numel(sig.forceTime) == nForce
    forceTime = sig.forceTime(:);
else
    assert(isfield(sig,'fs_force'),'Force timestamps or fs_force are required.');
    validateattributes(sig.fs_force,{'numeric'},{'scalar','finite','positive'});
    forceTime = (0:nForce-1)'/sig.fs_force;
end

resultFig = figure('Name',['Recruitment results - ' fileName], ...
    'NumberTitle','off','Color','w','Position',[100 80 1350 800]);
layout = tiledlayout(resultFig,2,1,'TileSpacing','compact','Padding','compact');
layout.OuterPosition = [0 0.055 1 0.945];
forceAxes = nexttile(layout); hold(forceAxes,'on'); grid(forceAxes,'on');
forceNames = arrayfun(@(k) sprintf('Force channel %d',k), ...
    1:size(sig.recordedForce,2),'UniformOutput',false);
forceColors = lines(size(sig.recordedForce,2));
for channel = 1:size(sig.recordedForce,2)
    lineWidth = 1;
    if isfield(rec,'trial') && isfield(rec.trial,'channel') && rec.trial.channel == channel
        lineWidth = 2;
        forceNames{channel} = [forceNames{channel} ' (selected)'];
    end
    plot(forceAxes,forceTime,sig.recordedForce(:,channel), ...
        'Color',forceColors(channel,:),'LineWidth',lineWidth, ...
        'DisplayName',forceNames{channel});
end
if isfield(sig,'target') && numel(sig.target) == nSamples
    plot(forceAxes,emgTime,sig.target(:),'k--','LineWidth',1.5,'DisplayName','Target');
end
ylabel(forceAxes,'Force (% calibrated)'); title(forceAxes,'Recorded force and target');
legend(forceAxes,'show','Location','best');

rasterAxes = nexttile(layout); hold(rasterAxes,'on'); grid(rasterAxes,'on');
muColors = lines(nMU);
muLabels = arrayfun(@(k) sprintf('MU %d',k),1:nMU,'UniformOutput',false);
if isfield(rec,'muLabels') && numel(rec.muLabels) == nMU
    muLabels = cellstr(string(rec.muLabels));
elseif isfield(rec,'muMap') && size(rec.muMap,1) == nMU && size(rec.muMap,2) >= 2
    muLabels = arrayfun(@(k) sprintf('G%d MU%d',rec.muMap(k,1),rec.muMap(k,2)), ...
        1:nMU,'UniformOutput',false);
end
% RT is selected-channel force at the first recorded discharge. Prefer the
% saved EMG-length force path, matching the recorder's force resampling.
recruitmentThreshold = nan(nMU,1);
if isfield(sig,'path') && numel(sig.path) == nSamples
    forceAtEMG = reshape(sig.path,1,[]);
else
    selectedChannel = 1;
    if isfield(rec,'trial') && isfield(rec.trial,'channel')
        selectedChannel = rec.trial.channel;
    end
    assert(selectedChannel >= 1 && selectedChannel <= size(sig.recordedForce,2), ...
        'Selected force channel is unavailable.');
    forceAtEMG = nan(1,nSamples);
    values = sig.recordedForce(:,selectedChannel);
    validForce = isfinite(forceTime) & isfinite(values);
    [times, uniqueIndex] = unique(forceTime(validForce));
    values = values(validForce); values = values(uniqueIndex);
    if numel(times) >= 2
        forceAtEMG = interp1(times,values,emgTime,'linear',nan);
    end
end
rasterLines = gobjects(nMU,1);
for mu = 1:nMU
    firstSpike = find(rec.Distime(:,mu),1,'first');
    if ~isempty(firstSpike) && isfinite(forceAtEMG(firstSpike))
        recruitmentThreshold(mu) = forceAtEMG(firstSpike);
    end
    if isnan(recruitmentThreshold(mu))
        muLabels{mu} = sprintf('%s (RT N/A)',muLabels{mu});
    else
        muLabels{mu} = sprintf('%s (RT %.0f)',muLabels{mu},recruitmentThreshold(mu));
    end
    spikeTimes = emgTime(find(rec.Distime(:,mu))); %#ok<FNDSB>
    rasterLines(mu) = plot(rasterAxes,spikeTimes,mu*ones(size(spikeTimes)),'|', ...
        'Color',muColors(mu,:),'MarkerSize',8);
end
ylim(rasterAxes,[0 max(1,nMU+1)]);
yticks(rasterAxes,1:nMU); yticklabels(rasterAxes,muLabels);
ylabel(rasterAxes,'Motor unit'); xlabel(rasterAxes,'Trial time (s)');
title(rasterAxes,'Recorded motor-unit raster | RT: force (%) at first recorded discharge');
sortControl = uicontrol(resultFig,'Style','checkbox', ...
    'String','Sort MUs by increasing recruitment threshold (RT)', ...
    'Value',0,'Units','normalized','Position',[0.02 0.008 0.65 0.035], ...
    'BackgroundColor','w', ...
    'TooltipString','RT uses the selected force channel; missing thresholds appear last.', ...
    'Callback',@(control,~) reorder_raster(control.Value,rasterAxes, ...
        rasterLines,muLabels,recruitmentThreshold));
% Retain thresholds and original identities for interactive inspection.
resultFig.UserData = struct('recruitmentThreshold',recruitmentThreshold, ...
    'definition','Selected force at first recorded discharge; percent calibrated', ...
    'recordingFile',recordingFile);
reorder_raster(false,rasterAxes,rasterLines,muLabels,recruitmentThreshold);
linkaxes([forceAxes rasterAxes],'x');
allTimes = [0; emgTime(:); forceTime(:)];
xlim(forceAxes,[min(allTimes) max(max(allTimes),1/sig.fsamp)]);
summaryText = fileName;
if isfield(rec,'trial')
    tr = rec.trial;
    if all(isfield(tr,{'participant','session','trial','traceType','repetitions'}))
        summaryText = sprintf('%s | Participant %s | Session %d | Trial %d | %s | %d repetitions', ...
            fileName,tr.participant,tr.session,tr.trial,tr.traceType,tr.repetitions);
    end
end
if isfield(sig,'simulated') && sig.simulated
    summaryText = [summaryText ' | SIMULATED'];
end
title(layout,summaryText,'Interpreter','none');
fprintf('Plotted %s\n%d EMG channels, %d samples, %d motor units, %d force samples.\n', ...
    recordingFile,size(sig.data,1),nSamples,nMU,nForce);

function reorder_raster(sortEnabled, ax, rasterLines, labels, thresholds)
% Reorder rows only: preserve original MU names, spike times and colors.
nMU = numel(rasterLines);
order = (1:nMU)';
if sortEnabled
    [~,order] = sort(thresholds,'ascend','MissingPlacement','last');
end
for row = 1:nMU
    mu = order(row);
    rasterLines(mu).YData = row*ones(size(rasterLines(mu).XData));
end
yticks(ax,1:nMU); yticklabels(ax,labels(order));
ax.YDir = 'normal'; % Ascending thresholds run from bottom to top.
end
