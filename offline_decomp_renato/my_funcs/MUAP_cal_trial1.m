% Plot MUAPs trial

% Problem is that when plotting source MUAP waveform has high 
% peak-to-peak amplitudes in more than one center (like if it was more than
% one source)

%% Prodecure 1 - spike trigered average

% peeloffwin = 0.025; % duration of the window (ms) for detecting the action potentials from the EMG signal
win = 0.025;

windowl = round(win*fs); % 51 samples for 0.025 ms
X_e = emg_grid;
mu_index = 5;
spikes = signal.Dischargetimes{mu_index};
firings = zeros(1, size(X_e,2));
firings(spikes) = 1;
% EMGtemp = zeros(size(X_e));

waveform = zeros(size(X_e,1),windowl*2+1); % waveform would be 103 samples

for l = 1:size(X_e,1)
    temp = cutMUAP(spikes,windowl,X_e(l,:));
    waveform(l,:) = mean(temp,1);
%     EMGtemp(l,:) = conv(firings,waveform,'same');
end 

% figure
% plot(waveform)

figure
t = tiledlayout('flow'); % As we call nexttile, the layout reflows as needed to accommodate the new axes while maintaining an aspect ratio of roughly 4:3 for all the tiles.

t.Padding = "compact";
t.TileSpacing = "compact";
t.GridSize = [8 8];
ylims = [];
for i = 1:64
    ax = nexttile(t);
    plot(ax,waveform(i,:));
    ax.Box = "off";
    ax.XAxis.Visible = "off";
    ax.Title.String = "Channel " + string(i);
    ylims = [ylims ax.YLim];
end
ylim_max = max(ylims);
ylim_min = min(ylims);
for i = 1:64
    ax = nexttile(t,i);
    ax.YLim = [ylim_min ylim_max];
end


%% Procedure 2 - Not working

raw = emg_grid;
chan = size(raw, 1);

MUPulses = signal.Dischargetimes; % cell array containing the motor unit indices for each identified MU

MUAP_all = cell(1, numel(MUPulses));

for mu_index = 1:numel(MUPulses)

    peak_indices = MUPulses{mu_index}; % array containing the firing indices for MU number mu_index

    MUAP_indices = zeros(length(peak_indices), 2*l+1);

    for i = 1:length(peak_indices)
        val = peak_indices(i);
        MUAP_indices(i,:) = (val-l):(val+l);
    end

    MUAP_indices = reshape(MUAP_indices, [1 length(peak_indices)*(2*l+1)]);

    if any(MUAP_indices < 0)
        MUAP_indices(MUAP_indices < 0) = 0;
        warning("Negative indice was found for MUAP indices!")
    end

    if any(MUAP_indices >  size(raw, 2))
        MUAP_indices(MUAP_indices > size(raw, 2)) = size(raw,2);
        warning("MUAP indices larger than the raw sample number were found!")
    end

    MAUPs = reshape(raw(:, MUAP_indices),[chan length(peak_indices) 2*l+1]);
    MUAPs = mean(MAUPs, 2);
    MUAPs = squeeze(MUAPs);
    MUAP_all{mu_index} = MUAPs;
end


%% Plot one MUAP

mu_index = 3;
chan = size(MUAP_all{1}, 1);
MUAPs = MUAP_all{mu_index};

figure
t = tiledlayout('flow'); % As we call nexttile, the layout reflows as needed to accommodate the new axes while maintaining an aspect ratio of roughly 4:3 for all the tiles.

t.Padding = "compact";
t.TileSpacing = "compact";
t.GridSize = [ceil(sqrt(chan)) ceil(sqrt(chan))];
ylims = [];
for i = 1:chan
    ax = nexttile(t);
    plot(ax,MUAPs(i,:));
    ax.Box = "off";
    ax.XAxis.Visible = "off";
    ax.Title.String = "Channel " + string(i);
    ylims = [ylims ax.YLim];
end
ylim_max = max(ylims);
ylim_min = min(ylims);
for i = 1:chan
    ax = nexttile(t,i);
    ax.YLim = [ylim_min ylim_max];
end


%% Inspect spike trains

MUindices = signal.Dischargetimes;
    spike_train = zeros( size(X,2), size(MUindices,2));
    for k=1:size(MUindices,2)
        spike_train(MUindices{1,k}, k) = 1;
    end
spike_train = sparse(spike_train);

plot_spikeTrain(spike_train,fs,.99*ones(1,size(spike_train,2)),.9)
