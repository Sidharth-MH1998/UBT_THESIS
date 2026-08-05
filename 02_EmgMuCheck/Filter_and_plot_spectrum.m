%% Simple EMG spectrum before and after filtering

emgData = recordedEMG;  % EMG matrix: channels x samples
fs = 2000;              % Sampling frequency in Hz
channel = 1;            % Channel to display

%% Filter the complete EMG matrix
filteredEMG = adaptiveNotchFilter(emgData,fs,[45 55],9,1);
filteredEMG = bandpassingals(filteredEMG,fs,1); % 1 = surface EMG

%% Select one channel and remove its DC offset
rawSignal = double(emgData(channel,:));
filteredSignal = double(filteredEMG(channel,:));

rawSignal = rawSignal - mean(rawSignal);
filteredSignal = filteredSignal - mean(filteredSignal);

%% Calculate both power spectra using identical settings
window = hann(fs,'periodic');
overlap = fs/2;
nfft = 2048;

[rawPower,f] = pwelch(rawSignal,window,overlap,nfft,fs);
filteredPower = pwelch(filteredSignal,window,overlap,nfft,fs);

%% Plot before and after filtering
figure;
plot(f,10*log10(rawPower),'DisplayName','Before');
hold on;
plot(f,10*log10(filteredPower),'DisplayName','After');

hold off;
xlim([0 700]);
xticks(0:50:700);
grid on;
legend('Location','best');
xlabel('Frequency (Hz)');
ylabel('Power (dB/Hz)');
title(sprintf('EMG spectrum before and after filtering - Channel %d',channel));
