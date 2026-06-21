        
gridSize = [5 13]; % Format: [rows cols]
IED = 8; %mm
[X,Y] = meshgrid( (0:(gridSize(2)+1)) , 0:(gridSize(1)+1) ); % MUAP location is flipped on Y axis due to meshgrid function
X = X*IED-IED;
Y = Y*IED;
Y = flip (Y); % flipping for plotting with correct orientation

mu = 6;

MU_p2p_grid = zeros(gridSize(1)+2, gridSize(2)+2);
p2p_grid_temp = get_p2p_grid(MUAP_all_cleaned, mu, gridSize);
MU_p2p_grid(2:end-1,2:end-1) = p2p_grid_temp; % rearranged to match spatial distribution of grid
% Get MU electrode location
[temp_row, temp_col] = find(p2p_grid_temp==max(p2p_grid_temp,[],"all"));
% convert to mm
temp_row = gridSize(1)+1-temp_row; % to start counting row from down to up direction
centroid_Y = temp_row*IED - IED/2;
centroid_X = temp_col*IED - IED/2;


figure
surf(X,Y,MU_p2p_grid,'EdgeColor','none')
hold on
scatter3(centroid_X,centroid_Y, max(p2p_grid_temp,[],"all"), 'kx')
colorbar
xlim([0 (gridSize(2))*IED])
ylim([0 (gridSize(1))*IED])
view(2)

%%

figure
t = tiledlayout('flow'); % As we call nexttile, the layout reflows as needed to accommodate the new axes while maintaining an aspect ratio of roughly 4:3 for all the tiles.
t = MUAP_plot_grid(t, MUAP_all_cleaned, mu, 5, 13); % Plot MUAP waveform for all channnels

%%

gridSize = [5 13]; % Format: [rows cols]
IED = 8; %mm

[X,Y] = meshgrid( (0:(gridSize(2)+1)) , 0:(gridSize(1)+1) ); % MUAP location is flipped on Y axis due to meshgrid function
X = X*IED-IED;
Y = Y*IED;
Y = flip (Y); % flipping for plotting with correct orientation

n_MUs = length(results_cleaned.MUPulses); % number of MUs

centroids_X = zeros(length(results_cleaned.MUPulses),1);
centroids_Y = zeros(length(results_cleaned.MUPulses),1);

for mu_i = 1:size(results_cleaned.MUPulses, 2) % iterate over each MU index
   % get peak to peak values
   MU_p2p_grid = zeros(gridSize(1)+2, gridSize(2)+2);
   p2p_grid_temp = get_p2p_grid(MUAP_all_cleaned, mu_i, gridSize);
   MU_p2p_grid(2:end-1,2:end-1) = p2p_grid_temp; % rearranged to match spatial distribution of grid
   % Get MU electrode location
   [temp_row, temp_col] = find(p2p_grid_temp==max(p2p_grid_temp,[],"all"));
   % convert to mm
   temp_row = gridSize(1)+1-temp_row; % to start counting row from down to up direction
   centroids_Y(mu_i) = temp_row*IED - IED/2;
   centroids_X(mu_i) = temp_col*IED - IED/2;
end

cent_x = mean(centroids_X);
cent_y = mean(centroids_Y);

stdDist = sqrt( sum((centroids_X-cent_x).^2 + (centroids_Y-cent_y).^2) / length(results_cleaned.MUPulses));

%%
% create new results variable without duplicates
                results_cleaned = results;
                % Remove rows corresponding to bad indices
                MUPulses = results.MUPulses;
                MUPulses(bad_idx) = [];
                results_cleaned.MUPulses = MUPulses;
                
                sil_all = results.sil_all;
                sil_all(bad_idx) = [];
                results_cleaned.sil_all = sil_all;
                
                pnr_all = results.pnr_all;
                pnr_all(bad_idx) = [];
                results_cleaned.pnr_all = pnr_all;
                
                % do the same for firing rates and MUAPs
                fr_cleaned = fr;
                fr_cleaned(bad_idx)= [];

                mean_fr_cleaned = mean_fr;
                mean_fr_cleaned(bad_idx)= [];

                MUAP_all_cleaned = MUAP_all;
                MUAP_all_cleaned(bad_idx) = [];

                MUAP_locs_cleaned = MUAP_locs;
                MUAP_locs_cleaned(:, bad_idx) = [];

%%

centroid_x = sum((X.*MU_p2p_grid),'all')/sum(MU_p2p_grid,'all')
    % xticks((1:13)+0.5)
    % xticklabels( 1:13 )
    % 
    % yticks((1:5)-0.5)
    % yticklabels( flip(1:5) )
    % title(strcat("Gesture ",num2str(i)))

sum((X(5,:).*MU_p2p_grid(5,:)),'all')/sum(MU_p2p_grid(5,:),'all')

[X,Y] = meshgrid(1-1:13+1,1-1:5+1); % MUAP location is flipped on Y axis due to meshgrid function
Y = flip (Y); % flipping for right plotting

amps_grid = zeros(5+2,13+2);
amps_grid(2:end-1,2:end-1) = reshape(amps, 13,5)'; % rearranged to match spatial distribution of grid 
% and surround by zeros for proper visualisation

surf(X,Y,amps_grid,'EdgeColor','none')
colorbar
xlim([1 13+1])
ylim([0 5])
view(2)

xticks((1:13)+0.5)
xticklabels( 1:13 )

yticks((1:5)-0.5)
yticklabels( flip(1:5) )

%%


[centroids_x, centroids_y, stdDist]= get_MUAP_centroids(results_cleaned, gridSize, IED, 1)

