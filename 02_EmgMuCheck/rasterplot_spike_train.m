%% Simple motor-unit raster plot using the older spike-train convention
%
% Uses results.spike_train and signal.fsamp from the workspace.

spikeTrain = Calib_data.spike_train;
fs =fs;
[nSamples,nMUs] = size(spikeTrain);
spikeCounts = zeros(1,nMUs);

figure('Color','w','Name','MU raster plot');
hold on;

for mu = 1:nMUs
    spikeSamples = find(spikeTrain(:,mu));
    spikeTimes = spikeSamples/fs;
    spikeCounts(mu) = numel(spikeSamples);

    plot(spikeTimes,mu*ones(size(spikeTimes)),'|', ...
        'MarkerSize',16,'LineWidth',1.5);
end

hold off;
grid on;
xlim([0 nSamples/fs]);
ylim([0.5 nMUs+0.5]);
yticks(1:nMUs);
yticklabels(arrayfun(@(mu) sprintf('MU%d (%d spikes)', ...
    mu,spikeCounts(mu)),1:nMUs,'UniformOutput',false));
xlabel('Time (s)');
ylabel('Motor unit');
title(sprintf('Motor-unit spike raster (%d total spikes)', ...
    sum(spikeCounts)));
