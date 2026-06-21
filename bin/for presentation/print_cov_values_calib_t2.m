%% Run full calibration from calib_t2.mat and print CoV values
%
% This script:
%   1. Loads Calibration_files/calib_t2.mat
%   2. Finds raw EMG in the file, or uses trimmedEMG/recordedEMG from workspace
%   3. Runs full offline calibration with decompose3()
%   4. Prints CoV values reported at each FastICA iteration
%   5. Prints final accepted/used MUs whose CoV is under covthr
%
% Change usedMU if you want one MU highlighted in the final plot.

clearvars -except trimmedEMG recordedEMG

%% File and display settings
matPath = fullfile('Calibration_files', 'calib_t2.mat');
usedMU = 1;

addpath('offline_decomp_renato/lib');
addpath('offline_decomp_renato/my_funcs');

S = load(matPath);
EMG = find_emg_signal(S);

if isempty(EMG)
    if exist('trimmedEMG', 'var') == 1 && ~isempty(trimmedEMG)
        EMG = trimmedEMG;
        fprintf('Raw EMG not found in %s. Using workspace trimmedEMG.\n', matPath)
    elseif exist('recordedEMG', 'var') == 1 && ~isempty(recordedEMG)
        EMG = recordedEMG;
        fprintf('Raw EMG not found in %s. Using workspace recordedEMG.\n', matPath)
    else
        error(['No raw EMG found. calib_t2.mat must contain EMG, trimmedEMG, or recordedEMG, ' ...
               'or you must have trimmedEMG/recordedEMG in the workspace.'])
    end
end

%% Calibration parameters
fs = 2000;
badchan = [];
padLen = 200;
initialization = 0;
NITER = 50;
nChannels = size(EMG, 1);
extfactor = 8;
nbextchan = nChannels * extfactor;
silthr = 0.9;
covfilter = 1;
covthr = 0.5;
differentialmode = 0;
peeloff_flag = 1;
peeloffwin = 0.025;
duplicatesthresh = 0.3;
CoVDR = 0.3;
contrastfunc = 'skew';
refineMU = 1;
preproc_flag = 1;

fprintf('\n=== Running full calibration from calib_t2 ===\n')
fprintf('EMG size: %d channels x %d samples\n', size(EMG, 1), size(EMG, 2))
fprintf('NITER = %d | SIL threshold = %.2f | CoV threshold = %.2f\n\n', ...
    NITER, silthr, covthr)

%% Run calibration and capture the iteration log
calibrationLog = evalc([ ...
    'Calib_data_full_run = decompose3(EMG, fs, badchan, padLen, initialization, NITER, nbextchan, silthr, covfilter, covthr, ', ...
    'differentialmode, peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU, preproc_flag);' ...
    ]);

fprintf('%s\n', calibrationLog)

%% Parse and print CoV values from every printed calibration iteration
iterExpr = 'Iteration #(\d+)\s*-\s*Sil\s*=\s*([-\d\.eE+]+)\s*CoV\s*=\s*([-\d\.eE+]+)';
tokens = regexp(calibrationLog, iterExpr, 'tokens');

if isempty(tokens)
    warning('No iteration CoV lines were found in the decompose3 output.')
    iteration_cov_table = table();
else
    iterNumber = zeros(numel(tokens), 1);
    silValues = zeros(numel(tokens), 1);
    covIterValues = zeros(numel(tokens), 1);

    for k = 1:numel(tokens)
        iterNumber(k) = str2double(tokens{k}{1});
        silValues(k) = str2double(tokens{k}{2});
        covIterValues(k) = str2double(tokens{k}{3});
    end

    passedSIL = silValues > silthr;
    passedCoV = covIterValues <= covthr;
    iteration_cov_table = table(iterNumber, silValues, covIterValues, passedSIL, passedCoV, ...
        'VariableNames', {'Iteration', 'SIL', 'CoV_ISI', 'PassedSIL', 'PassedCoV'});

    fprintf('\n=== CoV at each printed FastICA iteration ===\n')
    disp(iteration_cov_table)
end

%% Final accepted/used MUs after filtering, duplicate removal, and cleanup
if ~isfield(Calib_data_full_run, 'cov_all') || isempty(Calib_data_full_run.cov_all)
    error('Calibration finished, but Calib_data_full_run.cov_all is empty.')
end

finalCov = Calib_data_full_run.cov_all(:);
finalSIL = get_optional_vector(Calib_data_full_run, 'sil_all', numel(finalCov));
nUsedMUs = numel(finalCov);

usedUnderThreshold = finalCov <= covthr;
usedMUList = find(usedUnderThreshold);

if usedMU > nUsedMUs
    warning('usedMU = %d exceeds final nMUs = %d. Highlighting MU1 instead.', usedMU, nUsedMUs)
    usedMU = 1;
end

usedHighlight = false(nUsedMUs, 1);
usedHighlight(usedMU) = true;

final_cov_table = table((1:nUsedMUs)', finalSIL, finalCov, usedUnderThreshold, usedHighlight, ...
    'VariableNames', {'MU', 'SIL', 'CoV_ISI', 'Used_CoV_Under_Threshold', 'HighlightedMU'});

fprintf('\n=== Final used MUs after calibration cleanup ===\n')
disp(final_cov_table)

fprintf('MUs used with CoV <= %.2f: %s\n', covthr, mat2str(usedMUList'))
fprintf('Highlighted MU%d final CoV = %.4f\n', usedMU, finalCov(usedMU))

%% Plot final used MU CoV values
figure('Color', 'w', 'Name', 'Final used MU CoV values from full calibration');

barColors = repmat([0.80 0.80 0.80], nUsedMUs, 1);
barColors(usedUnderThreshold, :) = repmat([0.25 0.65 0.35], sum(usedUnderThreshold), 1);
barColors(usedMU, :) = [0.90 0.15 0.10];

b = bar(finalCov, 'FaceColor', 'flat');
b.CData = barColors;
grid on
xlabel('Final used MU / MU filter')
ylabel('CoV of ISI')
title(sprintf('Final used MUs: CoV threshold %.2f, highlighted MU%d', covthr, usedMU))
yline(covthr, 'k--', sprintf(' CoV threshold %.2f', covthr), 'LineWidth', 1.2)

hold on
plot(usedMU, finalCov(usedMU), 'ko', 'MarkerSize', 10, 'LineWidth', 1.5)
text(usedMU, finalCov(usedMU), sprintf('  MU%d used', usedMU), ...
    'VerticalAlignment', 'bottom', 'FontWeight', 'bold')
hold off

%% Helper functions
function EMG = find_emg_signal(S)
EMG = [];
preferredNames = {'EMG', 'trimmedEMG', 'recordedEMG'};

for i = 1:numel(preferredNames)
    name = preferredNames{i};
    if isfield(S, name) && isnumeric(S.(name)) && ismatrix(S.(name))
        candidate = S.(name);
        if size(candidate, 1) <= size(candidate, 2)
            EMG = candidate;
        else
            EMG = candidate.';
        end
        fprintf('Using raw EMG variable "%s" from calib_t2.mat.\n', name)
        return
    end
end
end

function values = get_optional_vector(S, fieldName, n)
if isfield(S, fieldName) && ~isempty(S.(fieldName))
    tmp = S.(fieldName);
    values = tmp(:);
    if numel(values) ~= n
        values = nan(n, 1);
    end
else
    values = nan(n, 1);
end
end
