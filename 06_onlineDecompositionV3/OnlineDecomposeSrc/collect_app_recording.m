function out = collect_app_recording(chunks, force, states, cfg, metadata, startSample, startTime)
%COLLECT_APP_RECORDING Assemble one explicitly recorded segment, independently of UI.
nMU = sum(cellfun(@(s) s.nMU,states));
out = struct('cfg',cfg,'metadata',metadata,'fs',cfg.fs, ...
    'startSample',startSample,'startSessionTime',startTime, ...
    'createdAt',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
    'simulation',~strcmp(cfg.acquisitionMode,'Hardware'));
online = struct();
if isempty(chunks.pulse)
    online.Pulsetrain = zeros(nMU,0);
    online.Distime = false(0,nMU);
else
    online.Pulsetrain = horzcat(chunks.pulse{:});
    online.Distime = vertcat(chunks.spikes{:});
end
online.EMG = zeros(numel(cfg.emgChannels),0);
if cfg.recordEMG && ~isempty(chunks.emg)
    online.EMG = horzcat(chunks.emg{:});
end
nSamples = size(online.Pulsetrain,2);
out.nWin = numel(chunks.pulse);
out.elapsedSec = nSamples/cfg.fs;
online.Time = (0:nSamples-1)/cfg.fs;
online.Dischargetimes = cell(1,nMU);
online.fr = cell(1,nMU);
online.mean_fr = nan(nMU,1);
for mu = 1:nMU
    online.Dischargetimes{mu} = find(online.Distime(:,mu));
    online.fr{mu} = cfg.fs./diff(online.Dischargetimes{mu});
    if ~isempty(online.fr{mu}), online.mean_fr(mu) = mean(online.fr{mu}); end
end
online.force = force;
online.force.Time = force.sessionTime-startTime;
online.force.fs = cfg.forceFs;
online.force.calibrationFactors = cfg.forceCalibration.calibrationFactors;
online.force.zeroValues = cfg.forceCalibration.zeroValues;
online.force.reverseStates = cfg.forceCalibration.reverseStates;
online.force.extensionPositive = cfg.extensionPositive;
online.force.simulated = ~strcmp(cfg.acquisitionMode,'Hardware');
if isfield(cfg,'forceSource')
    online.force.source = cfg.forceSource;
    online.force.simulated = strcmp(cfg.forceSource,'simulated');
    if strcmp(cfg.forceSource,'recorded')
        % Values are already calibrated in the source file. Original coefficients are unknown.
        online.force.calibrationFactors = [];
        online.force.zeroValues = [];
        online.force.reverseStates = [];
        online.force.extensionPositive = [];
        online.force.calibrationAppliedDuringReplay = false;
    end
end
out.replay = strcmp(cfg.acquisitionMode,'Replay calibration');
online.ngrid = numel(states);
online.muMap = zeros(nMU,2);
online.gridResults = cell(1,numel(states));
online.PulsetrainByGrid = cell(1,numel(states));
online.DischargetimesByGrid = cell(numel(states),max(cellfun(@(s) s.nMU,states)));
for g = 1:numel(states)
    state = states{g};
    ids = state.muIndices;
    result = struct('grid',g,'fsamp',cfg.fs,'time',online.Time, ...
        'calibChannels',state.calibChannels, ...
        'emgChannels',cfg.emgChannels(state.channelRows), ...
        'EMGmask',state.mask,'MUOriginalIDs',state.originalIDs, ...
        'globalMUIndices',ids,'MUfilt',state.MUfilt, ...
        'extensionfactor',state.extensionfactor, ...
        'normval',state.normval,'centroid',state.centroid);
    result.Pulsetrain = online.Pulsetrain(ids,:);
    if isfield(cfg,'quadrantReferenceRates')
        result.referenceRatePPS = cfg.quadrantReferenceRates(ids);
    end
    result.Distime = online.Distime(:,ids);
    result.Dischargetimes = online.Dischargetimes(ids);
    result.fr = online.fr(ids);
    result.mean_fr = online.mean_fr(ids);
    result.EMG = online.EMG(state.channelRows,:);
    online.gridResults{g} = result;
    online.PulsetrainByGrid{g} = result.Pulsetrain;
    online.DischargetimesByGrid(g,1:state.nMU) = result.Dischargetimes;
    online.muMap(ids,:) = [repmat(g,state.nMU,1) (1:state.nMU)'];
end
out.online = online;
end
