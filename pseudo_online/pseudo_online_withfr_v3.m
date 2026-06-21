%% =========================================================================
% PSEUDO-ONLINE EMG DECOMPOSITION + FORCE OVERLAY
%
% OUTPUTS saved to workspace after running:
%   Dischargetimes_online : cell (1 x nMUs) — spike indices per MU
%   Pulsetrain_online     : (nMUs x nSamples) — full pulse train
%   fr_online             : cell (1 x nMUs) — instantaneous firing rates
%   mean_fr_online        : (nMUs x 1) — mean firing rate per MU
% =========================================================================

%% =========================================================================
%  SECTION 1: PARAMETERS — edit these before running
% =========================================================================

fs         = 2000;   % EMG sampling frequency (Hz)
fs_force   = 50;     % force sampling frequency (Hz)
badchan    = [];     % manually specify bad channels e.g. [5 23 41]
window_sec = 0.125;  % window duration in seconds

%% =========================================================================
%  SECTION 2: VALIDATE CALIBRATION INPUTS
% =========================================================================

assert(exist('recordedEMG','var')==1, ...
    'recordedEMG (calibration) not found in workspace.')
assert(exist('Calib_data','var')==1, ...
    'Calib_data not found in workspace. Run decompose3() first.')

fprintf('\n=== Pseudo-Online EMG Decomposition ===\n')

%% =========================================================================
%  SECTION 3: BUILD CHANNEL MASK
% =========================================================================

nChan = size(recordedEMG,1);

if ~isempty(badchan)
    assert(all(badchan >= 1 & badchan <= nChan), ...
        'badchan contains invalid channel index/indices.')
    badchan = unique(badchan(:).');
end

% Convention: EMGmask = 0 -> good channel
%             EMGmask = 1 -> bad channel
EMGmask          = zeros(nChan,1);
EMGmask(badchan) = 1;
nGoodChan        = sum(EMGmask == 0);

fprintf('Channels: %d total | %d good | %d excluded\n\n', ...
    nChan, nGoodChan, numel(badchan))

%% =========================================================================
%  SECTION 4: LOAD CALIBRATION FILTERS
% =========================================================================

MUFilters = Calib_data.MUFilters;
nMUs      = size(MUFilters, 2);

if nMUs == 0
    error('No MU filters found in Calib_data. Check decomposition quality.')
end

fprintf('Calibration: %d MUs loaded from Calib_data\n\n', nMUs)

%% =========================================================================
%  SECTION 5: COMPUTE ONLINE PARAMETERS FROM CALIBRATION SIGNAL
% =========================================================================

fprintf('Computing online parameters on calibration signal...\n')

[extensionfactor, iReSIG, norm_fac, centroid] = getonlineparameters( ...
    recordedEMG, EMGmask, MUFilters, fs);

% Precompute online filter
MUfilt = MUFilters' * iReSIG;

fprintf('Online parameters ready. %d MUs loaded.\n\n', nMUs)

%% =========================================================================
%  SECTION 6: LOAD NEW TRIAL VIA FILE PICKER
% =========================================================================

fprintf('Select the new sample .mat file...\n')
[fname, fpath] = uigetfile('*.mat', ...
    'Select new EMG trial for pseudo-online decomposition');

if isequal(fname, 0)
    error('No file selected. Aborting.')
end

newdata = load(fullfile(fpath, fname), 'recordedEMG', 'recordedForce');

if ~isfield(newdata, 'recordedEMG')
    error('Variable ''recordedEMG'' not found in selected file: %s', fname)
end

if ~isfield(newdata, 'recordedForce')
    error('Variable ''recordedForce'' not found in selected file: %s', fname)
end

newEMG = newdata.recordedEMG;

% Force from 2nd column
if size(newdata.recordedForce,2) < 2
    error('recordedForce does not contain a 2nd column in file: %s', fname)
end

force_signal = newdata.recordedForce(:,2);
force_signal = force_signal(:).';   % row vector

% Validate channel count matches calibration
if size(newEMG,1) ~= size(recordedEMG,1)
    error('Channel mismatch: calibration has %d channels, new file has %d.', ...
        size(recordedEMG,1), size(newEMG,1))
end

% Derived parameters from new file
window_samples = round(window_sec * fs);
assert(window_samples >= 2, 'window_sec too small.')

total_samples  = size(newEMG, 2);
nwin           = floor(total_samples / window_samples);
total_duration = total_samples / fs;

if nwin < 1
    error('Selected file is shorter than one analysis window.')
end

% Build centroid matrices at correct window size
noise_centroids = ones(window_samples, nMUs) .* (centroid(:,1)');
spike_centroids = ones(window_samples, nMUs) .* (centroid(:,2)');

% Resample force to EMG timeline
t_emg   = (0:total_samples-1) / fs;
t_force = (0:length(force_signal)-1) / fs_force;
force_signal_resampled = interp1(t_force, force_signal, t_emg, 'linear', 'extrap');

fprintf('Loaded: %s\n', fname)
fprintf('Duration: %.1f sec | Windows: %d | Chunk: %d samples\n\n', ...
    total_duration, nwin, window_samples)

%% =========================================================================
%  SECTION 7: PREALLOCATE OUTPUTS
% =========================================================================

% esample2: boundary samples carried between windows
esample2 = zeros(nGoodChan * extensionfactor, extensionfactor-1);

% Full signal outputs
Pulsetrain_online = zeros(nMUs, nwin * window_samples);
Distime           = false(nwin * window_samples, nMUs);

% Accumulated results per MU
Dischargetimes_online = cell(1, nMUs);
fr_online             = cell(1, nMUs);

for mu = 1:nMUs
    Dischargetimes_online{mu} = [];
    fr_online{mu}             = [];
end

%% =========================================================================
%  SECTION 8: SETUP LIVE FIGURE
% =========================================================================

colors = lines(nMUs);

fig = figure('Color','w', 'Position',[50 50 1400 800], ...
    'Name', sprintf('Pseudo-Online Decomposition — %s', fname));

%--- Top panel: raster plot + force overlay
ax_raster = subplot(2,1,1);

yyaxis(ax_raster, 'left')
hold(ax_raster, 'on')
title(ax_raster, 'Real-Time Spike Trains + Force', 'FontSize',11)
xlabel(ax_raster, 'Time (s)')
ylabel(ax_raster, 'Motor Unit')
xlim(ax_raster, [0 total_duration])
ylim(ax_raster, [0 nMUs+1])
yticks(ax_raster, 1:nMUs)
yticklabels(ax_raster, arrayfun(@(x) sprintf('MU%d  (0 spikes)',x), ...
    1:nMUs, 'UniformOutput',false))
grid(ax_raster, 'on')
set(ax_raster, 'FontSize', 9)

yyaxis(ax_raster, 'right')
ylabel(ax_raster, 'Force')
force_min = min(force_signal_resampled);
force_max = max(force_signal_resampled);
if force_min == force_max
    force_max = force_min + 1;
end
ylim(ax_raster, [force_min force_max])

%--- Bottom panel: instantaneous firing rate
ax_fr = subplot(2,1,2);
hold(ax_fr, 'on')
title(ax_fr, 'Instantaneous Firing Rate (Hz)', 'FontSize',11)
xlabel(ax_fr, 'Time (s)')
ylabel(ax_fr, 'Firing Rate (Hz)')
xlim(ax_fr, [0 total_duration])
ylim(ax_fr, [0 60])
grid(ax_fr, 'on')
set(ax_fr, 'FontSize', 9)

% One handle per MU
yyaxis(ax_raster, 'left')
h_raster = gobjects(nMUs, 1);
for mu = 1:nMUs
    h_raster(mu) = plot(ax_raster, nan, nan, '|', ...
        'Color', colors(mu,:), 'MarkerSize',10, 'LineWidth',1.5);
end

% Force handle on right axis
yyaxis(ax_raster, 'right')
h_force = plot(ax_raster, nan, nan, 'k-', 'LineWidth',1.5);

h_fr = gobjects(nMUs, 1);
for mu = 1:nMUs
    h_fr(mu) = plot(ax_fr, nan, nan, '.', ...
        'Color', colors(mu,:), 'MarkerSize',4, ...
        'DisplayName', sprintf('MU%d',mu));
end
legend(ax_fr, 'Location','eastoutside', 'FontSize',6)

% Moving time indicator lines
yyaxis(ax_raster, 'left')
tline_raster = xline(ax_raster, 0, 'r--', 'LineWidth',1.5);
tline_fr     = xline(ax_fr,     0, 'r--', 'LineWidth',1.5);

%% =========================================================================
%  SECTION 9: PSEUDO-ONLINE LOOP
% =========================================================================

fprintf('Starting real-time loop on new sample...\n\n')

for k = 1:nwin

    %--- Window indices
    start_idx    = (k-1)*window_samples + 1;
    end_idx      =  k   *window_samples;
    current_time =  end_idx / fs;

    %--- Extract chunk from NEW trial — good channels only
    EMGtmp1 = newEMG(:, start_idx:end_idx);
    EMGtmp2 = EMGtmp1(EMGmask==0, :);

    %--- Detect spikes in this window
    [Pulsetrain_online(:,start_idx:end_idx), ...
     Distime(start_idx:end_idx,:), ...
     esample2] = getspikesonline(EMGtmp2, extensionfactor, esample2, ...
                                 MUfilt, norm_fac, noise_centroids, ...
                                 spike_centroids, window_samples, fs);

    %--- Accumulate spike times and firing rates
    for mu = 1:nMUs
        new_spikes = find(Distime(start_idx:end_idx, mu)) + start_idx - 1;

        if ~isempty(new_spikes)
            Dischargetimes_online{mu} = [Dischargetimes_online{mu}; new_spikes];
        end

        if length(Dischargetimes_online{mu}) > 1
            fr_online{mu} = 1 ./ (diff(Dischargetimes_online{mu}) / fs);
        end
    end

    %--- Update raster plot
    yyaxis(ax_raster, 'left')
    for mu = 1:nMUs
        if ~isempty(Dischargetimes_online{mu})
            spikes_t = Dischargetimes_online{mu} / fs;
            set(h_raster(mu), ...
                'XData', spikes_t, ...
                'YData', mu * ones(size(spikes_t)))
        end
    end

    %--- Update y-axis labels with live spike count per MU
    yticklabels(ax_raster, arrayfun(@(mu) ...
        sprintf('MU%d  (%d spikes)', mu, length(Dischargetimes_online{mu})), ...
        1:nMUs, 'UniformOutput', false))

    %--- Update force trace on right axis
    yyaxis(ax_raster, 'right')
    force_t = (1:end_idx) / fs;
    set(h_force, ...
        'XData', force_t, ...
        'YData', force_signal_resampled(1:end_idx))

    %--- Update firing rate plot
    for mu = 1:nMUs
        if length(Dischargetimes_online{mu}) > 1
            spike_times_fr = Dischargetimes_online{mu}(1:end-1) / fs;
            set(h_fr(mu), ...
                'XData', spike_times_fr, ...
                'YData', fr_online{mu})
        end
    end

    %--- Advance time indicator
    yyaxis(ax_raster, 'left')
    set(tline_raster, 'Value', current_time)
    set(tline_fr,     'Value', current_time)

    %--- Update title
    title(ax_raster, sprintf('Real-Time Spike Trains + Force  |  t = %.2f / %.2f sec  |  %s', ...
        current_time, total_duration, fname), 'FontSize',10)

    %--- Refresh display
    drawnow limitrate

end

%% =========================================================================
%  SECTION 10: FINALIZE AND SUMMARIZE
% =========================================================================

yyaxis(ax_raster, 'left')
title(ax_raster, sprintf('Done  |  %d MUs  |  %.1f sec  |  %s', ...
    nMUs, total_duration, fname), 'FontSize',11)

% Compute mean firing rate per MU
mean_fr_online = zeros(nMUs, 1);
for mu = 1:nMUs
    if ~isempty(fr_online{mu})
        mean_fr_online(mu) = mean(fr_online{mu});
    end
end

% Print formatted summary table
fprintf('\n=== Done ===\n')
fprintf('%-8s  %-10s  %-15s\n', 'MU', 'Spikes', 'Mean FR (Hz)')
fprintf('%s\n', repmat('-',1,38))
for mu = 1:nMUs
    fprintf('MU %-4d  %-10d  %.1f Hz\n', ...
        mu, length(Dischargetimes_online{mu}), mean_fr_online(mu))
end

fprintf('\nOutputs in workspace:\n')
fprintf('  Dischargetimes_online — spike indices per MU\n')
fprintf('  Pulsetrain_online     — full pulse train\n')
fprintf('  fr_online             — instantaneous firing rates\n')
fprintf('  mean_fr_online        — mean firing rate per MU\n\n')