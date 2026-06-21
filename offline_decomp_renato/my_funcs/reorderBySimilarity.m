function MatOut = reorderBySimilarity(MatIn,VecTemp)
% MatIn and MatOut are row-wise k x m matrices
% VecTemp is a 1 x m vector
% This function reorders rows in MatIn from the most similar to VecTemp
% first to the least similar at last

cosS = zeros(size(MatIn,1),1);

for i=1:size(MatIn,1)
    cosS(i,1) = cosSim(MatIn(i,:),VecTemp);
end

[~,idx] = sortrows(cosS);

MatOut = MatIn(idx,:);

end