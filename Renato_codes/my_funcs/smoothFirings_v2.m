%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Generates smoothed MU discharge rates by low-pass filtering  using
% convolution with a Hann window of variable width.
% Window size extracted from Del Vecchio et al., J of Neuroscience, 43(16), 2023

% Input: 
%   instantaneous discharge rates - sparse double, MUs column-wise
%   sampling frequency
%   hanning window width in seconds

% Output:
%   smoothed discharge rates, row-wise
% @author: Renato Mio
% Created: 02.01.24

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function smoothedDRs = smoothFirings_v2(spike_train,fs,hann_width)

L = floor(hann_width*fs/2);
w = hann(L); % Hanning window

% Convert spike train to time series, row-wise
spike_train2 = full(spike_train)';

smoothedDRs = zeros(size(spike_train2)); 

% Compute smoothed discharge rates by convolution with Hann window
for mu=1:size(spike_train2,1)
    smoothedDRs(mu,:) = conv(spike_train2(mu,:),w,'same');
end

end