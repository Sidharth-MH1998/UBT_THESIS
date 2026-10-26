%% Raster plot for saved decompose5 / auto-edited results
% Use retained MUs from edition when available; false plots original signal.
useEditedResults = true;

plotFolder = fileparts(mfilename('fullpath'));
[fileName, fileFolder] = uigetfile('*.mat', ...
    'Select decompose5 or auto-edited results', plotFolder);
if isequal(fileName, 0)
    disp('File selection cancelled.');
    return;
end
rasterSession = load(fullfile(fileFolder, fileName), 'signal', 'edition');
assert(isfield(rasterSession, 'signal'), 'File must contain signal.');
rasterSignal = rasterSession.signal;
assert(all(isfield(rasterSignal, ...
    {'fsamp','data','ngrid','Dischargetimes','Pulsetrain'})), ...
    'Expected decompose5 signal fields are missing.');
fs = rasterSignal.fsamp;
validateattributes(fs, {'numeric'}, {'scalar','finite','positive'});
nSamples = size(rasterSignal.data, 2);
assert(nSamples > 0, 'Recording has no samples.');

spikeTimes = {};
muLabels = {};
gridIDs = [];
for gridIdx = 1:rasterSignal.ngrid
    gridResults = rasterSignal;
    sourceLabel = 'decomp5';
    if useEditedResults && isfield(rasterSession, 'edition') && ...
            isstruct(rasterSession.edition) && ...
            isfield(rasterSession.edition, 'edited_grids') && ...
            ismember(gridIdx, rasterSession.edition.edited_grids)
        gridResults = rasterSession.edition;
        sourceLabel = 'auto-edited';
    end
    % Pulse-train rows give the true MU count; discharge cells are padded.
    nGridMUs = size(gridResults.Pulsetrain{gridIdx}, 1);
    originalIDs = 1:nGridMUs;
    statsField = sprintf('grid%d', gridIdx);
    if strcmp(sourceLabel, 'auto-edited') && ...
            isfield(gridResults, 'edit_stats') && ...
            isfield(gridResults.edit_stats, statsField) && ...
            isfield(gridResults.edit_stats.(statsField), 'quality_filter_kept_mu')
        originalIDs = gridResults.edit_stats.(statsField).quality_filter_kept_mu;
    end
    for mu = 1:nGridMUs
        samples = gridResults.Dischargetimes{gridIdx, mu};
        assert(isnumeric(samples) && all(isfinite(samples(:))) && ...
            all(samples(:) == round(samples(:))) && ...
            all(samples(:) >= 1 & samples(:) <= nSamples), ...
            'Invalid discharge indices in grid %d MU %d.', gridIdx, mu);
        samples = sort(unique(samples(:).'));
        spikeTimes{end+1} = (samples-1)/fs;
        muLabels{end+1} = sprintf('G%d MU%d (%d spikes, %s)', ...
            gridIdx, originalIDs(mu), numel(samples), sourceLabel);
        gridIDs(end+1) = gridIdx;
    end
end

nMUs = numel(spikeTimes);
figure('Color','w','Name','Decompose5 MU raster plot');
ax = axes;
hold(ax, 'on');
colors = lines(rasterSignal.ngrid);
for mu = 1:nMUs
    plot(ax, spikeTimes{mu}, mu*ones(size(spikeTimes{mu})), '|', ...
        'Color', colors(gridIDs(mu),:), 'MarkerSize', 12, 'LineWidth', 1.2);
end
hold(ax, 'off');
grid(ax, 'on');
xlim(ax, [0 nSamples/fs]);
ylim(ax, [0.5 max(nMUs,1)+0.5]);
yticks(ax, 1:nMUs);
yticklabels(ax, muLabels);
set(ax, 'TickLabelInterpreter', 'none');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Grid / motor unit');
title(ax, sprintf('%s | %d MUs, %d spikes', fileName, nMUs, ...
    sum(cellfun(@numel, spikeTimes))), 'Interpreter', 'none');
if nMUs == 0
    text(ax, 0.5, 0.5, 'No motor units retained', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center');
end
