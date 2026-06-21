function cleaned_grid = remGridOutliers(var_grid)

%{
Detects outlier values in a grid and replaces them with interpolated values
from neighbours

An outlier is determined as such if it is not within 5-95 percentile values or 3 standard deviations
from the mean, depending on the argument in the "isoutlier" function

INPUT: 
var_grid: 2D matrix (grid) to be analysed 

OUTPUT
cleaned_grid: grid after removing outliers and replacing values via interpolation

@author: Renato Mio
Creation: 21.11.2023

%}


gridSize = size(var_grid); % original grid size
numChannels = numel(var_grid); % Total numn
chanNumArray = reshape(1:numel(var_grid), gridSize(1), gridSize(2));

% Transform to vector to apply the outlier detection over all values (in a
% matrix this is done column-wise)
var_vector = reshape(var_grid,[],1);

% Detect outliers
% TF = isoutlier(var_vector,"mean");
TF = isoutlier(var_vector,"percentiles",[5 95]);

outliers_idx = find(TF == 1); % here we get the channel indexes to replace

%%% Replace outliers

% Create mask
mask = zeros(size(var_grid));
for i=1:length(outliers_idx)
    [row, col] = find(chanNumArray == outliers_idx(i));
    mask(row,col) = 1;
end

cleaned_grid = regionfill(var_grid,mask);