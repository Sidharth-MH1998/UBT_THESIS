function [centroids_x, centroids_y, cent_x, cent_y, stdDist, cumm_p2p_grid]= get_MUAP_centroids(results_cleaned, gridSize, IED, plot_flag)

%{
Get location of MU over an electrode grid
@author: Renato Mio
Creation: 18.05.2023

INPUT: 
results_cleaned: results file from decomosition
gridSize: [gridRows gridCols] e.g. [5 13], [8 8]
IED: inter-electrode distance in mm
plot_flag: true if plot is required

OUTPUT
centroids_x: vector of x locations of electrode with max peak-to-peak amplitude for all MUs
centroids_y: vector of y locations of electrode with max peak-to-peak amplitude for all MUs
cent_x: mean x centroid
cent_y: mean y centroid
stdDist: standard distance (measure of spread of MUs)
cumm_p2p_grid: cummulative peak-to-peak grid in mm
%}

% Toolboxes
addpath("Code\sample_data\")
addpath("Code\funcs\")
addpath("Code\visualization app\")

% For plotting (just plot_spikeTrain)
% addpath("Code\helper_functions\") % CAREFUL! There is a whiten.m function here that causes an issue with the other toolbox function with the same name 
% instead use just the plot_spikeTrain from another folder
addpath("Code\plot_funcs\")

% helper functions
addpath("Code\")

% Initialise

l = 31; % default value, sample length of MUAP 
raw = results_cleaned.x_flat_dis_fil_cr;
n_MUs = length(results_cleaned.MUPulses); % number of MUs

% Grid dimensions in mm
[X,Y] = meshgrid( (0:(gridSize(2)+1)) , 0:(gridSize(1)+1) ); % MUAP location is flipped on Y axis due to meshgrid function
X = X*IED-IED;
Y = Y*IED;
Y = flip (Y); % flipping for plotting with correct orientation

centroids_x = zeros(length(results_cleaned.MUPulses),1);
centroids_y = zeros(length(results_cleaned.MUPulses),1);

% Check number of MUAPs detected
if n_MUs == 0 % no MUAPs detected
    disp("No MUs detected in this trial")
    centroids_x = [];
    centroids_y = [];
    stdDist = [];
    cent_x = [];
    cent_y = []; 
    cumm_p2p_grid = zeros(gridSize(1)+2, gridSize(2)+2);
else
    MUAP_all_cleaned = MUAP_cal(results_cleaned, raw, l); % needed to calculate MUAP waveforms
    cumm_p2p_grid = zeros(gridSize(1)+2, gridSize(2)+2); % cummulative
    for mu_i = 1:n_MUs % iterate over each MU index
       % get peak to peak values
       MU_p2p_grid = zeros(gridSize(1)+2, gridSize(2)+2);
       p2p_grid_temp = get_p2p_grid(MUAP_all_cleaned, mu_i, gridSize);
       cumm_p2p_grid(2:end-1,2:end-1) = cumm_p2p_grid(2:end-1,2:end-1) + p2p_grid_temp;
       MU_p2p_grid(2:end-1,2:end-1) = p2p_grid_temp; % rearranged to match spatial distribution of grid
       % Get MU electrode location
       [temp_row, temp_col] = find(p2p_grid_temp==max(p2p_grid_temp,[],"all"));
       % convert to mm
       temp_row = gridSize(1)+1-temp_row; % to start counting row from down to up direction
       centroids_y(mu_i) = temp_row*IED - IED/2;
       centroids_x(mu_i) = temp_col*IED - IED/2;
    end
    
    cent_x = mean(centroids_x);
    cent_y = mean(centroids_y);
    
    stdDist = sqrt( sum((centroids_x-cent_x).^2 + (centroids_y-cent_y).^2) / n_MUs);

    if plot_flag
        figure
        surf(X,Y,cumm_p2p_grid/n_MUs,'EdgeColor','none')
        hold on
        scatter3(centroids_x,centroids_y, max(cumm_p2p_grid/n_MUs,[],"all"), 'kx')
        scatter3(cent_x,cent_y, max(cumm_p2p_grid/n_MUs,[],"all"), 'ro','filled')
        colorbar
        xlim([0 (gridSize(2))*IED])
        ylim([0 (gridSize(1))*IED])
        view(2)
    end

end