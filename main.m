function [X_c, Y_c, U, V, UF, VF, DUDX, DUDY, DVDX, DVDY, VORTICITY, SWIRL] = main(A, INPUTS, cross_parameter)
% LAST UPDATE IN: 19/05/2020
% By: Hadar Ben-Gida

% Update 1.6
% 1. The origin of the (X,Y) coordinate system of the PIV images is set at 
%   the bottom left corner of the image, where the x-axis points right and
%   the y-axis points upwards.
% 2. The WAKE GUI is now reading .mat files that were generated by spatialbox,
%   from .vec files of either INSIGHT or OPENPIV. This is done according to
%   the value of the dy variable. dy>0 relates to OPENPIV .mat file. dy<0
%   relates to INSIGHT .mat file.
% 3. OPENPIV saves PIV images with the y-axis originated at the upper left
%   corner and pointing downwards. As a result, the v velocity component is 
%   flipped in sign. To solve this, when a .mat is loaded from OPENPIV, we
%   flipped the y-axis, and change the sign of the v velocity component and
%   the partial derivatives dv/dx and du/dx.
% 4. dy is taken positive throughout the wake and forces analyses, yet if
%   the lsgradient function is used, dy value has to be negative. This is
%   because the definition of our y-axis (positive upwards). 
% 5. A minus sign SHOULD NOT BE before the integral of Xi, as it appeared
%   in Panda and Zaman (1994, JFM). This is due to the fact that in our wake
%   analysis we deinfe positive vorticity as counter-clockwise motion. In
%   Theoderson (1935) unsteady lift theory positive vorticity is deinfed as
%   clockwise rotation, since this motion exists on the upper surface of
%   airfoils when these generate lift.

% Update 1.3
% 1. Overlapping between two consequtive images now takes place at the mid
%   region of each PIV image, and not in the edge as was before. 
%   One can now choose between thw two options: either performing the
%   cross-correlation at the middle region or at the left edge of the PIV
%   image.
% 2. The vorticity in the wake can now be computed before or after the
%   cross-correlation takes place. One just needs to comment 2 coe lines to
%   calculate vorticity in the wake prior to the cross-correlation. It is
%   noteworthy that no changes in the wake were found if the vorticity is being
%   calculated prior or after the cross-correlation.

% Update 1.2
%    Whenever the cross-correlation is failed the advection velocity is used
%   for the shiftX. The command prompt in MATLAB let the user know when
%   that's happen.

% Update 1.1
%   main.m can now work with velocity maps that have a flipped y direction.




%% INPUTS
% A - .mat file consist with all the flow data
% INPUTS - Vector containing all the different paramters for the program 
% INPUTS = [laser_dt, p_cm, dt, chord, wingspan, body_l, body_w, weight,...
%    Uinf, density, viscosity, horizontal_cut, vertical_cut,...
%    ni, nf];
% cross_parameter - 'Velocity_fluctuations' or 'Velocity' - cross-correlation is
% performed based on that flow quantity
%%

%% OUTPUTS
% X_c - Normalized horizontal distance of the final wake [array]
% Y_c - Normalized vertical distance of the final wake [array]
% U - u velocity map of the final wake [array]
% V - v velocity map of the final wake [array]
% UF - u' velocity map of the final wake [array]
% VF - v' velocity map of the final wake [array]
% DUDX - du/dx velocity map of the final wake [array]
% DUDY - du/dy velocity map of the final wake [array]
% DVDX - dv/dx velocity map of the final wake [array]
% DVDY - dv/dy velocity map of the final wake [array]
% VORTICITY_NORM - normalized vorticity map of the final wake [array]
%%




%% METER TO PIXEL PARAMETERS 
p_cm = INPUTS(2); %[pixel/cm]
m_p = (1/p_cm)/100; %[m/pixel]
%%



%% WING PARAMETERS
c = INPUTS(4); % Bird's characteristic chord [m]
b = INPUTS(5); % Bird's wingspan [m] (includes the body width)
W = INPUTS(8); % Bird's weight [kg]
g = 9.81; % Gravitational acceleration [m/sec2]
bl = INPUTS(6); % Bird's body length [m]
bw = INPUTS(7); % Bird's body width [m]
%%



%% FLOW PARAMETERS
rho = INPUTS(10); % Air Density [kg/m3] at 14.8oC
Mu = INPUTS(11); %[Pa*sec] Air Viscosity
D_Mu = Mu/rho; % Dynamic Viscosity [m^2/sec]
U_inf = INPUTS(9); % Free Stream Velocity [m/sec]
Re = (U_inf*rho*c)/(Mu);
disp('                                              ');
disp(['Re =                                   ' num2str(Re)]);
disp('                                              ');
%%



%% GETTING THE FLOW QUANTITIES AND RE-DEFINE THE VELOVITY MAP SIZE
dt_laser = INPUTS(1); % [sec] Time difference between consecutive PIV images
dt = INPUTS(3); % [sec] Time difference between consecutive velocity maps
h_cut = INPUTS(12); % number of vectors we slice from the vertical edges of the PIV image
v_cut = INPUTS(13); % number of vectors we slice from the horizontal edges of the PIV image


A.x = A.x(1+v_cut:end-v_cut, 1+h_cut:end-h_cut);
x = (A.x - A.x(1,1)).*m_p;  % x Coordinate [m]

A.y = A.y(1+v_cut:end-v_cut, 1+h_cut:end-h_cut);

dx = A.dx*m_p; %dx=16pixels * (meter/pixel)
dy = A.dy*m_p; %dy=16pixels * (meter/pixel)

% THE (X,Y) ORIGIN IS SET THE LEFT BOTTOM CORNER OF THE IMAGE, WHERE X-AXIS
% IS DIRECTED TO THE RIGHT AND THE Y-AXIS IS DIRECTED UPWARDS
if dy < 0 % insight images (x,y) origin is at the left bottom corner of the image
    dy = dy*(-1);
elseif dy > 0 % openpiv images (x,y) origin is at the left upper corner of the image
    A.y = flip(A.y,1); % flipping the y axis to be origned at the left bootom corner of the image and directed upwards
    A.v = -A.v; % Flipping the v-component velocity to fit the new y-axis origin
    A.dvdx = -A.dvdx; % Flipping the dv/dx to fit the new y-axis origin
    A.dudy = -A.dudy; % Flipping the du/dy to fit the new y-axis origin
end
y = (A.y - A.y(end,1)).*m_p;  % y Coordinate [m]
y = y - (y(1)*0.5); % Placing the origin at the center of the Y-axis

% CALCULATING DERIVATIVES
[~, ~, nTime] = size(A.u);
for i=1:nTime
    [A.dudx(:,:,i), A.dudy(:,:,i)] = lsgradient(A.u(:,:,i), A.dx, -abs(A.dy)); % dy must be negative in lsgradient
    [A.dvdx(:,:,i), A.dvdy(:,:,i)] = lsgradient(A.v(:,:,i), A.dx, -abs(A.dy)); % dy must be negative in lsgradient
end
%%



%% Computing the Fluctuating velocity maps based on the spatial average
% Uncomment in order to use the uf & vf computed from the Spatial ToolBox
% [~,~,nTime] = size(A.uf);
% for i = 1:nTime
%     Uavg = mean(mean(A.u(:,:,i))); % getting the average streamwise velocity
%     Vavg = mean(mean(A.v(:,:,i))); % getting the average vertical velocity
%     A.uf(:,:,i) = A.u(:,:,i) - Uavg; % Computing the fluctuating streamwise velocity
%     A.vf(:,:,i) = A.v(:,:,i) - Vavg; % Computing the fluctuating vertical velocity
% end
Uavg = mean(A.u,3); % getting the average streamwise velocity
Vavg = mean(A.v,3); % getting the average vertical velocity
A.uf = A.u - Uavg; % Computing the fluctuating streamwise velocity
A.vf = A.v - Vavg; % Computing the fluctuating vertical velocity
%%


% Getting the different flow parameters (u, v, u', v', du/dx, du/dy,...)
A.u = A.u(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
u = A.u.*(m_p/dt_laser);
    
A.v = A.v(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
v = A.v.*(m_p/dt_laser);

A.uf = A.uf(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
uf = A.uf*(m_p/dt_laser);
    
A.vf = A.vf(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
vf = A.vf*(m_p/dt_laser);
    
A.dudx = A.dudx(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
dudx = A.dudx.*(1/dt_laser);
    
A.dvdx = A.dvdx(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
dvdx = A.dvdx.*(1/dt_laser);
    
A.dudy = A.dudy(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
dudy = A.dudy.*(1/dt_laser);
    
A.dvdy = A.dvdy(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
dvdy = A.dvdy.*(1/dt_laser);

vorticity = (dvdx - dudy);

[nRows, nColumns, ~] = size(uf); % Getting the NEW velocity map size
%% 






%% PERFORMING THE CROSS-CORRELATION 
X = 0; % initialize X - the x direction of the final wake image
Y = 0; % initialize Y - the y direction of the final wake image
U = 0; % initialize U - the u velocity map of the final wake image
V = 0; % initialize V - the v velocity map of the final wake image
UF = 0; % initialize UF - the u' velocity map of the final wake image
VF = 0; % initialize VF - the v' velocity map of the final wake image
DVDX = 0; % initialize DVDX - the dv/dx map of the final wake image
DUDY = 0; % initialize DUDY - the du/dy map of the final wake image
DUDX = 0; % initialize DUDX - the du/dx map of the final wake image
DVDY = 0; % initialize DVDY - the dv/dy map of the final wake image

ni = INPUTS(14); % Initial velocity map in the sequence
nf = INPUTS(15); % Final velocity map image in the sequence

dn = nf - ni; % Define the number of images used to reconstruct the wake
SHIFT_X = zeros(1,dn); % initialize SHIFT_X - for later usage
SHIFT_Y = zeros(1,dn); % initialize SHIFT_Y - for later usage

x_advec = U_inf*dt; % [m] Advection of the flow 
x_advec_pixel = x_advec/m_p; % [pixels] Advection of the flow 
x_advec_cell = round(x_advec_pixel/A.dx); % Advection of the flow in cells

min_shiftX = 1; % Define the minimum of shiftX 
max_shiftX = x_advec_cell*2; % Define the maximum of shiftX - We allow the second image to move only to the right of the first image. The maximum is defined so we will have an overllaping of 1 column at the maximum shiftX
min_shiftY = -round(0.6*x_advec_cell); % Define the minimum of shiftY
max_shiftY = round(0.6*x_advec_cell); % Define the maximum of shiftY - We allow the shiftY to be up and down and it's bounded by half of the image size


disp('Processing...');
% The loop starts from the last velocity map to the first
for n=1:dn

n1 = nf-n+1; % Number of the 1st velocity map for the correlation
n2 = nf-n; % Number of the 2nd velocity map for the correlation
disp(['Image No.', num2str(n1)]);

switch cross_parameter
    case 'Velocity_fluctuations'
        uf1 = uf(:,:,n1); % u' velocity field of the 1st image for the cross-correlation 
        vf1 = vf(:,:,n1); % v' velocity field of the 1st image for the cross-correlation 
        uf2 = uf(:,:,n2); % u' velocity field of the 2nd image for the cross-correlation 
        vf2 = vf(:,:,n2); % v' velocity field of the 2nd image for the cross-correlation 
    case 'Velocity'
        uf1 = u(:,:,n1); % u' velocity field of the 1st image for the cross-correlation 
        vf1 = v(:,:,n1); % v' velocity field of the 1st image for the cross-correlation 
        uf2 = u(:,:,n2); % u' velocity field of the 2nd image for the cross-correlation 
        vf2 = v(:,:,n2); % v' velocity field of the 2nd image for the cross-correlation 
end;

% The cross-correlation algorithm
[px, py, Cu, Cv, Cuv, Cu_peak, Cv_peak, Cuv_peak, shiftX_optCu,...
    shiftY_optCu, shiftX_optCv, shiftY_optCv, shiftX_optCuv,...
    shiftY_optCuv] = crosscorrelation(nRows, min_shiftX, max_shiftX, min_shiftY, max_shiftY, uf1, vf1, uf2, vf2);

% In case the cross-correlation failed - we use the advection velocity 
if shiftX_optCuv == 1
    shiftX_optCuv = x_advec_cell;
    shiftY_optCuv = 0;
    disp('Cross-correlation FAILED! Calculated X Shift is not physical, probabely due to no wake data in the PIV images. Therefore, advection velocity is assumed for the shift...');
end;
%%



%% CALCULATING THE OVERLAPPING EDGE FOR TWO CONSEQUTIVE IMAGES
overlap_left_loc_left = 1;  % left side of the image
overlap_left_loc_center = round((nColumns - (2*h_cut))/2);  % center of the image; 

overlap_left_bound = overlap_left_loc_center; % choose the overlap location for the WAKE images

overlap_right_bound = overlap_left_bound + shiftX_optCuv - 1; % The rightest side of the overlapping window

if overlap_right_bound > (nColumns - (2*h_cut))
    disp('OVERLAP ERROR! The shift calculated by the cross-correlation is higher than the required overlap location by the user!');
end;
%%



%% INTERPOLLATION AT THE OVERLAPPING COLUMN
if shiftY_optCuv > 0
    for i=2:nRows-1-shiftY_optCuv 
        x1 = x(i+1, shiftX_optCuv-1);
        x2 = x(i+1, shiftX_optCuv) + dx;
        x3 = x(i, shiftX_optCuv);
        y1 = y(i+1, shiftX_optCuv-1);
        y2 = y(i-1, shiftX_optCuv-1);
        y3 = y(i, shiftX_optCuv);
        u(i, overlap_right_bound, n1) = bilinear_interp(u(i+1, overlap_right_bound-1, n1),...
            u(i-1, overlap_right_bound-1, n1), u(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            u(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        v(i, overlap_right_bound, n1) = bilinear_interp(v(i+1, overlap_right_bound-1, n1),...
            v(i-1, overlap_right_bound-1, n1), v(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            v(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        uf(i, overlap_right_bound, n1) = bilinear_interp(uf(i+1, overlap_right_bound-1, n1),...
            uf(i-1, overlap_right_bound-1, n1), uf(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            uf(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        vf(i, overlap_right_bound, n1) = bilinear_interp(vf(i+1, overlap_right_bound-1, n1),...
            vf(i-1, overlap_right_bound-1, n1), vf(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            vf(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        vorticity(i, overlap_right_bound, n1) = bilinear_interp(vorticity(i+1, overlap_right_bound-1, n1),...
            vorticity(i-1, overlap_right_bound-1, n1), vorticity(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            vorticity(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        dvdx(i, overlap_right_bound, n1) = bilinear_interp(dvdx(i+1, overlap_right_bound-1, n1),...
            dvdx(i-1, overlap_right_bound-1, n1), dvdx(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            dvdx(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        dudy(i, overlap_right_bound, n1) = bilinear_interp(dudy(i+1, overlap_right_bound-1, n1),...
            dudy(i-1, overlap_right_bound-1, n1), dudy(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            dudy(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        dudx(i, overlap_right_bound, n1) = bilinear_interp(dudx(i+1, overlap_right_bound-1, n1),...
            dudx(i-1, overlap_right_bound-1, n1), dudx(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            dudx(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        dvdy(i, overlap_right_bound, n1) = bilinear_interp(dvdy(i+1, overlap_right_bound-1, n1),...
            dvdy(i-1, overlap_right_bound-1, n1), dvdy(i+1+shiftY_optCuv, overlap_left_bound+1, n2),...
            dvdy(i-1+shiftY_optCuv, overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
    end;
else 
    for i=2+abs(shiftY_optCuv):nRows-1 
        x1 = x(i+1, shiftX_optCuv-1);
        x2 = x(i+1, shiftX_optCuv) + dx;
        x3 = x(i, shiftX_optCuv);
        y1 = y(i+1, shiftX_optCuv-1);
        y2 = y(i-1, shiftX_optCuv-1);
        y3 = y(i, shiftX_optCuv);
        u(i, overlap_right_bound, n1) = bilinear_interp(u(i+1, overlap_right_bound-1, n1),...
            u(i-1, overlap_right_bound-1, n1), u(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            u(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        v(i, overlap_right_bound, n1) = bilinear_interp(v(i+1, overlap_right_bound-1, n1),...
            v(i-1, overlap_right_bound-1, n1), v(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            v(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        uf(i, overlap_right_bound, n1) = bilinear_interp(uf(i+1, overlap_right_bound-1, n1),...
            uf(i-1, overlap_right_bound-1, n1), uf(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            uf(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        vf(i, overlap_right_bound, n1) = bilinear_interp(vf(i+1, overlap_right_bound-1, n1),...
            vf(i-1, overlap_right_bound-1, n1), vf(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            vf(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        vorticity(i, overlap_right_bound, n1) = bilinear_interp(vorticity(i+1, overlap_right_bound-1, n1),...
            vorticity(i-1, overlap_right_bound-1, n1), vorticity(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            vorticity(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        dvdx(i, overlap_right_bound, n1) = bilinear_interp(dvdx(i+1, overlap_right_bound-1, n1),...
            dvdx(i-1, overlap_right_bound-1, n1), dvdx(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            dvdx(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        dudy(i, overlap_right_bound, n1) = bilinear_interp(dudy(i+1, overlap_right_bound-1, n1),...
            dudy(i-1, overlap_right_bound-1, n1), dudy(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            dudy(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        dudx(i, overlap_right_bound, n1) = bilinear_interp(dudx(i+1, overlap_right_bound-1, n1),...
            dudx(i-1, overlap_right_bound-1, n1), dudx(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            dudx(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
        dvdy(i, overlap_right_bound, n1) = bilinear_interp(dvdy(i+1, overlap_right_bound-1, n1),...
            dvdy(i-1, overlap_right_bound-1, n1), dvdy(i+1-abs(shiftY_optCuv), overlap_left_bound+1, n2),...
            dvdy(i-1-abs(shiftY_optCuv), overlap_left_bound+1, n2), x1, x2, y1, y2, x3, y3);
    end;
end;



%% CALCULATING X,Y AXES & u, v, du/dx, du/dy, dv/dx and dv/dy OF THE FINAL WAKE IMAGE

if shiftY_optCuv > 0
    x_wake = x(:,1:shiftX_optCuv);
    y_wake = y(:,1:shiftX_optCuv) + shiftY_optCuv.*dy;
    u_wake = u(:,overlap_left_bound:overlap_right_bound,n1);
    v_wake = v(:,overlap_left_bound:overlap_right_bound,n1);
    uf_wake = uf(:,overlap_left_bound:overlap_right_bound,n1);
    vf_wake = vf(:,overlap_left_bound:overlap_right_bound,n1);
    vorticity_wake = vorticity(:,overlap_left_bound:overlap_right_bound,n1);
    dvdx_wake = dvdx(:,overlap_left_bound:overlap_right_bound,n1);
    dudy_wake = dudy(:,overlap_left_bound:overlap_right_bound,n1);
    dudx_wake = dudx(:,overlap_left_bound:overlap_right_bound,n1);
    dvdy_wake = dvdy(:,overlap_left_bound:overlap_right_bound,n1);
else
    x_wake = x(:,1:shiftX_optCuv);
    y_wake = y(:,1:shiftX_optCuv) - shiftY_optCuv.*dy;
    u_wake = u(:,overlap_left_bound:overlap_right_bound,n1);
    v_wake = v(:,overlap_left_bound:overlap_right_bound,n1);
    uf_wake = uf(:,overlap_left_bound:overlap_right_bound,n1);
    vf_wake = vf(:,overlap_left_bound:overlap_right_bound,n1);
    vorticity_wake = vorticity(:,overlap_left_bound:overlap_right_bound,n1);
    dvdx_wake = dvdx(:,overlap_left_bound:overlap_right_bound,n1);
    dudy_wake = dudy(:,overlap_left_bound:overlap_right_bound,n1);
    dudx_wake = dudx(:,overlap_left_bound:overlap_right_bound,n1);
    dvdy_wake = dvdy(:,overlap_left_bound:overlap_right_bound,n1);
end;

if X==0
    X = x_wake;
    Y = y_wake;
    U = u_wake;
    V = v_wake;
    UF = uf_wake;
    VF = vf_wake;
    VORTICITY = vorticity_wake;
    DVDX = dvdx_wake;
    DUDY = dudy_wake;
    DUDX = dudx_wake;
    DVDY = dvdy_wake;
else
    X = cat(2, X, x_wake(:,2:end)+X(1,end));
    Y = cat(2, Y, y_wake(:,2:end));
    U = cat(2, U, u_wake(:,2:end));
    V = cat(2, V, v_wake(:,2:end));
    UF = cat(2, UF, uf_wake(:,2:end));
    VF = cat(2, VF, vf_wake(:,2:end));
    VORTICITY = cat(2, VORTICITY, vorticity_wake(:,2:end));
    DVDX = cat(2, DVDX, dvdx_wake(:,2:end));
    DUDY = cat(2, DUDY, dudy_wake(:,2:end));
    DUDX = cat(2, DUDX, dudx_wake(:,2:end));
    DVDY = cat(2, DVDY, dvdy_wake(:,2:end));
end;


%% CALCULATING THE FINAL SHIFT OF THE n-VELOCTY MAP IN X & Y
SHIFT_X(n) = shiftX_optCuv; % Getting the different x shifts along the wake
SHIFT_Y(n) = shiftY_optCuv; % Getting the different y shifts along the wake


%% NORMALIZING THE X,Y AXES OF THE WAKE
X_c = X./c; % Getting a normalized x direction
Y_c = Y./c; % Getting a normalized y direction
end;
%%


% %% VORTICITY CALCULATION 
% % Comment to compute VORTICITY prior to the cross-correlation perocess
clear VORTICITY;
VORTICITY = (DVDX - DUDY); %[1/sec]
%%

%% SWIRL CALCULATION
SWIRL = imag( sqrt( 0.25.*((DUDX + DVDY).^2) + (DUDY.*DVDX) - (DUDX.*DVDY) )); % [1/sec^2]2
%%
disp('Done!');




