signal = struct();

signal.data = recordedEMG;
signal.fsamp = fs_emg;
signal.nChan = size(recordedEMG, 1);
signal.ngrid = 1;

% MUedit requires cell arrays
signal.gridname = {'GR08MM1305'};
signal.muscle = {'First Dorsal Interosseous'}; % Change if needed

nSamples = size(recordedEMG, 2);
signal.path=recordedForce(:,2);
% Select the recorded force channel: 1, 2, or 3
forceChannel = 2;

% Resample force so it has the same number of samples as the EMG
forceTime = linspace(0, 1, size(recordedForce, 1));
emgTime = linspace(0, 1, nSamples);

signal.path = interp1( ...
    forceTime, ...
    recordedForce(:, forceChannel), ...
    emgTime, ...
    'linear');

signal.path = reshape(signal.path, 1, []);

% Enter the target force used during the trial
targetLevel = 20; % Change this value
signal.target = repmat(targetLevel, 1, nSamples);

