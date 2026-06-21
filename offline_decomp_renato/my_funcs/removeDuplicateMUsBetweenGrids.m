function updatedDecompResults = removeDuplicateMUsBetweenGrids(allDecompResults, fs)

% INPUTS: 
% 
% allDecompResults: Array of structs which have the following fields:
%     B: separation matrix (nbexthannels x NITER)
%     peaks: pulse trains of each MU with original amplitudes (nMUs x nSamples)
%     MUPulses: discharge times of each MU (1 x nMUs cell)
%     sil_all: SIL values of each MU (1 x nMUs)
%     cov_all: CoV of ISI for each MU spike train (1 x nMUs)
%     MUAPs: MUAP waveforms (1 x nMUs cell, and each is nChannels x 103 double)
%     fr: firing rates (instantaneous) time series for each MU (1 x nMUs cell)
%     mean_fr: mean fr for each MU (nMUs x 1 double)
%     p2ps: peak to peak of each MUAP waveform (nChannels x nMUs)
%     MU_locs: location of MU designes as the channel with max p2p (nMUs x 1)
% fs: sampling frequency

% OUTPUT: cell array containing a struct per grid after removing duplicates

    ngrids = length(allDecompResults); % number of grids to compare
    disp(strcat("Checking duplicates between ", num2str(ngrids), " grids"))
    allPulseTrain = cell(1,ngrids);
    fmu = [];
    nMUs = [];
    for g=1:ngrids %
        results = allDecompResults(g);
        allPulseTrain{1,g} = results.spike_train';
        fmu = [fmu ~isempty(results.spike_train)];
        nMUs = [nMUs length(results.sil_all)];
    end


    % Do the same for discharge times / MU pulses
    nMUsmax = max(nMUs);
    allDisTimes = cell(ngrids,nMUsmax);
    for g=1:ngrids
        for mu=1:nMUsmax
            results = allDecompResults(g);
            if mu <= length(results.MUPulses) % only do until we go through all MUs in a grid
                allDisTimes{g,mu} = results.MUPulses{1,mu};
            end
        end
    end
    
    if sum(fmu) > 0 % continue if there are MUs
        nmu = 0;
        for i = 1:size(allPulseTrain,2) % for every grid
            if ~isempty(allPulseTrain{i})
                nmu = nmu + size(allPulseTrain{i},1);
            end
        end
        % PROBLEM, last i is empty grid, size wrong
        PulseT = zeros(nmu, max(cellfun(@length,allPulseTrain)) ); % nMUs x nSamples (we get nSamples from a non-empty pulse train)
        Distim = cell(1,nmu);
        muscle = zeros(1,nmu);
        mu = 1;
        for i = 1:size(allPulseTrain,2) % for every grid
            if ~isempty(allPulseTrain{i}) % if MU spikes were detected
                for j = 1:size(allPulseTrain{i},1) % for every MU
                    PulseT(mu,:) = allPulseTrain{i}(j,:);
                    Distim{mu} = allDisTimes{i,j};
                    muscle(mu) = i;
                    mu = mu+ 1;
                end
            end
        end
        
        [PulseT, Distim, muscle] = remduplicatesbgrids(PulseT, Distim, muscle, round(fs/40), 0.00025, 0.3, fs);
    
        % Get indexes of survivor MUs
        survivors = zeros(ngrids,nMUsmax);
        for mu = 1:length(Distim)
            isSurvivor = cellfun(@(x) isequal(x,Distim{1,mu}), allDisTimes);
            [row,col] = find(isSurvivor);
            survivors(row,col) = 1;
        end
    
        % We update the updatedResults variable
        updatedDecompResults = [];
        for g=1:ngrids
            results  = allDecompResults(g);
            duplicateMUs = find(survivors(g,1:length(results.sil_all))==0);  % crop to a length to match the actual number of MUs 
            updatedDecompResults = [updatedDecompResults discardMUs_singleTrial(duplicateMUs,results)];
        end
    
    end

end