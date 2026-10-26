%% COMPARE OFFLINE VS PSEUDO-ONLINE DECOMPOSITION
%
% Required workspace variables from pseudo_online_withfr_v3:
%   Dischargetimes_online : 1 x nMU cell of 1-based sample indices
%   fs                    : sampling frequency in Hz
%
% Offline reference, in order of preference:
%   offline_MUPulses      : MUPulses from offline decomposition of the
%                           same trial processed by pseudo_online_withfr_v3
%   Offline_data.MUPulses : equivalent reference stored in a structure
%   Calib_data.MUPulses   : fallback, valid only when the calibration
%                           recording is also the pseudo-online test input
%
% Optional workspace variables:
%   fs_online_compare     : online sampling frequency; defaults to fs
%   tol_ms                : spike matching tolerance; defaults to 0.5 ms

%% Validate pseudo-online inputs
assert(exist('Dischargetimes_online', 'var') == 1, 'Dischargetimes_online not found in workspace.');
assert(exist('fs', 'var') == 1, 'fs not found in workspace.');

onlinePulses = Dischargetimes_online;
fsOffline = fs;

if exist('fs_online_compare', 'var') == 1
    fsOnline = fs_online_compare;
else
    fsOnline = fs;
end

if exist('tol_ms', 'var') ~= 1
    tol_ms = 0.5;
end

validateattributes(onlinePulses, {'cell'}, {});
validateattributes(fsOffline, {'numeric'}, {'scalar','positive'});
validateattributes(fsOnline, {'numeric'}, {'scalar','positive'});
validateattributes(tol_ms, {'numeric'}, {'scalar','positive'});

%% Select the offline reference
if exist('offline_MUPulses', 'var') == 1
    offlinePulses = offline_MUPulses;
    offlineSource = 'offline_MUPulses';
elseif exist('Offline_data', 'var') == 1 && isstruct(Offline_data) && ...
        isfield(Offline_data, 'MUPulses')
    offlinePulses = Offline_data.MUPulses;
    offlineSource = 'Offline_data.MUPulses';
elseif exist('Calib_data', 'var') == 1 && isstruct(Calib_data) && ...
        isfield(Calib_data, 'MUPulses')
    offlinePulses = Calib_data.MUPulses;
    offlineSource = 'Calib_data.MUPulses';
    warning(['Using calibration MUPulses as the offline reference. ' ...
        'This comparison is valid only if pseudo_online_withfr_v3 processed ' ...
        'that same calibration recording.']);
else
    error(['No offline reference found. Define offline_MUPulses or ' ...
        'Offline_data.MUPulses from an offline decomposition of the ' ...
        'same trial used by pseudo_online_withfr_v3.']);
end
validateattributes(offlinePulses, {'cell'}, {});

% V3 processes complete windows only. Exclude offline spikes in the final
% partial window so they are not incorrectly counted as false negatives.
if exist('nwin', 'var') == 1 && exist('window_samples', 'var') == 1
    processedSamples = nwin * window_samples;
    for mu = 1:numel(offlinePulses)
        offlinePulses{mu} = offlinePulses{mu}(offlinePulses{mu} <= processedSamples);
    end
else
    processedSamples = inf;
end

%% Calculate agreement for every MU pair
roa_matrix = zeros(numel(offlinePulses), numel(onlinePulses));

for i = 1:numel(offlinePulses)
    for j = 1:numel(onlinePulses)
        Aidx = offlinePulses{i};
        Bidx = onlinePulses{j};

        timeA = ((Aidx - 1) * 1000) / fsOffline;
        timeB = ((Bidx - 1) * 1000) / fsOnline;

        usedB = false(size(timeB));
        C = 0;

        for k = 1:numel(timeA)
            diffs = abs(timeB - timeA(k));
            diffs(usedB) = inf;
            [bestDiff, bestIdx] = min(diffs);
            if bestDiff <= tol_ms
                usedB(bestIdx) = true;
                C = C + 1;
            end
        end

        A = numel(Aidx) - C;
        B = numel(Bidx) - C;

        if (A + B + C) == 0
            roa_matrix(i,j) = 0;
        else
            roa_matrix(i,j) = 100 * (C / (A + B + C));
        end
    end
end

%% Pair offline and pseudo-online motor units
work_roa = roa_matrix;
matches = zeros(min(size(work_roa)),2);
matchCount = 0;

while ~isempty(work_roa) && any(isfinite(work_roa(:)))
    [bestVal, linearIdx] = max(work_roa(:));
    if isempty(bestVal) || ~isfinite(bestVal) || bestVal <= 0
        break;
    end

    [iBest, jBest] = ind2sub(size(work_roa), linearIdx);
    matchCount = matchCount + 1;
    matches(matchCount,:) = [iBest jBest];
    work_roa(iBest,:) = -inf;
    work_roa(:,jBest) = -inf;
end
matches = matches(1:matchCount,:);

%% Build the comparison summary
nMatch = size(matches, 1);
summary_table = table('Size', [nMatch 10], ...
    'VariableTypes', {'double','double','double','double','double','double','double','double','double','double'}, ...
    'VariableNames', {'offline_mu','online_mu','roa','tp','fp','fn','precision','sensitivity','n_offline','n_online'});

for k = 1:nMatch
    i = matches(k,1);
    j = matches(k,2);

    offlineIdx = offlinePulses{i};
    onlineIdx = onlinePulses{j};

    timeOffline = ((offlineIdx - 1) * 1000) / fsOffline;
    timeOnline = ((onlineIdx - 1) * 1000) / fsOnline;

    usedOnline = false(size(timeOnline));
    tp = 0;

    for s = 1:numel(timeOffline)
        diffs = abs(timeOnline - timeOffline(s));
        diffs(usedOnline) = inf;
        [bestDiff, bestIdx] = min(diffs);
        if bestDiff <= tol_ms
            usedOnline(bestIdx) = true;
            tp = tp + 1;
        end
    end

    fn = numel(offlineIdx) - tp;
    fp = numel(onlineIdx) - tp;

    if (tp + fp) == 0
        precision = 0;
    else
        precision = tp / (tp + fp);
    end

    if (tp + fn) == 0
        sensitivity = 0;
    else
        sensitivity = tp / (tp + fn);
    end

    summary_table.offline_mu(k) = i;
    summary_table.online_mu(k) = j;
    summary_table.roa(k) = roa_matrix(i,j);
    summary_table.tp(k) = tp;
    summary_table.fp(k) = fp;
    summary_table.fn(k) = fn;
    summary_table.precision(k) = precision;
    summary_table.sensitivity(k) = sensitivity;
    summary_table.n_offline(k) = numel(offlineIdx);
    summary_table.n_online(k) = numel(onlineIdx);
end

if ~isempty(summary_table)
    summary_table = sortrows(summary_table, 'offline_mu');
end

matched_offline = matches(:,1);
matched_online = matches(:,2);
unmatched_offline = setdiff(1:numel(offlinePulses), matched_offline);
unmatched_online = setdiff(1:numel(onlinePulses), matched_online);

%% Display results
disp(' ')
disp('=== Offline vs Pseudo-Online Comparison ===')
fprintf('Offline reference: %s\n', offlineSource)
if isfinite(processedSamples)
    fprintf('Compared complete V3 windows: %d samples (%.3f s)\n', ...
        processedSamples, processedSamples/fsOnline)
end
disp(summary_table)
fprintf('Unmatched offline MUs: %s\n', mat2str(unmatched_offline))
fprintf('Unmatched online  MUs: %s\n', mat2str(unmatched_online))
