function var_chan = grid2chan_Hyser(var_grid)

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

var_grid = fliplr(var_grid); % flip left-right
var_grid = flipud(var_grid); % flip up-down
var_chan = reshape(var_grid',[],1);


