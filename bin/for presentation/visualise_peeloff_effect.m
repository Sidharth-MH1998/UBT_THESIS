% Visualise the effect of peel-off in the offline decomposition pipeline.
%
% Peel-off removes the contribution of an accepted motor unit from the
% whitened signal X:
%   X_after = peeloff(X_before, spikes, fs, peeloffwin)
%
% This script shows:
%   1. Pulse train from the same MU filter before and after peel-off
%   2. A whitened component before and after peel-off
%   3. Zoom around one detected spike

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
peeloffwin = 0.025;
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

%% Find one candidate MU filter, like the first FastICA iteration
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

[pulseBefore, spikes] = getspikes(w, X, fs);

if isempty(spikes)
    error('No spikes detected. Try another recording or longer durationSeconds.');
end

%% Apply peel-off
Xpeeled = peeloff(X, spikes, fs, peeloffwin);
pulseAfter = (w' * Xpeeled) .* abs(w' * Xpeeled);
pulseAfter = pulseAfter / mean(maxk(abs(pulseBefore), min(10, length(pulseBefore))));

% Show a component where this MU filter has a strong weight.
[~, componentToShow] = max(abs(w));

time = (0:size(X, 2)-1) / fs;

%% Figure 1: same MU filter before and after peel-off
figure;

subplot(2, 1, 1);
plot(time, pulseBefore, 'b');
hold on;
plot(time(spikes), pulseBefore(spikes), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 4);
hold off;
grid on;
title(sprintf('Before peel-off: candidate pulse train, spikes = %d', length(spikes)));
xlabel('Time (s)');
ylabel('Pulse');

subplot(2, 1, 2);
plot(time, pulseAfter, 'k');
hold on;
plot(time(spikes), pulseAfter(spikes), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 4);
hold off;
grid on;
title('After peel-off: same filter projected on residual X');
xlabel('Time (s)');
ylabel('Residual pulse');

sgtitle('Peel-off reduces the already-detected MU contribution');

%% Figure 2: whitened component before and after peel-off
figure;

subplot(2, 1, 1);
plot(time, X(componentToShow, :), 'b');
grid on;
title(sprintf('Whitened component %d before peel-off', componentToShow));
xlabel('Time (s)');
ylabel('Amplitude');

subplot(2, 1, 2);
plot(time, Xpeeled(componentToShow, :), 'k');
grid on;
title(sprintf('Whitened component %d after peel-off', componentToShow));
xlabel('Time (s)');
ylabel('Residual amplitude');

%% Figure 3: zoom around one spike
spikeToZoom = spikes(round(length(spikes) / 2));
zoomHalfWindow = round(0.06 * fs);
zoomIdx = max(1, spikeToZoom - zoomHalfWindow):min(size(X, 2), spikeToZoom + zoomHalfWindow);
zoomTime = (zoomIdx - spikeToZoom) / fs * 1000;

figure;
plot(zoomTime, X(componentToShow, zoomIdx), 'b', 'LineWidth', 1);
hold on;
plot(zoomTime, Xpeeled(componentToShow, zoomIdx), 'k', 'LineWidth', 1);
xline(0, 'r--', 'Spike');
hold off;
grid on;
title(sprintf('Zoom around one detected spike, component %d', componentToShow));
xlabel('Time around spike (ms)');
ylabel('Amplitude');
legend('Before peel-off', 'After peel-off');

fprintf('Peel-off visualisation complete.\n');
fprintf('Detected spikes: %d\n', length(spikes));
fprintf('Displayed whitened component: %d\n', componentToShow);
fprintf('Mean abs pulse at detected spikes before peel-off: %.4f\n', mean(abs(pulseBefore(spikes))));
fprintf('Mean abs pulse at detected spikes after peel-off : %.4f\n', mean(abs(pulseAfter(spikes))));
