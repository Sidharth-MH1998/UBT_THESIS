%% ===== RASTER ORDERED BY RECRUITMENT THRESHOLD + FORCE IN FRONT =====

data = Calib_data;

fs = 2000;
fs_force = 50;

spike_train = data.spike_train;
[n_samples, n_MUs] = size(spike_train);

t_total = n_samples / fs;

%% --- Force signal ---
force = recordedForce(:, 2);
t_force = (0:length(force)-1) / fs_force;

%% --- Spike times, spike counts, and recruitment thresholds ---
spike_times = cell(1, n_MUs);
n_spikes = zeros(1, n_MUs);
recruitment_threshold = nan(1, n_MUs);

for mu = 1:n_MUs

    spike_index = find(spike_train(:, mu));
    n_spikes(mu) = length(spike_index);

    if isempty(spike_index)
        continue
    end

    spike_times{mu} = spike_index / fs;

    first_spike_time = spike_times{mu}(1);

    [~, force_index] = min(abs(t_force - first_spike_time));

    recruitment_threshold(mu) = force(force_index);

end

%% --- Sort MUs by recruitment threshold ---
[~, mu_order] = sort(recruitment_threshold);

%% --- Scale force to raster y-axis ---
force_min = min(force);
force_max = max(force);

force_scaled = 0.5 + ...
    (force - force_min) / (force_max - force_min) * n_MUs;

%% --- Plot ---
figure('Color','w','Position',[100 100 1300 650]);
hold on;

colors = lines(n_MUs);

%% --- Plot raster spikes first ---
for row = 1:n_MUs

    mu = mu_order(row);
    t_spikes = spike_times{mu};

    if isempty(t_spikes)
        continue
    end

    for s = 1:length(t_spikes)
        plot([t_spikes(s) t_spikes(s)], ...
             [row-0.35 row+0.35], ...
             'Color', colors(mu,:), ...
             'LineWidth', 1.1);
    end

end

%% --- Plot force after raster, so it appears in front ---
%plot(t_force, force_scaled, 'k', 'LineWidth', 2.0);

%% --- Add number of spikes on right side ---
for row = 1:n_MUs

    mu = mu_order(row);

    text(t_total * 1.01, row, ...
        sprintf('%d spikes', n_spikes(mu)), ...
        'Color', colors(mu,:), ...
        'FontSize', 9, ...
        'VerticalAlignment', 'middle');

end

%% --- Left y-axis: MUs ordered by recruitment threshold ---
yyaxis left

yticks(1:n_MUs);

y_labels = cell(1, n_MUs);

for row = 1:n_MUs

    mu = mu_order(row);

    y_labels{row} = sprintf('MU %d  RT %.1f', ...
        mu, recruitment_threshold(mu));

end

yticklabels(y_labels);

ylabel('Motor Units ordered by recruitment threshold');
ylim([0.5 n_MUs + 0.5]);

%% --- Right y-axis: true force values ---
yyaxis right

force_ticks = linspace(force_min, force_max, 5);

scaled_force_ticks = 0.5 + ...
    (force_ticks - force_min) / (force_max - force_min) * n_MUs;

yticks(scaled_force_ticks);
yticklabels(arrayfun(@(x) sprintf('%.1f', x), force_ticks, ...
    'UniformOutput', false));

ylabel('Force');
ylim([0.5 n_MUs + 0.5]);
set(gca, 'YColor', 'k');

%% --- Final formatting ---
yyaxis left

xlabel('Time (s)');
title('MU Raster Plot ');

xlim([0 t_total * 1.15]);

grid on;
box on;
