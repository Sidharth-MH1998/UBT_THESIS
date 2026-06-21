function var_grid = chan2grid_Hyser(var_chan, gridSize)

%{
Maps a variable from channels (row-wise) to a 2D grid corresponding to the
grid topology
@author: Renato Mio
Creation: 19.09.2023

INPUT: 
var_row: vector values to resize to match the electrode grid
gridSize: [gridRows gridCols] e.g. [5 13], [8 8]

OUTPUT
var_grid: variable in grid (matrix) of size gridSize
%}

var_grid = reshape(var_chan, gridSize(2),gridSize(1))';
% In the case of Hyser arrangement, we need to flip the grid both horizontally and vertically
var_grid = flipud(var_grid); % flip up-down
var_grid = fliplr(var_grid); % flip left-right