% Plot peaks after the first FastICA iteration of the offline decomposition.
%
% Before running, make sure trimmedEMG exists in the MATLAB workspace.
% This script follows the beginning of decompose3.m, but stops after
% iteration 1 and plots the detected peaks.

EMG = recordedEMG;
fs = 2000;
badchan = [];
padLen = 200;
initialization = 0;
nChannels = size(EMG, 1);
extfactor = 8;
nbextchan = nChannels * extfactor;
differentialmode = 0;
contrastfunc = 'skew';
preproc_flag = 1;

addpath('offline_decomp_renato/lib');
addpath('offline_decomp_renato/my_funcs');

% Step 1: same preprocessing preparation used by decompose3.m.
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

% Step 2: extension, demean, whitening.
exFactor = round(nbextchan / size(EMG, 1));
eSIG = extend(EMG, exFactor);
eSIG = demean(eSIG);

[E, D] = pcaesig(eSIG);
[wSIG, ~, ~] = whiteesig(eSIG, E, D);

% Step 3: first FastICA iteration only.
X = wSIG;
B = zeros(size(wSIG, 1), 1);

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

maxiter = 500;
w = fixedpointalg(w, X, B, maxiter, contrastfunc);

% Step 4: get pulse train and detected spikes after first iteration.
[icasig, spikes] = getspikes(w, X, fs);

% Remove the padding from the displayed time axis, if padding was used.
plotStart = padLen + 1;
plotEnd = length(icasig) - padLen;
plotIdx = plotStart:plotEnd;
time = (plotIdx - plotStart) / fs;

spikesToPlot = spikes(spikes >= plotStart & spikes <= plotEnd);
spikeTime = (spikesToPlot - plotStart) / fs;

figure;
plot(time, icasig(plotIdx), 'b');
hold on;
plot(spikeTime, icasig(spikesToPlot), 'ro', 'MarkerFaceColor', 'r');
hold off;
grid on;
xlabel('Time (s)');
ylabel('Normalized pulse train');
title('Detected peaks after first FastICA iteration');
legend('Pulse train', 'Detected peaks');

fprintf('First iteration detected %d peaks after removing padding.\n', length(spikesToPlot));
fprintf('First 20 detected peak sample indices, original unpadded signal:\n');
disp(spikesToPlot(1:min(20, end)) - padLen);
