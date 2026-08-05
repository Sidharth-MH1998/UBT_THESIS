function var_grid = chan2grid_Hu_Wei(var_chan, gridSize)

%{
Maps a variable from channels (row-wise) to a 2D grid corresponding to the
grid topology. This one for Hu & Wei EMG dataset
@author: Renato Mio
Creation: 26.10.2023

INPUT: 
var_row: var_row: vector values to resize to match the electrode grid
gridSize: [gridRows gridCols] e.g. [5 13], [8 8]

OUTPUT
var_grid: variable in grid (matrix) of size gridSize
%}

var_grid = reshape(var_chan, gridSize(2),gridSize(1))';
