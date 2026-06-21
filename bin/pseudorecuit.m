%% =========================================================================
% PSEUDO-ONLINE EMG DECOMPOSITION + FORCE OVERLAY
%
% MUs are plotted according to recruitment threshold.
% Recruitment threshold = force value at first detected spike of each MU.
%
% OUTPUTS saved to workspace after running:
%   Dischargetimes_online : cell (1 x nMUs) — spike indices per MU
%   Pulsetrain_online     : (nMUs x nSamples) — full pulse train
%   fr_online             : cell (1 x nMUs) — instantaneous firing rates
%   mean_fr_online        : (nMUs x 1) — mean firing rate per MU
%   recruitment_threshold_online : force at first spike per MU
% =========================================================================

%% =========================================================================
%  SECTION 1: PARAMETERS
% =========================================================================

fs         = 2000;
fs_force   = 50;
badchan    = [];
window_sec = 0.125;

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
%  SECTION 5: COMPUTE ONLINE PARAMETERS
% =========================================================================

fprintf('Computing online parameters on calibration signal...\n')

[extensionfactor, iReSIG, norm_fac, centroid] = getonlineparameters( ...
    recordedEMG, EMGmask, MUFilters, fs);

MUfilt = MUFilters' * iReSIG;

fprintf('Online parameters ready. %d MUs loaded.\n\n', nMUs)

%% =========================================================================
%  SECTION 6: LOAD NEW TRIAL
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

if size(newdata.recordedForce,2) < 2
    error('recordedForce does not contain a 2nd column in file: %s', fname)
end

force_signal = newdata.recordedForce(:,2);
force_signal = force_signal(:).';

if size(newEMG,1) ~= size(recordedEMG,1)
    error('Channel mismatch: calibration has %d channels, new file has %d.', ...
        size(recordedEMG,1), size(newEMG,1))
end

window_samples = round(window_sec * fs);
assert(window_samples >= 2, 'window_sec too small.')

total_samples  = size(newEMG, 2);
nwin           = floor(total_samples / window_samples);
total_duration = total_samples / fs;

if nwin < 1
    error('Selected file is shorter than one analysis window.')
end

noise_centroids = ones(window_samples, nMUs) .* (centroid(:,1)');
spike_centroids = ones(window_samples, nMUs) .* (centroid(:,2)');

t_emg   = (0:total_samples-1) / fs;
t_force = (0:length(force_signal)-1) / fs_force;

force_signal_resampled = interp1(t_force, force_signal, ...
    t_emg, 'linear', 'extrap');

fprintf('Loaded: %s\n', fname)
fprintf('Duration: %.1f sec | Windows: %d | Chunk: %d samples\n\n', ...
    total_duration, nwin, window_samples)

%% =========================================================================
%  SECTION 7: PREALLOCATE OUTPUTS
% =========================================================================

esample2 = zeros(nGoodChan * extensionfactor, extensionfactor-1);

Pulsetrain_online = zeros(nMUs, nwin * window_samples);
Distime           = false(nwin * window_samples, nMUs);

Dischargetimes_online = cell(1, nMUs);
fr_online             = cell(1, nMUs);

for mu = 1:nMUs
    Dischargetimes_online{mu} = [];
    fr_online{mu}             = [];
end

% Recruitment threshold is updated when each MU fires first
recruitment_threshold_online = nan(nMUs, 1);

% Initial plotting order before recruitment is known
mu_order = 1:nMUs;

%% =========================================================================
%  SECTION 8: SETUP LIVE FIGURE
% =========================================================================

colors = lines(nMUs);

fig = figure('Color','w', 'Position',[50 50 1400 800], ...
    'Name', sprintf('Pseudo-Online Decomposition — %s', fname));

%% --- Top panel: raster plot + force overlay
ax_raster = subplot(2,1,1);

yyaxis(ax_raster, 'left')
hold(ax_raster, 'on')
title(ax_raster, 'Real-Time Spike Trains + Force', 'FontSize',11)
xlabel(ax_raster, 'Time (s)')
ylabel(ax_raster, 'Motor Unit ordered by recruitment threshold')
xlim(ax_raster, [0 total_duration])
ylim(ax_raster, [0 nMUs+1])
yticks(ax_raster, 1:nMUs)
yticklabels(ax_raster, arrayfun(@(x) sprintf('MU%d  RT --  (0 spikes)',x), ...
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

%% --- Bottom panel: instantaneous firing rate
ax_fr = subplot(2,1,2);
hold(ax_fr, 'on')
title(ax_fr, 'Instantaneous Firing Rate ordered by recruitment threshold', ...
    'FontSize',11)
xlabel(ax_fr, 'Time (s)')
ylabel(ax_fr, 'Firing Rate (Hz)')
xlim(ax_fr, [0 total_duration])
ylim(ax_fr, [0 60])
grid(ax_fr, 'on')
set(ax_fr, 'FontSize', 9)

%% --- One raster handle per MU
yyaxis(ax_raster, 'left')

h_raster = gobjects(nMUs, 1);

for mu = 1:nMUs
    h_raster(mu) = plot(ax_raster, nan, nan, '|', ...
        'Color', colors(mu,:), ...
        'MarkerSize',10, ...
        'LineWidth',1.5);
end

%% --- Force handle
yyaxis(ax_raster, 'right')
h_force = plot(ax_raster, nan, nan, 'k-', 'LineWidth',1.5);

%% --- One firing-rate handle per MU
h_fr = gobjects(nMUs, 1);

for mu = 1:nMUs
    h_fr(mu) = plot(ax_fr, nan, nan, '.', ...
        'Color', colors(mu,:), ...
        'MarkerSize',4, ...
        'DisplayName', sprintf('MU%d',mu));
end

legend(ax_fr, 'Location','eastoutside', 'FontSize',6)

%% --- Moving time indicator
yyaxis(ax_raster, 'left')
tline_raster = xline(ax_raster, 0, 'r--', 'LineWidth',1.5);
tline_fr     = xline(ax_fr,     0, 'r--', 'LineWidth',1.5);

%% =========================================================================
%  SECTION 9: PSEUDO-ONLINE LOOP
% =========================================================================

fprintf('Starting real-time loop on new sample...\n\n')

for k = 1:nwin

    start_idx    = (k-1)*window_samples + 1;
    end_idx      =  k   *window_samples;
    current_time =  end_idx / fs;

    EMGtmp1 = newEMG(:, start_idx:end_idx);
    EMGtmp2 = EMGtmp1(EMGmask==0, :);

    [Pulsetrain_online(:,start_idx:end_idx), ...
     Distime(start_idx:end_idx,:), ...
     esample2] = getspikesonline(EMGtmp2, extensionfactor, esample2, ...
                                 MUfilt, norm_fac, noise_centroids, ...
                                 spike_centroids, window_samples, fs);

    %% --- Accumulate spike times, firing rates, and recruitment thresholds
    for mu = 1:nMUs

        new_spikes = find(Distime(start_idx:end_idx, mu)) + start_idx - 1;

        if ~isempty(new_spikes)

            Dischargetimes_online{mu} = ...
                [Dischargetimes_online{mu}; new_spikes];

            % First detected spike gives recruitment threshold
            if isnan(recruitment_threshold_online(mu))
                first_spike_idx = new_spikes(1);
                recruitment_threshold_online(mu) = ...
                    force_signal_resampled(first_spike_idx);
            end

        end

        if length(Dischargetimes_online{mu}) > 1
            fr_online{mu} = 1 ./ ...
                (diff(Dischargetimes_online{mu}) / fs);
        end

    end

    %% --- Sort MUs by recruitment threshold
    % MUs that have not fired yet stay at the bottom temporarily
    sort_values = recruitment_threshold_online;
    sort_values(isnan(sort_values)) = inf;

    [~, mu_order] = sort(sort_values);

    %% --- Update raster plot using sorted rows
    yyaxis(ax_raster, 'left')

    for row = 1:nMUs

        mu = mu_order(row);

        if ~isempty(Dischargetimes_online{mu})

            spikes_t = Dischargetimes_online{mu} / fs;

            set(h_raster(mu), ...
                'XData', spikes_t, ...
                'YData', row * ones(size(spikes_t)))

        end

    end

    %% --- Update y-axis labels with sorted MU order
    label_text = cell(1, nMUs);

    for row = 1:nMUs

        mu = mu_order(row);

        if isnan(recruitment_threshold_online(mu))
            label_text{row} = sprintf('MU%d  RT --  (%d spikes)', ...
                mu, length(Dischargetimes_online{mu}));
        else
            label_text{row} = sprintf('MU%d  RT %.1f  (%d spikes)', ...
                mu, recruitment_threshold_online(mu), ...
                length(Dischargetimes_online{mu}));
        end

    end

    yticklabels(ax_raster, label_text)

    %% --- Update force trace
    yyaxis(ax_raster, 'right')

    force_t = (1:end_idx) / fs;

    set(h_force, ...
        'XData', force_t, ...
        'YData', force_signal_resampled(1:end_idx))

    %% --- Update firing rate plot
    for row = 1:nMUs

        mu = mu_order(row);

        if length(Dischargetimes_online{mu}) > 1

            spike_times_fr = Dischargetimes_online{mu}(1:end-1) / fs;

            set(h_fr(mu), ...
                'XData', spike_times_fr, ...
                'YData', fr_online{mu}, ...
                'DisplayName', sprintf('MU%d  RT %.1f', ...
                mu, recruitment_threshold_online(mu)))

        end

    end

    legend(ax_fr, 'Location','eastoutside', 'FontSize',6)

    %% --- Advance time indicator
    yyaxis(ax_raster, 'left')

    set(tline_raster, 'Value', current_time)
    set(tline_fr,     'Value', current_time)

    title(ax_raster, ...
        sprintf('Real-Time Spike Trains + Force  |  t = %.2f / %.2f sec  |  %s', ...
        current_time, total_duration, fname), ...
        'FontSize',10)

    drawnow limitrate

end

%% =========================================================================
%  SECTION 10: FINALIZE AND SUMMARIZE
% =========================================================================

yyaxis(ax_raster, 'left')

title(ax_raster, sprintf('Done  |  %d MUs  |  %.1f sec  |  %s', ...
    nMUs, total_duration, fname), 'FontSize',11)

mean_fr_online = zeros(nMUs, 1);

for mu = 1:nMUs
    if ~isempty(fr_online{mu})
        mean_fr_online(mu) = mean(fr_online{mu});
    end
end

%% --- Final MU order by recruitment threshold
sort_values = recruitment_threshold_online;
sort_values(isnan(sort_values)) = inf;
[~, mu_order] = sort(sort_values);

fprintf('\n=== Done ===\n')
fprintf('%-8s  %-10s  %-15s  %-15s\n', ...
    'MU', 'Spikes', 'Mean FR (Hz)', 'Rec Threshold')
fprintf('%s\n', repmat('-',1,58))

for row = 1:nMUs

    mu = mu_order(row);

    fprintf('MU %-4d  %-10d  %-15.1f  %-15.2f\n', ...
        mu, ...
        length(Dischargetimes_online{mu}), ...
        mean_fr_online(mu), ...
        recruitment_threshold_online(mu))

end

fprintf('\nOutputs in workspace:\n')
fprintf('  Dischargetimes_online          — spike indices per MU\n')
fprintf('  Pulsetrain_online              — full pulse train\n')
fprintf('  fr_online                      — instantaneous firing rates\n')
fprintf('  mean_fr_online                 — mean firing rate per MU\n')
fprintf('  recruitment_threshold_online   — force at first spike per MU\n\n')
