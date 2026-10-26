function edition = launch_edit_single_session()
% LAUNCH_EDIT_SINGLE_SESSION Select a file and run the single-session editor.
%   edition = launch_edit_single_session()
%   Cancelling the file picker returns [] without processing a session.

% Remove a MU if post-edit SIL is too low OR CoV is too high.
filterMUs = true;
silThreshold = 0.90;
covThreshold = 0.50; % Ratio: 0.50 means 50%.

edition = [];
launcher_folder = fileparts(mfilename('fullpath'));
[file_name, file_folder] = uigetfile( ...
    {'*.mat;*.mat_decomp', 'Decomposition files (*.mat, *.mat_decomp)'; ...
     '*.*', 'All files (*.*)'}, ...
    'Select decomposition session to automatically edit', launcher_folder);

if isequal(file_name, 0)
    disp('File selection cancelled. No processing performed.');
    return;
end

input_file = fullfile(file_folder, file_name);
edition = edit_single_session(input_file, FilterMUs=filterMUs, ...
    SILThreshold=silThreshold, CoVThreshold=covThreshold);
end
