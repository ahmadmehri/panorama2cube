function panorama2cube()
    close all
    clc

    % Main GUI function for Panorama to Cubemap conversion with live preview
    fig = figure('Name', 'Panorama to Cubemap', 'Position', [100, 100, 1000, 800], 'NumberTitle', 'off');
    
    % Initialize variables
    subsamplingFactors = [1, 2, 4, 8, 16];
    currentSubsampling = 8;
    currentRotation = 0;
    interpolationMethods = {'linear', 'cubic', 'spline', 'nearest'};
    currentInterpolation = 'linear';
    
    % Create UI controls --------------------------------------------------
    % Input image selection
    uicontrol('Style', 'pushbutton',...
        'String', 'Select Input Image',...
        'Position', [50, 770, 200, 30],...
        'Callback', @selectInputImage,...
        'TooltipString', 'Select a panoramic image with 2:1 aspect ratio');
    
    inputPathText = uicontrol('Style', 'text',...
        'String', 'No image selected',...
        'Position', [50, 740, 200, 20]);

    % Output directory selection
    uicontrol('Style', 'pushbutton',...
        'String', 'Select Output Directory',...
        'Position', [50, 710, 200, 30],...
        'Callback', @selectOutputDir,...
        'TooltipString', 'Choose directory to save cubemap faces');
    
    outputDirText = uicontrol('Style', 'text',...
        'String', 'Default: output_faces',...
        'Position', [50, 680, 200, 20]);

    % Rotation controls
    rotationSlider = uicontrol('Style', 'slider',...
        'Min', 0, 'Max', 360, 'Value', currentRotation,...
        'Position', [50, 640, 200, 30],...
        'Callback', @updatePreview,...
        'TooltipString', 'Rotate cubemap around vertical axis (0°-360°)');
    
    rotationLabel = uicontrol('Style', 'text',...
        'String', sprintf('Rotation: %d°', currentRotation),...
        'Position', [50, 670, 200, 20]);

    % Quality controls
    subsamplingPopup = uicontrol('Style', 'popupmenu',...
        'String', {'1 (Full)', '2', '4', '8', '16'},...
        'Position', [50, 600, 200, 30],...
        'Value', 4,...
        'Callback', @updatePreview,...
        'TooltipString', 'Preview quality/speed tradeoff (doesn''t affect final render)');
    
    interpolationPopup = uicontrol('Style', 'popupmenu',...
        'String', interpolationMethods,...
        'Position', [50, 570, 200, 30],...
        'Callback', @updatePreview,...
        'TooltipString', 'Pixel interpolation method for preview');

    % Render button
    uicontrol('Style', 'pushbutton',...
        'String', 'Render',...
        'Position', [50, 540, 100, 30],...
        'Callback', @renderCallback,...
        'TooltipString', 'Generate full-resolution cubemap faces');

    % Axes for preview display
    ax = axes('Parent', fig, 'Position', [0.3, 0.1, 0.6, 0.8]);

    % Callback functions --------------------------------------------------
    function selectInputImage(~, ~)
        [file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif;*.tiff', 'Image Files'}, 'Select Panorama Image');
        if isequal(file, 0)
            return;
        end
        inputPath = fullfile(path, file);
        try
            img = imread(inputPath);
            [h, w, ~] = size(img);
            if w ~= 2*h
                errordlg('Image must have 2:1 aspect ratio', 'Invalid Image');
                return;
            end
            setappdata(fig, 'originalImg', img);
            setappdata(fig, 'inputPath', inputPath);
            set(inputPathText, 'String', file);
            updatePreview();
        catch ME
            errordlg(sprintf('Error loading image:\n%s', ME.message), 'File Error');
        end
    end

    function selectOutputDir(~, ~)
        outputDir = uigetdir('', 'Select Output Directory');
        if outputDir == 0
            return;
        end
        setappdata(fig, 'outputDir', outputDir);
        set(outputDirText, 'String', outputDir);
    end

    function updatePreview(~, ~)
        originalImg = getappdata(fig, 'originalImg');
        if isempty(originalImg)
            cla(ax);
            title(ax, 'Please select an input image');
            return;
        end
        
        [h, w, ~] = size(originalImg);
        if w ~= 2*h
            cla(ax);
            title(ax, 'Image must be 2:1 aspect ratio');
            return;
        end
        
        currentRotation = round(get(rotationSlider, 'Value'));
        set(rotationLabel, 'String', sprintf('Rotation: %d°', currentRotation));
        currentSubsampling = subsamplingFactors(get(subsamplingPopup, 'Value'));
        currentInterpolation = interpolationMethods{get(interpolationPopup, 'Value')};
        
        % Subsample image
        subsampledImg = originalImg(1:currentSubsampling:end, 1:currentSubsampling:end, :);
        
        % Process and display preview
        arranged_image = processCubeMap(subsampledImg, currentRotation, currentInterpolation);
        imshow(arranged_image, 'Parent', ax);
        title(ax, 'Live Cubemap Preview');
    end

    function renderCallback(~, ~)
        inputPath = getappdata(fig, 'inputPath');
        if isempty(inputPath)
            errordlg('Please select an input image first', 'Missing Input');
            return;
        end
        
        outputDir = getappdata(fig, 'outputDir');
        if isempty(outputDir)
            outputDir = 'output_faces';
            setappdata(fig, 'outputDir', outputDir);
            set(outputDirText, 'String', outputDir);
        end
        
        currentRotation = round(get(rotationSlider, 'Value'));
        currentInterpolation = interpolationMethods{get(interpolationPopup, 'Value')};
        
        try
            originalImg = getappdata(fig, 'originalImg');
            [h, w, ~] = size(originalImg);
            faceSize = floor(w / 4);
            rotationRad = deg2rad(currentRotation);
            
            % Face labels and their corresponding names
            faceLabels = {'pz', 'nz', 'px', 'nx', 'py', 'ny'};
            faceNames = {'front', 'back', 'right', 'left', 'top', 'bottom'};
            
            % Create output directory if it doesn't exist
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end
            
            for faceIdx = 1:length(faceLabels)
                face = faceLabels{faceIdx};
                [xGrid, yGrid] = meshgrid(1:faceSize, 1:faceSize);
                u = 2*(xGrid - 0.5)/faceSize - 1;
                v = 2*(yGrid - 0.5)/faceSize - 1;
                
                switch face
                    case 'pz'
                        X = -ones(size(u)); Y = -u; Z = -v;
                    case 'nz'
                        X = ones(size(u)); Y = u; Z = -v;
                    case 'px'
                        X = u; Y = -ones(size(u)); Z = -v;
                    case 'nx'
                        X = -u; Y = ones(size(u)); Z = -v;
                    case 'py'
                        X = -v; Y = -u; Z = ones(size(v));
                    case 'ny'
                        X = v; Y = -u; Z = -ones(size(v));
                end
                
                r = sqrt(X.^2 + Y.^2 + Z.^2);
                theta = atan2(Y, X) + rotationRad;
                theta = mod(theta, 2*pi);
                phi = acos(Z ./ r);
                
                xEqui = (theta / (2*pi)) * w + 0.5;
                yEqui = (phi / pi) * h + 0.5;
                xEqui = max(1, min(w, xEqui));
                yEqui = max(1, min(h, yEqui));
                
                [cols, rows] = meshgrid(1:w, 1:h);
                R = double(originalImg(:,:,1));
                G = double(originalImg(:,:,2));
                B = double(originalImg(:,:,3));
                
                faceR = interp2(cols, rows, R, xEqui, yEqui, currentInterpolation, 0);
                faceG = interp2(cols, rows, G, xEqui, yEqui, currentInterpolation, 0);
                faceB = interp2(cols, rows, B, xEqui, yEqui, currentInterpolation, 0);
                
                faceImg = uint8(cat(3, faceR, faceG, faceB));
                outputPath = fullfile(outputDir, [faceNames{faceIdx} '.jpg']);
                imwrite(faceImg, outputPath);
            end
            
            msgbox(sprintf('Rendering complete!\nOutput saved to:\n%s', outputDir), 'Success');
        catch ME
            errordlg(sprintf('Rendering failed:\n%s', ME.message), 'Error');
        end
    end

    % Initial setup
    updatePreview();
end

function arranged_image = processCubeMap(img, rotationDeg, interpolationMethod)
    [height, width, ~] = size(img);
    rotationRad = deg2rad(rotationDeg);
    faceSize = floor(width / 4);
    
    arranged_image = zeros(faceSize*4, faceSize*3, 3, 'uint8');
    
    if isempty(img) || width ~= 2*height
        warning('Invalid input image dimensions - must be 2:1 aspect ratio');
        return;
    end
    
    faces = {'pz', 'nz', 'px', 'nx', 'py', 'ny'};
    out = cell(1, length(faces));
    
    try
        for faceIdx = 1:length(faces)
            face = faces{faceIdx};
            [xGrid, yGrid] = meshgrid(1:faceSize, 1:faceSize);
            u = 2*(xGrid - 0.5)/faceSize - 1;
            v = 2*(yGrid - 0.5)/faceSize - 1;
            
            switch face
                case 'pz'
                    X = -ones(size(u)); Y = -u; Z = -v;
                case 'nz'
                    X = ones(size(u)); Y = u; Z = -v;
                case 'px'
                    X = u; Y = -ones(size(u)); Z = -v;
                case 'nx'
                    X = -u; Y = ones(size(u)); Z = -v;
                case 'py'
                    X = -v; Y = -u; Z = ones(size(v));
                case 'ny'
                    X = v; Y = -u; Z = -ones(size(v));
            end
            
            r = sqrt(X.^2 + Y.^2 + Z.^2);
            theta = atan2(Y, X) + rotationRad;
            theta = mod(theta, 2*pi);
            phi = acos(Z ./ r);
            
            xEqui = (theta / (2*pi)) * width + 0.5;
            yEqui = (phi / pi) * height + 0.5;
            xEqui = max(1, min(width, xEqui));
            yEqui = max(1, min(height, yEqui));
            
            [cols, rows] = meshgrid(1:width, 1:height);
            R = double(img(:,:,1));
            G = double(img(:,:,2));
            B = double(img(:,:,3));
            
            faceR = interp2(cols, rows, R, xEqui, yEqui, interpolationMethod, 0);
            faceG = interp2(cols, rows, G, xEqui, yEqui, interpolationMethod, 0);
            faceB = interp2(cols, rows, B, xEqui, yEqui, interpolationMethod, 0);
            
            out{faceIdx} = uint8(cat(3, faceR, faceG, faceB));
        end
        
        arranged_image = [
            zeros(size(out{5})), out{5}, zeros(size(out{5}));
            out{4}, out{1}, out{3};
            zeros(size(out{6})), out{6}, zeros(size(out{6}));
            zeros(size(out{3})), out{2}, zeros(size(out{3}))
        ];
    catch ME
        warning('Error processing cubemap: %s', E.message);
        arranged_image = insertText(zeros(faceSize*4, faceSize*3, 3, 'uint8'),...
            [faceSize, faceSize*2], 'Processing Error',...
            'FontSize', 20, 'TextColor', 'white', 'BoxColor', 'red');
    end
end