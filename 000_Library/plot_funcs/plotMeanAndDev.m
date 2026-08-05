function plotMeanAndDev(meanSeries, devSeries, meanColour, devShade, alpha)
% Plots meand and variance of time series data.
% INPUTS
% meanSeries: Mean of all time series data
% devSeries: Standard deviation of all time series data
% meanColour and devShade are the colours for plotting them
% alpha: Transparency value for the standar deviation in the range between 0 (transparent) and 1 (solid colour)
x = 1:numel(meanSeries);
curve1 = meanSeries + devSeries;
curve2 = meanSeries - devSeries;
x2 = [x, fliplr(x)];
inBetween = [curve1, fliplr(curve2)];
fill(x2, inBetween, devShade,'FaceAlpha',alpha,'LineStyle','none');
hold on;
plot(x, meanSeries, 'Color', meanColour, 'LineWidth', 2);

end