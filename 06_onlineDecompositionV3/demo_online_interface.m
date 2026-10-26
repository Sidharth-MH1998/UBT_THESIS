function demo = demo_online_interface()
%DEMO_ONLINE_INTERFACE Preview the real online displays without hardware.
% Synthetic force and discharges illustrate the UI, not EMG decoding accuracy.
% Close either main window or press Stop/Close to end; figures remain on exit.
setup_online_dependencies();
durationSec = 20;
playbackSpeed = 1; % 1 = real time, 2 = twice as fast
fs = 2000;
nsamp = 256;
windowSec = nsamp/fs;
nMU = 5;
cfg = struct('visibleWindowSec',10,'showLegend',true,'frYLim',60);
cfg.muLabels = {'G1 MU1','G1 MU2','G1 MU3','G2 MU1','G2 MU2'};
cfg.quadrantXMU = 1;
cfg.quadrantYMU = 4; % Show one MU from each simulated grid
cfg.quadrantRateWindowSec = 1;
cfg.quadrantSmoothingWindows = 4;
cfg.quadrantHistorySec = 7.5;
cfg.quadrantAxisMax = [];

[forceFig, forceAx, rasterAx, closeButton, zeroButton, recordButton, ...
    trackButton] = setupRecordingFigure(true,0);
forceFig.Name = 'SIMULATION: Force and Multi-grid Spike Trains';
% Recording controls are inactive in this display-only preview.
set([zeroButton recordButton trackButton], 'Enable','off');
forceLines = initializeStreamForcePlot(forceAx,3);
sharedUI = struct('fig',forceFig,'axRaster',rasterAx);
[rateFig, plotState] = online_live_display('init',nMU,cfg,sharedUI);
rateFig.Name = 'SIMULATION: Multi-grid Firing Rates';
quadrant = ispin_quadrant_feedback('init',nMU,fs,windowSec,cfg);
quadrant.fig.Name = 'SIMULATION: G1 MU1 vs G2 MU1';
xlabel(quadrant.ax,'G1 MU1 discharge rate (pps)');
ylabel(quadrant.ax,'G2 MU1 discharge rate (pps)');

% Keep the simulation reproducible without changing MATLAB's global RNG.
random = RandStream('mt19937ar','Seed',17);
spikes = repmat({zeros(0,1)},1,nMU);
firingRates = repmat({zeros(0,1)},1,nMU);
lastSpike = -inf(1,nMU);
forceFs = 50;
forceTime = (0:ceil(durationSec*forceFs)-1)'/forceFs;
forceData = zeros(numel(forceTime),3);
for channel = 1:3
    forceData(:,channel) = 35 + 25*sin(2*pi*forceTime/(7+channel) + channel);
end
forceData = forceData + 0.6*randn(random,size(forceData));
sampleCursor = 0;
for window = 1:floor(durationSec/windowSec)
    if ~ishghandle(forceFig) || ~ishghandle(rateFig) || ...
            closeButton.Value || getappdata(rateFig,'stopRequested')
        break;
    end
    windowClock = tic;
    timeSec = window*windowSec;
    rates = 12 + 6*sin(2*pi*timeSec/8 + (0:nMU-1));
    detected = false(nsamp,nMU);
    for sample = 1:nsamp
        globalSample = sampleCursor + sample;
        for mu = 1:nMU
            if globalSample-lastSpike(mu) >= round(0.020*fs) && ...
                    rand(random) < rates(mu)/fs
                detected(sample,mu) = true;
                lastSpike(mu) = globalSample;
            end
        end
    end
    for mu = 1:nMU
        spikes{mu} = [spikes{mu}; find(detected(:,mu))+sampleCursor];
        firingRates{mu} = fs./diff(spikes{mu});
    end
    sampleCursor = sampleCursor + nsamp;
    forceIndex = min(size(forceData,1),floor(timeSec*forceFs));
    updateStreamForcePlot(forceAx,forceLines,forceData,forceFs,3,15,5,0,0,forceIndex);
    online_live_display('update',rateFig,plotState,spikes,firingRates,timeSec,cfg,fs);
    quadrant = ispin_quadrant_feedback('update',quadrant,detected,timeSec);
    drawnow;
    pause(max(0,windowSec/playbackSpeed-toc(windowClock)));
end
demo = struct('simulated',true,'fs',fs,'muLabels',{cfg.muLabels}, ...
    'Dischargetimes',{spikes},'fr',{firingRates}, ...
    'quadrant',ispin_quadrant_feedback('export',quadrant));
disp('Interface simulation finished. No hardware was connected or data saved.');
end
