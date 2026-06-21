% Takes decomposition results struct and removes discarded MUs
% The struct has the following variables to modify:
% - results.peaks (nMUs x samples)
% - results.spike_train (samples x nMUs)
% - results.MUPulses, MUAPs, fr (1 x nMUs cell)
% - results.sil_all, cov_all (1 x nMUs)
% - results.mean_fr, MU_locs (nMUs x 1)
% - results.p2ps (64 x nMUs)

function results_w_discarded = discardMUs_singleTrial(discarded, results)
    
    results_w_discarded = results;
    results_w_discarded.peaks(discarded,:) = [];
    results_w_discarded.spike_train(:,discarded) = [];
    results_w_discarded.MUPulses(:,discarded) = [];
    results_w_discarded.MUAPs(:,discarded) = [];
    results_w_discarded.fr(:,discarded) = [];
    results_w_discarded.sil_all(:,discarded) = [];
    results_w_discarded.cov_all(:,discarded) = [];
    results_w_discarded.mean_fr(discarded,:) = [];
    results_w_discarded.MU_locs(discarded,:) = [];
    results_w_discarded.p2ps(:,discarded) = [];

end