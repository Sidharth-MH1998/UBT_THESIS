function var_grid = chan2grid_Rojas(var_chan, muscle, varargin)

%{
Maps a variable from channels (row-wise) to a 2D grid corresponding to the
grid topology for Rojas EMG dataset
@author: Renato Mio
Creation: 11.11.2023

INPUT: 
var_row: results file from decomosition
muscle: 'biceps', 'triceps' or 'forearm'

Note: When the muscle is forearm, gridSize is determined from the size of
the array, since it can be 6 rows x 16-19 columns (length can be 96, 102, 108 or 114)

OUTPUT
var_grid: variable in grid form

%}
if isequal(muscle,'biceps') | isequal(muscle,'triceps')
    gridSize = [8 15];
    var_grid = reshape(var_chan, gridSize(1),gridSize(2));
elseif isequal(muscle,'forearm')
    % The grid variable will be length 114 by default, size 6 x 19
    % Smaller matrix sizes will be expanded through bicubic interpolation
    gridSize = [6 length(var_chan)/6]; % actual grid
    var_grid = reshape(var_chan, gridSize(1),gridSize(2));
    if ~isequal( length(var_chan), 114)
        var_grid = imresize(var_grid,[6 19]); % resized grid
    end

end

