function plot_HDEMG_wRMS(emg, nrows, ncols, fs, rms_flag)

%{
Plots HD EMG channels time series with the option of also plotting a heatmap of
RMS values
@author: Renato Mio
Creation: 11.08.2023

INPUT: 
gridSize: [gridRows gridCols] e.g. [5 13], [8 8]

OUTPUT
MUAP_locs: electrode locations of MUs
stdDist: standard distance (measure of spread of MUs)

%}
% 
% figure
% title('EMG RMS values (\muV)')
% % nrows = 8;
% % ncols = 8;


IED = 8;

% t = (1:length(emg))./fs; % Convert samples to seconds
% 
% k = 1;
% for i = 1:nrows % rows
%     for j= 1:ncols % columns
%         subplot(nrows,ncols,k)
%         plot(t,emg(k,:))
%         xlabel(strcat('Time [s] - ch',num2str(k)))
%         k = k+1;       
%     end
% end

%%
figure
t = tiledlayout('flow'); % As we call nexttile, the layout reflows as needed to accommodate the new axes while maintaining an aspect ratio of roughly 4:3 for all the tiles.

t.Padding = "compact";
t.TileSpacing = "compact";
t.GridSize = [nrows ncols];
ylims = [];
k = 1;
for i = 1:nrows % rows
    for j= 1:ncols % columns
        ax = nexttile(k);
        plot(ax,emg(k,:))
        ax.Box = "off";
        ax.XAxis.Visible = "off";
        ax.Title.String = strcat('Time [s] - ch',num2str(k));
        ylims = [ylims ax.YLim];
        k = k+1;     
    end
end

ylim_max = max(ylims);
ylim_min = min(ylims);

for i = 1:(nrows*ncols)
    ax = nexttile(t,i);
    ax.YLim = [ylim_min ylim_max];
end



if rms_flag
    rms_grid = zeros(10,10);
    rms_grid(2:9,2:9) = reshape(rms(emg'),nrows,ncols)';

    % Grid dimensions in mm
    [X,Y] = meshgrid( (0:(ncols+1)) , 0:(nrows+1) ); % MUAP location is flipped on Y axis due to meshgrid function
    X = X*IED-IED;
    Y = Y*IED;
    Y = flip (Y); % flipping for plotting with correct orientation
    
    figure
    surf(X,Y,rms_grid,'EdgeColor','none')
    hold on
    c = colorbar;
    set(c.Label,{'String','Rotation','Position'},{'(a.u.)',0,[0.5 -0.005]})
    xlim([0 (ncols)*IED])
    ylim([0 (nrows)*IED])
    xlabel("mm")
    ylabel("mm")
    view(2)
    hold off
end
