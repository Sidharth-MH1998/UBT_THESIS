warning('off','all');
root = 'D:\UBT_Thesis\decomp_code_and_data';
files = dir(fullfile(root, '*.mat'));
for k = 1:numel(files)
    filename = fullfile(root,files(k).name);
    vars = whos('-file',filename);
    if any(strcmp({vars.name},'signal'))
        s = load(filename,'signal','parameters');
        if isfield(s.signal,'data')
            fprintf('\nFILE %s DATA %s\n',files(k).name,mat2str(size(s.signal.data)));
            if isfield(s.signal,'sil_all'), fprintf('SIL %s\n',mat2str(s.signal.sil_all,5)); end
            if isfield(s.signal,'MUPulses'), fprintf('MUS %d\n',numel(s.signal.MUPulses)); end
            if isfield(s,'parameters'), disp(s.parameters); end
        end
    elseif any(strcmp({vars.name},'decomp_results3'))
        s = load(filename);
        fprintf('\nFILE %s\n',files(k).name);
        disp(s.params3);
        fprintf('PEAKS %s SIL %s\n',mat2str(size(s.decomp_results3.peaks)),mat2str(s.decomp_results3.sil_all,5));
    end
end
