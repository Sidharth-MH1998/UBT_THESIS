function cSim = cosSim(A,B)

% Computes cosine similarity of two column vectors

% Normalize the vectors
A = A ./ norm(A,2);
B = B ./ norm(B,2);
  
% Calculate cosine similarity between each row
cSim = mean ( dot(A,B) ./ (norm(A,2) .* norm(B,2)), 'all' , 'omitnan');
