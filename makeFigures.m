function [figures, files] = makeFigures(data, results, outdir, options)
%MAKEFIGURES Reproduce the five manuscript figures from paired plan data.
%   [FIGURES,FILES] = glottic.makeFigures(DATA,RESULTS,OUTDIR,OPTIONS) uses
%   DATA.CRT and DATA.IMRT numeric columns and DATA.patient_id. OPTIONS is a
%   scalar struct with FigureVisible ('off' by default) and Resolution (600
%   by default). Each figure is saved as PNG (up to 300 dpi), TIFF at the
%   requested resolution, vector PDF, and an editable MATLAB FIG file.
%   All connections identify the same patient in both treatment plans.
%   Axis ranges expand when a new workbook extends the manuscript ranges.
%   This function performs no statistical hypothesis tests.

if nargin < 2 || isempty(results), results = struct; end
if nargin < 3 || strlength(string(outdir)) == 0
    error('glottic:FigureOutput', 'Supply a figure output directory.');
end
if nargin < 4 || isempty(options), options = struct; end
if ~isfield(options, 'FigureVisible'), options.FigureVisible = 'off'; end
if ~isfield(options, 'Resolution'), options.Resolution = 600; end
visible = lower(string(options.FigureVisible));
if ~isscalar(visible) || ~ismember(visible, ["on", "off"])
    error('glottic:FigureOption', 'FigureVisible must be ''on'' or ''off''.');
end
validateattributes(options.Resolution, {'numeric'}, ...
    {'scalar','real','finite','positive','integer'}, mfilename, 'Resolution');

ids = string(data.patient_id(:));
n = numel(ids);
if n == 0
    error('glottic:FigureData', 'The paired dataset contains no patients.');
end
keys = {'carotid_L_Dmean_Gy','carotid_R_Dmean_Gy', ...
    'carotid_worse_Dmean_Gy','carotid_worse_Dmax_Gy', ...
    'ptv_D99_9_Gy','ptv_D95_Gy','ptv_Dmax_Gy'};
for technique = {'CRT','IMRT'}
    for k = 1:numel(keys)
        if ~isfield(data.(technique{1}), keys{k})
            error('glottic:FigureData', 'Missing %s.%s.', technique{1}, keys{k});
        end
        validateattributes(data.(technique{1}).(keys{k}), {'numeric'}, ...
            {'vector','real','numel',n}, mfilename, ...
            [technique{1}, '.', keys{k}]);
    end
end

outdir = char(string(outdir));
if ~isfolder(outdir), mkdir(outdir); end
[ok, folderInfo] = fileattrib(outdir);
if ok, outdir = folderInfo.Name; end
palette.orange = [166 95 0] / 255;
palette.blue = [0 114 178] / 255;
palette.gray = [182 182 182] / 255;
palette.dark = [34 34 34] / 255;

figures = struct;
files = strings(0,1);
try
    figures.Fig1 = newFigure('Fig1', 510, 296, visible);
    for k = 1:2
        x = 50 + (k-1)*256;
        ax = newAxes(figures.Fig1, [x 55 196 216], [510 296], palette);
        pairPlot(ax, data, keys{k}, [0 80], 0:20:80, [], 196, palette);
        side = {'Left','Right'};
        ylabel(ax, [side{k}, ' carotid mean dose (Gy)'], 'FontSize',9.3);
        panelLabel(figures.Fig1, 12+(k-1)*256, 283, char('a'+k-1), [510 296], palette);
    end
    addPlanLegend(figures.Fig1, [510 296], palette);
    files = [files; saveFigure(figures.Fig1, 'Fig1', outdir, options.Resolution)];

    figures.Fig2 = newFigure('Fig2', 510, 296, visible);
    ax = newAxes(figures.Fig2, [52 58 229 211], [510 296], palette);
    a = data.CRT.carotid_worse_Dmean_Gy(:);
    b = data.IMRT.carotid_worse_Dmean_Gy(:);
    u = data.CRT.carotid_worse_Dmax_Gy(:);
    v = data.IMRT.carotid_worse_Dmax_Gy(:);
    xRange = expandedLimits([a;b], [0 80], 20);
    yRange = expandedLimits([u;v], [0 80], 50);
    xlim(ax, xRange); ylim(ax, yRange);
    setReferenceTicks(ax, 'x', xRange, [0 80], 0:20:80);
    setReferenceTicks(ax, 'y', yRange, [0 80], 0:20:80);
    paired = isfinite(a) & isfinite(b) & isfinite(u) & isfinite(v);
    plot(ax, [a(paired)';b(paired)'], [u(paired)';v(paired)'], ...
        'Color',palette.gray, 'LineWidth',0.45);
    plot(ax, a, u, 's', 'LineStyle','none', 'MarkerSize',4, ...
        'MarkerFaceColor',palette.orange, 'MarkerEdgeColor',palette.orange);
    plot(ax, b, v, 'o', 'LineStyle','none', 'MarkerSize',4.8, ...
        'MarkerFaceColor',palette.blue, 'MarkerEdgeColor',palette.blue);
    xline(ax, 20, '--', 'Color',palette.dark, 'LineWidth',0.8);
    yline(ax, 50, '--', 'Color',palette.dark, 'LineWidth',0.8);
    xlabel(ax, 'Worse-side mean dose (Gy)', 'FontSize',9.3);
    ylabel(ax, 'Maximum across both carotids (Gy)', 'FontSize',9.3);
    panelLabel(figures.Fig2, 12, 283, 'a', [510 296], palette);

    ax = newAxes(figures.Fig2, [340 58 162 211], [510 296], palette);
    counts = [sum(isfinite(a) & a<20), sum(isfinite(u) & u<=50), ...
        sum(isfinite(a) & isfinite(u) & a<20 & u<=50); ...
        sum(isfinite(b) & b<20), sum(isfinite(v) & v<=50), ...
        sum(isfinite(b) & isfinite(v) & b<20 & v<=50)];
    bars = bar(ax, 1:3, counts', 0.72, 'grouped');
    bars(1).FaceColor = palette.orange; bars(1).EdgeColor = 'none';
    bars(2).FaceColor = palette.blue; bars(2).EdgeColor = 'none';
    maxCount = max(30, ceil(n/10)*10);
    ylim(ax, [0 maxCount*1.07]); xlim(ax, [0.45 3.55]);
    ax.YTick = 0:max(1,ceil(maxCount/3/5)*5):maxCount;
    ax.XTick = 1:3;
    % Axis tick labels split embedded newlines into separate tick entries.
    % Draw multiline text explicitly so all three categories stay aligned.
    ax.XTickLabel = {};
    categoryLabels = {sprintf('Mean\n<20 Gy'),sprintf('Peak\n%c50 Gy',char(8804)),'Both'};
    for k = 1:3
        text(ax,k,-maxCount*.045,categoryLabels{k},'HorizontalAlignment','center', ...
            'VerticalAlignment','top','FontName','Arial','FontSize',8.5, ...
            'Color',palette.dark,'Clipping','off','Interpreter','none');
    end
    ylabel(ax, 'Plans attaining markers (n)', 'FontSize',9.3);
    drawnow;
    for technique = 1:2
        for k = 1:3
            text(ax, bars(technique).XEndPoints(k), counts(technique,k)+maxCount*0.025, ...
                sprintf('%d',counts(technique,k)), 'HorizontalAlignment','center', ...
                'FontName','Arial','FontSize',8.6, 'FontWeight','bold', ...
                'Color',bars(technique).FaceColor, 'Interpreter','none');
        end
    end
    panelLabel(figures.Fig2, 301, 283, 'b', [510 296], palette);
    addPlanLegend(figures.Fig2, [510 296], palette);
    files = [files; saveFigure(figures.Fig2, 'Fig2', outdir, options.Resolution)];

    figures.Fig3 = newFigure('Fig3', 510, 296, visible);
    targetKeys = {'ptv_D99_9_Gy','ptv_D95_Gy','ptv_Dmax_Gy'};
    targetLabels = {'PTV D99.9 (Gy)','PTV D95 (Gy)','PTV maximum dose (Gy)'};
    ranges = {[50 70],[64 71],[68 76]};
    ticks = {50:5:70,64:2:70,68:2:76};
    thresholds = [62.7 66 72.6];
    for k = 1:3
        x = 43+(k-1)*171;
        ax = newAxes(figures.Fig3, [x 55 123 216], [510 296], palette);
        pairPlot(ax, data, targetKeys{k}, ranges{k}, ticks{k}, ...
            thresholds(k), 123, palette);
        ylabel(ax, targetLabels{k}, 'FontSize',9.3);
        panelLabel(figures.Fig3, x-34, 283, char('a'+k-1), [510 296], palette);
    end
    addPlanLegend(figures.Fig3, [510 296], palette);
    files = [files; saveFigure(figures.Fig3, 'Fig3', outdir, options.Resolution)];

    figures.Fig4 = patientMatrix(data, ids, visible, palette);
    files = [files; saveFigure(figures.Fig4, 'Fig4', outdir, options.Resolution)];

    figures.FigS1 = newFigure('FigS1', 510, 296, visible);
    correlationKeys = {'ptv_D95_Gy','ptv_D99_9_Gy','ptv_Dmax_Gy'};
    correlationLabels = {'PTV D95 change (Gy)','PTV D99.9 change (Gy)', ...
        'PTV maximum change (Gy)'};
    ranges = {[-3.5 3],[-10 13],[-1 5]};
    ticks = {[-3 -1 0 1 3],[-10 -5 0 5 10],[-1 0 2 4]};
    reduction = a-b;
    for k = 1:3
        x = 43+(k-1)*171;
        ax = newAxes(figures.FigS1, [x 61 123 207], [510 296], palette);
        change = data.IMRT.(correlationKeys{k})(:) - data.CRT.(correlationKeys{k})(:);
        xRange = expandedLimits(reduction, [0 55], []);
        yRange = expandedLimits(change, ranges{k}, 0);
        xlim(ax, xRange); ylim(ax, yRange);
        setReferenceTicks(ax, 'x', xRange, [0 55], [0 25 50]);
        setReferenceTicks(ax, 'y', yRange, ranges{k}, ticks{k});
        yline(ax, 0, '--', 'Color',palette.gray, 'LineWidth',0.6);
        plot(ax, reduction, change, 'o', 'LineStyle','none', 'MarkerSize',4.8, ...
            'MarkerFaceColor',palette.blue, 'MarkerEdgeColor',palette.blue);
        xlabel(ax, 'Carotid reduction (Gy)', 'FontSize',9.3);
        ylabel(ax, correlationLabels{k}, 'FontSize',9.3);
        panelLabel(figures.FigS1, x-33, 283, char('a'+k-1), [510 296], palette);
        [rho, p] = correlationValues(results, correlationKeys{k});
        if isfinite(rho), rhoText = sprintf('\\rho = %.3f',rho);
        else, rhoText = '\rho unavailable'; end
        if isfinite(p)
            if p < 0.001, pText = 'p < 0.001';
            else, pText = sprintf('p = %.3f',p); end
        else, pText = 'p unavailable'; end
        text(ax, 0.025, 0.96, rhoText, 'Units','normalized', ...
            'FontName','Arial', 'FontSize',8.6, 'Color',palette.dark, ...
            'VerticalAlignment','top', 'Interpreter','tex');
        text(ax, 0.025, 0.90, pText, 'Units','normalized', ...
            'FontName','Arial', 'FontSize',8.6, 'Color',palette.dark, ...
            'VerticalAlignment','top', 'Interpreter','none');
    end
    figureText(figures.FigS1, [35 2 440 20], ...
        'Carotid reduction = 3DCRT - IMRT; target change = IMRT - 3DCRT', ...
        [510 296], 8.5, palette.dark, 'center');
    files = [files; saveFigure(figures.FigS1, 'FigS1', outdir, options.Resolution)];
catch failure
    % Close partially constructed figures after a failed run, so repeated
    % app runs do not accumulate orphaned windows or hidden graphics.
    names = fieldnames(figures);
    for k = 1:numel(names)
        if isgraphics(figures.(names{k})), close(figures.(names{k})); end
    end
    rethrow(failure);
end
end

function fig = newFigure(name, widthPoints, heightPoints, visible)
fig = figure('Name',[name,' - paired glottic cancer planning data'], ...
    'NumberTitle','off', 'Color','white', 'Visible',char(visible), ...
    'Units','inches', 'Position',[0.5 0.5 widthPoints/72 heightPoints/72], ...
    'PaperUnits','inches', 'PaperPosition',[0 0 widthPoints/72 heightPoints/72], ...
    'PaperSize',[widthPoints/72 heightPoints/72], 'InvertHardcopy','off');
% Explicit colours keep publication exports independent of desktop theme.
setappdata(fig, 'glotticExportSizeInches', [widthPoints heightPoints]/72);
end

function ax = newAxes(fig, rectangle, page, palette)
ax = axes('Parent',fig, 'Units','normalized', ...
    'Position',rectangle./[page page], 'FontName','Arial', 'FontSize',8.5, ...
    'Color','white', 'XColor',palette.dark, 'YColor',palette.dark, ...
    'Box','off', 'LineWidth',0.7, 'TickDir','out', 'TickLength',[0.015 0.015], ...
    'XGrid','off', 'YGrid','on', 'GridColor',[0.89 0.89 0.89], ...
    'GridAlpha',1, 'Layer','bottom', 'NextPlot','add');
ax.XAxis.Exponent = 0;
ax.YAxis.Exponent = 0;
ax.XLabel.Color = palette.dark;
ax.YLabel.Color = palette.dark;
end

function pairPlot(ax, data, key, baseRange, ticks, threshold, widthPoints, palette)
a = data.CRT.(key)(:); b = data.IMRT.(key)(:);
range = expandedLimits([a;b], baseRange, threshold);
xlim(ax, [0 1]); ylim(ax, range);
ax.XTick = [0.2 0.8]; ax.XTickLabel = {'3DCRT','IMRT'};
setReferenceTicks(ax, 'y', range, baseRange, ticks);
% Both members retain the same horizontal displacement. No randomness is
% used, so repeated runs of the same workbook produce the same plot.
if numel(a) > 1, shift = linspace(-0.048,0.048,numel(a))';
else, shift = 0; end
paired = isfinite(a) & isfinite(b);
plot(ax, [0.2+shift(paired)';0.8+shift(paired)'], [a(paired)';b(paired)'], ...
    'Color',palette.gray, 'LineWidth',0.5);
plot(ax, 0.2+shift, a, 's', 'LineStyle','none', 'MarkerSize',3.8, ...
    'MarkerFaceColor',palette.orange, 'MarkerEdgeColor',palette.orange);
plot(ax, 0.8+shift, b, 'o', 'LineStyle','none', 'MarkerSize',4, ...
    'MarkerFaceColor',palette.blue, 'MarkerEdgeColor',palette.blue);
halfWidth = 9/widthPoints;
for technique = 1:2
    if technique == 1, values = a; x = 0.2; else, values = b; x = 0.8; end
    valid = values(isfinite(values));
    if ~isempty(valid)
        average = mean(valid);
        plot(ax, [x-halfWidth x+halfWidth], [average average], ...
            'Color',palette.dark, 'LineWidth',2);
    end
end
if ~isempty(threshold)
    yline(ax, threshold, '--', 'Color',palette.dark, 'LineWidth',0.8);
end
end

function range = expandedLimits(values, baseRange, threshold)
finiteValues = values(isfinite(values));
finiteValues = [finiteValues(:); threshold(:)];
range = baseRange;
if isempty(finiteValues), return; end
span = max(diff(baseRange), max(finiteValues)-min(finiteValues));
if span == 0, span = 1; end
if min(finiteValues) < range(1), range(1) = min(finiteValues)-0.04*span; end
if max(finiteValues) > range(2), range(2) = max(finiteValues)+0.04*span; end
end

function setReferenceTicks(ax, direction, range, baseRange, ticks)
if isequal(range, baseRange)
    if strcmp(direction,'x'), ax.XTick = ticks; else, ax.YTick = ticks; end
else
    % Automatic tick placement remains readable when a new workbook changes
    % the scale; all observations remain inside the expanded limits.
    if strcmp(direction,'x'), ax.XTickMode = 'auto'; else, ax.YTickMode = 'auto'; end
end
end

function panelLabel(fig, x, y, letter, page, palette)
box = annotation(fig, 'textbox', [x/page(1) (y-7)/page(2) 20/page(1) 16/page(2)], ...
    'String',letter, 'FontName','Arial', 'FontSize',11, 'FontWeight','bold', ...
    'Color',palette.dark, 'LineStyle','none', 'Margin',0, 'Interpreter','none');
box.VerticalAlignment = 'middle';
end

function figureText(fig, rectangle, content, page, fontSize, color, alignment)
annotation(fig, 'textbox', rectangle./[page page], 'String',content, ...
    'FontName','Arial', 'FontSize',fontSize, 'Color',color, ...
    'HorizontalAlignment',alignment, 'VerticalAlignment','middle', ...
    'LineStyle','none', 'Margin',0, 'Interpreter','none');
end

function addPlanLegend(fig, page, palette)
annotation(fig,'rectangle',[157/page(1) 10/page(2) 5/page(1) 5/page(2)], ...
    'FaceColor',palette.orange, 'Color',palette.orange, 'LineWidth',0.6);
figureText(fig, [169 4 109 17], '3DCRT / PBC', page, 9, palette.dark, 'left');
annotation(fig,'ellipse',[279/page(1) 10/page(2) 5/page(1) 5/page(2)], ...
    'FaceColor',palette.blue, 'Color',palette.blue, 'LineWidth',0.6);
figureText(fig, [291 4 109 17], 'IMRT / AAA', page, 9, palette.dark, 'left');
end

function fig = patientMatrix(data, ids, visible, palette)
n = numel(ids);
height = max(566,185+12.7*n);
page = [510 height];
fig = newFigure('Fig4', page(1), page(2), visible);
ax = axes('Parent',fig, 'Position',[0 0 1 1], 'XLim',[0 page(1)], ...
    'YLim',[0 page(2)], 'Visible','off', 'NextPlot','add');
keys = {'carotid_worse_Dmean_Gy','carotid_worse_Dmax_Gy', ...
    'ptv_D95_Gy','ptv_D99_9_Gy','ptv_Dmax_Gy'};
labels = {sprintf('Carotid\nmean <20\nGy'), sprintf('Carotid\npeak %c50\nGy',char(8804)), ...
    sprintf('PTV D95\n%c66 Gy',char(8805)), sprintf('PTV\nD99.9\n%c62.7 Gy',char(8805)), ...
    sprintf('PTV peak\n%c72.6 Gy',char(8804))};
[~, order] = sort(data.IMRT.carotid_worse_Dmean_Gy(:), 'ascend', 'MissingPlacement','last');
step = 12.7; top = height-75;
ys = top-(0:n-1)*step;
for k = 1:n
    if mod(k,2) == 1
        patch(ax, [18 504 504 18], ys(k)+[-6 -6 step-6 step-6], ...
            [0.945 0.945 0.945], 'EdgeColor','none');
    end
    label = ids(order(k));
    if ~isempty(regexp(char(label), '^\d+(\.\d+)?$', 'once')), label = "P"+label; end
    text(ax, 46, ys(k), label, 'HorizontalAlignment','right', ...
        'VerticalAlignment','middle', 'FontName','Arial', 'FontSize',8.4, ...
        'Color',palette.dark, 'Interpreter','none');
end
anyMissing = false;
techniques = {'CRT','IMRT'};
for technique = 1:2
    start = 70+(technique-1)*237;
    panelLabel(fig, start-15, height-14, char('a'+technique-1), page, palette);
    titles = {'3DCRT / PBC','IMRT / AAA'};
    text(ax, start+88, height-14, titles{technique}, ...
        'HorizontalAlignment','center', 'FontWeight','bold', ...
        'FontName','Arial', 'FontSize',10, 'Color',palette.dark, 'Interpreter','none');
    for k = 1:5
        x = start+(k-1)*43;
        text(ax, x, height-43, labels{k}, 'HorizontalAlignment','center', ...
            'FontName','Arial', 'FontSize',8.5, 'Color',palette.dark, 'Interpreter','none');
        values = data.(techniques{technique}).(keys{k})(:);
        switch k
            case 1, attained = values < 20;
            case 2, attained = values <= 50;
            case 3, attained = values >= 66;
            case 4, attained = values >= 62.7;
            case 5, attained = values <= 72.6;
        end
        valid = isfinite(values);
        anyMissing = anyMissing || any(~valid);
        attained = attained & valid;
        for patient = 1:n
            index = order(patient); y = ys(patient);
            if ~valid(index)
                plot(ax, x, y, '.', 'Color',[0.54 0.54 0.54], 'MarkerSize',5);
            elseif attained(index)
                rectangle(ax,'Position',[x-3 y-3 6 6], 'FaceColor',palette.blue, ...
                    'EdgeColor',palette.blue, 'LineWidth',0.7);
            else
                rectangle(ax,'Position',[x-3 y-3 6 6], 'EdgeColor',[0.54 0.54 0.54], ...
                    'LineWidth',0.7);
                plot(ax, [x-2 x+2], [y-2 y+2], 'Color',[0.54 0.54 0.54], 'LineWidth',0.6);
            end
        end
        text(ax, x, 90, sprintf('%d/%d',sum(attained),sum(valid)), ...
            'HorizontalAlignment','center', 'FontWeight','bold', ...
            'FontName','Arial', 'FontSize',8.4, 'Color',palette.dark, 'Interpreter','none');
    end
end
text(ax, 46, 90, 'n', 'HorizontalAlignment','right', 'FontName','Arial', ...
    'FontSize',8.4, 'Color',palette.dark, 'Interpreter','none');
rectangle(ax,'Position',[80 48 6 6], 'FaceColor',palette.blue, 'EdgeColor',palette.blue);
text(ax, 92, 51, 'Marker attained', 'FontName','Arial', 'FontSize',9, ...
    'Color',palette.dark, 'Interpreter','none');
rectangle(ax,'Position',[282 48 6 6], 'EdgeColor',[0.54 0.54 0.54], 'LineWidth',0.7);
plot(ax, [283 287], [49 53], 'Color',[0.54 0.54 0.54], 'LineWidth',0.6);
text(ax, 294, 51, 'Marker not attained', 'FontName','Arial', 'FontSize',9, ...
    'Color',palette.dark, 'Interpreter','none');
if anyMissing
    plot(ax, 82, 36, '.', 'Color',[0.54 0.54 0.54], 'MarkerSize',5);
    text(ax, 92, 36, 'Missing; excluded from denominator', 'FontName','Arial', ...
        'FontSize',8, 'Color',palette.dark, 'Interpreter','none');
end
text(ax, 255, 24, 'Rows ordered by increasing IMRT worse-side carotid mean dose', ...
    'HorizontalAlignment','center', 'FontName','Arial', 'FontSize',8.5, ...
    'Color',palette.dark, 'Interpreter','none');
end

function [rho, p] = correlationValues(results, key)
rho = NaN; p = NaN;
if isfield(results,'correlations') && isfield(results.correlations,key)
    entry = results.correlations.(key);
    if isfield(entry,'spearman_rho'), rho = entry.spearman_rho; end
    if isfield(entry,'spearman_p_two_sided'), p = entry.spearman_p_two_sided; end
end
end

function files = saveFigure(fig, name, outdir, resolution)
drawnow;
sizeInches = getappdata(fig, 'glotticExportSizeInches');
files = string(fullfile(outdir, name+[".png";".tiff";".pdf";".fig"]));
exportgraphics(fig, files(1), 'Resolution',min(300,resolution), ...
    'BackgroundColor','white', 'Colorspace','rgb', 'Padding','figure', ...
    'Units','inches', 'Width',sizeInches(1), 'Height',sizeInches(2));
exportgraphics(fig, files(2), 'Resolution',resolution, ...
    'BackgroundColor','white', 'Colorspace','rgb', 'Padding','figure', ...
    'Units','inches', 'Width',sizeInches(1), 'Height',sizeInches(2));
exportgraphics(fig, files(3), 'ContentType','vector', 'BackgroundColor','white', ...
    'Padding','figure', 'Units','inches', 'Width',sizeInches(1), 'Height',sizeInches(2));
savefig(fig, files(4));
end
