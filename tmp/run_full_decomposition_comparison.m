warning('off','MATLAB:dispatcher:nameConflict');
set(groot,'defaultFigureVisible','off');
root = 'D:\UBT_Thesis\decomp_code_and_data';
loaded = load(fullfile(root,'2292026222222222.mat'),'signal');
signal = loaded.signal;
run(fullfile(root,'03_OfflineDecomposition','compare_decompose3_decompose4.m'));
save(fullfile(root,'tmp','full_comparison_baseline.mat'),'comparison','comparisonOutputFile','-v7.3');
fprintf('\nEXACT FIELD COMPARISON\n');
fields = intersect(fieldnames(comparison.result3),fieldnames(comparison.result4));
for k = 1:numel(fields)
    name = fields{k};
    x = comparison.result3.(name); y = comparison.result4.(name);
    fprintf('%s: size3=%s size4=%s exact=%d',name,mat2str(size(x)),mat2str(size(y)),isequaln(x,y));
    if isnumeric(x) && isnumeric(y) && isequal(size(x),size(y)) && ~isempty(x)
        fprintf(' maxAbsDiff=%.17g',full(max(abs(x(:)-y(:)))));
    end
    fprintf('\n');
end
fprintf('\nSOURCE INPUT CHECK\n');
previous = load(fullfile(root,'2292026222222222_decomposed4.mat'),'signal','parameters');
fprintf('Raw data equal to previous decompose4 input: %d\n',isequaln(signal.data,previous.signal.data));
fprintf('Previous decompose4 parameters:\n'); disp(previous.parameters);
fprintf('Previous decompose4 spikes: '); disp(cellfun(@numel,previous.signal.MUPulses));
fprintf('Current decompose4 spikes: '); disp(cellfun(@numel,comparison.result4.MUPulses));
issues = checkcode(fullfile(root,'03_OfflineDecomposition','compare_decompose3_decompose4.m'),'-id');
disp('Code analyzer:'); disp(issues);
close all force;
