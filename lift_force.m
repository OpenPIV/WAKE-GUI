function [x_c, time, CIRC_NORM, Cl_circ] = lift_force(A, INPUTS, U, DUDX, DUDY, VORTICITY, VORTICITY_w_thresh, vort_thresh, MASK, FLAG)
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


%% INPUTS
% A - .mat file consist with all the flow data
% INPUTS - Vector containing all the different paramters for the program 
% INPUTS = [laser_dt, p_cm, dt, chord, wingspan, body_l, body_w, weight,...
%    Uinf, density, viscosity, horizontal_cut, vertical_cut,...
%    cycle_ni, cycle_nf];
% U - Streamwise velocity array of the final wake
% DUDX - du/dx array of the final wake
% DUDY - du/dy array of the final wake
% VORTICITY - Vorticity array of the final wake (no threshold)
% VORTICITY_w_thresh - Vorticity array of the final wake (with threshold)
% vort_thresh - corticity threshold
% MASK - masking options for the representation of vorticity in the wake
% FLAG - flag for determing the method of calculating the unsteady lift
%%

%% OUTPUTS
% x_c - Non-dimensional streamwise distacne along the wake
% time - Physical time of the wingbeats cycles [vector]
% CIRC_NORM - Estimation quantity of the vertical momentum (~lift) =>
%        normalized circulation (Gamma) with the chord (c) and the free stream velocity (Uinf) [vector]
% Cl_circ - The circulatory lift coefficient [vector]
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
Uinf = INPUTS(9); % Free Stream Velocity [m/sec]
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

% THE (X,Y) ORIGIN IS SET THE LEFT BOTTOM CORNER OF THE IMAGE
if dy < 0 % insight images (x,y) origin is at the left bottom corner of the image
    dy = dy*(-1);
elseif dy > 0 % openpiv images (x,y) origin is at the left upper corner of the image
    A.y = flip(A.y,1); % flipping the y axis to be at the left bootom corner of the image
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


%% Computing the Fluctuating velocity maps based on the spatial average
% Uncomment in order to use the uf & vf computed from the Spatial ToolBox
% [~, ~, nTime] = size(A.u);
% for i = 1:nTime
%     Uavg = mean(mean(A.u(:,:,i))); % getting the average streamwise velocity
%     Vavg = mean(mean(A.v(:,:,i))); % getting the average vertical velocity
%     A.uf(:,:,i) = A.u(:,:,i) - Uavg; % Computating the fluctuating streamwise velocity
%     A.vf(:,:,i) = A.v(:,:,i) - Vavg; % Computating the fluctuating vertical velocity
% end
Uavg = mean(A.u,3); % getting the average streamwise velocity
Vavg = mean(A.v,3); % getting the average vertical velocity
A.uf = A.u - Uavg; % Computing the fluctuating streamwise velocity
A.vf = A.v - Vavg; % Computing the fluctuating vertical velocity
%%



%% Computing the 2nd order derivatives
[nRows_wake, nColumns_wake] = size(DUDX);
D2UDX2 = zeros(nRows_wake, nColumns_wake);
D2UDY2 = zeros(nRows_wake, nColumns_wake);
tmp = 1;
[D2UDX2, ~] = lsgradient(DUDX, dx, -abs(dy));
[~, D2UDY2] = lsgradient(DUDY, dx, -abs(dy));

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

[nRows, nColumns,~] = size(uf); % Getting the NEW velocity map size
%% 



%% WINGBEAT TIME DATA
ni = INPUTS(14); % Wingbeat start at this image
nf = INPUTS(15); % Wingbeat ends at this image
nTime = nf - ni + 1; % Number of images for the wingbeat
%%



%% ESTIMATION OF THE VERTICAL MOMENTUM
switch FLAG
    case 1 % Calculation based on Panda & Zaman 1994 (JFM) with Vorticity array of the final wake (not threshold)
        [~, nColumns_wake] = size(VORTICITY);
        u_Vort = U.*VORTICITY; % calculating the u*omega_z array
        Diffusion_term = (Mu/rho).*(D2UDX2 + D2UDY2);
        xi1 = sum(u_Vort,1).*dy; % Calculating the xi1 vector - summation of all the rows in each column of the wake
        xi2 = sum(Diffusion_term,1).*dy; % Calculating the xi2 vector - summation of all the rows in each column of the wake
        xi1 = fliplr(xi1); % Flip the order of the xi1 vector to account for the fact that the earliest wake is on the right
        xi2 = fliplr(xi2); % Flip the order of the xi1 vector to account for the fact that the earliest wake is on the right
        dt_wake = dx/Uinf; % Estimating the dt between two consecutive colmuns in the wake array   
        circ = cumtrapz(xi1).*dt_wake + cumtrapz(xi2).*dt_wake; % Circulation [m^2/sec] - Panda & Zaman 1994 (JFM) -> A MINUS SIGN DOES NOT EXIST BEFORE xi INTEGRAL DUE TO OUR DEFINITION OF POSITIVE VORTICITY AS COUNTER-CLOCKWISE
        CIRC_NORM = (1/(Uinf*c)).*circ; % Normalized Circulation
        Cl_circ = (2.*circ)./(c*Uinf); % Circulatory 2D lift coefficient, which accounts for the unsteady phenomenon - Cl = 2G/(U*c)
        time = 0:dx./U:(nColumns_wake*dx-dx)./U; % physical time in [sec]
        % Calculating the x/c vector
        x_c = 0:dx:(nColumns_wake*dx-dx); % Actually only the final value is zero - corresponding to the last image (larger in #) taken
        x_c = x_c./c;
        x_c = fliplr(x_c); % To account for the fact that the earliest wake is the rightest

    case 2 % Calculation based on Panda & Zaman 1994 (JFM) with Vorticity array of the final wake (with threshold)
        [~, nColumns_wake] = size(VORTICITY_w_thresh);
        u_Vort = U.*VORTICITY_w_thresh; % calculating the u*omega_z array
        Diffusion_term = (Mu/rho).*(D2UDX2 + D2UDY2);
        xi1 = sum(u_Vort,1).*dy; % Calculating the xi1 vector - summation of all the rows in each column of the wake
        xi2 = sum(Diffusion_term,1).*dy; % Calculating the xi2 vector - summation of all the rows in each column of the wake
        xi1 = fliplr(xi1); % Flip the order of the xi1 vector to account for the fact that the earliest wake is on the right
        xi2 = fliplr(xi2); % Flip the order of the xi1 vector to account for the fact that the earliest wake is on the right
        dt_wake = dx/Uinf; % Estimating the dt between two consecutive colmuns in the wake array   
        circ = cumtrapz(xi1).*dt_wake + cumtrapz(xi2).*dt_wake; % Circulation [m^2/sec] - Panda & Zaman 1994 (JFM) -> A MINUS SIGN DOES NOT EXIST BEFORE xi INTEGRAL DUE TO OUR DEFINITION OF POSITIVE VORTICITY AS COUNTER-CLOCKWISE
        CIRC_NORM = (1/(Uinf*c)).*circ; % Normalized Circulation 
        Cl_circ = (2.*circ)./(c*Uinf); % Circulatory 2D lift coefficient, which accounts for the unsteady phenomenon - Cl = 2G/(U*c)
        time = 0:dx./U:(nColumns_wake*dx-dx)./U; % physical time in [sec]
        % Calculating the x/c vector
        x_c = 0:dx:(nColumns_wake*dx-dx); % Actually only the final value is zero - corresponding to the last image (larger in #) taken
        x_c = x_c./c;
        x_c = fliplr(x_c); % To account for the fact that the earliest wake is the rightest
        
    case 3 % Calculation based on Panda & Zaman 1994 (JFM) with Vorticity array of each PIV image 
        d2udx2 = zeros(nRows, nColumns, nTime);
        d2udy2 = zeros(nRows, nColumns, nTime);
        for i = 1:nTime
            n = ni + i - 1; % image no.
            time(i) = (i-1)*dt; % physical time in [sec]
            VORTICITY_trsh(:,:,i) = vorticity_threshold(vorticity(:,:,n), 0, 'Vorticity', vort_thresh, MASK); % Thresholding on the vorticity
            U_avg(:,i) = mean(u(:,:,n), 2); % getting the average streamwise velocity for each row in the PIV map
            V_avg(i) = mean(mean(v(:,:,n), 2));
            VORTICITY_trsh_avg(:,i) = mean(VORTICITY_trsh(:,:,i), 2); % getting the average vorticity for each row in the PIV map
            u_Vort_avg = U_avg(:,i).*VORTICITY_trsh_avg(:,i); % calculating the <u>*<omega_z> array
            % Computing the 2nd order derivatives
            [d2udx2(:,:,i), ~] = lsgradient(dudx(:,:,n), dx, -abs(dy));
            [~, d2udy2(:,:,i)] = lsgradient(dudy(:,:,n), dx, -abs(dy));
            Diffusion_term = (Mu/rho).*(d2udx2(:,:,i) + d2udy2(:,:,i));
            Diffusion_term_avg = mean(Diffusion_term, 2);
            xi1(i) = sum(u_Vort_avg, 1).*dy; % Calculating the xi1 vector - summation of all the rows in each column of the wake
            xi2(i) = sum(Diffusion_term_avg, 1).*dy; % Calculating the xi2 vector - summation of all the rows in each column of the wake
        end
        circ = cumtrapz(xi1).*dt + cumtrapz(xi2).*dt; % Circulation calculation [m^2/sec] - Panda & Zaman 1994 (JFM) -> A MINUS SIGN DOES NOT EXIST BEFORE xi INTEGRAL DUE TO OUR DEFINITION OF POSITIVE VORTICITY AS COUNTER-CLOCKWISE
        CIRC_NORM = circ./(c*Uinf); % Normalized Circulation  
        Cl_circ = (2.*circ)./(c*Uinf); % Circulatory 2D lift coefficient, which accounts for the unsteady phenomenon - Cl = 2G/(U*c)
        % Calculating the x/c vector
        delta_x = dt*Uinf; % delta x in [m] between two consequtive PIV images
        x_c = 0:delta_x:(delta_x*(nTime-1));
        x_c = x_c./c;
        x_c = fliplr(x_c);

    case 4 % Calculation based on circulation summation
        VORTICITY_trsh = zeros(nRows, nColumns, nTime);
        CIRC_NORM = zeros(1,nTime);
        CIRC_NORM(1) = 0;
        Cl_circ = zeros(1,nTime);
        Cl_circ(1) = 0;
        circ = zeros(1,nTime);
        circ(1) = 0;
        time(1) = 0;
        for i = 2:1:nTime
            n = ni + i - 1; % image no.
            time(i) = (i-1)*dt; % physical time in [sec]
            VORTICITY_trsh(:,:,i) = vorticity_threshold(vorticity(:,:,n), 0, 'Vorticity', vort_thresh, MASK); % Thresholding on the vorticity

            circ(i) = circ(i-1) + sum(sum(VORTICITY_trsh(:,:,i)))*dx*dy;
            CIRC_NORM(i) = (1/(Uinf*c))*circ(i);
            Cl_circ(i) = (2.*circ(i))./(c*Uinf); % Circulatory 2D lift coefficient, which accounts for the unsteady phenomenon - Cl = 2G/(U*c)
        end
        % Calculating the x/c vector
        delta_x = dt*Uinf; % delta x in [m] between two consequtive PIV images
        x_c = 0:delta_x:(delta_x*(nTime-1));
        x_c = x_c./c;
        x_c = fliplr(x_c); % To account for the fact that the earliest wake is the rightest
end


%%