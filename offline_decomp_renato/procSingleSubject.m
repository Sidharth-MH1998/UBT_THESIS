
%{
    Preprocess and decompose all trials of a single subject from dataset by
    Renato Mio and Jan Bodenschlaegel
    using decompose3.mat function

    Experiment consisted in 60 seconds thumb and index flexion at 10% and 20% of MVF
    Electrode grids were two 64-chan 8mm IED 13x5 (128 chan in total) applied over the forearm

    @author: Renato Mio
    Created: 26.09.2024

%}

% clear all
% close all

%% Initialisation

% subjects =["14"];
subjects = ["8", "9", "10", "11", "12"];
ss = "1"; % session
forces = ["10", "20"]; % MVF
digits = ["1", "2", "3"]; % only first three diigts were analysed
dig_labels = ["Thumb", "Index", "Middle", "Ring", "Little"];
trials = 5;
fs = 2000; % emg sampling rate
fs_force = 50; % force sampling rate

raw_path = "D:\Datasets\SingleDigitForceEMG\raw\S";
preproc_path = "D:\Datasets\SingleDigitForceEMG\preproc\S";
proc_path = "D:\Datasets\SingleDigitForceEMG\proc\";

% badchan_manual = [52, 63, 64, 76, 84, 90, 91, 92, 117, 127]; % manually annotated bad channels

ElChannelMap = getElChannelMap("HD08MM1305");

%% Iterate through all trials to preprocess
% 
% for S = 1:length(subjects)
% % for S = 1:1 % test on one subject
%     save_path = strcat(proc_path,"S",subjects(S),"_processed.mat");
%     if isfile(save_path) % if processed and saved already, we skip
%         disp(strcat("Subject ", subjects(S)," already processed"))
%         continue
%     end
% 
%     % Variables for aggregated data
%     % Save preprocessed emg, plus additional metrics
%     % digits x forces x trials x variable dimension
%     all_emg10 = zeros(length(digits),trials,128,74*fs); % at 10%, trials last 74 secs
%     all_emg20 = zeros(length(digits),trials,128,78*fs); % at 20%, trials last 78 secs
%     all_force10 = zeros(length(digits),trials,3,74*fs_force);
%     all_force20 = zeros(length(digits),trials,3,78*fs_force);
%     all_force_rmse = zeros(length(digits),length(forces),trials); % rmse between force path and target per trial
%     all_dig_ind = zeros(length(digits),length(forces),trials); % digit individuation score per trial
%     all_emg_rms = zeros(length(digits),length(forces),trials,128,1);
%     all_rms_g1 = zeros(length(digits),length(forces),trials,size(ElChannelMap,1),size(ElChannelMap,2));
%     all_rms_g2 = zeros(length(digits),length(forces),trials,size(ElChannelMap,1),size(ElChannelMap,2));
%     all_badchan = cell(length(digits),length(forces),trials);
%     all_goodchan = cell(length(digits),length(forces),trials);
%     all_SNR = zeros(length(digits),length(forces),trials,128,1);
%     discardTrial = zeros(length(digits),length(forces),trials); % flag for mistakes, we discard the trial
% 
%     for digit = 1:length(digits) % Iterate per digit 
%         for f = 1:length(forces) % 10 or 20% MVF
%             for t = 1:trials % trial 1 to 5
%                 disp(strcat("Loading subject ", subjects(S)," on session ",ss,", digit ",digits(digit),", force level ",forces(f),"%MVC and trial ",num2str(t)));    
%                 load(strcat(raw_path,subjects(S),"\S",subjects(S),"_ss",ss,"_dig",digits(digit),"_f",forces(f),"_t",num2str(t)))
%                 disp("Processing...")
%                 [emg, emg_rms, emg_rms_grid1, emg_rms_grid2, emg_power, force, force_rmse, digit_ind, badchan, goodchan, SNR, discard] = ...
%                     proc_hdemg(recordedEMG,recordedForce, fTrace, digit, fs,fs_force, ElChannelMap);
%                 % Save data in arrays
%                 if strcmp(forces(f),"10")
%                     all_emg10(digit,t,:,:) = emg;
%                     all_force10(digit,t,:,:) = force;
%                 else
%                     all_emg20(digit,t,:,:) = emg;
%                     all_force20(digit,t,:,:) = force;
%                 end
%                 all_emg_rms(digit,f,t,:,:) = emg_rms;
%                 all_force_rmse(digit,f,t) = force_rmse;
%                 all_dig_ind(digit,f,t) = digit_ind;
%                 all_rms_g1(digit,f,t,:,:) = emg_rms_grid1;
%                 all_rms_g2(digit,f,t,:,:) = emg_rms_grid2;
%                 all_badchan{digit,f,t} = badchan;
%                 all_goodchan{digit,f,t} = goodchan;
%                 discardTrial(digit,f,t) = discard;
%                 all_SNR(digit,f,t,:,:) = SNR;
%                 disp(strcat("Finished processing subject ", subjects(S)," on session ",ss,", digit ",digits(digit),", force level ",forces(f),"%MVC and trial ",num2str(t)));
%                 % save file (comment this line after the first complete run)
%             end
%         end
%     end
%     save(save_path, "all_emg10", ...
%                     "all_emg20", ...
%                     "all_force10", ...
%                     "all_force20", ...
%                     "all_force_rmse", ...
%                     "all_dig_ind", ...
%                     "all_emg_rms", ...
%                     "all_rms_g1", ...
%                     "all_rms_g2", ...
%                     "all_badchan", ...
%                     "all_goodchan", ...
%                     "all_SNR", ...
%                     "discardTrial", '-v7.3')
%     disp( strcat("Finished processing subject ", subjects(S)) );
% end
% 
%% Prepare to decompose
% Decomposition parameters
NITER = 100; % it was 150 before, but not many iterations needed since it is a very long recording
ref_exist = 1; % if ref_signal exist ref_exist = 1; if not ref_exist = 0 and manual selection of windows
checkEMG = 0; % 0 = Consider all the channels ; 1 = Visual checking
differentialmode = 0; % 0 = no; 1 = yes (filter out the smallest MU, can improve decomposition at the highest intensities
initialization = 1; % 0 = max EMG; 1 = random weights
peeloff_flag = 1; % 0 = no; 1 = yes (update the residual EMG by removing the motor units with the highest SIL value)
covfilter = 1; % 0 = no; 1 = yes (filter out the motor units with a coefficient of variation of their ISI > than parameters.covthr)
refineMU = 1; % 0 = no; 1 = yes (refine the MU spike train over the entire signal 1-remove the discharge times that generate outliers in the discharge rate and 2- reevaluate the MU pulse train)
preproc_flag = 0; % 0 = no; 1 = yes (apply notch and bandpass, if the signal has not been preprocessed)
padLen = 200; % length to add zero padding to our signal only during decomposition (sometimes needed to prevent decomposition mistakes)

% SPECIFIC VALUES
nbelectrodes = 64; % number of electrodes per grid or array
thresholdtarget = 0.8; % threshold to segment the target displayed to the participant, 1 being the maxima of the target (e.g., plateau)
nbextchan = 1000; % nb of extended channels (1000 in Negro 2016, can be higher to improve the decomposition)
contrastfunc = 'skew'; % contrast functions: 'skew', 'kurtosis', 'logcosh'
silthr = 0.7; % Threshold for SIL values
covthr = 1; % Threshold for CoV of ISI values
peeloffwin = 0.025; % duration of the window (ms) for detecting the action potentials from the EMG signal
duplicatesthresh = 0.3; % threshold that define the minimal percentage of common discharge times between duplicated motor units
CoVDR = 0.3; % threshold that define the CoV of Discharge rate that we want to reach for cleaning the MU discharge times when refineMU is on

IED = 8; % inter-electrode distance

%% Run decomposition

for S = 1:length(subjects)

    path = strcat(proc_path,"S",subjects(S),"_processed.mat");
    load(path)
    for digit = 1:length(digits) % Iterate per digit 
        for f = 1:length(forces) % 10 or 20% MVF
            for t = 1:trials % trial 1 to 5
                
                decomp_path = strcat(proc_path,"decomposed_sil_07_cov_on\S",subjects(S),"_ss",ss,"_dig",digits(digit),"_f",forces(f),"_t",num2str(t),".mat");
                disp(strcat("Loading subject ", subjects(S)," on session ",ss,", digit ",digits(digit),", force level ",forces(f),"%MVC and trial ",num2str(t)));    
                if isfile(decomp_path) % if decomposed already, we skip
                    disp("Already decomposed.")
                    continue
                end
                
                if strcmp(forces(f),"10")
                    emg = squeeze(all_emg10(digit,t,:,:));
                    force = squeeze(all_force10(digit,t,:,:));
                else
                    emg = squeeze(all_emg20(digit,t,:,:));
                    force = squeeze(all_force20(digit,t,:,:));
                end

                badchan = all_badchan{digit,f,t};
                goodchan = all_goodchan{digit,f,t};

                badchan_g1 = badchan(badchan<=64);
                goodchan_g1 = goodchan(goodchan<=64);
                badchan_g2 = badchan(badchan>64);
                goodchan_g2 = goodchan(goodchan>64);

                if length(badchan_g1) == 64 || length(badchan_g2) == 64
                    disp("Bad grid, trial discarded")
                    continue
                end

                disp("Decomposing first grid...")
                % 1st grid
                decomp_results_g1 = decompose3(emg(1:64,:), fs, badchan_g1, padLen, initialization, NITER, nbextchan, silthr, covfilter, covthr, ...
                    differentialmode, peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU, preproc_flag)
                % 2nd grid
                disp("Decomposing second grid...")
                decomp_results_g2 = decompose3(emg(65:end,:), fs, badchan_g2-64, padLen, initialization, NITER, nbextchan, silthr, covfilter, covthr, ...
                    differentialmode, peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU, preproc_flag)
                disp(strcat("Finished decomposing subject ", subjects(S)," on session ",ss,", digit ",digits(digit),", force level ",forces(f),"%MVC and trial ",num2str(t)));    
                
                % Check and remove duplicates between grids
                updatedDecompResults = removeDuplicateMUsBetweenGrids([decomp_results_g1 decomp_results_g2], fs);     
                decomp_results_g1 = updatedDecompResults(1);
                decomp_results_g2 = updatedDecompResults(2);

                % Save results
                save(decomp_path, "decomp_results_g1","decomp_results_g2","emg","force","badchan","goodchan","fs","fs_force")
            end
        end
    end
end

