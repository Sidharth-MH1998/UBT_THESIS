function rates = get_mu_reference_rates(signal, edition)
%GET_MU_REFERENCE_RATES Retained MU means in combined grid/MU order, in pps.
% Prefer edition.mean_fr. Calculate missing values from edited discharge times.
if nargin < 2, edition = struct(); end
counts = cellfun(@(pulse) size(pulse,1),signal.Pulsetrain);
rates = nan(1,sum(counts));
offset = 0;
for grid = 1:numel(counts)
    for mu = 1:counts(grid)
        idx = offset+mu;
        value = [];
        if isfield(edition,'mean_fr') && iscell(edition.mean_fr) && ...
                size(edition.mean_fr,1) >= grid && size(edition.mean_fr,2) >= mu
            value = edition.mean_fr{grid,mu};
        elseif isfield(signal,'onlineMUReferenceRates') && ...
                numel(signal.onlineMUReferenceRates) == numel(rates)
            value = signal.onlineMUReferenceRates(idx);
        end
        if isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && value > 0
            rates(idx) = double(value);
        else
            spikes = sort(unique(double(signal.Dischargetimes{grid,mu}(:))));
            if numel(spikes) >= 2
                rates(idx) = mean(signal.fsamp./diff(spikes));
            end
        end
    end
    offset = offset+counts(grid);
end
end
