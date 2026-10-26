function edition = edit_single_session(input_file, options)
% EDIT_SINGLE_SESSION Automatically edit a decomposition MAT file.
%   results = edit_single_session('session.mat')
%   edition = edit_single_session('session.mat', ShowPlots=false)
%   edition = edit_single_session('session.mat', FilterMUs=true, ...
%       SILThreshold=0.90, CoVThreshold=0.50)
% Remove MUs with post-edit SIL below threshold OR CoV above threshold.
% CoV is a ratio: 0.50 means 50%.
%   edit_single_session() opens a file picker; cancellation returns [].
% Editing input remains signal.Dischargetimes, not edition.Dischargetimes.
% Returns corrected results in edition, with statistics in edit_stats.gridN.
% Saves <input_name>_auto_edited.mat with the original session and edition.

arguments
    input_file (1,1) string = ""
    options.Grids (1,:) double {mustBeInteger, mustBePositive} = [1 2]
    options.ShowPlots (1,1) logical = true
    options.OverwriteOutput (1,1) logical = false
    options.MaskBadValue (1,1) double {mustBeMember(options.MaskBadValue,[0 1])} = 1
    options.OutputFile (1,1) string = ""
    options.FilterMUs (1,1) logical = false
    options.SILThreshold (1,1) double {mustBeFinite, mustBeGreaterThanOrEqual(options.SILThreshold,-1), mustBeLessThanOrEqual(options.SILThreshold,1)} = 0.90
    options.CoVThreshold (1,1) double {mustBeFinite, mustBeNonnegative} = 0.50
end

edition = [];
%% Settings
script_folder = fileparts(mfilename('fullpath'));
grids_to_edit = unique(options.Grids, 'stable');
show_plots = options.ShowPlots;
overwrite_output = options.OverwriteOutput;
mask_bad_value = options.MaskBadValue;

%% Select an existing decomposition file
if strlength(input_file) == 0
    [selected_name, selected_folder] = uigetfile( ...
    {'*.mat;*.mat_decomp', 'Decomposition files (*.mat, *.mat_decomp)'; ...
     '*.*', 'All files (*.*)'}, ...
    'Select decomposition session to automatically edit', script_folder);
    if isequal(selected_name, 0)
        disp('File selection cancelled. No processing performed.');
        return;
    end
    input_file = string(fullfile(selected_folder, selected_name));
end
assert(isfile(input_file), 'Input file not found: %s', input_file);
[found, attributes] = fileattrib(input_file);
assert(found, 'Cannot resolve input file: %s', input_file);
input_file = attributes.Name;
[selected_folder, output_stem] = fileparts(input_file);
output_file = fullfile(selected_folder, ...
    [output_stem '_auto_edited.mat']);
if strlength(options.OutputFile) > 0
    output_file = char(options.OutputFile);
end
[output_folder, output_name, output_ext] = fileparts(output_file);
if isempty(output_folder), output_folder = pwd; end
[found, attributes] = fileattrib(output_folder);
assert(found && attributes.directory, 'Output folder must exist: %s', output_folder);
output_file = fullfile(attributes.Name, [output_name output_ext]);

%% Load and validate the session
addpath(genpath(fullfile(script_folder, 'autoedit_funcs')));
addpath(genpath(fullfile(script_folder, 'decomp_funcs')));
assert(exist('iirnotch', 'file') ~= 0, ...
    ['The existing editor requires iirnotch (DSP System Toolbox), plus ' ...
     'Signal Processing Toolbox. Install/enable these before running.']);
assert(overwrite_output || ~isfile(output_file), ...
    'Output already exists. Use OutputFile or OverwriteOutput=true.');
assert(~strcmpi(input_file, output_file), 'Use a separate output file.');
session = load(input_file);
assert(isfield(session, 'signal'), 'Expected a top-level signal structure.');
sig = session.signal;
required = {'data','fsamp','ngrid','EMGmask','Dischargetimes','Pulsetrain'};
assert(all(isfield(sig, required)), 'Session is missing required signal fields.');
assert(all(ismember(grids_to_edit, 1:sig.ngrid)), 'Invalid grid selection.');
assert(size(sig.Dischargetimes, 1) == sig.ngrid, ...
    'Expected Dischargetimes arranged as grids x motor units.');
channel_counts = cellfun(@numel, sig.EMGmask);
assert(sum(channel_counts) == size(sig.data, 1), 'EMG/mask channel counts differ.');
fs = sig.fsamp;
n_samples = size(sig.data, 2);
edition = struct('edit_stats', struct());
edition.Pulsetrain = sig.Pulsetrain;
edition.Dischargetimes = sig.Dischargetimes;
edition.silval = cell(size(sig.Dischargetimes));
edition.CoV = cell(size(sig.Dischargetimes)); % ratios, not percentages
edition.mean_fr = cell(size(sig.Dischargetimes));
edition.ISI = cell(size(sig.Dischargetimes));
edition.time = (0:n_samples-1) / fs;
edition.arraynb = repelem((1:sig.ngrid)', channel_counts(:));
edition.edited_grids = grids_to_edit;
edition.note = ['Automatic editing; no duplicate-MU cleanup performed. ' ...
    'SIL is reconstructed-filter quality; unavailable values are NaN.'];
edition.settings.grids = grids_to_edit;
edition.settings.ipt_ratios = [0.331 0.339 0.539 0.508];
edition.settings.max_cycles = 5;
edition.settings.filter_mus = options.FilterMUs;
edition.settings.sil_threshold = options.SILThreshold;
edition.settings.cov_threshold = options.CoVThreshold;
review_results = struct(); % Temporary plot data; not saved or returned.

%% Edit each grid independently
for grid = grids_to_edit
    channels = sum(channel_counts(1:grid-1)) + (1:channel_counts(grid));
    emg = sig.data(channels, :);
    % Mask conventions differ between decomposition exporters; see setting.
    bad = find(sig.EMGmask{grid} == mask_bad_value);
    good = setdiff(1:numel(channels), bad);
    assert(~isempty(good), 'Grid %d has no usable channels.', grid);
    n_mu = size(sig.Pulsetrain{grid}, 1);
    assert(n_mu <= size(sig.Dischargetimes, 2), 'Missing discharge-time cells.');
    original = sig.Dischargetimes(grid, 1:n_mu);
    for mu = 1:n_mu
        times = original{mu};
        assert(isnumeric(times) && all(isfinite(times(:))) && ...
            all(times(:) == round(times(:))) && ...
            all(times(:) >= 1 & times(:) <= n_samples), ...
            'Grid %d MU %d must contain valid discharge sample indices.', grid, mu);
        original{mu} = sort(unique(double(times(:).')));
    end
    fprintf('\nGrid %d: %d MUs, %d usable channels\n', grid, n_mu, numel(good));
    % Disable the wrapper's plots: its plot_comparison helper is absent.
    if n_mu > 0
        [edited, stats, quality] = auto_edit_spikes(emg(good,:), original, fs, false, ...
            sprintf('Grid %d', grid));
    else
        edited = original;
        stats = struct('total_added', 0, 'total_removed', 0);
        quality = struct('sil_pre', [], 'sil_post', [], ...
            'pulsetrain', zeros(0, n_samples));
    end
    metrics = spike_metrics(edited, fs);
    remove_mu = false(1, n_mu);
    if options.FilterMUs
        remove_mu = quality.sil_post(:).' < options.SILThreshold | ...
            metrics.CoV(:).' > options.CoVThreshold;
    end
    kept_mu = find(~remove_mu);
    n_kept = numel(kept_mu);
    stats.quality_filter_removed_mu = find(remove_mu);
    stats.quality_filter_kept_mu = kept_mu;
    stats.quality_filter_removed_count = nnz(remove_mu);
    edition.Pulsetrain{grid} = quality.pulsetrain(kept_mu,:);
    edition.Dischargetimes(grid,:) = {[]};
    edition.Dischargetimes(grid,1:n_kept) = edited(kept_mu);
    edition.silval(grid,1:n_kept) = num2cell(quality.sil_post(kept_mu));
    edition.CoV(grid,1:n_kept) = num2cell(metrics.CoV(kept_mu));
    edition.mean_fr(grid,1:n_kept) = num2cell(metrics.mean_fr(kept_mu));
    edition.ISI(grid,1:n_kept) = metrics.ISI(kept_mu);
    fprintf('Grid %d reconstructed-filter SIL (per MU):\n', grid);
    disp(table((1:n_mu)', quality.sil_pre(:), quality.sil_post(:), ...
        metrics.CoV(:), remove_mu(:), ...
        'VariableNames', {'MU', 'SIL_before', 'SIL_after', 'CoV_after', 'Removed'}));
    if options.FilterMUs
        fprintf('Grid %d: removed %d MUs; retained %d.\n', grid, nnz(remove_mu), n_kept);
    end
    edition.edit_stats.(sprintf('grid%d', grid)) = stats;
    if show_plots
        result.mu_ids = kept_mu;
        result.original_spikes = sig.Dischargetimes(grid, kept_mu);
        result.results_edited = struct('MUPulses', {edited(kept_mu)}, 'SIL', quality.sil_post(kept_mu));
        result.sil_pre = quality.sil_pre(kept_mu);
        review_results.(sprintf('grid%d', grid)) = result;
    end
end

% Save before plotting so closing a figure cannot lose the editing results.
session.edition = edition;
if isfield(session, 'processed_data')
    session = rmfield(session, 'processed_data');
end
save(output_file, '-struct', 'session', '-v7.3');
fprintf('\nSaved edited session: %s\n', output_file);

%% Review: select any MU using the figure dropdown
if show_plots
    for grid = grids_to_edit
        result = review_results.(sprintf('grid%d', grid));
        if isempty(result.original_spikes), continue; end
        fig = figure('Name', sprintf('Grid %d: automatic editing review', grid), ...
            'NumberTitle', 'off');
        ax1 = subplot(2,1,1, 'Parent', fig);
        ax2 = subplot(2,1,2, 'Parent', fig);
        linkaxes([ax1 ax2], 'x');
        selector = uicontrol(fig, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [0.70 0.95 0.25 0.04], ...
            'String', arrayfun(@(m) sprintf('MU %d', m), ...
            result.mu_ids, 'UniformOutput', false));
        selector.Callback = @(src,~) draw_session_mu(ax1, ax2, ...
            sig.Pulsetrain{grid}, result, fs, src.Value);
        draw_session_mu(ax1, ax2, sig.Pulsetrain{grid}, result, fs, 1);
    end
end

end

function metrics = spike_metrics(spikes, fs)
% Only calculate the discharge statistics saved in edition; no MUAP averaging.
    metrics.ISI = cell(size(spikes));
    metrics.CoV = zeros(size(spikes));
    metrics.mean_fr = zeros(size(spikes));
    for mu = 1:numel(spikes)
        if numel(spikes{mu}) < 2, continue; end
        isi = diff(spikes{mu}) / fs;
        metrics.ISI{mu} = isi;
        metrics.CoV(mu) = std(isi) / mean(isi);
        metrics.mean_fr(mu) = mean(1 ./ isi);
    end
end

function draw_session_mu(ax1, ax2, pulse, result, fs, mu)
    pulse_mu = result.mu_ids(mu);
    before = result.original_spikes{mu}(:).';
    after = result.results_edited.MUPulses{mu}(:).';
    cov_before = NaN;
    cov_after = NaN;
    if numel(before) >= 2
        intervals = diff(before) / fs;
        cov_before = 100 * std(intervals) / mean(intervals);
    end
    if numel(after) >= 2
        intervals = diff(after) / fs;
        cov_after = 100 * std(intervals) / mean(intervals);
    end
    t = (0:size(pulse,2)-1)/fs;
    plot(ax1, t, pulse(pulse_mu,:), 'Color', [0.6 0.6 0.6]);
    hold(ax1, 'on');
    plot(ax1, (before-1)/fs, pulse(pulse_mu,before), 'bo');
    plot(ax1, (after-1)/fs, pulse(pulse_mu,after), 'r.');
    hold(ax1, 'off');
    ylabel(ax1, 'Original pulse amplitude');
    title(ax1, {sprintf('MU %d | Reconstructed-filter SIL: %.3f -> %.3f', ...
        pulse_mu, result.sil_pre(mu), result.results_edited.SIL(mu)), ...
        sprintf('CoV of ISI: %.2f%% -> %.2f%% (before -> after)', ...
        cov_before, cov_after)});
    legend(ax1, 'Saved pulse train', 'Original spikes', 'Edited spikes');
    plot(ax2, (before(2:end)-1)/fs, fs./diff(before), 'b.-');
    hold(ax2, 'on');
    plot(ax2, (after(2:end)-1)/fs, fs./diff(after), 'r.-');
    hold(ax2, 'off');
    xlabel(ax2, 'Time (s)'); ylabel(ax2, 'Firing rate (Hz)');
    legend(ax2, 'Original', 'Edited'); grid(ax2, 'on');
end
