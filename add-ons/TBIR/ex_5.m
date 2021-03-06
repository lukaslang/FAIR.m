% Copyright 2019 Lukas F. Lang and Sebastian Neumayer
%
% This file is part of TBIR.
%
%    TBIR is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    TBIR is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with TBIR.  If not, see <http://www.gnu.org/licenses/>.
%
% This script creates the results shown in Figure 7.
% Results are saved to the folder 'results'. When run for the first time,
% measurements (sinograms) are created and also saved to the results
% folder. In every subsequent run these measurements are used again. Make
% sure to delete these files when you change the images or their sizes.
clear;
close all;
clc;

% Flag that activates plotting.
plot = false;

% Set GPU.
gpuIdx = 0;

% Set results output folder.
outputfolder = fullfile(FAIRpath, 'add-ons', 'TBIR', 'results', 'ex_5');
mkdir(outputfolder);

% Name of dataset.
name = 'mice3D';

% Load images and resize to power of two.
D = load('mice3D', 'dataT', 'dataR');
image1 = double(imresize3(D.dataT, [32, 32, 32], 'Method', 'linear', 'Antialiasing', false));
image2 = double(imresize3(D.dataR, [32, 32, 32], 'Method', 'linear', 'Antialiasing', false));

% Save size of template.
m = size(image1);

% Set bumber of Runge-Kutta steps.
N = 5;

% Define data term.
dist = 'SSD_op';

% Define regularization term.
reg = 'mfCurvatureST';

% Define image model.
imageModel = 'splineInterMex';

% Define objective.
objfun = 'LDDMMobjFctn';

% Define temporal discretization of the velocity (number of time steps is
% then nt + 1.
nt = 1;

% Define noise level.
sigma = 0.05;

% Set regularization parameters.
alpha = [5, 5];

% Set Hessian shift.
hessianShift = 1e-2;

% Set domain size.
omega = [0, 1, 0, 1, 0, 1];

% Set domain for velocities by padding.
pad = 0.5;
omegaV = omega;
omegaV(1:2:end) = omegaV(1:2:end) - pad;
omegaV(2:2:end) = omega(2:2:end) + pad;

% Initialize models.
imgModel('reset', 'imgModel', imageModel);
trafo('reset', 'trafo', 'affine2D');
distance('reset', 'distance', dist);
viewImage('reset', 'viewImage', 'imgmontage', 'direction', '-zyx', 'colormap', gray(256));
NPIRpara = optPara('NPIR-GN');
NPIRpara.maxIter = 50;
NPIRpara.scheme = @GaussNewtonLDDMM;

% Create multilevel versions of template.
[ML, minLevel, maxLevel, ~] = getMultilevel(image1, omega, m, 'fig', 0);

% Set directions for Radon transform.
theta = linspace(0, 179, 10);

% Set up operators for all levels.
for k=minLevel:maxLevel
    [ML{k}.K, ML{k}.Kadj, ML{k}.cleanup, ML{k}.ndet] = createRadon3d(ML{k}.m, theta, gpuIdx);
end

% Run algorithm for each setting.
mV = @(m) ceil(1*m);

% Check if measurements exists, otherwise create.
sinogramfile = fullfile(outputfolder, 'Sinograms', sprintf('%s_sino_%g.mat', name, sigma));
if(exist(sinogramfile, 'file'))
    S = load(sinogramfile);
    ML{maxLevel}.R = S.R;
else
    % Apply operator on finest level to generate synthetic measurements.
    R = ML{maxLevel}.K(image2);
    ML{maxLevel}.R = R;

    % Add noise to measurements.
    ML{maxLevel}.R = addnoise(ML{maxLevel}.R, sigma);

    % Save measurements.
    mkdir(fullfile(outputfolder, 'Sinograms'));
    save(sinogramfile, 'R', 'theta', 'm');
end

% Save template, unknown image, and measurements to results folder.
imwrite(flatten3d(image1 / 255, 6), fullfile(outputfolder, sprintf('%s_source.png', name)));
imwrite(flatten3d(image2 / 255, 6), fullfile(outputfolder, sprintf('%s_target.png', name)));
Rperm = permute(ML{maxLevel}.R, [1, 3, 2]);
imwrite(flatten3d(Rperm / max(Rperm(:)), 6), fullfile(outputfolder, sprintf('%s_sino_%.2f.png', name, sigma)));

% Create multilevel versions of measurements.
ML = multilevelRadon3d(ML, maxLevel, minLevel);

% Run indirect registration.
regularizer('reset', 'regularizer', reg, 'nt', nt,...
    'alpha', alpha, 'HessianShift', hessianShift);
[vc, ~, ~, his] = MLLDDMM(ML, 'operator', true, 'minLevel',...
    minLevel, 'maxLevel', maxLevel, 'omegaV', omegaV, 'mV', mV,...
    'N', N, 'parametric', false, 'NPIRpara', NPIRpara,...
    'NPIRobj', str2func(objfun), 'plots', plot);

% Transform template and reshape.
yc = getTrafoFromInstationaryVelocityRK4(vc, getNodalGrid(omega,m),...
    'omega', omegaV, 'm', m, 'nt', nt, 'tspan', [1, 0], 'N', N);
rec = linearInterMex(ML{maxLevel}.T, omega, center(yc, m));
rec = reshape(rec, m);

% Output stats.
fprintf('Elapsed time is: %.2f seconds, SSIM=%.3f.\n', his.time, ssim(rec, image2));

% Save result.
[resfile, paramfile] = saveresults(name, outputfolder, flatten3d(image1, 6),...
    flatten3d(image2, 6), flatten3d(ML{maxLevel}.R, 6), flatten3d(rec, 6), dist,...
    reg, objfun, imageModel, N, nt, alpha, theta, sigma, his.time, true);

%% Cleanup and show results.

% Free resources.
for k=minLevel:maxLevel
    ML{k}.cleanup();
end
close all;

% Plot result.
if(plot)
    figure;
    colormap gray;
    subplot(2, 2, 1);
    imagesc(flatten3d(image1, 6));
    axis image;
    title('Template image');
    subplot(2, 2, 2);
    imagesc(flatten3d(image2, 6));
    axis image;
    title('Unknown image');
    subplot(2, 2, 3);
    imagesc(flatten3d(ML{maxLevel}.K(image2)));
    axis square;
    title('Measurements');
    ylabel('Directions');
    subplot(2, 2, 4);
    imagesc(flatten3d(rec, 6));
    axis image;
    title('SSD, transport equation');
end
