% Simple 3-iteration visualisation of the CoV-ISI update:
%   w = sum(X(:, spikes), 2)
%
% The plot shows how the detected peaks and CoV of ISI change over 3
% updates after the first FastICA candidate.

%% Parameters, same style as your offline calibration script
if exist('trimmedEMG', 'var')
    EMG = trimmedEMG;
elseif exist('recordedEMG', 'var')
    EMG = recordedEMG;
else
    load('demo_covisi_update.mat', 'EMG', 'fs');
end

if ~exist('fs', 'var')
    fs = 2000;
end
badchan = [];
padLen = 200;
initialization = 0;
NITER = 50;
nChannels = size(EMG, 1);
extfactor = 8;
nbextchan = nChannels * extfactor;
differentialmode = 0;
contrastfunc = 'skew';
preproc_flag = 1;
nIterations = 3;
durationSeconds = 10;

addpath('offline_decomp_renato/lib');
addpath('offline_decomp_renato/my_funcs');

EMG = EMG(:, 1:min(durationSeconds * fs, size(EMG, 2)));

%% Preprocess like decompose3.m
if preproc_flag
    EMG = adaptiveNotchFilter(EMG, fs);
    EMG = bandpassingals(EMG, fs, 1);
end

if ~isempty(badchan)
    goodchan = setdiff(1:size(EMG, 1), badchan);
    EMG = EMG(goodchan, :);
end

if padLen > 0
    EMG = [zeros(size(EMG, 1), padLen), EMG, zeros(size(EMG, 1), padLen)];
end

if differentialmode
    EMG = diff(EMG, 1, 2);
end

%% Extend, demean, whiten
exFactor = round(nbextchan / size(EMG, 1));
eSIG = extend(EMG, exFactor);
eSIG = demean(eSIG);

[E, D] = pcaesig(eSIG);
[X, ~, ~] = whiteesig(eSIG, E, D);

%% First FastICA candidate
B = zeros(size(X, 1), NITER);

if initialization == 0
    actind = sum(X, 1).^2;
    [~, idx1] = max(actind);
    w = X(:, idx1);
else
    rng(1);
    w = randn(size(X, 1), 1);
end

w = w - B * B' * w;
w = w / norm(w);
w = fixedpointalg(w, X, B, 500, contrastfunc);

%% Visualise 3 CoV-ISI update iterations
time = (0:size(X, 2)-1) / fs;
covValues = nan(1, nIterations);
spikeCounts = zeros(1, nIterations);

figure;

for iter = 1:nIterations
    [pulseTrain, spikes] = getspikes(w, X, fs);

    if length(spikes) > 1
        ISI = diff(spikes / fs);
        covValues(iter) = std(ISI) / mean(ISI);
    end
    spikeCounts(iter) = length(spikes);

    subplot(nIterations, 1, iter);
    plot(time, pulseTrain, 'b');
    hold on;
    plot(time(spikes), pulseTrain(spikes), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 4);
    hold off;
    grid on;
    title(sprintf('Iteration %d: spikes = %d, CoV ISI = %.3f', ...
        iter, spikeCounts(iter), covValues(iter)));
    xlabel('Time (s)');
    ylabel('Pulse');

    fprintf('Iteration %d: spikes = %d, CoV ISI = %.4f\n', ...
        iter, spikeCounts(iter), covValues(iter));

    if isempty(spikes)
        warning('No spikes detected at iteration %d. Stopping update.', iter);
        break;
    end

    % Main update: rebuild w from whitened EMG columns at detected spikes.
    w = sum(X(:, spikes), 2);
    w = w / norm(w);
end

sgtitle('Offline-style CoV-ISI update visualisation');

figure;
plot(1:nIterations, covValues, 'o-', 'LineWidth', 1.5);
grid on;
title('CoV ISI over 3 updates');
xlabel('Iteration');
ylabel('CoV ISI');
