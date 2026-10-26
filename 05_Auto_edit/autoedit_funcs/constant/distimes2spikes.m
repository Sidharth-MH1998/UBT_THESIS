function spike_train = distimes2spikes(distimes,siglen)
%DISTIMES2SPIKES Converts cell array of dischargetimes to binary vector of spike trains
%   Inputs:
%       distimes:       discharge times cell array 1 x nMUs
%       siglen:         singal length in samples
%   Outputs:
%       spike_train:    column-wise binary spike train (sparse double) of size siglen x nMUs
%
% Author: Renato Mio (09.12.2025)

if ~iscell(distimes) % if we don't find a cell array
    if isnan(distimes) % and the value is a NaN
        spike_train = NaN;
        return
    end
end

nMUs = size(distimes,2);
spike_train = zeros( siglen, nMUs);
for mu=1:nMUs
    spike_train(distimes{1,mu}, mu) = 1;
end

end

