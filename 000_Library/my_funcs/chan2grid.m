function gridVals = chan2grid(chanVals, chanGrid)
% MAPCHANNELSTOGRID Maps channel values to a 2D grid based on channel indexes.
%
% Inputs:
%   chanVals: vector of size [N x 1] or [1 x N] with values for each channel.
%   chanGrid: [M x K] matrix describing the grid layout, 
%                     where each element holds the channel index (1..N) or NaN.
%
% Output:
%   gridVals: [M x K] matrix with values mapped from chanValues, 
%                     or NaN where no valid channel exists.
%
% Example:
%   chanVals = [10 20 30];
%   chanGrid = [1 2; 3 NaN];
%   gridVals = mapChannelsToGrid(chanValues, chanIndexGrid);
%   % gridVals will be [10 20; 30 NaN]

    % Ensure chanValues is a row vector
    chanVals = chanVals(:).';
    
    % Preallocate gridMap with NaNs
    gridVals = NaN(size(chanGrid));
    
    % Find valid positions (non-NaN indexes)
    validMask = ~isnan(chanGrid);
    
    % Get indexes where mapping is valid
    validIndexes = chanGrid(validMask);
    
    % Check bounds
    if any(validIndexes < 1) || any(validIndexes > numel(chanVals))
        error('Channel indexes in chanIndexGrid exceed bounds of chanValues.');
    end
    
    % Map values
    gridVals(validMask) = chanVals(validIndexes);
end