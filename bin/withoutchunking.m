%% Apply MUFilters to full recorded EMG and compare spike counts

fs      = 2000;
badchan = [];
EMGmask = zeros(size(recordedEMG,1), 1);
EMGmask(badchan) = 1;

MUFilters = Calib_data.MUFilters;
nMUs      = size(MUFilters, 2);

%% Step 1: Extend and preprocess full signal
fprintf('Preprocessing full signal...\n')
EMG_good    = recordedEMG(EMGmask==0, :);          % good channels only
exFactor    = round(1024 / size(EMG_good,1));
eSIG_full   = demean(extend(EMG_good, exFactor));   % extend + demean

fprintf('EMG size:      %d x %d\n', size(EMG_good))
fprintf('Extended size: %d x %d\n', size(eSIG_full))

%% Step 2: Apply MUFilters via iReSIG (same as online)
fprintf('Applying MUFilters to full signal...\n')
ReSIG   = eSIG_full * eSIG_full' / size(eSIG_full,2);
iReSIG  = pinv(ReSIG);
MUfilt  = MUFilters' * iReSIG;                      % (nMUs x nExtChan)

%% Step 3: Get pulse train and spikes for each MU
Dischargetimes_full = cell(1, nMUs);

for mu = 1:nMUs
    % Project full signal
    pt = MUfilt(mu,:) * eSIG_full;                  % 1 x nSamples
    pt = pt(1:size(EMG_good,2));                     % trim to original length
    pt = pt .* abs(pt);                              % square with sign

    % Normalize
    [~, spikes_tmp] = findpeaks(pt, 'MinPeakDistance', round(fs*0.02));

    if length(spikes_tmp) > 2
        norm_val = mean(maxk(pt(spikes_tmp), 10));
        pt       = pt / norm_val;

        % KMeans to separate spikes from noise
        [L, C] = kmeans(pt(spikes_tmp)', 2);
        [~, idx] = max(C);
        spikes = spikes_tmp(L == idx);

        % Remove outliers
        spikes(pt(spikes) > mean(pt(spikes)) + 3*std(pt(spikes))) = [];

        Dischargetimes_full{mu} = spikes;
    else
        Dischargetimes_full{mu} = spikes_tmp;
    end
end

%% Step 4: Compare spike counts
fprintf('\n=== Spike Count Comparison ===\n')
fprintf('%-6s %-12s %-12s %-10s\n', 'MU', 'Calib', 'Full EMG', 'Diff(%)')
fprintf('%s\n', repmat('-',1,45))

for mu = 1:nMUs
    n_calib = length(Calib_data.MUPulses{mu});
    n_full  = length(Dischargetimes_full{mu});
    diff_pct = 100 * (n_full - n_calib) / n_calib;
    fprintf('%-6d %-12d %-12d %-10.1f\n', mu, n_calib, n_full, diff_pct)
end

%% Step 5: Plot raster comparison
figure('Color','w', 'Position',[50 50 1400 600]);
time = linspace(0, size(EMG_good,2)/fs, size(EMG_good,2));

ax = axes;
hold on
for mu = 1:nMUs
    % Calib (offline) — green
    off_t = Calib_data.MUPulses{mu} / fs;
    plot(off_t, mu*ones(size(off_t))+0.3, '|', ...
        'Color',[0.18 0.72 0.18], 'MarkerSize',8, 'LineWidth',1.2)
    % Full EMG application — blue
    full_t = Dischargetimes_full{mu} / fs;
    plot(full_t, mu*ones(size(full_t)), '|', ...
        'Color',[0.20 0.45 0.90], 'MarkerSize',6, 'LineWidth',0.8)
end
plot(nan, nan, '|', 'Color',[0.18 0.72 0.18], 'DisplayName','Calib (offline)')
plot(nan, nan, '|', 'Color',[0.20 0.45 0.90], 'DisplayName','Full EMG')
legend('Location','northeast','FontSize',8)
title('MUFilters applied to full EMG vs Calib discharge times','FontSize',11)
xlabel('Time (s)'); ylabel('Motor Unit #')
yticks(1:nMUs)
yticklabels(arrayfun(@(x) sprintf('MU%d',x), 1:nMUs, 'UniformOutput',false))
xlim([0 size(EMG_good,2)/fs]); ylim([0 nMUs+1])
grid on