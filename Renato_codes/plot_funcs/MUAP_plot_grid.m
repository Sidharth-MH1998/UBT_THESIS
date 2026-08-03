function t = MUAP_plot_grid(t, MUAP_all, mu_index, grid_rows, grid_cols)
%{
This function recieves calculates the motor unit shapes on each channel and
plots them on the grid of pre-defined size (same as electrode grid)
%}

chan = size(MUAP_all{1}, 1);
MUAPs = MUAP_all{mu_index};

t.Padding = "compact";
t.TileSpacing = "compact";
t.GridSize = [grid_rows grid_cols];
ylims = [];
for i = 1:chan
    ax = nexttile(t);
    plot(ax,MUAPs(i,:));
    ax.Box = "off";
    ax.XAxis.Visible = "off";
    ax.Title.String = "Channel " + string(i);
    ylims = [ylims ax.YLim];
end
ylim_max = max(ylims);
ylim_min = min(ylims);
for i = 1:chan
    ax = nexttile(t,i);
    ax.YLim = [ylim_min ylim_max];
end

end