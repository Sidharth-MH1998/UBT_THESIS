% Takes a cell array containing vectors of length equal to the number of
% MUs and returns similar cell arrays without the DISCARDED MUs

% discarded and cellIn must have the same size

function varargout = discardMUs(discarded,varargin)

for j = 1:(nargin-1)

is_p2p = 0; % For this to be true, all cells should have 64 rows
is_segm = 0; % Cell content is a segmented matrix. For this to be true, all cells should have 5120 columns (number of samples)

cellIn = varargin{j};

    s = size(cellIn); % original cell array dimensions
    
    cellIn = reshape(cellIn, 1, []);
    discarded = reshape(discarded, 1, []);
    cellOut = cell(size(cellIn));

    % Find values dimensionality and set flags, checking the first three cells
    if size(cellIn{1},1) == 64 && size(cellIn{2},1) == 64 && size(cellIn{3},1) == 64
        is_p2p = 1;
    elseif size(cellIn{1},2) == 5120 && size(cellIn{2},2) == 5120 && size(cellIn{3},2) == 5120
        is_segm = 1;
    end
    
    for i=1:size(cellIn,2)

        if isempty(cellIn{i})
            continue
        end

        if is_p2p % this is a p2p matrix, MUs in cols
                cellIn{i}(:,discarded{i}) = [];
                cellOut{i} = cellIn{i};
        
        elseif is_segm % this is a segmented matrix, MUs in rows
                cellIn{i}(discarded{i},:) = [];
                cellOut{i} = cellIn{i};
        
        elseif isvector(cellIn{i})
            cellIn{i}(discarded{i}) = [];
            cellOut{i} = cellIn{i};

%         else % If the content is a matrix
%             if size(cellIn{i},1) == 64 % this is a p2p matrix, MUs in cols
%                 cellIn{i}(:,discarded{i}) = [];
%                 cellOut{i} = cellIn{i};
%             elseif size(cellIn{i},2) == 5120 % this is a segmented matrix, MUs in rows
%                 cellIn{i}(discarded{i},:) = [];
%                 cellOut{i} = cellIn{i};
%             end
        end
    end
    
    cellOut = reshape(cellOut,s);

varargout{j} = cellOut;

end