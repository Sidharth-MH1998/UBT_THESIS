function decomp_results = decomp_Hyser_single_trial_2_SIL09(emg)

% Decompose a single trial of HD EMG using decompose2.mat function
% Each 8x8 electrode grid is decomposed separately

% @author: Renato Mio
% Created: 26.08.2023

%% Analyse grids separately

grids = cell(4,1);
grids{1,1} = emg(:,1:64);
grids{2,1}= emg(:,65:128);
grids{3,1}= emg(:,129:192);
grids{4,1}= emg(:,193:256);

%% Decomposition parameters

% DECOMPOSITION PARAMETERS
NITER = 150;
ref_exist = 1; % if ref_signal exist ref_exist = 1; if not ref_exist = 0 and manual selection of windows
checkEMG = 0; % 0 = Consider all the channels ; 1 = Visual checking
differentialmode = 0; % 0 = no; 1 = yes (filter out the smallest MU, can improve decomposition at the highest intensities
initialization = 1; % 0 = max EMG; 1 = random weights
peeloff_flag = 1; % 0 = no; 1 = yes (update the residual EMG by removing the motor units with the highest SIL value)
covfilter = 0; % 0 = no; 1 = yes (filter out the motor units with a coefficient of variation of their ISI > than parameters.covthr)
refineMU = 1; % 0 = no; 1 = yes (refine the MU spike train over the entire signal 1-remove the discharge times that generate outliers in the discharge rate and 2- reevaluate the MU pulse train)
drawingmode = 0; % 0 = Output in the command window ; 1 = Output in a figure

% SPECIFIC VALUES
nbelectrodes = 64; % number of electrodes per grid or array
thresholdtarget = 0.8; % threshold to segment the target displayed to the participant, 1 being the maxima of the target (e.g., plateau)
nbextchan = 1000; % nb of extended channels (1000 in Negro 2016, can be higher to improve the decomposition)
edges = 0.2; % edges of the signal to remove after preprocessing the signal (in sec)
contrastfunc = 'skew'; % contrast functions: 'skew', 'kurtosis', 'logcosh'
silthr = 0.9; % Threshold for SIL values
covthr = 0.5; % Threshold for CoV of ISI values
peeloffwin = 0.025; % duration of the window (ms) for detecting the action potentials from the EMG signal
duplicatesthresh = 0.3; % threshold that define the minimal percentage of common discharge times between duplicated motor units
CoVDR = 0.3; % threshold that define the CoV of Discharge rate that we want to reach for cleaning the MU discharge times when refineMU is on


fs = 2048;
gridSize = [8 8];
IED = 8; % inter-electrode distance
%% Start performing decomposition over all grids and saving the results

% Struct to save results
decomp_results = struct("results",{[];[];[];[]});

for i=1:4
    disp(['Analysing grid #' num2str(i)])
    t_decomp = tic; % time to run decomposition

    emg_data = grids{i,1}';
    
    % add 500 samples silence at the beginning and ending (for processing purposes)
    emg_data= [zeros(size(emg_data,1),500) emg_data zeros(size(emg_data,1),500)]; 
    
    % C. Perform decomposition
    results = decompose2(emg_data, fs, initialization, NITER, nbextchan, silthr, covfilter, covthr, ...
    differentialmode, drawingmode, peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU)
    disp(['Finished analysing grid #' num2str(i)])
    decomp_results(i,1).decomp_time = toc(t_decomp);
    decomp_results(i,1).results = results;
end

% Important!
% logcosh yields little MUs
% expsqr converges to the same MUs again and again % maybe solve with peeloff
 
