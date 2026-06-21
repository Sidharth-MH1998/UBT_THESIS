function cov = CoVar(rowVar)
% Find coefficient of variation of row-wise matrix

if ~isempty(rowVar)
    cov = zeros(size(rowVar,1),1);
    for i=1:size(rowVar,1)
        cov(i,:) = std(rowVar(i,:))/mean(rowVar(i,:));
    end
else
    cov=NaN;
end

end
