%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generates smoothed MU discharge rates by low-pass filtering  using
% convolution with a Hann window of 400 ms (2.5 Hz)
% Window size extracted from Del Vecchio et al., J of Neuroscience, 43(16), 2023

% Input: 
%   instantaneous discharge rates - sparse double, MUs column-wise
%   sampling frequency

% Output:
%   smoothed discharge rates, row-wise
% @author: Renato Mio
% Created: 02.01.24

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function smoothedDRs = smoothFirings(spike_train,fs)

% Window is 400ms, we need its lenght in samples
L = floor(0.4*fs/2);
w = hann(L); % Hanning window

% Convert spike train to time series, row-wise
spike_train2 = full(spike_train)';

smoothedDRs = zeros(size(spike_train2)); 

% Compute smoothed discharge rates by convolution with Hann window
for mu=1:size(spike_train2,1)
    smoothedDRs(mu,:) = conv(spike_train2(mu,:),w,'same');
end

end