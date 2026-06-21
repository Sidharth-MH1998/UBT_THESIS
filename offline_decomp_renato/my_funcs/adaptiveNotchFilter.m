function filteredSignal = adaptiveNotchFilter(signal, fsamp, baseFreqRange, numHarmonics, notchWidth)
    % Adaptive notch filter that detects peaks in the frequency domain and applies
    % notch filters to those frequencies and their harmonics.
    %
    % Inputs:
    %   signal: Input signal (can be multi-channel, rows = channels)
    %   fsamp: Sampling frequency in Hz
    %   baseFreqRange: Range to search for the base frequency [minFreq, maxFreq]
    %   numHarmonics: Number of harmonics to filter (including the base frequency)
    %   notchWidth: Width of the notch filter in Hz
    %
    % Output:
    %   filteredSignal: Filtered signal

    if nargin < 3
        baseFreqRange = [45, 55];  % Default range for 50 Hz and nearby
    end
    if nargin < 4
        numHarmonics = 9;  % Filter up to the 9th harmonic by default
    end
    if nargin < 5
        notchWidth = 1;  % 2 Hz notch width by default
    end

    [numChannels, signalLength] = size(signal);
    filteredSignal = zeros(size(signal));

    for channel = 1:numChannels
        % Compute the frequency spectrum
        signalFFT = fft(signal(channel, :));
        freqAxis = (0:signalLength-1) * fsamp / signalLength;
        
        % Find the base frequency
        baseFreqRange_idx = find(freqAxis >= baseFreqRange(1) & freqAxis <= baseFreqRange(2));
        [~, maxIdx] = max(abs(signalFFT(baseFreqRange_idx)));
        baseFreq = freqAxis(baseFreqRange_idx(maxIdx));
        
        % Apply notch filters to the base frequency and its harmonics
        for harmonic = 1:numHarmonics
            notchFreq = harmonic * baseFreq;
             
            [b, a] = designNotchFilter(notchFreq, notchWidth, fsamp);
            signal(channel, :) = filtfilt(b, a, signal(channel, :));
        end
        
        filteredSignal(channel, :) = signal(channel, :);
    end
end

function [b, a] = designNotchFilter(notchFreq, notchWidth, fsamp)

    wo = 2*pi*notchFreq/fsamp;
    bw = 2*pi*notchWidth/fsamp;

    r = 1 - bw/2;

    b = [1 -2*cos(wo) 1];
    a = [1 -2*r*cos(wo) r^2];

end