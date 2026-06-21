%{
    Determine wether two MUs are a match by using normalised cross corr between their waveforms
    We load two sets of MUs to compute matches between all of them.
    
    INPUTS:
    - MUAPs_1: 1 x nMUs cell array. Each element is a 64x103 double waveform.
    - MUAPs_2: 1 x nMUs cell array. Each element is a 64x103 double waveform.
    - corrTh: Threshold value for correlations  (e.g. 0.8)

    OUTPUTS:
    - MUmatches: nMatches x 2 int of pairs of MUs matched, from first and second batch in each column
    - corr: nMatches x 1 single of mean cross correlation
    
    @author: Renato Mio
    Created: 24.06.2024
%}

function [MUmatches, corrs] = matchMUs(MUAPs_1, MUAPs_2, corrTh)

    nMU1 = length(MUAPs_1);
    nMU2 = length(MUAPs_2);

    MUmatches = [];
    corrs = []; 

    if nMU1>0 && nMU2>0 % check that there are MUs to compare first

        % check that dimensions match
        if ~ ((size(MUAPs_1{1},1)==size(MUAPs_2{1},1)) && (size(MUAPs_1{1},2)==size(MUAPs_2{1},2)))
            error("Data size mismatch between the input MU sets")
        end
    
        
    
        for mu1=1:nMU1
            for mu2=1:nMU2
                % for every channel
                thiscorr = zeros(size(MUAPs_1{mu1},1),1);
                for ch=1:size(MUAPs_1{mu1},1)
                    muap1 = MUAPs_1{mu1}(ch,:);
                    muap2 = MUAPs_2{mu2}(ch,:);
                    [crosscorr, ~] = xcorr(muap1,muap2,'normalized');
                    thiscorr(ch) = max(crosscorr);
                end
    
                % check if they are a match
                if all(thiscorr > corrTh) % checks that all are true
                    MUmatches = [MUmatches; [mu1 mu2] ]; % add another row for mu1 and mu2 indices
                    corrs = [corrs; mean(thiscorr)];
                end
            end
        end
    
    end

end