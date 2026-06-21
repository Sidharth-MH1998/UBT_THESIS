% Example covariance heatmap for 16 mostly decorrelated channels.
% This is not perfectly decorrelated: off-diagonal values are small but nonzero.

nChannels = 16;
rng(4);

% Start with small random covariance between different channels.
covExample = 0.08 * randn(nChannels);
covExample = (covExample + covExample') / 2; % make it symmetric

% Strong diagonal means each channel/component has its own variance.
% Values are close to 1 but not exactly 1.
diagValues = 0.85 + 0.25 * rand(nChannels, 1);
covExample(1:nChannels+1:end) = diagValues;

% Keep off-diagonal values small so it looks decorrelated but not perfect.
for i = 1:nChannels
    for j = 1:nChannels
        if i ~= j
            covExample(i, j) = max(min(covExample(i, j), 0.15), -0.15);
        end
    end
end

figure;
imagesc(covExample);
axis square;
colorbar;
clim([-0.2 1.1]);
title('Example: mostly decorrelated covariance, 16 channels');
xlabel('Channel / component');
ylabel('Channel / component');

fprintf('Diagonal values, should be close to 1:\n');
disp(diag(covExample)');

offDiag = covExample(~eye(nChannels));
fprintf('Mean absolute off-diagonal covariance: %.4f\n', mean(abs(offDiag)));
fprintf('Maximum absolute off-diagonal covariance: %.4f\n', max(abs(offDiag)));
