%% ===== COMBINED RASTER + FIRING RATE PLOT =====


data  = Calib_data;
fs    = 2000;

% --- Extract spike train ---
spike_train         = data.spike_train;
[n_samples, n_MUs]  = size(spike_train);
t_total             = n_samples / fs;

% --- Get spike times per MU ---
spike_times = cell(1, n_MUs);
n_spikes    = zeros(1, n_MUs);
for mu = 1:n_MUs
    idx             = find(spike_train(:, mu));
    spike_times{mu} = idx(:)' / fs;
    n_spikes(mu)    = numel(idx);
end

% -------------------------------------------------------
%% COMBINED FIGURE: Raster (top) + Firing Rate (bottom)
figure('Color','w','Position',[100 100 1200 600]);
colors = lines(n_MUs);

% --- TOP: Raster Plot ---
subplot(2,1,1);
hold on;

for mu = 1:n_MUs
    t = spike_times{mu};
    if isempty(t), continue; end
    plot([t; t], repmat([mu-0.4; mu+0.4], 1, numel(t)), ...
        'Color', colors(mu,:), 'LineWidth', 1.2);
end

% Write number of spikes next to each MU label on the right
for mu = 1:n_MUs
    text(t_total * 1.01, mu, sprintf('%d spikes', n_spikes(mu)), ...
        'Color', colors(mu,:), 'FontSize', 9, 'VerticalAlignment', 'middle');
end

yticks(1:n_MUs);
yticklabels(arrayfun(@(x) sprintf('MU %d', x), 1:n_MUs, 'UniformOutput', false));
xlabel('Time (s)');
ylabel('Motor Unit');
title('Raster Plot — Motor Unit Spike Trains');
xlim([0 t_total * 1.15]);   % extra space for spike count labels
ylim([0.5 n_MUs + 0.5]);
grid on; box on;

% --- BOTTOM: Instantaneous Firing Rate ---
subplot(2,1,2);
hold on;

for mu = 1:n_MUs
    t = spike_times{mu};
    if numel(t) < 2, continue; end
    isi  = diff(t);
    ifr  = 1 ./ isi;
    t_fr = t(1:end-1) + isi/2;
    plot(t_fr, ifr, 'Color', colors(mu,:), 'LineWidth', 1.5, ...
        'DisplayName', sprintf('MU %d  (%d spikes)', mu, n_spikes(mu)));
end

xlabel('Time (s)');
ylabel('Firing Rate (pps)');
title('Instantaneous Firing Rate per Motor Unit');
xlim([0 t_total]);
legend('Location','northeast','FontSize',9);
grid on; box on;

sgtitle('Motor Unit Spike Train Analysis', 'FontSize', 14, 'FontWeight', 'bold');