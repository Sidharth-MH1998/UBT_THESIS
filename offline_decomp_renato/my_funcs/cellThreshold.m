function [cellVarTh, selected] = cellThreshold(cellVar, cellCond, thresh)

%{
This function applies a thresholding function on the elements of cellVar based on the condition applied by Thresh over cellCond,
and generates a cellMask. Then, cellVarTh keeps the values that meet the thresholding criteria
cellVar, cellCond, and cellVarTh are cell arrays of the same size.

@author: Renato Mio
Creation: 16.02.2024

INPUTS:
    cellVar: cell array variable to be thresholded
    cellCond: cell array over which the threshold is evaluated
    Thresh: Threshold value

OUTPUTS:
    cellVarTh: cell array variable after threshold
    selected: cell array of indexes meeting the criteria
%}

% Find values that meet criteria

s = size(cellVar); % original cell array dimensions
    
cellVar = reshape(cellVar, 1, []);
cellCond = reshape(cellCond, 1, []);
cellVarTh = cell(size(cellVar));
selected = cell(size(cellVar));

for i=1:size(cellVar,2)

    if isempty(cellVar{i})
        selected{i} = [];
        cellVar{i} = [];
        continue
    end

    selected{i} = find( cellCond{i} > thresh );

    cellVar{i}( : , setdiff(1:end, selected{i}) ) = []; % This operation discards all values not in "selected"

end
    
cellVarTh = reshape(cellVarTh,s);
selected = reshape(selected,s);