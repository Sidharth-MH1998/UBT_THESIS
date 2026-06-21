function plotGrid_wCentroids(cumm_p2p_grid, X, Y, cent_x, cent_y, stdDist, gridSize, IED)

surf(X,Y,cumm_p2p_grid,'EdgeColor','none')
hold on
% add centroid
scatter3(cent_x,cent_y, max(cumm_p2p_grid,[],"all"), 'ro','filled')
% add standard distance circunference (as a cylinder)
[X_c,Y_c,Z_c] = cylinder(stdDist,40);
X_c = X_c + cent_x;
Y_c = Y_c + cent_y;
Z_c = Z_c*0.001 + max(cumm_p2p_grid,[],"all");
surf(X_c,Y_c,Z_c)
c = colorbar;
set(c.Label,{'String','Rotation','Position'},{'(a.u.)',0,[0.5 -0.005]})
xlim([0 (gridSize(2))*IED])
ylim([0 (gridSize(1))*IED])
xlabel("mm")
ylabel("mm")
view(2)
hold off