function plotFreqSpectrum(signal, fs)

% Plots the frequency spectrum of the signal (row vector) and sampling frequency fs

% Preprocesed EMG
x = signal;
y = fft(x);
% Plot the power spectrum as a function of frequency
n = length(x);          % number of samples
f = (0:n-1)*(fs/n);     % frequency range
power = abs(y).^2/n;    % power of the DFT
y0 = fftshift(y);         % shift y values
f0 = (-n/2:n/2-1)*(fs/n); % 0-centered frequency range
power0 = abs(y0).^2/n;    % 0-centered power
figure
subplot(2,1,1)
plot(f0,power0)
xlabel('Frequency')
ylabel('Power')
xlim([0 450])

% Add time series below
t = (1:length(signal))./fs; % Convert samples to seconds
subplot(2,1,2)
plot(t,signal)
