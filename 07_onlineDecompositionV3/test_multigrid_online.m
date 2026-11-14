function test_multigrid_online()
% Hardware-free regression checks for independent multi-grid streaming.
folder = fileparts(mfilename('fullpath'));
addpath(folder);
setup_online_dependencies();
rng(7);
fs = 2000;
states = cell(1,3);
states{1} = make_state(1:3, [false true false], 2, 1:2);
states{2} = make_state(4:7, [true false false true], 1, 3);
states{3} = make_state(8:9, [true true], 0, []);
initialStates = states;
emg = randn(9,256);

% Compare two consecutive combined windows against independent single-grid calls.
referenceStates = states;
for window = 1:2
    [pulse, spikes, states] = decode_online_grid_window(emg, states, fs);
    assert(isequal(size(pulse), [3 256]));
    assert(isequal(size(spikes), [256 3]) && islogical(spikes));
    for gridIdx = 1:2
        ref = referenceStates{gridIdx};
        block = emg(ref.channelRows,:);
        [p, d, ref.overlap] = getspikesonline(block(~ref.mask,:), ...
            ref.extensionfactor, ref.overlap, ref.MUfilt, ref.normval, ...
            repmat(ref.centroid(:,1)',256,1), ...
            repmat(ref.centroid(:,2)',256,1),256,fs);
        assert(isequal(pulse(ref.muIndices,:), p));
        assert(isequal(spikes(:,ref.muIndices), d));
        assert(isequal(states{gridIdx}.overlap, ref.overlap));
        referenceStates{gridIdx} = ref;
    end
    emg = randn(9,256);
end

% Changing another grid or a masked electrode must not affect grid 1.
[baseline, baselineSpikes] = decode_online_grid_window(emg, initialStates, fs);
emg(4:9,:) = 100*randn(6,256);
emg(2,:) = 1e6*randn(1,256);
[changed, changedSpikes] = decode_online_grid_window(emg, initialStates, fs);
assert(isequal(baseline(1:2,:), changed(1:2,:)));
assert(isequal(baselineSpikes(:,1:2), changedSpikes(:,1:2)));

% Single-grid operation uses exactly the same decoder.
[singlePulse, singleSpikes] = decode_online_grid_window(emg, initialStates(1), fs);
assert(isequal(singlePulse, changed(1:2,:)));
assert(isequal(singleSpikes, changedSpikes(:,1:2)));

% Prepare realistic grid calibration with unequal MU counts and padded cells.
nSamples = 2400;
signal = struct('fsamp',fs,'ngrid',3);
signal.data = randn(192,nSamples);
signal.EMGmask = {zeros(64,1), zeros(64,1), ones(64,1)};
signal.EMGmask{1}(2) = 1;
signal.EMGmask{2}([1 4]) = 1;
signal.Pulsetrain = {zeros(2,nSamples), zeros(1,nSamples), zeros(0,nSamples)};
signal.Dischargetimes = cell(3,2);
signal.Dischargetimes(1,:) = {100:100:2200, 150:130:2200};
signal.Dischargetimes{2,1} = 180:150:2200;
signal.onlineMUOriginalIDs = {[2 5], 7, []};
for gridIdx = 1:2
    for mu = 1:size(signal.Pulsetrain{gridIdx},1)
        channels = (gridIdx-1)*64 + (1:64);
        pattern = randn(64,1);
        signal.data(channels,signal.Dischargetimes{gridIdx,mu}) = ...
            signal.data(channels,signal.Dischargetimes{gridIdx,mu}) + 20*pattern;
    end
end
cfg.calibChannels = 1:192;
cfg.emgChannels = reshape((1:64).' + 70*(0:2),1,[]);
parameters.gridChannels = {1:64,65:128,129:192};
rng(11);
[prepared, mapping] = prepare_online_grid_states(signal, parameters, cfg);
assert(isequal(mapping, [1 1; 1 2; 2 1]));
assert(isequal(prepared{2}.channelRows,65:128));
assert(isequal(prepared{1}.originalIDs,[2 5]));
assert(prepared{3}.nMU == 0);
onlineBlock = signal.data(:,1:256);
[p,d] = decode_online_grid_window(onlineBlock,prepared,fs);
assert(isequal(size(p),[3 256]) && all(isfinite(p(:))));
assert(isequal(size(d),[256 3]));

% Calibration must match direct I-Spin calls for every nonempty grid.
rng(11);
for gridIdx = 1:2
    rows = parameters.gridChannels{gridIdx};
    nGridMU = size(signal.Pulsetrain{gridIdx},1);
    filters = getMUfilters(signal.data(rows,:),signal.EMGmask{gridIdx}, ...
        signal.Dischargetimes(gridIdx,1:nGridMU));
    [extension,inverseCov,normalization,centroids] = getonlineparameters( ...
        signal.data(rows,:),signal.EMGmask{gridIdx},filters,fs);
    assert(prepared{gridIdx}.extensionfactor == extension);
    assert(isequal(prepared{gridIdx}.MUfilt, filters'*inverseCov));
    assert(isequal(prepared{gridIdx}.normval, normalization));
    assert(isequal(prepared{gridIdx}.centroid, centroids));
end

% Shared recorder defaults keep auxiliary channels out of two-grid EMG.
streamRows = reshape((1:64).' + 70*(0:1),1,[]);
hardwareCfg = makeNovecentoConfig(0.128,1:2,streamRows);
assert(isequal(hardwareCfg.emgChannels,[1:64 71:134]));
assert(isequal(find(hardwareCfg.IN_Active)',1:2));

% A calibration-channel permutation must preserve paired stream routing.
permutation = randperm(192);
cfg.calibChannels = cfg.calibChannels(permutation);
cfg.emgChannels = cfg.emgChannels(permutation);
rng(31);
[permuted, map2] = prepare_online_grid_states(signal,parameters,cfg);
% Test routing using the same prepared numerical filters to avoid kmeans randomness.
for gridIdx = 1:3
    permuted{gridIdx} = prepared{gridIdx};
    [~,permuted{gridIdx}.channelRows] = ...
        ismember(prepared{gridIdx}.calibChannels,cfg.calibChannels);
end
[permutedPulse,permutedSpikes] = ...
    decode_online_grid_window(onlineBlock(permutation,:),permuted,fs);
assert(isequal(mapping,map2) && isequal(p,permutedPulse) && isequal(d,permutedSpikes));

% Reject ambiguous channel routing before attempting numerical calibration.
badCfg = cfg;
badCfg.emgChannels(2) = badCfg.emgChannels(1);
expect_failure(@() prepare_online_grid_states(signal,parameters,badCfg), ...
    'distinct stream row');
emptySignal = signal;
emptySignal.Pulsetrain = repmat({zeros(0,nSamples)},1,3);
emptySignal.Dischargetimes = cell(3,0);
emptySignal.onlineMUOriginalIDs = {[],[],[]};
expect_failure(@() prepare_online_grid_states(emptySignal,parameters,cfg), ...
    'No motor units remain');

% Replay the calibration EMG through the application acquisition service.
streamCfg = makeNovecentoConfig(0.128,1:3,reshape((1:64).'+70*(0:2),1,[]));
streamCfg.calibChannels = 1:192;
streamCfg.windowBaseCols = 64;
streamCfg.numberOfGrids = 3;
streamCfg.acquisitionMode = 'Replay calibration';
streamCfg.showQuadrant = true;
streamCfg.quadrantXMU = 1;
streamCfg.quadrantYMU = 3;
streamCfg.onlineDurationSec = Inf;
streamCfg.recordEMG = true;
streamCfg.forceFs = 25; % Source metadata must override this for recorded force.
signal.fs_force = 50;
forceSamples = ceil(nSamples/fs*signal.fs_force);
signal.recordedForce = [(1:forceSamples)' -(1:forceSamples)' 3*ones(forceSamples,1)];
streamCfg.forceMaxDurationSec = 600;
streamCfg.extensionPositive = false;
streamCfg.printEveryNWindows = 0;
streamCfg.forceCalibration = struct('calibrationFactors',[10 10 10], ...
    'zeroValues',[0 0 0],'reverseStates',[false false false]);
replay = OnlineAcquisitionSession(streamCfg,signal,parameters);
cleanup = onCleanup(@() delete(replay));
replay.start(false);
assert(replay.Config.forceFs == 50 && strcmp(replay.Config.forceSource,'recorded'));
expect_failure(@() replay.zeroForce(),'already calibrated');
replay.startRecording(struct('participant','REPLAY','session',1,'trial',1));
for window = 1:20
    if ~replay.Running, break; end
    replay.advanceSimulation();
end
assert(~replay.Running && ~replay.Recording);
assert(replay.LastRecording.online.gridResults{3}.grid == 3);
assert(isempty(replay.LastRecording.online.gridResults{3}.Pulsetrain));
assert(size(replay.LastRecording.online.gridResults{2}.Pulsetrain,1) == 1);
assert(size(replay.LastRecording.online.EMG,2) == floor(nSamples/256)*256);
assert(isequal(replay.LastRecording.online.EMG, ...
    signal.data(:,1:size(replay.LastRecording.online.EMG,2))));
forceOut = replay.LastRecording.online.force;
expectedCount = ceil(replay.LastRecording.elapsedSec*50-1e-9);
assert(isequal(forceOut.data,signal.recordedForce(1:expectedCount,:)));
assert(isequal(forceOut.Time,(0:expectedCount-1)'/50));
assert(all(isnan(forceOut.arduinoTime)));
assert(~forceOut.simulated && replay.LastRecording.replay);
assert(~forceOut.calibrationAppliedDuringReplay && isempty(forceOut.calibrationFactors));
% Save an edited fixture to exercise app imports separately from file pickers.
fixtureFolder = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'tmp','online_app_validation');
if ~isfolder(fixtureFolder), mkdir(fixtureFolder); end
edition = struct('Pulsetrain',{signal.Pulsetrain}, ...
    'Dischargetimes',{signal.Dischargetimes});
save(fullfile(fixtureFolder,'edited_fixture.mat'),'signal','edition','parameters');
disp('Multi-grid online regression checks passed.');
end

function expect_failure(action, message)
try
    action();
catch exception
    assert(contains(exception.message,message), exception.message);
    return;
end
error('Expected failure containing: %s',message);
end

function state = make_state(rows, mask, nMU, indices)
state.channelRows = rows;
state.mask = mask(:);
state.nMU = nMU;
state.muIndices = indices;
state.extensionfactor = 2;
state.MUfilt = randn(nMU,2*sum(~mask));
state.normval = ones(1,nMU);
state.centroid = repmat([0 1],nMU,1);
state.overlap = zeros(2*sum(~mask),1);
end
