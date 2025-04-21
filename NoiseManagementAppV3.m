function NoiseManagementAppV3
    %% Load trained models (Pre & Live)
    if ~isfile('BestMLModel_Pre_AR.mat') || ~isfile('BestMLModel_Pre_DR.mat') || ...
            ~isfile('BestMLModel_Live_AR.mat') || ~isfile('BestMLModel_Live_DR.mat')
        error('One or more model files are missing. Please run the Prediction_Main.m script first.');
    end
    load('BestMLModel_Pre_AR.mat', 'model_final'); model_Pre_AR = model_final;
    load('BestMLModel_Pre_DR.mat', 'model_final'); model_Pre_DR = model_final;
    load('BestMLModel_Live_AR.mat', 'model_final'); model_Live_AR = model_final;
    load('BestMLModel_Live_DR.mat', 'model_final'); model_Live_DR = model_final;
    % Load normalization stats for scaling
    load('pre_scaling.mat', 'mu_pre', 'sigma_pre');
    load('live_scaling.mat', 'mu_live', 'sigma_live');


    % Define sensitivity extremes for the psychological inputs.
   
    minSens = [1.0, 1.0];
    maxSens = [5.0, 5.0];

    %% Create Main Figure
    fig = figure('Name', 'Noise Management Application', 'Position', [100, 100, 1300, 700]);
    movegui(fig, 'center');

   
    % Map axes for layout
    ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.05, 0.15, 0.55, 0.8]);
    title(ax, 'Map and Heatmap');

    % Load Map Button
    uicontrol('Style', 'pushbutton', 'String', 'Upload Map', ...
        'Units', 'normalized', 'Position', [0.05, 0.02, 0.15, 0.05], ...
        'Callback', @(src, event) loadMap(ax));

    %% Grid Setup
    uicontrol('Style', 'text', 'String', 'Grid Rows:', ...
        'Units', 'normalized', 'Position', [0.63, 0.88, 0.08, 0.03]);
    gridRows = uicontrol('Style', 'edit', 'String', '5', ...
        'Units', 'normalized', 'Position', [0.71, 0.88, 0.05, 0.03]);

    uicontrol('Style', 'text', 'String', 'Grid Columns:', ...
        'Units', 'normalized', 'Position', [0.77, 0.88, 0.1, 0.03]);
    gridCols = uicontrol('Style', 'edit', 'String', '5', ...
        'Units', 'normalized', 'Position', [0.87, 0.88, 0.05, 0.03]);

    uicontrol('Style', 'pushbutton', 'String', 'Generate Grid', ...
        'Units', 'normalized', 'Position', [0.63, 0.83, 0.29, 0.04], ...
        'Callback', @(src, event) generateGrid(ax, str2double(gridRows.String), str2double(gridCols.String)));

    %% Psychological Inputs for Pre-Festival (HNoiSeQ, CNoiSeQ)
    uicontrol('Style', 'text', 'String', 'HNoiSeQ:', ...
        'Units', 'normalized', 'Position', [0.63, 0.78, 0.06, 0.03]);
    H_input = uicontrol('Style', 'edit', 'String', '2.5', ...
        'Units', 'normalized', 'Position', [0.69, 0.78, 0.05, 0.03]);

    uicontrol('Style', 'text', 'String', 'CNoiSeQ:', ...
        'Units', 'normalized', 'Position', [0.75, 0.78, 0.06, 0.03]);
    C_input = uicontrol('Style', 'edit', 'String', '2.5', ...
        'Units', 'normalized', 'Position', [0.81, 0.78, 0.05, 0.03]);

   
    %% Window State Switch
    % 1 indicates "Opened Window" (penalty = 10 dB); 0 indicates "Closed Window" (penalty = 27 dB)
    windowState = uicontrol('Style', 'togglebutton', ...
    'String', 'Closed Window', ...  % Initial state
    'Value', 0, ...                 % 0 means closed (27 dB penalty)
    'Units', 'normalized', ...
    'Position', [0.45, 0.059, 0.15, 0.03], ...
    'Callback', @(src, event) toggleWindowState(src));


    %% Acoustic Data Inputs Header
    headers = {'Cell #', 'LAeq (dB)', 'LCeq (dB)', 'Leq63Hz (dB)', ...
        'LZF99 (dB)', 'LZFmax (dB)', 'LCFmax (dB)', 'LCF90 (dB)'};
    numCols = numel(headers);
    startX = 0.63;
    endX = 0.98;
    colWidth = (endX - startX) / numCols;
    headerY = 0.68;
    for j = 1:numCols
        xPos = startX + (j-1)*colWidth;
        uicontrol('Style', 'text', 'String', headers{j}, 'Units', 'normalized', ...
            'Position', [xPos, headerY, colWidth, 0.03], 'FontWeight', 'bold', 'FontSize', 10);
    end

    %% Acoustic Data Input Fields for 5 Cells
    acousticInputs = cell(5, numCols);
    for i = 1:5
        ypos = headerY - 0.05 - (i-1)*0.07;
        for j = 1:numCols
            xPos = startX + (j-1)*colWidth;
            if j == 1
                defaultStr = num2str(i);
            elseif j <= 4
                if j == 2, defaultStr = '65';
                elseif j == 3, defaultStr = '70';
                elseif j == 4, defaultStr = '63';
                end
            else
                defaultStr = '0';
            end
            acousticInputs{i,j} = uicontrol('Style', 'edit', 'String', defaultStr, ...
                'Units', 'normalized', 'Position', [xPos, ypos, colWidth, 0.04]);
        end
    end

    %% Buttons and Toggles for Predictions
    toggleSwitch = uicontrol('Style', 'togglebutton', 'String', 'Show DR (Pre)', ...
        'Units', 'normalized', 'Position', [0.63, 0.2, 0.1, 0.05], ...
        'Callback', @(src, event) toggleHeatmap(src, ax, acousticInputs, ...
            model_Pre_AR, model_Pre_DR, str2double(gridRows.String), str2double(gridCols.String), ...
            str2double(H_input.String), str2double(C_input.String), 'Pre', windowState));

    uicontrol('Style', 'pushbutton', 'String', 'Calculate Pre', ...
        'Units', 'normalized', 'Position', [0.63, 0.15, 0.29, 0.05], ...
        'Callback', @(src, event) updatePre(fig, ax, acousticInputs, gridRows, gridCols, H_input, C_input, windowState, model_Pre_AR));

    liveToggleSwitch = uicontrol('Style', 'togglebutton', 'String', 'Show DR (Live)', ...
        'Units', 'normalized', 'Position', [0.63, 0.1, 0.1, 0.05], ...
        'Callback', @(src, event) toggleLiveHeatmap(src, ax, acousticInputs, ...
            model_Live_AR, model_Live_DR, str2double(gridRows.String), str2double(gridCols.String), ...
            str2double(H_input.String), str2double(C_input.String), 'Live', windowState));

    uicontrol('Style', 'pushbutton', 'String', 'Calculate Live', ...
        'Units', 'normalized', 'Position', [0.63, 0.05, 0.29, 0.05], ...
        'Callback', @(src, event) updateLive(fig, ax, acousticInputs, gridRows, gridCols, H_input, C_input, windowState, model_Live_AR));

    %% Save UI handles in app data
    state.ax = ax;
    state.gridRows = gridRows;
    state.gridCols = gridCols;
    state.H_input = H_input;
    state.C_input = C_input;
    state.acousticInputs = acousticInputs;
    state.windowState = windowState;
    state.model_Pre_AR = model_Pre_AR;
    state.model_Pre_DR = model_Pre_DR;
    state.model_Live_AR = model_Live_AR;
    state.model_Live_DR = model_Live_DR;
    state.mu_pre = mu_pre;
    state.sigma_pre = sigma_pre;
    state.mu_live = mu_live;
    state.sigma_live = sigma_live;

    state.currentMode = '';  % 'Pre' or 'Live'
    state.predictionMode = 'AR'; % sub-mode: 'AR' or 'DR'
    setappdata(fig, 'appState', state);
end

%% Local Helper Functions

function setCurrentMode(fig, mode)
    state = getappdata(fig, 'appState');
    state.currentMode = mode;
    setappdata(fig, 'appState', state);
end

function updatePre(fig, ax, acousticInputs, gridRows, gridCols, H_input, C_input,windowState, model_Pre_AR)
    
    state = getappdata(fig, 'appState');
    mu_pre = state.mu_pre;
    sigma_pre = state.sigma_pre;
    mu_live = state.mu_live;
    sigma_live = state.sigma_live;
    
    rows = str2double(get(gridRows, 'String'));
    cols = str2double(get(gridCols, 'String'));
    HNoiSeQ = max(1, min(5, str2double(get(H_input, 'String'))));
    CNoiSeQ = max(1, min(5, str2double(get(C_input, 'String'))));
    
    

    dynamicCalculate(ax, acousticInputs, model_Pre_AR, rows, cols, HNoiSeQ, CNoiSeQ, ...
        'Pre AR', [1.0,1.0], [5.0,5.0], windowState, mu_pre, sigma_pre, mu_live, sigma_live);
    
    % Update title and state.
    titleStr = sprintf('Pre AR Heatmap - HNoiSeQ: %.1f, CNoiSeQ: %.1f, Window: %s', ...
        HNoiSeQ, CNoiSeQ, windowState.String);
    title(ax, titleStr);
    drawnow;
    
    state = getappdata(fig, 'appState');
    state.currentMode = 'Pre';
    state.predictionMode = 'AR';
    setappdata(fig, 'appState', state);
end

function updateLive(fig, ax, acousticInputs, gridRows, gridCols, H_input, C_input, windowState, model_Live_AR)
    
    state = getappdata(fig, 'appState');
    mu_pre = state.mu_pre;
    sigma_pre = state.sigma_pre;
    mu_live = state.mu_live;
    sigma_live = state.sigma_live;

    rows = str2double(get(gridRows, 'String'));
    cols = str2double(get(gridCols, 'String'));
    HNoiSeQ = max(1, min(5, str2double(get(H_input, 'String'))));
    CNoiSeQ = max(1, min(5, str2double(get(C_input, 'String'))));
    
    

    dynamicCalculateLive(ax, acousticInputs, model_Live_AR, rows, cols, HNoiSeQ, CNoiSeQ, ...
        'Live AR', [1.0,1.0], [5.0,5.0], windowState, mu_pre, sigma_pre, mu_live, sigma_live);
    
    % Update title and state.
    titleStr = sprintf('Live AR Heatmap - HNoiSeQ: %.1f, CNoiSeQ: %.1f, Window: %s', ...
        HNoiSeQ, CNoiSeQ, windowState.String);
    title(ax, titleStr);
    drawnow;
    
    state = getappdata(fig, 'appState');
    state.currentMode = 'Live';
    state.predictionMode = 'AR';
    setappdata(fig, 'appState', state);
end

function toggleWindowState(src)
    if src.Value == 1
        src.String = 'Opened Window';
    else
        src.String = 'Closed Window';
    end

    fig = ancestor(src, 'figure');
    state = getappdata(fig, 'appState');

    % ✅ Add this block to retrieve normalization stats
    mu_pre = state.mu_pre;
    sigma_pre = state.sigma_pre;
    mu_live = state.mu_live;
    sigma_live = state.sigma_live;

    if isfield(state, 'currentMode') && ~isempty(state.currentMode)
        rows = str2double(get(state.gridRows, 'String'));
        cols = str2double(get(state.gridCols, 'String'));
        HNoiSeQ = max(1, min(5, str2double(get(state.H_input, 'String'))));
        CNoiSeQ = max(1, min(5, str2double(get(state.C_input, 'String'))));
        
        if strcmp(state.currentMode, 'Pre')
            if isfield(state, 'predictionMode') && strcmp(state.predictionMode, 'DR')
                dynamicCalculate(state.ax, state.acousticInputs, ...
                    state.model_Pre_DR, rows, cols, HNoiSeQ, CNoiSeQ, ...
                    'Pre DR', [1.0,1.0], [5.0,5.0], state.windowState, ...
                mu_pre, sigma_pre, mu_live, sigma_live);
                title(state.ax, sprintf('Pre DR Heatmap - HNoiSeQ: %.1f, CNoiSeQ: %.1f, Window: %s', ...
                    HNoiSeQ, CNoiSeQ, state.windowState.String));
            else
                dynamicCalculate(state.ax, state.acousticInputs, ...
                    state.model_Pre_AR, rows, cols, HNoiSeQ, CNoiSeQ, ...
                    'Pre AR', [1.0,1.0], [5.0,5.0], state.windowState, ...
                mu_pre, sigma_pre, mu_live, sigma_live);
                title(state.ax, sprintf('Pre AR Heatmap - HNoiSeQ: %.1f, CNoiSeQ: %.1f, Window: %s', ...
                    HNoiSeQ, CNoiSeQ, state.windowState.String));
            end
        elseif strcmp(state.currentMode, 'Live')
            if isfield(state, 'predictionMode') && strcmp(state.predictionMode, 'DR')
                dynamicCalculateLive(state.ax, state.acousticInputs, ...
                    state.model_Live_DR, rows, cols, HNoiSeQ, CNoiSeQ, ...
                    'Live DR', [1.0,1.0], [5.0,5.0], state.windowState, ...
                mu_pre, sigma_pre, mu_live, sigma_live);
                title(state.ax, sprintf('Live DR Heatmap - HNoiSeQ: %.1f, CNoiSeQ: %.1f, Window: %s', ...
                    HNoiSeQ, CNoiSeQ, state.windowState.String));
            else
                dynamicCalculateLive(state.ax, state.acousticInputs, ...
                    state.model_Live_AR, rows, cols, HNoiSeQ, CNoiSeQ, ...
                    'Live AR', [1.0,1.0], [5.0,5.0], state.windowState, ...
                mu_pre, sigma_pre, mu_live, sigma_live);
                title(state.ax, sprintf('Live AR Heatmap - HNoiSeQ: %.1f, CNoiSeQ: %.1f, Window: %s', ...
                    HNoiSeQ, CNoiSeQ,state.windowState.String));
            end
        end
        drawnow;
    end
end

function loadMap(ax)
    [file, path] = uigetfile({'*.jpg;*.png;*.bmp'}, 'Select a Map');
    if isequal(file, 0)
        disp('Map loading cancelled.');
    else
        img = imread(fullfile(path, file));
        cla(ax);
        imshow(img, 'Parent', ax);
        title(ax, 'Imported Map');
        set(ax, 'Tag', 'ImportedImage', 'UserData', img);
    end
end

function generateGrid(ax, rows, cols)
    img = get(ax, 'UserData');
    if isempty(img)
        disp('No map loaded.');
        return;
    end
    cla(ax);
    [height, width, ~] = size(img);
    cellHeight = height / rows;
    cellWidth = width / cols;
    hold(ax, 'on');
    imagesc(ax, img, 'AlphaData', 1);
    set(ax, 'YDir', 'reverse');
    for i = 1:rows
        for j = 1:cols
            x = (j - 1) * cellWidth;
            y = (rows - i) * cellHeight;
            cellNumber = (i - 1) * cols + j;
            rectangle(ax, 'Position', [x, y, cellWidth, cellHeight], 'EdgeColor', 'w', 'LineWidth', 1);
            text(ax, x + 5, y + 5, num2str(cellNumber), 'Color', 'w', 'FontWeight', 'bold', ...
                'BackgroundColor', 'k', 'HorizontalAlignment', 'left', 'FontSize', 10, 'Clipping', 'on');
        end
    end
    hold(ax, 'off');
end

function dynamicCalculate(ax, acousticInputs, model, rows, cols, HNoiSeQ, CNoiSeQ, ratingType, minSens, maxSens, windowState,mu_pre, sigma_pre, mu_live, sigma_live)
    % For Pre mode.
    % Constructs the feature vector:
    % [LAeq, LCeq, Leq63Hz, HNoiSeQ, CNoiSeQ]
    % Then adjust min and max predictions so they bound the full prediction.
    
    img = get(ax, 'UserData');
    if isempty(img)
        disp('No map loaded.');
        return;
    end

    if windowState.Value == 1
        penalty = 10;
    else
        penalty = 27;
    end

    cla(ax);
    [height, width, ~] = size(img);
    cellHeight = height / rows;
    cellWidth = width / cols;
    ratingMatrix = zeros(height, width);
    hold(ax, 'on');
    imagesc(ax, img, 'AlphaData', 1);
    set(ax, 'YDir', 'reverse');

   for i = 1:size(acousticInputs, 1)
        cellNum = str2double(acousticInputs{i,1}.String);
        if cellNum <= rows * cols
           % Apply penalty to acoustic inputs
            LAeq_pen = str2double(acousticInputs{i,2}.String) - penalty;
            LCeq_pen = str2double(acousticInputs{i,3}.String) - penalty;
            Leq63Hz_pen = str2double(acousticInputs{i,4}.String) - penalty;

            % Derived features from penalized values
            Delta_LC_LA = LCeq_pen - LAeq_pen;
            Leq63Hz_LAeq_Ratio = Leq63Hz_pen / (LAeq_pen + eps);
            TotalNoiSeQ = HNoiSeQ + CNoiSeQ;
            LAeq_HNoiSeQ = LAeq_pen * HNoiSeQ;
            Leq63Hz_HNoiSeQ = Leq63Hz_pen * HNoiSeQ;

            % Final feature vector
            X_input = [LAeq_pen, LCeq_pen, Leq63Hz_pen, HNoiSeQ, CNoiSeQ, ...
                       Delta_LC_LA, Leq63Hz_LAeq_Ratio, TotalNoiSeQ, ...
                       LAeq_HNoiSeQ, Leq63Hz_HNoiSeQ];

            % Sensitivity extremes
            Hmin = minSens(1); Cmin = minSens(2);
            Hmax = maxSens(1); Cmax = maxSens(2);

            X_input_min = [LAeq_pen, LCeq_pen, Leq63Hz_pen, Hmin, Cmin, ...
                           Delta_LC_LA, Leq63Hz_pen / (LAeq_pen + eps), ...
                           Hmin + Cmin, LAeq_pen * Hmin, Leq63Hz_pen * Hmin];

            X_input_max = [LAeq_pen, LCeq_pen, Leq63Hz_pen, Hmax, Cmax, ...
                           Delta_LC_LA, Leq63Hz_pen / (LAeq_pen + eps), ...
                           Hmax + Cmax, LAeq_pen * Hmax, Leq63Hz_pen * Hmax];

            % Normalize input using training stats
if strcmp(ratingType, 'Pre AR') || strcmp(ratingType, 'Pre DR')
    X_input = (X_input - mu_pre) ./ sigma_pre;
    X_input_min = (X_input_min - mu_pre) ./ sigma_pre;
    X_input_max = (X_input_max - mu_pre) ./ sigma_pre;
else
    X_input = (X_input - mu_live) ./ sigma_live;
    X_input_min = (X_input_min - mu_live) ./ sigma_live;
    X_input_max = (X_input_max - mu_live) ./ sigma_live;
end

            pred = predict(model, X_input);
            pred_min = predict(model, X_input_min);
            pred_max = predict(model, X_input_max);
            
            % Ensure that the min and max predictions bound the full prediction.
            if pred < pred_min
                pred_min = pred;
            end
            if pred > pred_max
                pred_max = pred;
            end
            
            % Clamp all values between 0 and 10.
            pred = max(0, min(10, pred));
            pred_min = max(0, min(10, pred_min));
            pred_max = max(0, min(10, pred_max));
            
            rowIdx = floor((cellNum - 1) / cols) + 1;
            colIdx = mod(cellNum - 1, cols) + 1;
            rowStart = (rows - rowIdx) * cellHeight + 1;
            rowEnd = rowStart + cellHeight - 1;
            colStart = (colIdx - 1) * cellWidth + 1;
            colEnd = colStart + cellWidth - 1;
            
            ratingMatrix(round(rowStart):round(rowEnd), round(colStart):round(colEnd)) = pred;
            
            centerX = colStart + cellWidth / 2;
            centerY = rowStart + cellHeight / 2;
            text(ax, centerX, centerY, sprintf('%.2f\n(%.2f, %.2f)', pred, pred_min, pred_max), ...
                'Color', 'y', 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                'FontSize', 16, 'BackgroundColor', 'k', 'Clipping', 'on');
        end
    end

    imagesc(ax, 'CData', ratingMatrix, 'AlphaData', 0.5);
    caxis(ax, [0, 10]);
    colormap(ax, jet);
    c = colorbar(ax);
    c.Label.String = [ratingType, ' (', ratingType, ' Rating)'];
    titleStr = sprintf('%s Heatmap - HNoiSeQ: %.1f, CNoiSeQ: %.1f, Window: %s', ...
        ratingType, HNoiSeQ, CNoiSeQ, windowState.String);
    title(ax, titleStr);
    drawnow;
    
    % Redraw grid cells with numbering.
    for i = 1:rows
        for j = 1:cols
            x = (j - 1) * cellWidth;
            y = (rows - i) * cellHeight;
            cellNumber = (i - 1) * cols + j;
            rectangle(ax, 'Position', [x, y, cellWidth, cellHeight], 'EdgeColor', 'w', 'LineWidth', 1);
            text(ax, x + 5, y + 5, num2str(cellNumber), 'Color', 'w', 'FontWeight', 'bold', ...
                'BackgroundColor', 'k', 'HorizontalAlignment', 'left', 'FontSize', 10, 'Clipping', 'on');
        end
    end
    hold(ax, 'off');
end

function dynamicCalculateLive(ax, acousticInputs, model, rows, cols, HNoiSeQ, CNoiSeQ, ratingType, minSens, maxSens, windowState,mu_pre, sigma_pre, mu_live, sigma_live)
    % For Live mode.
    % Constructs feature vector:
    % [LAeq, LCeq, Leq63Hz, HNoiSeQ, CNoiSeQ, LZF99, LZFmax, LCFmax, LCF90]
    % Then adjust min and max predictions so they bound the full prediction.
    
    img = get(ax, 'UserData');
    if isempty(img)
        disp('No map loaded.');
        return;
    end

    if windowState.Value == 1
        penalty = 10;
    else
        penalty = 27;
    end

    cla(ax);
    [height, width, ~] = size(img);
    cellHeight = height / rows;
    cellWidth = width / cols;
    ratingMatrix = zeros(height, width);

    hold(ax, 'on');
    imagesc(ax, img, 'AlphaData', 1);
    set(ax, 'YDir', 'reverse');

    for i = 1:size(acousticInputs, 1)
        cellNum = str2double(acousticInputs{i,1}.String);
        if cellNum <= rows * cols

% Extract raw values from GUI
LAeq = str2double(acousticInputs{i,2}.String);
LCeq = str2double(acousticInputs{i,3}.String);
Leq63Hz = str2double(acousticInputs{i,4}.String);
LZF99 = str2double(acousticInputs{i,5}.String);
LZFmax = str2double(acousticInputs{i,6}.String);
LCFmax = str2double(acousticInputs{i,7}.String);
LCF90 = str2double(acousticInputs{i,8}.String);


% Apply penalty to acoustic features
LAeq_pen = LAeq - penalty;
LCeq_pen = LCeq - penalty;
Leq63Hz_pen = Leq63Hz - penalty;
LZF99_pen = LZF99 - penalty;
LZFmax_pen = LZFmax - penalty;
LCFmax_pen = LCFmax - penalty;
LCF90_pen = LCF90 - penalty;

% Derived features using penalized values
Delta_LC_LA = LCeq_pen - LAeq_pen;
Leq63Hz_LAeq_Ratio = Leq63Hz_pen / (LAeq_pen + eps);
TotalNoiSeQ = HNoiSeQ + CNoiSeQ;
Delta_ZF_CF = LZF99_pen - LCF90_pen;
LAeq_HNoiSeQ = LAeq_pen * HNoiSeQ;
Leq63Hz_HNoiSeQ = Leq63Hz_pen * HNoiSeQ;
LZF99_LCFmax_Ratio = LZF99_pen / (LCFmax_pen + eps);
LCFmax_CNoiSeQ = LCFmax_pen * CNoiSeQ;
LZFmax_LAeq_Ratio = LZFmax_pen / (LAeq_pen + eps);
LZF99_HNoiSeQ = LZF99_pen * HNoiSeQ;
LZFmax_LCF90_Ratio = LZFmax_pen / (LCF90_pen + eps);

% X_input (full)
X_input = [LAeq_pen, LCeq_pen, Leq63Hz_pen, HNoiSeQ, CNoiSeQ, ...
           Delta_LC_LA, Leq63Hz_LAeq_Ratio, TotalNoiSeQ, ...
           LAeq_HNoiSeQ, Leq63Hz_HNoiSeQ, LZF99_pen, LCFmax_pen, ...
           LZFmax_pen, LCF90_pen, LZF99_LCFmax_Ratio, Delta_ZF_CF, ...
           LZF99_LCFmax_Ratio, LCFmax_CNoiSeQ, LZFmax_LAeq_Ratio, ...
           LZF99_HNoiSeQ, LZFmax_LCF90_Ratio];

% X_input_min
Hmin = minSens(1); Cmin = minSens(2);
X_input_min = [LAeq_pen, LCeq_pen, Leq63Hz_pen, Hmin, Cmin, ...
               Delta_LC_LA, Leq63Hz_pen / (LAeq_pen + eps), ...
               Hmin + Cmin, LAeq_pen * Hmin, Leq63Hz_pen * Hmin, ...
               LZF99_pen, LCFmax_pen, LZFmax_pen, LCF90_pen, ...
               LZF99_pen / (LCFmax_pen + eps), Delta_ZF_CF, ...
               LZF99_pen / (LCFmax_pen + eps), LCFmax_pen * Cmin, ...
               LZFmax_pen / (LAeq_pen + eps), LZF99_pen * Hmin, ...
               LZFmax_pen / (LCF90_pen + eps)];

% X_input_max
Hmax = maxSens(1); Cmax = maxSens(2);
X_input_max = [LAeq_pen, LCeq_pen, Leq63Hz_pen, Hmax, Cmax, ...
               Delta_LC_LA, Leq63Hz_pen / (LAeq_pen + eps), ...
               Hmax + Cmax, LAeq_pen * Hmax, Leq63Hz_pen * Hmax, ...
               LZF99_pen, LCFmax_pen, LZFmax_pen, LCF90_pen, ...
               LZF99_pen / (LCFmax_pen + eps), Delta_ZF_CF, ...
               LZF99_pen / (LCFmax_pen + eps), LCFmax_pen * Cmax, ...
               LZFmax_pen / (LAeq_pen + eps), LZF99_pen * Hmax, ...
               LZFmax_pen / (LCF90_pen + eps)];

% ✅ Normalize using live scaling
X_input = (X_input - mu_live) ./ sigma_live;
X_input_min = (X_input_min - mu_live) ./ sigma_live;
X_input_max = (X_input_max - mu_live) ./ sigma_live;

% Predict using the model
pred = predict(model, X_input);
pred_min = predict(model, X_input_min);
pred_max = predict(model, X_input_max);

           % Predict using the model
            pred      = predict(model, X_input);
            pred_min  = predict(model, X_input_min);
            pred_max  = predict(model, X_input_max);


            % Adjust the min and max predictions so they bound the full prediction.
            if pred < pred_min
                pred_min = pred;
            end
            if pred > pred_max
                pred_max = pred;
            end
            
            % Clamp all values between 0 and 10.
            pred = max(0, min(10, pred));
            pred_min = max(0, min(10, pred_min));
            pred_max = max(0, min(10, pred_max));

            rowIdx = floor((cellNum - 1) / cols) + 1;
            colIdx = mod(cellNum - 1, cols) + 1;
            rowStart = (rows - rowIdx) * cellHeight + 1;
            rowEnd = rowStart + cellHeight - 1;
            colStart = (colIdx - 1) * cellWidth + 1;
            colEnd = colStart + cellWidth - 1;

            ratingMatrix(round(rowStart):round(rowEnd), round(colStart):round(colEnd)) = pred;

            centerX = colStart + cellWidth / 2;
            centerY = rowStart + cellHeight / 2;
            text(ax, centerX, centerY, sprintf('%.2f\n(%.2f, %.2f)', pred, pred_min, pred_max), ...
                'Color', 'c', 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                'FontSize', 16, 'BackgroundColor', 'k', 'Clipping', 'on');
        end
    end

    imagesc(ax, 'CData', ratingMatrix, 'AlphaData', 0.5);
    caxis(ax, [0, 10]);
    colormap(ax, jet);
    c = colorbar(ax);
    c.Label.String = [ratingType, ' (', ratingType, ' Rating)'];
    titleStr = sprintf('%s Heatmap - HNoiSeQ: %.1f, CNoiSeQ: %.1f, Window: %s', ...
        ratingType, HNoiSeQ, CNoiSeQ, windowState.String);
    title(ax, titleStr);
    drawnow;

    for i = 1:rows
        for j = 1:cols
            x = (j - 1) * cellWidth;
            y = (rows - i) * cellHeight;
            cellNumber = (i - 1) * cols + j;
            rectangle(ax, 'Position', [x, y, cellWidth, cellHeight], 'EdgeColor', 'w', 'LineWidth', 1);
            text(ax, x + 5, y + 5, num2str(cellNumber), 'Color', 'w', 'FontWeight', 'bold', ...
                'BackgroundColor', 'k', 'HorizontalAlignment', 'left', 'FontSize', 10, 'Clipping', 'on');
        end
    end
    hold(ax, 'off');
end

function toggleHeatmap(src, ax, acousticInputs, model_AR, model_DR, rows, cols, HNoiSeQ, CNoiSeQ, mode, windowState)
    fig = ancestor(src, 'figure');
    state = getappdata(fig, 'appState');

    % ✅ Retrieve normalization variables
    mu_pre = state.mu_pre;
    sigma_pre = state.sigma_pre;
    mu_live = state.mu_live;
    sigma_live = state.sigma_live;

    if src.Value
        if strcmp(mode, 'Pre')
            src.String = 'Show AR (Pre)';
            state.predictionMode = 'DR';
            dynamicCalculate(ax, acousticInputs, model_DR, rows, cols, HNoiSeQ, CNoiSeQ, ...
                             'Pre DR', [1.0,1.0], [5.0,5.0], windowState, mu_pre, sigma_pre, mu_live, sigma_live);
        end
    else
        if strcmp(mode, 'Pre')
            src.String = 'Show DR (Pre)';
            state.predictionMode = 'AR';
            dynamicCalculate(ax, acousticInputs, model_AR, rows, cols, HNoiSeQ, CNoiSeQ, ...
                             'Pre AR', [1.0,1.0], [5.0,5.0], windowState, mu_pre, sigma_pre, mu_live, sigma_live);
        end
    end
    setappdata(fig, 'appState', state);
end

function toggleLiveHeatmap(src, ax, acousticInputs, model_AR, model_DR, rows, cols, HNoiSeQ, CNoiSeQ, mode, windowState)
    fig = ancestor(src, 'figure');
    state = getappdata(fig, 'appState');

    % ✅ Retrieve normalization variables
    mu_pre = state.mu_pre;
    sigma_pre = state.sigma_pre;
    mu_live = state.mu_live;
    sigma_live = state.sigma_live;

    if src.Value
        if strcmp(mode, 'Live')
            src.String = 'Show AR (Live)';
            state.predictionMode = 'DR';
            dynamicCalculateLive(ax, acousticInputs, model_DR, rows, cols, HNoiSeQ, CNoiSeQ, ...
                                 'Live DR', [1.0,1.0], [5.0,5.0], windowState, mu_pre, sigma_pre, mu_live, sigma_live);
        end
    else
        if strcmp(mode, 'Live')
            src.String = 'Show DR (Live)';
            state.predictionMode = 'AR';
            dynamicCalculateLive(ax, acousticInputs, model_AR, rows, cols, HNoiSeQ, CNoiSeQ,  ...
                                 'Live AR', [1.0,1.0], [5.0,5.0], windowState, mu_pre, sigma_pre, mu_live, sigma_live);
        end
    end
    setappdata(fig, 'appState', state);
end

function exportReport(fig)
    % Use auto PaperPositionMode to export GUI window size
    set(fig, 'PaperUnits', 'inches');
    set(fig, 'PaperPositionMode', 'auto');

    % Turn off clipping for text objects
    txtObjs = findall(fig, 'Type', 'text');
    oldClipping = get(txtObjs, 'Clipping');
    if ~iscell(oldClipping)
        oldClipping = {oldClipping};
    end
    set(txtObjs, 'Clipping', 'off');

    % Prompt for filename
    [file, path] = uiputfile('NoiseManagementReport.pdf', 'Save Report As');
    if isequal(file, 0)
        disp('User cancelled report export.');
    else
        exportFile = fullfile(path, file);
        print(fig, exportFile, '-dpdf', '-r300');
        disp(['Report exported to ', exportFile]);
    end

    % Restore clipping settings
    for k = 1:length(txtObjs)
        set(txtObjs(k), 'Clipping', oldClipping{k});
    end
end
