% Simple before/after visualisation of demean on a small EMG portion.
%
% Assign your EMG data below. It must be channels x samples.
% Example:
%   EMG = trimmedEMG;

if exist('recordedEMG', 'var')
    EMG = recordedEMG; % <-- put your EMG matrix here
else
    load('demo_emg_demean.mat', 'EMG', 'fs');
end
fs = 2000; % sampling frequency in Hz

channelsToPlot = 1; % choose a few channels
sampleStart = 10;
sampleEnd = 100; % show only data points 10 to 15
if sampleStart > size(EMG, 2)
    sampleStart = 1;
    sampleEnd = min(2000, size(EMG, 2));
else
    sampleEnd = min(sampleEnd, size(EMG, 2));
end

% Take a small portion of the EMG.
emgSmall = EMG(channelsToPlot, sampleStart:sampleEnd);

% Apply the same demean idea used in decomposition:
% subtract each channel's own mean.
emgDemeaned = emgSmall - mean(emgSmall, 2);

time = (sampleStart:sampleEnd) / fs;

figure;

subplot(2, 1, 1);
plot(time, emgSmall');
title('Before demean');
xlabel('Time (s)');
ylabel('EMG amplitude');
grid on;

subplot(2, 1, 2);
plot(time, emgDemeaned');
title('After demean');
xlabel('Time (s)');
ylabel('EMG amplitude');
grid on;

fprintf('Mean before demean:\n');
disp(mean(emgSmall, 2));

fprintf('Mean after demean:\n');
disp(mean(emgDemeaned, 2));

fprintf('Original data points, channel(s) x samples 10 to 15:\n');
disp(emgSmall);

fprintf('Demeaned data points, channel(s) x samples 10 to 15:\n');
disp(emgDemeaned);
