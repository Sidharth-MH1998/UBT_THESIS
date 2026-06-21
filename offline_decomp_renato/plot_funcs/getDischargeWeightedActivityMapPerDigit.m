function [cumm_p2p, cumm_MUcounts, cumm_p2p_grid, cumm_MUcounts_grid] = getDischargeWeightedActivityMapPerDigit(p2p, MUcount, MUAP_locs, discharges, gridSize)


% Initialise
cumm_p2p = zeros(64,5); cumm_MUcounts = zeros(64,5); % activity vectors
cumm_p2p_grid = zeros(gridSize(1), gridSize(2),5); % in grid form
cumm_MUcounts_grid = zeros(gridSize(1), gridSize(2),5);

subjects ={'01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20'};

for S = 1:length(subjects)
    for digit = 1:5 % Iterate per digit 
        for ss = 1:2 % session 1 or 2
            for t = 1:3 % trial 1 to 3               
    
                if MUcount(S,digit,ss,t) == 0 % if true, we just create a grid of zeros
                    temp_p2p = zeros(64,1);
                else % otherwise we add all MU's p2ps (column-wise) multiplied by their mean discharge rate
                    % p2p has dimension 64 x nMUs and the mean discharge rates have dimension 1 x nMUs
                    % Hence, we use repmat to copy the discharge rate vector into 64 rows using repmat and perform element-wise multiplication
                    temp_p2p = sum( p2p{S,digit,ss,t}.*repmat(discharges{S,digit,ss,t}, [size(p2p{S,digit,ss,t},1) 1]), 2 )  ;

                    % Transform to grid and remove outliers
                    temp_p2p_grid = chan2grid_Hyser( temp_p2p, gridSize );
                    temp_p2p_grid = remGridOutliers(temp_p2p_grid); % remove outliers
                    temp_p2p = grid2chan_Hyser(temp_p2p_grid);
                    
                    for mu = 1:MUcount(S,digit,ss,t) % Iterate over each MU detected on that trial
                        temp_chan = MUAP_locs{S,digit,ss,t}(mu,1); % get channel where MU was located
                        % Add MU count to grid only if its discharge rate is over 5
                        if discharges{S,digit,ss,t}(mu)>5
                            cumm_MUcounts(temp_chan, digit) = cumm_MUcounts(temp_chan, digit) + 1;
                        end
                    end
                end
    
                % Add to the cummulative vector and grid
                cumm_p2p(:,digit) = cumm_p2p(:,digit) + temp_p2p;

            end
        end
    end
end

for digit = 1:5 % Iterate per digit
    cumm_p2p_grid(:,:, digit) = chan2grid_Hyser(cumm_p2p(:,digit), gridSize);
    cumm_MUcounts_grid(:,:, digit) = chan2grid_Hyser(cumm_MUcounts(:,digit), gridSize); 
end

