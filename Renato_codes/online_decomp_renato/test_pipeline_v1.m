% Test pipeline

% path = "D:\Datasets\SingleDigitForceEMG\raw\S15\S15_ss1_dig2_f10_t3.mat";
path = "/Users/renatomio/Library/CloudStorage/OneDrive-UniversitätBayreuth/2Laptop/S15_ss1_dig2_f10_t3.mat";
load(path)
fs = 2000;
fs_force = 50;
digit = 2;
ElChannelMap = getElChannelMap("HD08MM1305");

[emg, emg_rms, emg_rms_grid1, emg_rms_grid2, emg_power, force, force_rmse, digit_ind, badchan, goodchan, SNR, discard] = ...
                    proc_hdemg(recordedEMG,recordedForce, fTrace, digit, fs,fs_force, ElChannelMap);

%% Prepare to decompose
% Decomposition parameters
NITER = 25; % it was 150 before, but not many iterations needed since it is a very long recording
ref_exist = 1; % if ref_signal exist ref_exist = 1; if not ref_exist = 0 and manual selection of windows
checkEMG = 0; % 0 = Consider all the channels ; 1 = Visual checking
differentialmode = 0; % 0 = no; 1 = yes (filter out the smallest MU, can improve decomposition at the highest intensities
initialization = 1; % 0 = max EMG; 1 = random weights
peeloff_flag = 1; % 0 = no; 1 = yes (update the residual EMG by removing the motor units with the highest SIL value)
covfilter = 1; % 0 = no; 1 = yes (filter out the motor units with a coefficient of variation of their ISI > than parameters.covthr)
refineMU = 1; % 0 = no; 1 = yes (refine the MU spike train over the entire signal 1-remove the discharge times that generate outliers in the discharge rate and 2- reevaluate the MU pulse train)
preproc_flag = 1; % 0 = no; 1 = yes (apply notch and bandpass, if the signal has not been preprocessed)
padLen = 200; % length to add zero padding to our signal only during decomposition (sometimes needed to prevent decomposition mistakes)

% SPECIFIC VALUES
nbelectrodes = 64; % number of electrodes per grid or array
thresholdtarget = 0.8; % threshold to segment the target displayed to the participant, 1 being the maxima of the target (e.g., plateau)
nbextchan = 1000; % nb of extended channels (1000 in Negro 2016, can be higher to improve the decomposition)
contrastfunc = 'skew'; % contrast functions: 'skew', 'kurtosis', 'logcosh'
silthr = 0.9; % Threshold for SIL values
covthr = 0.7; % Threshold for CoV of ISI values
peeloffwin = 0.025; % duration of the window (ms) for detecting the action potentials from the EMG signal
duplicatesthresh = 0.3; % threshold that define the minimal percentage of common discharge times between duplicated motor units
CoVDR = 0.3; % threshold that define the CoV of Discharge rate that we want to reach for cleaning the MU discharge times when refineMU is on

IED = 8; % inter-electrode distance


%% Try using I-Spin functions

nbextchan = 1000;
            
offsetMU = 0;
% for i=1:ngrids
% Crop to only have data from 20 to 30 seconds
SIG = emg(1:64,20*fs+1:30*fs);
SIG = SIG(goodchan<=64,:); % discard bad channels

% Signal Extension
exFactor = round(nbextchan/size(SIG,1));
eSIG = extend(SIG,exFactor);
eSIG = demean(eSIG);

% Signal Whitening
[E, D] = pcaesig(eSIG);
[wSIG, ~, dewhiteningMatrix] = whiteesig(eSIG, E, D);

% % Removing the edges
% wSIG = wSIG(:,round(fs):end-round(fs));

% FastICA
% Initialize matrix B (n x m) n: separation vectors, m: iterations 
% Initialize matrix MUFilters to only save the reliable filters
% Intialize SIL and PNR
B = zeros(size(wSIG,1), NITER); % all separation vectors
MUFilters = zeros(size(wSIG,1), NITER); % only reliable vectors
SIL = zeros(1,NITER);
COV = zeros(1,NITER);
%%
% Find the index where the square of the summed whitened vectors is
% maximized and initialize W with the whitened observations at this time
for j = 1:NITER
    if j == 1
        X = wSIG; % Initialize X (whitened signal), then X: residual
        w = randn(size(X,1),1); % Initialize w
    else
        w = randn(size(X,1),1); % Initialize w
    end
    
    w = w - B * B' * w; % Orthogonalization
    w = w / norm(w); % Normalization
    
    %       3a: Fixed point algorithm (end when sparsness is maximized)
    maxiter = 500; % max number of iterations for the fixed point algorithm
    w = fixedpointalg(w, X, B , maxiter, 'skew');
    
    % Step 4: Minimization of the CoV of discharge times (end when CoV is
    % minimized)
    % Initialize CoV (variation of interspike intervals, %) Step 4a => 4e
    [~, spikes] = getspikes(w, X, fs);
    
    if length(spikes) > 10 % If the number of peaks is low, skip the second algorithm
        ISI = diff(spikes/fs); % Interspike interval
        COV(j) = std(ISI)/mean(ISI); % Coefficient of variation
        Wini = sum(X(:,spikes),2); % update W by summing the spikes
                       
        % Minimization of the CoV of discharge times (end when CoV is minimized)
        [MUFilters(:,j), ~, COV(j)] = minimizeCOVISI(Wini, X, COV(j), fs);
        B(:,j) = w;
    
        % Calculate SIL values
        [~, ~, SIL(j)] = calcSIL(X, MUFilters(:,j), fs);
    else
        B(:,j) = w;
    end
    disp(['Iter : ' num2str(j) ' - SIL : ' num2str(round(SIL(j),2)) ' - COV : ' num2str(round(COV(j),2))]);

end

%% Filter out MUfilters below the SIL threshold
MUFilters(:,SIL < silthr) = [];
COV(SIL < silthr) = [];
SIL(SIL < silthr) = [];
MUFilters(:,COV > covthr) = [];
MUFilters = dewhiteningMatrix * MUFilters;

%% Get the pulse train for the entire signal
EMG = emg(1:64,20*fs+1:30*fs);
EMGmask = zeros(size(EMG,1),1);
EMGmask(badchan(badchan<=64)) = 1;
[PulseT, Distime, ~] = getPulseT(EMG, EMGmask, MUFilters, fs);

% Remove duplicates
[~, Distime] = remduplicates(PulseT, Distime, Distime, round(fs/40), 0.00025, 0.3, fs);

% Get the decomposition parameters for the biofeedback
MUFilters = getMUfilters(EMG, EMGmask, Distime);
[PulseT, Distime, ~] = getPulseT(EMG, EMGmask, MUFilters, fs);
[extensionfactor, iReSIG, norm, centroid] = getonlineparameters(EMG, EMGmask, MUFilters, fs);

%% Plot

time = linspace(0,size(PulseT,2)/fs,size(PulseT,2));

for k = 1:length(Distime)
    plot(time, PulseT(k,:)+k+offsetMU, time(Distime{k}), PulseT(k,Distime{k})+k+offsetMU, 'o', 'LineWidth', 1.5, 'MarkerSize', 10, 'Color', [0.9412 0.9412 0.9412], 'MarkerEdgeColor', [0.81 0.50 1.00]);
    hold on
    Dischargetimes{k} = Distime{k};
    DR(k) = mean(1./(diff(Distime{k})/fs));
end
    
offsetMU = offsetMU + length(Distime) + 1;
    
% signal.EMGmask{i} = badchan<=64;
% app.DecompParameters.EMGmask{i} = badchan<=64;
% signal.Pulsetrain{i} = PulseT;
% signal.gridname{i} = app.file.signal.gridname{i};
% signal.SIL{i} = SIL;
% signal.COV{i} = COV;
% 
% clearvars Distime PulseT B w wSIG X E D eSIG SIG maskEMG SIL COV

% C1 = strsplit(app.XaxisdisplayedDropDown.Value,'_');
% idxmuscle1 = str2double(C1{2});
% 
% durationonline = (Durationplateau * fs + 2*Durationramp*fs + 2*Durationrest*fs) * Nbiterations;

%% Perform reverse procedure using MUfilters

Refreshrate = 60; % Hz
durationonline = size(EMG,2);
nsamp = floor(fs/Refreshrate);

nwin = floor(durationonline/nsamp);
nwinbuff = floor(fs*5/nsamp);
k = 1; % index for the window

% Pre allocate empty matrices
Time = linspace(0,nwin*nsamp/fs,nwin*nsamp);
EMG = zeros(size(emg(1:64,20*fs+1:30*fs)));
Force = NaN(1,durationonline);
% forceidx = find(gridchannels == 7, 1, 'First');    
% idxgrids = gridchannels(gridchannels < 7 & gridchannels > 0);

EMGtmp1 = zeros(size(EMG,1),nsamp); % nsamp is samples in the time window for biofeedback
EMGtmp2 = zeros(sum(EMGmask==0),nsamp);
esample2 = zeros(sum(EMGmask==0)*extensionfactor,extensionfactor-1);
Distime = zeros(nwin*nsamp, size(MUFilters,2));
Pulsetrain = zeros(size(MUFilters,2), nsamp*nwin);
noise_centroids = ones(nsamp,size(MUFilters,2)) .* (centroid(:,1)');
spike_centroids = ones(nsamp,size(MUFilters,2)) .* (centroid(:,2)');
MUfilt = MUFilters' * iReSIG;
MUoffset = 1:1:size(MUFilters,2);
forcefb = zeros(1,nwin);
feedback = zeros(1,nwin);

% % Set the properties of the axes for data viz
% 
% plot(app.UIAxes4, Time(1:str2double(app.FrequencyDropDown.Value)*5), Distime(1:str2double(app.FrequencyDropDown.Value)*5,:).*MUoffset, '|', 'LineWidth', 4, 'MarkerSize', 20)
% plot(app.UIAxes5, 1, forcefb(k),'o', 'LineWidth', 4, 'MarkerSize', 20)
% line(app.UIAxes5,[0 2], [feedback(k)*0.95 feedback(k)*0.95],'LineWidth', 4)
% line(app.UIAxes5,[0 2], [feedback(k)*1.05 feedback(k)*1.05],'LineWidth', 4)          
% plot(app.UIAxes2, Time, app.OnlineParameters.targetonline, Time(k*app.ComParameters.nsamp), app.OnlineParameters.targetonline(k*app.ComParameters.nsamp), 'o', 'MarkerSize', 20, 'LineWidth', 2);
% 
% app.UIAxes4.XLim = [Time(1) Time(str2double(app.FrequencyDropDown.Value)*5)];
% app.UIAxes4.YLim = [0.5 size(app.DecompParameters.MUFilters{idxmuscle1},2)+0.5];
% app.UIAxes5.XLim = [0 2];
% app.UIAxes5.YLim = [0 max(app.OnlineParameters.targetonline)*1.25];
% app.UIAxes4.XColor = [0.9412 0.9412 0.9412];
% app.UIAxes4.YColor = [0.9412 0.9412 0.9412];
% app.UIAxes5.XColor = [0.9412 0.9412 0.9412];
% app.UIAxes5.YColor = [0.9412 0.9412 0.9412];
% xlabel(app.UIAxes4,'Time (s)');
% ylabel(app.UIAxes4,'MU Discharge times');
% app.UIAxes4.ColorOrder = cool(30);
% app.UIAxes5.ColorOrder = cool(3);
% app.UIAxes2.ColorOrder = cool(2);

% % Get the data
% app.ComParameters.ConfString(1) = app.ComParameters.ConfString(1) + 1; % Update the first byte that start the data transer
% app.ComParameters.ConfString(40) = CRC8(app.ComParameters.ConfString, 39);
% fopen(app.ComParameters.tcpSocket);
% set(app.ComParameters.tcpSocket, 'ByteOrder', 'little-endian');
% fwrite(app.ComParameters.tcpSocket, app.ComParameters.ConfString, 'uint8'); % Send the configuration to quattrocento

while k <= nwin - floor(nwinbuff/2)
    data = emg(1:64,20*fs+1:30*fs);
    EMG(:,(k-1)*nsamp+1:k*nsamp) = data(:,(k-1)*nsamp+1:k*nsamp);
    % Force(:,(k-1)*nsamp+1:k*nsamp) = (data(forceidx,:) - offsetforce);
    % forcefb(k) = mean(abs(Force((k-1)*nsamp+1:k*nsamp)));
    %feedback(k) = mean(app.OnlineParameters.targetonline((k-1)*app.ComParameters.nsamp+1:k*app.ComParameters.nsamp));
    
    EMGtmp1 = EMG(:, (k-1)*nsamp+1:k*nsamp);
    EMGtmp2 = EMGtmp1(EMGmask==0, :); % good channels

    [Pulsetrain(:,(k-1)*nsamp+1:k*nsamp), Distime((k-1)*nsamp+1:k*nsamp, :), esample2] = getspikesonline(EMGtmp2, extensionfactor, esample2, MUfilt, norm, noise_centroids, spike_centroids, nsamp, fs);
    
%     if k <= round(nwinbuff/2)
%         plot(app.UIAxes4, Time(1:str2double(app.FrequencyDropDown.Value)*5), Distime(1:str2double(app.FrequencyDropDown.Value)*5,:).*MUoffset, '|', 'LineWidth', 4, 'MarkerSize', 20)
%         app.UIAxes4.XLim = [Time(1) Time(str2double(app.FrequencyDropDown.Value)*5)];
%         plot(app.UIAxes5, 1, forcefb(k)/app.RecordParameters.MVC * 100,'o', 'LineWidth', 4, 'MarkerSize', 20)
%         line(app.UIAxes5,[0 2], [feedback(k)*0.95 feedback(k)*0.95],'LineWidth', 4)
%         line(app.UIAxes5,[0 2], [feedback(k)*1.05 feedback(k)*1.05],'LineWidth', 4)
%         plot(app.UIAxes2, Time, app.OnlineParameters.targetonline, Time(k*app.ComParameters.nsamp), app.OnlineParameters.targetonline(k*app.ComParameters.nsamp), 'o', 'MarkerSize', 20, 'LineWidth', 2);
%     else
%         plot(app.UIAxes4, Time((k-1)*app.ComParameters.nsamp+1-str2double(app.FrequencyDropDown.Value)*2.5:str2double(app.FrequencyDropDown.Value)*2.5+(k-1)*app.ComParameters.nsamp), Distime((k-1)*app.ComParameters.nsamp+1-str2double(app.FrequencyDropDown.Value)*2.5:str2double(app.FrequencyDropDown.Value)*2.5+(k-1)*app.ComParameters.nsamp,:).*MUoffset, '|', 'LineWidth', 4, 'MarkerSize', 20)
%         app.UIAxes4.XLim = [Time((k-1)*app.ComParameters.nsamp+1-str2double(app.FrequencyDropDown.Value)*2.5) Time(str2double(app.FrequencyDropDown.Value)*2.5+(k-1)*app.ComParameters.nsamp)];
%         plot(app.UIAxes5, 1, forcefb(k)/app.RecordParameters.MVC * 100,'o', 'LineWidth', 4, 'MarkerSize', 20)
%         line(app.UIAxes5,[0 2], [feedback(k)*0.95 feedback(k)*0.95],'LineWidth', 4)
%         line(app.UIAxes5,[0 2], [feedback(k)*1.05 feedback(k)*1.05],'LineWidth', 4)
%         plot(app.UIAxes2, Time, app.OnlineParameters.targetonline, Time(k*app.ComParameters.nsamp), app.OnlineParameters.targetonline(k*app.ComParameters.nsamp), 'o', 'MarkerSize', 20, 'LineWidth', 2);
%     end
%     drawnow limitrate
    k = k+1;
end

%% Verify decomposition

% First, change "Distime" to the previous "Dischargetimes" variable format
% Preallocate cell array
Dischargetimes_online = cell(1, size(Distime, 2));

% Find and store nonzero indices per column
for mu = 1:size(Distime, 2)
    Dischargetimes_online{mu} = find(Distime(:, mu)); % Row indices for each column
end

% Access example: Dischargetimes_online{2} gives nonzero row indices for column 2
disp(Dischargetimes_online);

figure;
for mu = 1:length(Dischargetimes_online)
    plot(Time, Pulsetrain(mu,:)+mu+offsetMU, Time(Dischargetimes_online{mu}), Pulsetrain(mu,Dischargetimes_online{mu})+mu+offsetMU, 'o', 'LineWidth', 1.5, 'MarkerSize', 10, 'Color', [0.9412 0.9412 0.9412], 'MarkerEdgeColor', [0.81 0.50 1.00]);
    hold on
    % Dischargetimes{k} = Distime{k};
    DR_online(mu) = mean(1./(diff(Dischargetimes_online{mu})/fs));
end
title("Decomposed with MU filters")

%%


app.ComParameters.ConfString(1) = app.ComParameters.ConfString(1) - 1; % Update the first byte that start the data transer
app.ComParameters.ConfString(40) = CRC8(app.ComParameters.ConfString, 39);            
fwrite(app.ComParameters.tcpSocket, app.ComParameters.ConfString, 'uint8');
fclose(app.ComParameters.tcpSocket); % Close the communication
flush(app.ComParameters.tcpSocket)

% Save the data
signal.data = EMG(idxgrids == idxmuscle1, :);
signal.allEMG = EMG;
signal.target = app.OnlineParameters.targetonline;
signal.path = Force;
signal.fsamp = str2double(app.FrequencyDropDown.Value);
signal.muscle{1} = app.RecordParameters.Muscles{idxmuscle1};
signal.nChan = size(EMG,1);
signal.ngrid = app.RecordParameters.ngrid;
signal.EMGmask{1} = app.DecompParameters.EMGmask{idxmuscle1};
signal.gridname{1} = app.file.signal.gridname{idxmuscle1};
signal.coordinates = app.RecordParameters.coordinates;
signal.emgtype = app.RecordParameters.emgtype;
signal.IED = app.RecordParameters.IED;
signal.feedback{1} = 'Raster plot';
for mu = 1:size(Distime,2)
    signal.Dischargetimes{mu} = find(Distime(:,mu) > 0)';
end
for mu = 1:size(AUX,1)
    signal.auxiliaryname{mu} = ['Auxiliary #' num2str(mu)];
end
save([app.EditField_saving.Value 'Online ' replace(datestr(datetime('now')),':','_') '.mat'], 'signal');

% Update the results of the last decomposition
app.OnlineParameters.Timeplot = linspace(0,size(signal.Pulsetrain{1},2)/str2double(app.FrequencyDropDown.Value),size(signal.Pulsetrain{1},2));
app.OnlineParameters.Dischargetimes = {};
nMU = 1;
app.OnlineParameters.Pulsetrain = signal.Pulsetrain{1};
for j = 1:size(Distime,2)
    app.OnlineParameters.Dischargetimes{nMU} =  signal.Dischargetimes{1,j};
    nMU = nMU + 1;
end
clearvars Distime

% Updates the parameters of the decomposition
% EMG = EMG(:,str2double(app.FrequencyDropDown.Value):end);
% [~, Distime, ~] = getPulseT(EMG, app.RecordParameters.DiscardChannels{idxmuscle1}, app.DecompParameters.MUFilters{idxmuscle1}, str2double(app.FrequencyDropDown.Value));
% app.DecompParameters.MUFilters{idxmuscle1} = getMUfilters(EMG, app.RecordParameters.DiscardChannels{idxmuscle1}, Distime);

% Update the UI for the next acquisition
app.InitialisetheaquisitionButton.Enable = 'on';
app.StoptheacquisitionButton.Enable = 'off';
app.StartQuadrantButton.Enable = 'off';
app.StartRasterPlotButton.Enable = 'off';
app.StartDRtrackingButton.Enable = 'off';
app.DisplaythePulsetrainsButton.Enable = 'on';
