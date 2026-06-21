function [emg, emg_rms, emg_rms_grid1, emg_rms_grid2, emg_power, force, force_rmse, digit_ind, badchan, goodchan, SNR, discard] = ...
    proc_hdemg(raw_emg, raw_force, force_trace, digit, fs,fs_force, ElChannelMap)
%{
    Preprocess HD EMG grid data

    raw_emg: row-wise signal
    raw_force: column-wise force channels paths
    fs: emg sampling rate
    fs_force: force sampling rate
    ElChannelMap: electrode channel map, a matrix for mapping 2D positions of the electrode channels 

    @author: Renato Mio
    Created: 25.10.2024

%}

%% Step 0: Verify dimensions
% For force
nSamplesF = size(raw_force,1);
disp(strcat("Number of force samples: ",num2str(nSamplesF)))
targetMVF = max(force_trace); % should be 10% or 20%
if targetMVF==10 % % at 10%, trials last 74 secs
    if not(nSamplesF==74*fs_force) % there could be one missing sample, we pad it at the end with last force value
        warning("Wrong force dimension, a fix will be attempted")
        raw_force = padarray(raw_force,[74*fs_force-size(raw_force,1) 0],'replicate','post');
    end
else % at 20%, trials last 78 secs
    if not(nSamplesF==78*fs_force)
        warning("Wrong force dimension, a fix will be attempted")
        raw_force = padarray(raw_force,[78*fs_force-size(raw_force,1) 0],'replicate','post');
    end
end % Now the force sample should have the right dimension.
% For EMG
nSamplesEmg = size(raw_emg,2);
nSamplesF = size(raw_force,1);
disp(strcat("Number of EMG samples: ",num2str(nSamplesEmg)))
if not(nSamplesEmg / fs == nSamplesF / fs_force)
    warning("Mismatch in force and EMG dimensions, a fix will be attempted")
    if nSamplesEmg > nSamplesF * fs / fs_force  % EMG has more samples, so crop
        raw_emg2 = raw_emg(:, 1:end - fs / fs_force);
        nSamplesEmg = size(raw_emg2, 2);
        % Second check for mismatch
        if not(nSamplesEmg / fs == nSamplesF / fs_force)
            raw_emg2 = raw_emg2(:, fs/fs_force+1:end );  % Try cropping once more from the other side
            nSamplesEmg = size(raw_emg2, 2);
            % Third check: if mismatch persists, crop both edges
            if not(nSamplesEmg / fs == nSamplesF / fs_force)
                len2crop = (nSamplesEmg - nSamplesF * fs / fs_force) / 2;
                raw_emg2 = raw_emg2(:, len2crop + 1:end - len2crop);
                nSamplesEmg = size(raw_emg2, 2);
                if not(nSamplesEmg / fs == nSamplesF / fs_force)
                    error("Dimensions of EMG and force not consistent")
                else
                    raw_emg = raw_emg2;
                end
            else
                raw_emg = raw_emg2;
            end
        else
            raw_emg = raw_emg2;
        end
    elseif nSamplesEmg < nSamplesF * fs / fs_force  % EMG has fewer samples, so pad
        paddingLength = nSamplesF * fs / fs_force - nSamplesEmg;
        raw_emg = padarray(raw_emg, [0 paddingLength], 'replicate', 'post');
    end
end
%% Step 1: Automatically detect bad channels
% First, detect flat
flatchan = find(not(any(raw_emg,2))); % indexes of rows of flat (full of zeros) channels
% To detect noisy channels, measure SNR or RMS
emg_rms = rms(raw_emg,2); % get RMS
noisychan = find(isoutlier(emg_rms,"mean")); % finds outliers more than 3 std away from mean
% Merge arrays to get bad channels
badchan = unique(sort([flatchan; noisychan],'descend'));
goodchan = setdiff(1:size(raw_emg, 1), badchan); % get the good channel indexes

%% Step 2: Preprocess with notch and bandpass filters
emg = raw_emg;
% emg = demean(emg) % demean, if needed
% Apply notch and bandpass
emg = adaptiveNotchFilter(emg,fs); 
emg = bandpassingals(emg,fs, 1);

%% Step 5: Get Signal-to-Noise Ratio
% Compute SNR only after preprocessing as the ratio between the active area (60 secs in the middle) and the first 3 seconds (6144 samples)
edgeLenEmg = (size(emg,2) - 60*fs)/2; % length of the edges in samples
SNR = 10*log10( mean(emg(:,edgeLenEmg+1:(60*fs+edgeLenEmg)).^2,2)...
    ./mean(emg(:,1:3*fs).^2,2) );
% lowSNRchan = find(SNR<10); % Find channels with low SNR by thresholding
lowSNRchan = find(isoutlier(SNR)); % Find channels with low SNR by outlier detection
badchan = unique(sort([badchan; lowSNRchan],'descend'));  % add to bad channels list
goodchan = setdiff(1:size(raw_emg, 1), badchan); % update the good channel indexes

%% Step 3: Get new RMS and activations map
% get rms for the active part (60 secs in the middle)
emg_rms = rms(emg(:,edgeLenEmg+1:(60*fs+edgeLenEmg)),2);
% get in grid form per each grid
emg_rms_grid1 = signal2grid(emg_rms(1:64),ElChannelMap);
emg_rms_grid2 = signal2grid(emg_rms(65:128),ElChannelMap);
% replace bad channels before plotting
emg_rms_grid1 = replaceBadChannels(emg_rms_grid1, ElChannelMap, badchan(badchan<=64));
emg_rms_grid2 = replaceBadChannels(emg_rms_grid2, ElChannelMap, badchan(badchan>64)-64);

% imagesc(emg_rms_grid1)

%% Step 4: Get mean EMG power (excluding bad channels) over time
% get emg envelope
downsample_factor = 1;
cutoff_freq = 5; % Cutoff frequency in Hz
% compute the low-passed power and downsample it
[emg_power, downsampled_time] = lowpassed_downsample_emg(emg, fs, downsample_factor, cutoff_freq);
% % Optionally:
% % get mean per trial, because badchan might differ between trials
% emg_pow_mean = mean(emg_power(goodchan,:),1);
% emg_pow_std = std(emg_power(goodchan,:),1,1);
% % Also per grid
% emg_pow_mean1 = mean(emg_power(goodchan(goodchan<=64),:),1);
% emg_pow_std1 = std(emg_power(goodchan(goodchan<=64),:),1,1);
% emg_pow_mean2 = mean(emg_power(goodchan(goodchan>64),:),1);
% emg_pow_std2 = std(emg_power(goodchan(goodchan>64),:),1,1);



%% Step X: Force processing (to complete later)
windowSize = 25;  % Choose a window size based on your data
threshold = 3;   % Number of standard deviations

force = hampel(raw_force, windowSize, threshold);
force = force'; % convert to row-wise

% compute RMSE
force_rmse = sqrt( mean( (force(digit,:) - force_trace).^2, 2) ); % RMSE computed agains ideal force trace

% Compute digit individuation (only during tracking)

edgeLenF = (size(force,2) - 60*fs_force)/2;% length of the edges in samples
force_rms = rms(force(:,edgeLenF+1:(60*fs_force+edgeLenF)),2);
fTrace_rms = rms(force_trace(edgeLenF+1:(60*fs_force+edgeLenF))); % this should be equal to either 10 or 20
target_rms = force_rms(digit);

% Here we can use the RMS to check wether the right digit was targeted
discard = false;
if not(max(force_rms) == force_rms(digit))
    warning("Target digit labeled is not the same digit used in the experiment")
    discard = true; % we discard the trial for now
end

% Get rms for other fingers
nontargets_rms = sum(force_rms(setdiff(1:length(force_rms),digit))); % sum of non-target digits force rms
digit_ind = (target_rms-nontargets_rms) / fTrace_rms;% individuation metric

% Other filter options were lowpass, sgolayfilt, local outlier factor,
% movmedian, but hampel performed the best.

% % Apply Savitzky-Golay filter
% polyOrder = 3;  % Order of polynomial
% frameSize = 35;  % Window size
% force = sgolayfilt(raw_force, polyOrder, frameSize);

% force = lowpass(force,0.001,fs_force); % smoothing with a low-pass

% % Detect outliers using Local Outlier Factor
% spikeIndices = isoutlier(recordedForce, 'movmedian', 5);  % 5-point window
% % Replace outliers
% clean_signal = recordedForce;
% clean_signal(spikeIndices) = NaN;
% % Interpolate to fill gaps
% clean_signal = fillmissing(clean_signal, 'linear');

% Variables to save: emg, rms, emg_rms_grid1, emg_rms_grid2, force, badchan, goodchan, fs, fs_force


end