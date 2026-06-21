function plotGrid_wCentroids_v2(p2p_grids, MU_counts_grids, digit, gridSize, plot_count)

%{
This function plots a finger HD EMG MUAP p2p activations with the option of
adding circles representing the number of MUs detected per electrode location

@author: Renato Mio
Creation: 27.07.2023

INPUTS: 
    p2p_grids: cummulative MUAP peak-to-peak grids for the five digits
    MU_counts_grids: MU counts per electrode in a grid, 1 grid per digit
    digit: finger movement activations analysed to plot
    norm_flag: true if normalisation per grid is needed (each grid is divided by its total MU ount)
    plot_Count: true for plotting MU counts on top of grid

%}

% Create grid of X-Y positions
% gridSize = [16 8];
IED = 8;
[X,Y] = meshgrid( (0:(gridSize(2)+1)) , 0:(gridSize(1)+1) ); % MUAP location is flipped on Y axis due to meshgrid function
X = X*IED-IED;
Y = Y*IED;
Y = flip (Y); % flipping for plotting with correct orientation

% Load digit grid
cumm_p2p_grid = p2p_grids(:,:,digit);
count_grid = MU_counts_grids(:,:,digit);


% Plot p2p grid
% figure
hold on
surf(X,Y,cumm_p2p_grid,'EdgeColor','none')
c = colorbar;
set(c.Label,{'String','Rotation','Position'},{'(a.u.)',0,[0.5 -0.005]})
xlim([0 (gridSize(2))*IED])
ylim([0 (gridSize(1))*IED])
xlabel("mm")
ylabel("mm")

if plot_count % Add circles to show MU count per electrode
    for row = 2:gridSize(1)+1 % rows
        for col= 2:gridSize(2)+1 % cols
            if count_grid(row,col)>0 % Only plot if there are MUs in that electrode
                % Get X,Y coordinates
                x = (col-1)*IED - IED/2;
                y = (gridSize(1)+2-row)*IED - IED/2;
                scatter3(x,y, max(cumm_p2p_grid,[],"all"), count_grid(row,col)*10, 'ko','filled','MarkerFaceAlpha', 0.2)
            end
        end
    end
end

view(2)
hold off