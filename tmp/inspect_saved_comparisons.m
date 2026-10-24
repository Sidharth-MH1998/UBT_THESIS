warning('off','all');
root = 'D:\UBT_Thesis\decomp_code_and_data';
files = {'tp287f2133_e7b0_4903_8e1b_2fdfc97a1f04_decompose3_results.mat', ...
    'tp84c08df8_68ff_4b33_a281_085b3d045126_decompose3_results.mat', ...
    '2292026222222222_decomposed4.mat', ...
    '2292026222222222.mat_decomp.mat', ...
    '2292026222222222.mat_decomp.mat_edited.mat'};
raw = load(fullfile(root,'2292026222222222.mat'),'signal');
for k = 1:numel(files)
    s = load(fullfile(root,files{k}));
    fprintf('\nFILE %s\n',files{k});
    if isfield(s,'decomp_results3'), r = s.decomp_results3; else, r = s.signal; end
    if isfield(r,'data'), fprintf('Raw data identical: %d\n',isequaln(raw.signal.data,r.data)); end
    names = fieldnames(r);
    for j = 1:numel(names)
        if ismember(names{j},{'data','target','path','auxiliary','recordedForce'}), continue; end
        fprintf('  %s %s\n',names{j},mat2str(size(r.(names{j}))));
    end
    if isfield(r,'MUPulses')
        fprintf('Spike counts: '); disp(cellfun(@numel,r.MUPulses));
        fprintf('Cov: '); disp(r.cov_all);
        fprintf('Mean FR: '); disp(r.mean_fr');
    end
    if isfield(r,'Dischargetimes')
        fprintf('Dischargetimes spike counts: '); disp(cellfun(@numel,r.Dischargetimes));
    end
    if isfield(r,'EMGmask'), fprintf('Excluded channels: '); disp(cellfun(@(x)sum(x(:)~=0),r.EMGmask)); end
end
