%% =========================================================================
% ULTIMATE RASTER PLOT FOR PSEUDO-ONLINE / OFFLINE RESULTS
%
% This script plots the selected time interval.
% Leave plot_start_sec and plot_stop_sec empty ([]) to plot the full
% available recording.
%
% It can read spikes from:
%   1. Dischargetimes_online  - cell array, one cell per MU, sample indices
%   2. Distime                - samples x MUs logical spike matrix
%   3. Calib_data.spike_train - samples x MUs logical spike matrix
%
% Optional force overlay:
%   recordedForce(:,2) is used as the force signal, matching the older
%   raster plot scripts in this folder.
% =========================================================================

%% USER SETTINGS
fs = 2000;                 % EMG sampling frequency in Hz
fs_force = 50;             % Force sampling frequency in Hz

plot_force_overlay = 0;    % 1 = plot force on raster, 0 = no force

plot_start_sec = [];       % Start time in seconds. [] = start at 0 s
plot_stop_sec = [];        % Stop time in seconds. [] = use full recording

plot_firing_rate = 0;      % 1 = add firing-rate subplot, 0 = raster only
fr_ylim = [0 60];          % Firing-rate y-axis limits in Hz

%% GET SPIKES
[spike_times_all, source_name, n_samples] = get_spike_times_from_workspace(fs);
n_MUs = numel(spike_times_all);

if n_MUs == 0
    error('No motor units found to plot.')
end

recording_stop_sec = n_samples / fs;

if isempty(plot_start_sec)
    plot_start_sec = 0;
end

if isempty(plot_stop_sec)
    plot_stop_sec = recording_stop_sec;
end

plot_start_sec = max(0, plot_start_sec);
plot_stop_sec = min(plot_stop_sec, recording_stop_sec);

if plot_stop_sec <= plot_start_sec
    error('plot_stop_sec must be greater than plot_start_sec.')
end

%% KEEP ONLY THE REQUESTED TIME INTERVAL
spike_times = cell(1, n_MUs);
n_spikes = zeros(1, n_MUs);
first_spike_sec = inf(1, n_MUs);

for mu = 1:n_MUs
    t = spike_times_all{mu};
    t = t(t >= plot_start_sec & t <= plot_stop_sec);

    spike_times{mu} = t(:).';
    n_spikes(mu) = numel(t);

    if ~isempty(t)
        first_spike_sec(mu) = t(1);
    end
end

% Always plot first-spiking MU first. MUs without spikes in the selected
% interval are placed at the bottom.
[~, mu_order] = sort(first_spike_sec, 'ascend');

%% PREPARE FORCE, IF REQUESTED
force_time = [];
force_signal = [];
force_available = false;

if plot_force_overlay
    if exist('recordedForce', 'var') ~= 1
        warning('recordedForce was not found. Plotting without force overlay.')
        plot_force_overlay = false;
    elseif size(recordedForce, 2) < 2
        warning('recordedForce does not have column 2. Plotting without force overlay.')
        plot_force_overlay = false;
    else
        force_signal = recordedForce(:, 2);
        force_signal = force_signal(:).';
        force_time = (0:numel(force_signal)-1) / fs_force;

        keep_force = force_time >= plot_start_sec & force_time <= plot_stop_sec;
        force_time = force_time(keep_force);
        force_signal = force_signal(keep_force);
        force_available = ~isempty(force_signal);

        if ~force_available
            warning('No force samples found in the selected time interval.')
            plot_force_overlay = false;
        end
    end
end

%% PLOT
colors = lines(n_MUs);

if plot_firing_rate
    figure_height = 760;
else
    figure_height = 470;
end

figure('Color', 'w', 'Position', [80 80 1350 figure_height], ...
    'Name', 'Ultimate raster plot');

if plot_firing_rate
    ax_raster = subplot(2, 1, 1);
else
    ax_raster = axes;
end

plot_raster_panel(ax_raster, spike_times, mu_order, n_spikes, colors, ...
    plot_start_sec, plot_stop_sec, plot_force_overlay, ...
    force_time, force_signal, source_name);

if plot_firing_rate
    ax_fr = subplot(2, 1, 2);
    plot_firing_rate_panel(ax_fr, spike_times, mu_order, colors, ...
        plot_start_sec, plot_stop_sec, fs, fr_ylim);
end

title_text = sprintf('Motor unit raster plot, %.2f to %.2f s | %s', ...
    plot_start_sec, plot_stop_sec, source_name);
sgtitle(title_text, 'FontSize', 12, 'FontWeight', 'bold', ...
    'Interpreter', 'none')

%% PRINT SUMMARY
summary_table = table( ...
    mu_order(:), ...
    n_spikes(mu_order(:)).', ...
    first_spike_sec(mu_order(:)).', ...
    'VariableNames', {'MU', 'Spike Count', 'First SpikeTime'});

disp(' ')
disp('=== Raster plot summary ===')
disp(summary_table)

%% LOCAL FUNCTIONS
function [spike_times, source_name, n_samples] = get_spike_times_from_workspace(fs)
% Choose the first available spike source in the current workspace.

if evalin('base', 'exist(''Dischargetimes_online'', ''var'') == 1')
    discharges = evalin('base', 'Dischargetimes_online');
    spike_times = cell(1, numel(discharges));

    for mu = 1:numel(discharges)
        samples = discharges{mu};
        samples = samples(:).';
        spike_times{mu} = samples / fs;
    end

    source_name = 'Dischargetimes_online';
    n_samples = get_recording_length_from_workspace(discharges);
    return
end

if evalin('base', 'exist(''Distime'', ''var'') == 1')
    spike_matrix = evalin('base', 'Distime');
    [n_samples, n_MUs] = size(spike_matrix);
    spike_times = spike_matrix_to_times(spike_matrix, fs, n_MUs);
    source_name = 'Distime';
    return
end

if evalin('base', 'exist(''Calib_data'', ''var'') == 1 && isfield(Calib_data, ''spike_train'')')
    spike_matrix = evalin('base', 'Calib_data.spike_train');
    [n_samples, n_MUs] = size(spike_matrix);
    spike_times = spike_matrix_to_times(spike_matrix, fs, n_MUs);
    source_name = 'Calib_data.spike_train';
    return
end

error(['No spike source found. Run pseudo-online decomposition first, ', ...
       'or load Calib_data.spike_train.'])
end

function n_samples = get_recording_length_from_workspace(discharges)
if evalin('base', 'exist(''Pulsetrain_online'', ''var'') == 1')
    n_samples = evalin('base', 'size(Pulsetrain_online, 2)');
    return
end

if evalin('base', 'exist(''Distime'', ''var'') == 1')
    n_samples = evalin('base', 'size(Distime, 1)');
    return
end

if evalin('base', 'exist(''recordedEMG'', ''var'') == 1')
    n_samples = evalin('base', 'size(recordedEMG, 2)');
    return
end

last_sample = 0;
for mu = 1:numel(discharges)
    if ~isempty(discharges{mu})
        last_sample = max(last_sample, max(discharges{mu}));
    end
end

n_samples = max(last_sample, 1);
end

function spike_times = spike_matrix_to_times(spike_matrix, fs, n_MUs)
spike_times = cell(1, n_MUs);

for mu = 1:n_MUs
    spike_idx = find(spike_matrix(:, mu));
    spike_times{mu} = spike_idx(:).' / fs;
end
end

function plot_raster_panel(ax, spike_times, mu_order, n_spikes, colors, ...
    plot_start_sec, plot_stop_sec, plot_force_overlay, ...
    force_time, force_signal, source_name)

n_MUs = numel(mu_order);
axes(ax)

if plot_force_overlay
    yyaxis(ax, 'left')
end

hold(ax, 'on')

for row = 1:n_MUs
    mu = mu_order(row);
    t = spike_times{mu};

    if isempty(t)
        continue
    end

    x_tick = [t; t; nan(size(t))];
    y_tick = [ ...
        (row - 0.4) * ones(size(t)); ...
        (row + 0.4) * ones(size(t)); ...
        nan(size(t))];

    plot(ax, x_tick(:), y_tick(:), ...
        'Color', colors(mu, :), ...
        'LineStyle', '-', ...
        'Marker', 'none', ...
        'LineWidth', 1.2)
end

hold(ax, 'off')

ylim(ax, [0.5 n_MUs + 0.5])
xlim(ax, [plot_start_sec plot_stop_sec])
yticks(ax, 1:n_MUs)
yticklabels(ax, make_mu_labels(mu_order, n_spikes))
xlabel(ax, 'Time (s)')
ylabel(ax, 'Motor unit')
title(ax, '')
grid(ax, 'on')
box(ax, 'on')

if plot_force_overlay
    force_min = min(force_signal);
    force_max = max(force_signal);

    if force_max == force_min
        force_scaled = ones(size(force_signal)) * 0.5;
        force_labels = force_min * ones(1, 5);
    else
        force_scaled = 0.5 + (force_signal - force_min) ./ ...
            (force_max - force_min) * n_MUs;
        force_labels = linspace(force_min, force_max, 5);
    end

    yyaxis(ax, 'left')
    hold(ax, 'on')
    plot(ax, force_time, force_scaled, 'k-', ...
        'LineStyle', '-', ...
        'Marker', 'none', ...
        'LineWidth', 1.4)
    hold(ax, 'off')

    yyaxis(ax, 'right')
    ylim(ax, [0.5 n_MUs + 0.5])
    yticks(ax, linspace(0.5, n_MUs + 0.5, 5))
    yticklabels(ax, arrayfun(@(x) sprintf('%.2f', x), ...
        force_labels, 'UniformOutput', false))
    ylabel(ax, 'Force')
    set(ax, 'YColor', 'k')
    yyaxis(ax, 'left')
end
end

function labels = make_mu_labels(mu_order, n_spikes)
labels = cell(1, numel(mu_order));

for row = 1:numel(mu_order)
    mu = mu_order(row);
    labels{row} = sprintf('MU%d  (%d spikes)', mu, n_spikes(mu));
end
end

function plot_firing_rate_panel(ax, spike_times, mu_order, colors, ...
    plot_start_sec, plot_stop_sec, fs, fr_ylim)

hold(ax, 'on')

for row = 1:numel(mu_order)
    mu = mu_order(row);
    t = spike_times{mu};

    if numel(t) < 2
        continue
    end

    isi = diff(t);
    fr = 1 ./ isi;
    fr_time = t(1:end-1) + isi / 2;

    plot(ax, fr_time, fr, '.', ...
        'Color', colors(mu, :), ...
        'MarkerSize', 8, ...
        'DisplayName', sprintf('MU%d', mu))
end

hold(ax, 'off')
xlim(ax, [plot_start_sec plot_stop_sec])
ylim(ax, fr_ylim)
xlabel(ax, 'Time (s)')
ylabel(ax, 'Firing rate (Hz)')
title(ax, 'Instantaneous firing rate')
grid(ax, 'on')
box(ax, 'on')
legend(ax, 'Location', 'eastoutside', 'FontSize', 7)

if nargin > 6 && fs <= 0
    error('fs must be positive.')
end
end
