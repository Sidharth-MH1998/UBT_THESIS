warning('off','all');
root = 'D:\UBT_Thesis\decomp_code_and_data';
d3a = load(fullfile(root,'tp287f2133_e7b0_4903_8e1b_2fdfc97a1f04_decompose3_results.mat'));
d3b = load(fullfile(root,'tp84c08df8_68ff_4b33_a281_085b3d045126_decompose3_results.mat'));
d4 = load(fullfile(root,'2292026222222222_decomposed4.mat'));
edit0 = load(fullfile(root,'2292026222222222.mat_decomp.mat'));
edit1 = load(fullfile(root,'2292026222222222.mat_decomp.mat_edited.mat'));
fprintf('MUedit original/edited discharge times identical: %d\n', ...
    isequaln(edit0.signal.Dischargetimes,edit1.signal.Dischargetimes));
fprintf('MUedit original/edited pulse trains identical: %d\n', ...
    isequaln(edit0.signal.Pulsetrain,edit1.signal.Pulsetrain));
fprintf('MUedit grid/channel metadata:\n');
disp(edit0.signal.ngrid); disp(edit0.signal.nChan); disp(edit0.signal.gridname);
for k=1:numel(edit0.signal.Pulsetrain)
    fprintf('Grid %d pulse train size %s\n',k,mat2str(size(edit0.signal.Pulsetrain{k})));
end
fprintf('\nLatest saved decompose3: average absolute pulse amplitude at each MU discharge\n');
amp = zeros(size(d3b.decomp_results3.peaks,1),numel(d3b.decomp_results3.MUPulses));
for j=1:size(amp,2)
    amp(:,j) = mean(abs(d3b.decomp_results3.peaks(:,d3b.decomp_results3.MUPulses{j})),2);
end
[~,bestRows] = max(amp,[],1);
disp(table((1:numel(bestRows))',bestRows','VariableNames',{'DischargeUnit','StrongestPulseRow'}));
fprintf('\nSAVED D3 LATEST versus SAVED D4 (rows D3, cols D4)\n');
[savedAgreement,savedLag] = lagAgreement(d3b.decomp_results3.MUPulses,d4.signal.MUPulses);
disp(100*savedAgreement); disp('Best lag in samples:'); disp(savedLag);
fprintf('\nMUedit nonempty discharge counts and linear indices\n');
cells = edit0.signal.Dischargetimes;
indices = find(~cellfun(@isempty,cells));
disp([indices(:),cellfun(@numel,cells(indices(:)))]);
fprintf('\nSaved D4 vs MUedit (columns: nonempty cells, including one-spike entry)\n');
[editAgreement,editLag] = lagAgreement(d4.signal.MUPulses,cells(indices));
disp(100*editAgreement); disp(editLag);
save(fullfile(root,'tmp','saved_agreement_analysis.mat'),'savedAgreement','savedLag', ...
    'editAgreement','editLag','indices','amp','bestRows');

function [agreement,lags] = lagAgreement(a,b)
    agreement = zeros(numel(a),numel(b)); lags = agreement;
    for i=1:numel(a)
        for j=1:numel(b)
            for lag=-50:50
                n=matches(a{i},b{j}+lag,2);
                score=n/max(1,numel(a{i})+numel(b{j})-n);
                if score>agreement(i,j)
                    agreement(i,j)=score; lags(i,j)=lag;
                end
            end
        end
    end
end
function n=matches(a,b,tol)
    a=unique(a(:)); b=unique(b(:)); i=1;j=1;n=0;
    while i<=numel(a) && j<=numel(b)
        if abs(a(i)-b(j))<=tol, n=n+1;i=i+1;j=j+1;
        elseif a(i)<b(j), i=i+1;
        else, j=j+1;
        end
    end
end
