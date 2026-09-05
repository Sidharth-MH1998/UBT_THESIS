% PSEUDO-ONLINE EMG DECOMPOSITION WITH OPTIONAL FORCE OVERLAY
%
% OUTPUTS saved to workspace after running:
%   Dischargetimes_online : cell (1 x nMUs) — spike indices per MU
%   Pulsetrain_online     : (nMUs x nSamples) — full pulse train
%   fr_online             : cell (1 x nMUs) — instantaneous firing rates
%   mean_fr_online        : (nMUs x 1) — mean firing rate per MU

%% User settings
fs         = 2000;   % EMG sampling frequency (Hz)
fs_force   = 50;     % force sampling frequency (Hz)
display_force = true; % true = force overlay, false = EMG/MU plots only
badchan    = [];     % manually specify bad channels e.g. [5 23 41]
window_sec = 0.125;  % window duration in seconds

%% Load calibration file
fprintf('Select the calibration decomposition .mat file...\n')
[calib_fname, calib_fpath] = uigetfile('*.mat', ...
    'Select calibration file containing recordedEMG and Calib_data');

if isequal(calib_fname, 0)
    error('No calibration file selected. Aborting.')
end

calibration = load(fullfile(calib_fpath, calib_fname), ...
    'recordedEMG', 'Calib_data');

if ~isfield(calibration, 'recordedEMG')
    error('Variable ''recordedEMG'' not found in calibration file: %s', calib_fname)
end
if ~isfield(calibration, 'Calib_data')
    error('Variable ''Calib_data'' not found in calibration file: %s', calib_fname)
end

recordedEMG = calibration.recordedEMG;
Calib_data = calibration.Calib_data;
fprintf('Loaded calibration file: %s\n', calib_fname)

fprintf('\n=== Pseudo-Online EMG Decomposition ===\n')

%% Build channel mask

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

%% Load filters

MUFilters = Calib_data.MUFilters;
nMUs      = size(MUFilters, 2);

if nMUs == 0
    error('No MU filters found in Calib_data. Check decomposition quality.')
end

fprintf('Calibration: %d MUs loaded from Calib_data\n\n', nMUs)

%% Compute online parameters

fprintf('Computing online parameters on calibration signal...\n')

[extensionfactor, iReSIG, norm_fac, centroid] = getonlineparameters(recordedEMG, EMGmask, MUFilters, fs);

% Precompute online filter
MUfilt = MUFilters' * iReSIG;

fprintf('Online parameters ready. %d MUs loaded.\n\n', nMUs)

%% Load the trial via uigetfile

fprintf('Select the new sample .mat file...\n')
[fname, fpath] = uigetfile(fullfile(calib_fpath, '*.mat'), ...
    'Select new EMG trial for pseudo-online decomposition');

if isequal(fname, 0)
    error('No file selected. Aborting.')
end

if display_force
    newdata = load(fullfile(fpath, fname), 'recordedEMG', 'recordedForce');
else
    newdata = load(fullfile(fpath, fname), 'recordedEMG');
end

if ~isfield(newdata, 'recordedEMG')
    error('Variable ''recordedEMG'' not found in selected file: %s', fname)
end

if display_force && ~isfield(newdata, 'recordedForce')
    error('Variable ''recordedForce'' not found in selected file: %s', fname)
end

newEMG = newdata.recordedEMG;

if display_force
    % Force from 2nd column
    if size(newdata.recordedForce,2) < 2
        error('recordedForce does not contain a 2nd column in file: %s', fname)
    end
    force_signal = newdata.recordedForce(:,2);
    force_signal = force_signal(:).';
end

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

if display_force
    % Resample force to the EMG timeline
    t_emg   = (0:total_samples-1) / fs;
    t_force = (0:length(force_signal)-1) / fs_force;
    force_signal_resampled = interp1(t_force, force_signal, t_emg, 'linear', 'extrap');
end

fprintf('Loaded: %s\n', fname)
fprintf('Duration: %.1f sec | Windows: %d | Chunk: %d samples\n\n', ...
    total_duration, nwin, window_samples)

%% Allocate outputs

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

%% Setup figure

colors = lines(nMUs);

fig = figure('Color','w', 'Position',[50 50 1400 800], ...
    'Name', sprintf('Pseudo-Online Decomposition — %s', fname));

%--- Top panel: raster plot with optional force overlay
ax_raster = subplot(2,1,1);

if display_force
    yyaxis(ax_raster, 'left')
    raster_title = 'Real-Time Spike Trains + Force';
else
    raster_title = 'Real-Time Spike Trains';
end
hold(ax_raster, 'on')
title(ax_raster, raster_title, 'FontSize',11)
xlabel(ax_raster, 'Time (s)')
ylabel(ax_raster, 'Motor Unit')
xlim(ax_raster, [0 total_duration])
ylim(ax_raster, [0 nMUs+1])
yticks(ax_raster, 1:nMUs)
yticklabels(ax_raster, arrayfun(@(x) sprintf('MU%d  (0 spikes)',x), ...
    1:nMUs, 'UniformOutput',false))
grid(ax_raster, 'on')
set(ax_raster, 'FontSize', 9)

if display_force
    yyaxis(ax_raster, 'right')
    ylabel(ax_raster, 'Force')
    force_min = min(force_signal_resampled);
    force_max = max(force_signal_resampled);
    if force_min == force_max
        force_max = force_min + 1;
    end
    ylim(ax_raster, [force_min force_max])
end

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
if display_force
    yyaxis(ax_raster, 'left')
end
h_raster = gobjects(nMUs, 1);
for mu = 1:nMUs
    h_raster(mu) = plot(ax_raster, nan, nan, '|', ...
        'Color', colors(mu,:), 'MarkerSize',10, 'LineWidth',1.5);
end

if display_force
    % Force handle on right axis
    yyaxis(ax_raster, 'right')
    h_force = plot(ax_raster, nan, nan, 'k-', 'LineWidth',1.5);
end

h_fr = gobjects(nMUs, 1);
for mu = 1:nMUs
    h_fr(mu) = plot(ax_fr, nan, nan, '.', ...
        'Color', colors(mu,:), 'MarkerSize',4, ...
        'DisplayName', sprintf('MU%d',mu));
end
legend(ax_fr, 'Location','eastoutside', 'FontSize',6)

% Moving time indicator lines
if display_force
    yyaxis(ax_raster, 'left')
end
tline_raster = xline(ax_raster, 0, 'r--', 'LineWidth',1.5);
tline_fr     = xline(ax_fr,     0, 'r--', 'LineWidth',1.5);

%% Pseudo-online loop

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
    [Pulsetrain_online(:,start_idx:end_idx),Distime(start_idx:end_idx,:),esample2] = getspikesonline(EMGtmp2, extensionfactor, esample2, ...
                                 MUfilt, norm_fac, noise_centroids,spike_centroids, window_samples, fs);

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
    if display_force
        yyaxis(ax_raster, 'left')
    end
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

    if display_force
        %--- Update force trace on right axis
        yyaxis(ax_raster, 'right')
        force_t = (1:end_idx) / fs;
        set(h_force, ...
            'XData', force_t, ...
            'YData', force_signal_resampled(1:end_idx))
    end

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
    if display_force
        yyaxis(ax_raster, 'left')
    end
    set(tline_raster, 'Value', current_time)
    set(tline_fr,     'Value', current_time)

    %--- Update title
    title(ax_raster, sprintf('%s  |  t = %.2f / %.2f sec  |  %s', ...
        raster_title, current_time, total_duration, fname), 'FontSize',10)

    %--- Refresh display
    drawnow limitrate

end

%% Produce summary

if display_force
    yyaxis(ax_raster, 'left')
end
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

