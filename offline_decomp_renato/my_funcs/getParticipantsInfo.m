function [heights, weights, bmi, mgf] = getParticipantsInfo(path_info)
%   INPUT
%       path_info: path to excel file with participants information

% Load the Excel file
subjInfo = readtable(path_info);

% Access data
variables = subjInfo{:, 1}; % Variable names
units = subjInfo{:, 2};     % Units
% Get relevant variables by finding their indexes first
height_idx = find(cellfun(@(x) strcmp(x,"Height"),variables)); % in meters
weight_idx = find(cellfun(@(x) strcmp(x,"Weight"),variables)); % in kg
bmi_idx = find(cellfun(@(x) strcmp(x,"BMI"),variables));
mgf_idx = find(cellfun(@(x) strcmp(x,"MGF"),variables)); % maximum grip force in N

heights = table2cell(subjInfo(height_idx, 3:end));
weights = table2cell(subjInfo(weight_idx, 3:end));
bmi = table2cell(subjInfo(bmi_idx, 3:end));
mgf = table2cell(subjInfo(mgf_idx, 3:end));

% Make sure all is numeric data
for i=1:length(heights)
    if not(isnumeric(heights{i}))
        heights{i} = str2double(heights{i});
    end
    if not(isnumeric(weights{i}))
        weights{i} = str2double(weights{i});
    end
    if not(isnumeric(bmi{i}))
        bmi{i} = str2double(bmi{i});
    end
    if not(isnumeric(mgf{i}))
        mgf{i} = str2double(mgf{i});
    end
end

% now convert to matrices
heights = cell2mat(heights);
weights = cell2mat(weights);
bmi = cell2mat(bmi);
mgf = cell2mat(mgf);