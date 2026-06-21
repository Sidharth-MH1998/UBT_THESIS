% Simple whitening visualisation for EMG decomposition.
%
% The script uses recordedEMG if it exists in your MATLAB workspace.
% Otherwise, it loads demo_emg_demean.mat.

if exist('recordedEMG', 'var')
    EMG = recordedEMG; % channels x samples
    fs = 2000;
else
    load('demo_emg_demean.mat', 'EMG', 'fs');
end

addpath('offline_decomp_renato/lib');

channelsToUse = 1:12;
sampleStart = 20000;
sampleEnd = min(80000, size(EMG, 2));
extensionFactor = 1;

% Take a small EMG portion.
emgSmall = EMG(channelsToUse, sampleStart:sampleEnd);

% Same preparation idea as decomposition:
% extend -> demean -> PCA/eigendecomposition -> whitening.
eSIG = extend(emgSmall, extensionFactor);
eSIG = demean(eSIG);

[E, D] = pcaesig(eSIG);
[wSIG, ~, ~] = whiteesig(eSIG, E, D);

% Keep only the first few rows for trace plots.
nRowsToPlot = min(8, size(eSIG, 1));
timeExtended = (0:size(eSIG, 2)-1) / fs;

figure;

subplot(2, 1, 1);
plot(timeExtended, eSIG(1:nRowsToPlot, :)');
title('Before whitening: extended + demeaned EMG');
xlabel('Time (s)');
ylabel('Amplitude');
grid on;

subplot(2, 1, 2);
plot(timeExtended, wSIG(1:nRowsToPlot, :)');
title('After whitening');
xlabel('Time (s)');
ylabel('Whitened amplitude');
grid on;

% Covariance before and after whitening.
covBefore = cov(eSIG', 1);
covAfter = cov(wSIG', 1);

figure;

subplot(1, 2, 1);
imagesc(covBefore);
axis square;
colorbar;
title('Covariance before whitening');
xlabel('Extended channel');
ylabel('Extended channel');

subplot(1, 2, 2);
imagesc(covAfter);
axis square;
colorbar;
title('Covariance after whitening');
xlabel('Whitened component');
ylabel('Whitened component');

% Eigenvalue spectrum.
figure;
plot(diag(D), 'o-', 'LineWidth', 1);
title('Eigenvalues before whitening');
xlabel('Component');
ylabel('Eigenvalue');
grid on;

% Scatter plot: two dimensions before and after.
figure;

subplot(1, 2, 1);
plot(eSIG(1, :), eSIG(2, :), '.');
axis equal;
grid on;
title('Before whitening scatter');
xlabel('Dimension 1');
ylabel('Dimension 2');

subplot(1, 2, 2);
plot(wSIG(1, :), wSIG(2, :), '.');
axis equal;
grid on;
title('After whitening scatter');
xlabel('Dimension 1');
ylabel('Dimension 2');

fprintf('Mean diagonal covariance before whitening: %.4f\n', mean(diag(covBefore)));
fprintf('Mean off-diagonal covariance before whitening: %.4f\n', mean(abs(covBefore(~eye(size(covBefore))))));
fprintf('Mean diagonal covariance after whitening: %.4f\n', mean(diag(covAfter)));
fprintf('Mean off-diagonal covariance after whitening: %.4f\n', mean(abs(covAfter(~eye(size(covAfter))))));
