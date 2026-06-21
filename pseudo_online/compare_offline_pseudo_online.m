%% COMPARE OFFLINE VS PSEUDO-ONLINE DECOMPOSITION
% -------------------------------------------------------------------------
% Required variables in workspace:
%   Calib_data.MUPulses
%   Dischargetimes_online
%   fs
%
% Optional variables in workspace:
%   fs_online_compare
%   tol_ms

assert(exist('Calib_data', 'var') == 1, 'Calib_data not found in workspace.');
assert(isfield(Calib_data, 'MUPulses'), 'Calib_data.MUPulses not found.');
assert(exist('Dischargetimes_online', 'var') == 1, 'Dischargetimes_online not found in workspace.');
assert(exist('fs', 'var') == 1, 'fs not found in workspace.');

offlinePulses = Calib_data.MUPulses;
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

validateattributes(offlinePulses, {'cell'}, {});
validateattributes(onlinePulses, {'cell'}, {});
validateattributes(fsOffline, {'numeric'}, {'scalar','positive'});
validateattributes(fsOnline, {'numeric'}, {'scalar','positive'});
validateattributes(tol_ms, {'numeric'}, {'scalar','positive'});

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

work_roa = roa_matrix;
matches = zeros(0,2);

while ~isempty(work_roa) && any(isfinite(work_roa(:)))
    [bestVal, linearIdx] = max(work_roa(:));
    if isempty(bestVal) || ~isfinite(bestVal) || bestVal <= 0
        break;
    end

    [iBest, jBest] = ind2sub(size(work_roa), linearIdx);
    matches(end+1,:) = [iBest jBest]; %#ok<AGROW>
    work_roa(iBest,:) = -inf;
    work_roa(:,jBest) = -inf;
end

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

disp(' ')
disp('=== Offline vs Pseudo-Online Comparison ===')
disp(summary_table)
fprintf('Unmatched offline MUs: %s\n', mat2str(unmatched_offline))
fprintf('Unmatched online  MUs: %s\n', mat2str(unmatched_online))

% Results left in workspace:
%   roa_matrix
%   matches
%   summary_table
%   unmatched_offline
%   unmatched_online
