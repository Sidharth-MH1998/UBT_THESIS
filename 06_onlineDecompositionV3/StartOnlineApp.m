% Start the multi-grid biofeedback app, or bring its existing window forward.
addpath(fullfile(fileparts(mfilename('fullpath')), 'OnlineDecomposeSrc'));
if exist('onlineApp','var') && isa(onlineApp,'OnlineDecompositionApp') && ...
        isvalid(onlineApp) && isgraphics(onlineApp.Figure)
    figure(onlineApp.Figure);
else
    onlineApp = OnlineDecompositionApp();
end
