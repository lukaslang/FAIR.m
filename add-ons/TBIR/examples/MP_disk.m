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
% This script runs an example based on 2D Radon transform using ASTRA.
clear;
close all;
clc;

% Create images of same mass.
image1 = 255 * double(createdisk([128, 128], [60, 60], 12));
%image1 = imgaussfilt(image1, 0.5, 'FilterSize', 5);
mass = sum(image1(:));
image2 = double(createdisk([128, 128], [40, 40], 24));
%image2 = imgaussfilt(image2, 0.5, 'FilterSize', 5);
image2 = mass * image2 / sum(image2(:));

% Save size of template.
m = size(image1);

% Set bumber of Runge-Kutta steps.
N = 5;

% Define data term.
dist = 'SSD_op';

% Define regularization term ('mfCurvatureST', 'mfDiffusionST', 'mfDiffusionCC').
reg = 'mfCurvatureST';

% Define image model ('linearInterMex', 'splineInterMex').
imageModel = 'splineInterMex';

% Define temporal discretization of the velocity (number of time steps is
% then nt + 1.
nt = 1;

% Define noise level.
sigma = 0.05;

% Set regularization parameters (in order: space, time, L2-norm squared).
% The following parameters can be given as array
alpha = [1e-1, 1e-1, 0];

% Set Hessian shift.
hessianShift = 1e-2;

% Fixed paramters
pad = 0.5;

% Set domain size.
omega = [0, 1, 0, 1];

% Set domain for velocities by padding.
omegaV = omega;
omegaV(1:2:end) = omegaV(1:2:end)-pad;
omegaV(2:2:end) = omega(2:2:end)+pad;

% Initialize models.
imgModel('reset', 'imgModel', imageModel);
regularizer('reset', 'regularizer', reg, 'nt', nt, 'alpha', alpha, 'HessianShift', hessianShift);
trafo('reset', 'trafo', 'affine2D');
distance('reset', 'distance', dist);
viewImage('reset', 'viewImage', 'viewImage2D', 'colormap', gray(256));
NPIRpara = optPara('NPIR-GN');
NPIRpara.maxIter = 30;
NPIRpara.scheme = @GaussNewtonLDDMM;

% Create multilevel versions of template.
[ML, minLevel, maxLevel, ~] = getMultilevel(image1, omega, m, 'fig', 0);

% Set directions for Radon transform.
% theta = 0:10:179;
theta = [0, 30, 50, 60, 90];

% Set up operators for all levels.
for k=minLevel:maxLevel
    [ML{k}.K, ML{k}.Kadj, ML{k}.cleanup, ML{k}.ndet] = createRadon2d(size(ML{k}.T), theta);
end

% Apply operator on finest level to generate synthetic measurements.
xc = getCellCenteredGrid(ML{maxLevel}.omega, ML{maxLevel}.m);
[~, R] = imgModel('coefficients', ML{maxLevel}.T, image2, omega);
R = imgModel(R, omega, center(xc, m));
ML{maxLevel}.R = ML{maxLevel}.K(R);

% Add noise to measurements.
ML{maxLevel}.R = addnoise(ML{maxLevel}.R, sigma);

% Create multilevel versions of measurements.
ML = multilevelRadon2d(ML, maxLevel, minLevel);

% Run algorithm
mV = @(m) ceil(1*m);
[vc, ~, wc, his] = MLLDDMM(ML, 'operator', true, 'minLevel', minLevel, 'maxLevel', maxLevel, 'omegaV', omegaV, 'mV', mV, 'N', N, 'parametric', false, 'NPIRpara', NPIRpara, 'NPIRobj', @MPLDDMMobjFctn, 'plots', 1);

% Transform template and reshape.
yInv = getTrafoFromInstationaryVelocityRK4(vc,getNodalGrid(omega,m),'omega',omegaV,'m',m,'nt',nt,'tspan',[1,0],'N',N);
Jac = geometry(yInv, m, 'Jac', 'omega', omega);
Topt = linearInterMex(ML{maxLevel}.T,omega,center(yInv,m));
Topt = reshape(Topt .* Jac, m);

% yc = getTrafoFromInstationaryVelocityRK4(vc,xc,'omega',omegaV,'m',m,'nt',nt,'tspan',[0,1],'N',N);
% Int = getPICMatrixAnalyticIntegral(omega,m,m,yc,'doDerivative',false);
% Topt = reshape(Int*image1(:), m);

% Output stats.
fprintf('Elapsed time is: %.2f seconds, SSIM=%.3f.\n', his.time, ssim(Topt, image2));

% Free resources.
for k=minLevel:maxLevel
    ML{k}.cleanup();
end
close all;

% Plot result.
figure;
colormap gray;
subplot(2, 3, 1);
imagesc(image1);
axis image;
caxis([0, 255]);
title('Template');
subplot(2, 3, 2);
imagesc(image2);
axis image;
caxis([0, 255]);
title('Unknown');
subplot(2, 3, 3);
imagesc(ML{maxLevel}.R);
axis square;
title('Measurements');
ylabel('Directions');
subplot(2, 3, 4);
imagesc(Topt);
axis image;
caxis([0, 255]);
title('Deformed template');
subplot(2, 3, 5);
imagesc(abs(Topt - image2));
axis image;
title('Error in image');
subplot(2, 3, 6);
imagesc(abs(ML{maxLevel}.K(Topt) - ML{maxLevel}.R));
axis square;
title('Error in measurements');
ylabel('Directions');