function subjDecompData = loadSubjectDecompData(S,path,digits,forces,trials)
%{
    Loads single subject data into a struct
    
    Inputs:
    - S: Subject identifier (e.g. ID number)
    - path: to the folder where decomposed mat files are saved


    @author: Renato Mio
    Created: 13.01.2025

    Pipeline includes:
    - Total MU counts
    - SIL values
    - CoV of ISI
    ...
    - Identifying and removing MUs co-contracting for the whole trial that also have low peak-to-peak amplitudes
    - Firing rates per digit and force level (violin plots)
    - MU activation maps
    - Exporting MU smoothed DR time series for regression task

%}


% OUTPUTS from decompose3
% Struct containing fields:
% B: separation matrix (nbexthannels x NITER)
% peaks: pulse trains of each MU with original amplitudes (nMUs x nSamples)
% MUPulses: discharge times of each MU (1 x nMUs cell)
% spike_train: sparse double of spikes (nSamples x nMUs)
% sil_all: SIL values of each MU (1 x nMUs)
% cov_all: CoV of ISI for each MU spike train (1 x nMUs)
% MUAPs: MUAP waveforms (1 x nMUs cell, and each is nChannels x 103 double)
% fr: firing rates (instantaneous) time series for each MU (1 x nMUs cell)
% mean_fr: mean fr for each MU (nMUs x 1 double)
% p2ps: peak to peak of each MUAP waveform (nChannels x nMUs)
% MU_locs: location of MU designes as the channel with max p2p (nMUs x 1)

%% Path to files

if isnumeric(S)
    S = num2str(S);
end

proc_path = strcat(path,"S",S,"_100\");

%% Discard co-contracting MUs
% Variables for survivor MUs
nMUs_g1 = zeros(length(digits),length(forces),trials);
nMUs_g2 = zeros(length(digits),length(forces),trials);

MUPulses_g1 = cell(length(digits),length(forces),trials); % discharge times of each MU (1 x nMUs cell)
MUPulses_g2 = cell(length(digits),length(forces),trials); 

spiketrains_g1 = cell(length(digits),length(forces),trials); % spike_train: sparse double of spikes (nSamples x nMUs)
spiketrains_g2 = cell(length(digits),length(forces),trials);

sil_all_g1 = cell(length(digits),length(forces),trials); % sil_all: SIL values of each MU (1 x nMUs)
sil_all_g2 = cell(length(digits),length(forces),trials);
cov_all_g1 = cell(length(digits),length(forces),trials); % cov_all: CoV of ISI for each MU spike train (1 x nMUs)
cov_all_g2 = cell(length(digits),length(forces),trials);

MUAPs_g1 = cell(length(digits),length(forces),trials); % MUAPs: MUAP waveforms (1 x nMUs cell, and each is nChannels x 103 double)
MUAPs_g2 = cell(length(digits),length(forces),trials); 

fr_g1 = cell(length(digits),length(forces),trials); % fr: firing rates (instantaneous) time series for each MU (1 x nMUs cell)
fr_g2 = cell(length(digits),length(forces),trials);

mean_fr_g1 = cell(length(digits),length(forces),trials); % mean_fr: mean fr for each MU (nMUs x 1 double)
mean_fr_g2 = cell(length(digits),length(forces),trials);

p2ps_g1 = cell(length(digits),length(forces),trials); % p2ps: peak to peak of each MUAP waveform (nChannels x nMUs)
p2ps_g2 = cell(length(digits),length(forces),trials); 

MU_locs_g1 = cell(length(digits),length(forces),trials); % MU_locs: location of MU designes as the channel with max p2p (nMUs x 1)
MU_locs_g2 = cell(length(digits),length(forces),trials);

% Iterate over all trials
for digit = 1:length(digits) % Iterate per digit 
    for f = 1:length(forces) % 10 or 20% MVF
        for t = 1:trials % trial 1 to 5
            % Try to load trial. If not found, means this was a discarded one
            try
                fname = strcat(proc_path,"S",num2str(S),"_ss1_dig",num2str(digit),"_f",forces(f),"_t",num2str(t),".mat");
                load(fname)
            catch ME
                warning('File not found: "%s"', fname)
                warning('This trial will be skipped (NaN values will be saved)\n')
                nMUs_g1(digit,f,t) = NaN;
                nMUs_g2(digit,f,t) = NaN;
                MUPulses_g1{digit,f,t} = NaN;
                MUPulses_g2{digit,f,t} = NaN;
                spiketrains_g1{digit,f,t} = NaN;
                spiketrains_g2{digit,f,t} = NaN;
                sil_all_g1{digit,f,t} = NaN;
                sil_all_g2{digit,f,t} = NaN;
                cov_all_g1{digit,f,t} = NaN;
                cov_all_g2{digit,f,t} = NaN;
                MUAPs_g1{digit,f,t} = NaN;
                MUAPs_g2{digit,f,t} = NaN;
                fr_g1{digit,f,t} = NaN;
                fr_g2{digit,f,t} = NaN;
                mean_fr_g1{digit,f,t} = NaN;
                mean_fr_g2{digit,f,t} = NaN;
                p2ps_g1{digit,f,t} = NaN;
                p2ps_g2{digit,f,t} = NaN;
                MU_locs_g1{digit,f,t} = NaN;
                MU_locs_g2{digit,f,t} = NaN;
                continue
            end

            % Indexes of MUs to discard   
            cc_g1 = [];
            cc_g2 = [];
            % Co-contracting is active from start of the contraction
            for mu=1:length(decomp_results_g1.sil_all)
                if sum(decomp_results_g1.MUPulses{1,mu}<3*fs) >= 5 % check for 5 or more spikes over the first 3 seconds
                    cc_g1 = [cc_g1; mu];
                end
            end

            for mu=1:length(decomp_results_g2.sil_all)
                if sum(decomp_results_g2.MUPulses{1,mu}<3*fs) >= 5
                    cc_g2 = [cc_g2; mu];
                end
            end
            
            % Add second check based on active time:
            [cc_act_g1, inactive_g1] = find_cocontracting_MUs(decomp_results_g1.spike_train, fs);
            [cc_act_g2, inactive_g2] = find_cocontracting_MUs(decomp_results_g2.spike_train, fs);

            discardedMUs_g1 = unique([cc_g1; cc_act_g1; inactive_g1]); % we add the inactive (if any) to discard them as well
            discardedMUs_g2 = unique([cc_g2; cc_act_g2; inactive_g2]);

            refined_results_g1 = discardMUs_singleTrial(discardedMUs_g1, decomp_results_g1);
            refined_results_g2 = discardMUs_singleTrial(discardedMUs_g2, decomp_results_g2);
            
            % Assign to corresponding variable 
            nMUs_g1(digit,f,t) = length(refined_results_g1.sil_all);
            nMUs_g2(digit,f,t) = length(refined_results_g2.sil_all);

            MUPulses_g1{digit,f,t} = refined_results_g1.MUPulses; % discharge times of each MU (1 x nMUs cell)
            MUPulses_g2{digit,f,t} = refined_results_g2.MUPulses; 
            
            spiketrains_g1{digit,f,t} = refined_results_g1.spike_train; % spike_train: sparse double of spikes (nSamples x nMUs)
            spiketrains_g2{digit,f,t} = refined_results_g2.spike_train;

            sil_all_g1{digit,f,t} = refined_results_g1.sil_all; % sil_all: SIL values of each MU (1 x nMUs)
            sil_all_g2{digit,f,t} = refined_results_g2.sil_all;
            cov_all_g1{digit,f,t} = refined_results_g1.cov_all; % cov_all: CoV of ISI for each MU spike train (1 x nMUs)
            cov_all_g2{digit,f,t} = refined_results_g2.cov_all;
            
            MUAPs_g1{digit,f,t} = refined_results_g1.MUAPs; % MUAPs: MUAP waveforms (1 x nMUs cell, and each is nChannels x 103 double)
            MUAPs_g2{digit,f,t} = refined_results_g2.MUAPs; 
            
            fr_g1{digit,f,t} = refined_results_g1.fr; % fr: firing rates (instantaneous) time series for each MU (1 x nMUs cell)
            fr_g2{digit,f,t} = refined_results_g2.fr;
            
            mean_fr_g1{digit,f,t} = refined_results_g1.mean_fr; % mean_fr: mean fr for each MU (nMUs x 1 double)
            mean_fr_g2{digit,f,t} = refined_results_g2.mean_fr;
            
            p2ps_g1{digit,f,t} = refined_results_g1.p2ps; % p2ps: peak to peak of each MUAP waveform (nChannels x nMUs)
            p2ps_g2{digit,f,t} = refined_results_g2.p2ps; 
            
            MU_locs_g1{digit,f,t} = refined_results_g1.MU_locs; % MU_locs: location of MU designes as the channel with max p2p (nMUs x 1)
            MU_locs_g2{digit,f,t} = refined_results_g2.MU_locs;
            
        end
    end
end

subjDecompData.nMUs_g1 = nMUs_g1; % MU counts
subjDecompData.nMUs_g2 = nMUs_g2;

subjDecompData.MUPulses_g1 = MUPulses_g1; % discharge times of each MU (1 x nMUs cell)
subjDecompData.MUPulses_g2 = MUPulses_g2; 

subjDecompData.spiketrains_g1 = spiketrains_g1; % spike_train: sparse double of spikes (nSamples x nMUs)
subjDecompData.spiketrains_g2 = spiketrains_g2;

subjDecompData.sil_all_g1 = sil_all_g1; % sil_all: SIL values of each MU (1 x nMUs)
subjDecompData.sil_all_g2 = sil_all_g2;
subjDecompData.cov_all_g1 = cov_all_g1; % cov_all: CoV of ISI for each MU spike train (1 x nMUs)
subjDecompData.cov_all_g2 = cov_all_g2;

subjDecompData.MUAPs_g1 = MUAPs_g1; % MUAPs: MUAP waveforms (1 x nMUs cell, and each is nChannels x 103 double)
subjDecompData.MUAPs_g2 = MUAPs_g2; 

subjDecompData.fr_g1 = fr_g1; % fr: firing rates (instantaneous) time series for each MU (1 x nMUs cell)
subjDecompData.fr_g2 = fr_g2;

subjDecompData.mean_fr_g1 = mean_fr_g1; % mean_fr: mean fr for each MU (nMUs x 1 double)
subjDecompData.mean_fr_g2 = mean_fr_g2;

subjDecompData.p2ps_g1 = p2ps_g1; % p2ps: peak to peak of each MUAP waveform (nChannels x nMUs)
subjDecompData.p2ps_g2 = p2ps_g2; 

subjDecompData.MU_locs_g1 = MU_locs_g1; % MU_locs: location of MU designes as the channel with max p2p (nMUs x 1)
subjDecompData.MU_locs_g2 = MU_locs_g2;


end