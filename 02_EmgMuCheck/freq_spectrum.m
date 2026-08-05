%% Simple EMG power spectrum

emgData = recordedEMG;  % EMG matrix: channels x samples
fs = 2000;              % Sampling frequency in Hz
channel = 1;            % Channel to display

emg = double(emgData(channel,:));
emg = emg - mean(emg);       % Remove the DC offset

% Use a one-second Hann window with 50% overlap.
window = hann(fs,'periodic');
overlap = fs/2;
nfft = 2048;

% Estimate and display the power spectrum.
[power,f] = pwelch(emg,window,overlap,nfft,fs);

figure;
plot(f,10*log10(power));

xlim([0 700]);
xticks(0:50:700);
grid on;
xlabel('Frequency (Hz)');
ylabel('Power (dB/Hz)');
title(sprintf('EMG power spectrum - Channel %d',channel));
