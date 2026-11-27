function setup_online_dependencies()
%SETUP_ONLINE_DEPENDENCIES Reuse the recorder and I-Spin implementations.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root, '02_DataRecording', 'srcNovecento'), ...
    fullfile(root, '02_DataRecording', 'srcForce'), ...
    fullfile(root, '000_Library', 'I_spin', 'lib'));
end
