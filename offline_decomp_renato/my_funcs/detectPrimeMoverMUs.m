% Smoothed discharge rates is a cell array of size 6x1 where each cell is a
% stage's smoothed DRs of dimension nMUs x 5120 samples

% Output a mean CoV for the flexion phases and another for the extension phases

function [CoV, PrimeMoversFlexIdx, PosturalFlexIdx, PrimeMoversExtIdx, PosturalExtIdx] = detectPrimeMoverMUs(covTh,smoothedDischargeRates)

m = size(smoothedDischargeRates{1}, 1); % number of MUs

CoV = zeros(m,2); % flexion CoV in first column, ext CoV on second

DRstd = [std(smoothedDischargeRates{1}'); std(smoothedDischargeRates{2}'); std(smoothedDischargeRates{3}'); ... % results in 6 x nMUs matrix
        std(smoothedDischargeRates{4}'); std(smoothedDischargeRates{5}'); std(smoothedDischargeRates{6}')];

DRmean = [mean(smoothedDischargeRates{1}'); mean(smoothedDischargeRates{2}'); mean(smoothedDischargeRates{3}'); ... % results in 6 x nMUs matrix
        mean(smoothedDischargeRates{4}'); mean(smoothedDischargeRates{5}'); mean(smoothedDischargeRates{6}')];

tmpCoV = DRstd./DRmean;

% Set CoV = 0 when std is 0
idx = find(DRstd==0);
tmpCoV(idx) = 0;

CoV_flex = mean(tmpCoV(3:4,:),1); % mean over finger flexion stages
CoV_ext = mean(tmpCoV([(1:2),(5:6)],:),1); % mean over finger extension phases

CoV = [CoV_flex; CoV_ext];

PrimeMoversFlexIdx = find(CoV_flex>covTh);
PosturalFlexIdx = find(CoV_flex<=covTh);
PrimeMoversExtIdx = find(CoV_ext>covTh);
PosturalExtIdx = find(CoV_ext<=covTh);

end