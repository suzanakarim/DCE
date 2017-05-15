function Results = LCMXL(INPUT,Results_old,EstimOpt,OptimOpt)


% save tmp_LCMXL
% return

global B_backup

tic

Results.bhat = [];
Results.R = [];
Results.R_out = {};
Results.stats = [];


%% Check data and inputs


if nargin < 3 % check no. of inputs
    error('Too few input arguments for LCMXL(INPUT,EstimOpt,OptimOpt)')
end

if isfield(EstimOpt,'NClass') == 0
    EstimOpt.NClass = 2;
end

disp(' ');
disp('__________________________________________________________________________________________________________________');
disp(' ');

warning off MATLAB:mir_warning_maybe_uninitialized_temporary

format shortG;
format compact;

if any(INPUT.W ~= 1)
    cprintf('Black','Estimating '); cprintf('*Black','weighted '); cprintf('Black','LCMXL model with '); cprintf('Black',num2str(EstimOpt.NClass)); cprintf('Black','  classes ...\n');
else
    disp(num2str(EstimOpt.NClass,'Estimating LCMXL model with %1.0f classes ...'))
end

if isfield(EstimOpt,'FullCov') == 0
    EstimOpt.FullCov = 0;
end
if isfield(EstimOpt, 'WTP_space') == 0
    EstimOpt.WTP_space = 0;
    EstimOpt.WTP_matrix = [];
elseif EstimOpt.WTP_space == 0
    EstimOpt.WTP_matrix = [];
end

if EstimOpt.FullCov == 0
    disp('with non-correlated random parameters ...')
    if EstimOpt.WTP_space > 0
        disp('in WTP-space.')
    else
        disp('in preference-space.')
    end
else
    disp('with correlated random parameters ...')
    if EstimOpt.WTP_space > 0
        disp('in WTP-space.')
    else
        disp('in preference-space.')
    end
end

if isfield(EstimOpt,'Dist') == 0 || isempty(EstimOpt.Dist)
    EstimOpt.Dist = zeros(1,EstimOpt.NClass*EstimOpt.NVarA);
    if EstimOpt.WTP_space == 0
        cprintf(rgb('DarkOrange'), 'WARNING: distributions for random parameters not specified - assuming normality \n')
    else
        cprintf(rgb('DarkOrange'), 'WARNING: distributions for random parameters not specified - assuming normality (monetary parameters assumed log-normal) \n')
        EstimOpt.Dist = reshape(EstimOpt.Dist,[EstimOpt.NVarA,EstimOpt.NClass]);
        EstimOpt.Dist(end-EstimOpt.WTP_space+1:end,:) = 1; % cost in WTP-space models log-normally distributed
        EstimOpt.Dist = reshape(EstimOpt.Dist, 1, EstimOpt.NVarA*EstimOpt.NClass);
    end
elseif numel(EstimOpt.Dist) == 1
    EstimOpt.Dist = EstimOpt.Dist*ones(1,EstimOpt.NClass*EstimOpt.NVarA);
elseif length(EstimOpt.Dist) == EstimOpt.NVarA
    EstimOpt.Dist = repmat(EstimOpt.Dist(:)',[1,EstimOpt.NClass]);
elseif length(EstimOpt.Dist) ~= EstimOpt.NClass*EstimOpt.NVarA
    EstimOpt.Dist = zeros(1,EstimOpt.NClass*EstimOpt.NVarA);
    if EstimOpt.WTP_space == 0
        cprintf(rgb('DarkOrange'), 'WARNING: incorrect number of distributions for random pararameters specified - overriding user setting and assuming normality \n')
    else
        cprintf(rgb('DarkOrange'), 'WARNING: incorrect number of distributions for random pararameters specified - overriding user setting and assuming normality (monetary parameters assumed log-normal) \n')
        EstimOpt.Dist = reshape(EstimOpt.Dist,[EstimOpt.NVarA,EstimOpt.NClass]);
        EstimOpt.Dist(end-EstimOpt.WTP_space+1:end,:) = 1; % cost in WTP-space models log-normally distributed
        EstimOpt.Dist = reshape(EstimOpt.Dist,[1,EstimOpt.NVarA*EstimOpt.NClass]);
    end
else
    EstimOpt.Dist = EstimOpt.Dist(:)';
end
disp(['Random parameters distributions: ',num2str(EstimOpt.Dist),' (-1 - constant, 0 - normal, 1 - lognormal, 2 - spike, 5 - Weibull)'])

if EstimOpt.WTP_space > 0 && sum(EstimOpt.Dist(end-EstimOpt.WTP_space+1:end)==1) > 0 && any(mean(INPUT.Xa(:,end-EstimOpt.WTP_space+1:end)) >= 0)
    cprintf(rgb('DarkOrange'), 'WARNING: Cost attributes with log-normally distributed parameters should enter utility function with a ''-'' sign \n')
end

if isfield(INPUT, 'Xc') == 0 || numel(INPUT.Xc) == 0
    INPUT.Xc = ones(size(INPUT.Y,1),1);
else
    INPUT.Xc = [ones(size(INPUT.Y,1),1),INPUT.Xc];
end

if det(INPUT.Xc'*INPUT.Xc) == 0
    error('Xc matrix cointains collinear variables')
end

EstimOpt.NVarC = size(INPUT.Xc,2); % no. of variables explaining class probabilities

if isfield(INPUT,'Xs') == 0 || numel(INPUT.Xs) == 0
    INPUT.Xs = zeros(size(INPUT.Y,1),0);
end    
EstimOpt.NVarS = size(INPUT.Xs,2); % no. of variables explaining class probabilities  

if isfield(EstimOpt,'Scores') == 0
    EstimOpt.Scores = 0;
end

if EstimOpt.WTP_space > 0
    if isfield(EstimOpt,'WTP_matrix') == 0
        WTP_att = (EstimOpt.NVarA-EstimOpt.WTP_space)/EstimOpt.WTP_space;
        if rem(WTP_att,1) ~= 0
            error('EstimOpt.WTP_matrix associating attributes with cost parameters not provided')
        else
            if EstimOpt.WTP_space > 1
                disp(['EstimOpt.WTP_matrix associating attributes with cost parameters not provided - assuming equal shares for each of the ',num2str(EstimOpt.WTP_space),' monetary attributes'])
            end
            EstimOpt.WTP_matrix = EstimOpt.NVarA - EstimOpt.WTP_space + kron(1:EstimOpt.WTP_space,ones(1,WTP_att));
            %         tic; EstimOpt.WTP_matrix = 1:EstimOpt.WTP_space;...
            %         EstimOpt.WTP_matrix = EstimOpt.WTP_matrix(floor((0:size(EstimOpt.WTP_matrix,2)*WTP_att-1)/WTP_att)+1); toc
        end
    elseif size(EstimOpt.WTP_matrix,2) ~= EstimOpt.NVarA - EstimOpt.WTP_space
        error('Dimensions of EstimOpt.WTP_matrix not correct - for each non-monetary attribute provide no. of attribute to multiply it with')
    else
        EstimOpt.WTP_matrix = EstimOpt.WTP_matrix(:)';
    end
end

if isfield(EstimOpt,'NamesA') == 0 || isempty(EstimOpt.NamesA) || length(EstimOpt.NamesA) ~= EstimOpt.NVarA
    EstimOpt.NamesA = (1:EstimOpt.NVarA)';
    EstimOpt.NamesA = cellstr(num2str(EstimOpt.NamesA));
elseif size(EstimOpt.NamesA,1) ~= EstimOpt.NVarA
    EstimOpt.NamesA = EstimOpt.NamesA';
end
if EstimOpt.NVarC > 1
    if isfield(EstimOpt,'NamesC') == 0 || isempty(EstimOpt.NamesC)|| length(EstimOpt.NamesC) ~= (EstimOpt.NVarC-1)
        EstimOpt.NamesC = (1:EstimOpt.NVarC-1)';
        EstimOpt.NamesC = cellstr(num2str(EstimOpt.NamesC));
    elseif size(EstimOpt.NamesC,1) ~= EstimOpt.NVarC - 1
        EstimOpt.NamesC = EstimOpt.NamesC';
    end
    EstimOpt.NamesC = [{'Cons'};EstimOpt.NamesC];
else
    EstimOpt.NamesC = {'Cons'};
end
if EstimOpt.NVarS > 0
    if isfield(EstimOpt,'NamesS') == 0 || isempty(EstimOpt.NamesS) || length(EstimOpt.NamesS) ~= EstimOpt.NVarS
        EstimOpt.NamesS = (1:EstimOpt.NVarS)';
        EstimOpt.NamesS = cellstr(num2str(EstimOpt.NamesS));
    elseif size(EstimOpt.NamesS,1) ~= EstimOpt.NVarS
        EstimOpt.NamesS = EstimOpt.NamesS';
    end
end

%% Starting values


EstimOpt.jitter1 = 0.8; % Jittering parameter (relative) for MNL or MXL starting values (attributes)
EstimOpt.jitter2 = 0.3; % Jittering parameter (absolute) for class probabilities starting values

if EstimOpt.FullCov == 0
    if exist('B_backup','var') && ~isempty(B_backup) && size(B_backup,1) == (2*EstimOpt.NVarA+EstimOpt.NVarS)*EstimOpt.NClass + EstimOpt.NVarC*(EstimOpt.NClass-1)
        b0 = B_backup(:);
        disp('Using the starting values from Backup')
    elseif isfield(Results_old,'LCMXL_d') && isfield(Results_old.LCMXL_d,'b0') % starting values provided
        Results_old.LCMXL_d.b0_old = Results_old.LCMXL_d.b0(:);
        Results_old.LCMXL_d = rmfield(Results_old.LCMXL_d,'b0');
        if length(Results_old.LCMXL_d.b0_old) ~= (2*EstimOpt.NVarA+EstimOpt.NVarS)*EstimOpt.NClass + EstimOpt.NVarC*(EstimOpt.NClass-1)
            cprintf(rgb('DarkOrange'), 'WARNING: Incorrect no. of starting values or model specification \n')
            Results_old.LCMXL_d = rmfield(Results_old.LCMXL_d,'b0_old');
        else
            b0 = Results_old.LCMXL_d.b0_old(:);
        end
    end
    if  ~exist('b0','var')
        if isfield(Results_old,'LC') && isfield(Results_old.LC,'bhat')
            disp('Using LC coefficients for starting values')
            Results_old.LC.bhat = Results_old.LC.bhat(:);
            tmp = Results_old.LC.bhat(1:EstimOpt.NVarA*EstimOpt.NClass);
            if EstimOpt.WTP_space > 0
                tmp = reshape(tmp, [EstimOpt.NVarA, EstimOpt.NClass]);
                tmp(end - EstimOpt.WTP_space+1:end,:) = log(abs(tmp(end - EstimOpt.WTP_space+1:end,:)));
                tmp = reshape(tmp,[EstimOpt.NVarA*EstimOpt.NClass,1]);
            end
            b0 = [tmp;0.3*ones(EstimOpt.NVarA*EstimOpt.NClass,1);Results_old.LC.bhat(EstimOpt.NClass*EstimOpt.NVarA+1:end) ];
        elseif isfield(Results_old,'MXL_d') && isfield(Results_old.MXL_d,'bhat')
            disp('Using MXL_d coefficients for starting values')
            Results_old.MXL_d.bhat = Results_old.MXL_d.bhat(:);
            b0 = [Results_old.MXL_d.bhat(repmat(reshape(1:2*EstimOpt.NVarA,EstimOpt.NVarA,2),EstimOpt.NClass,1),:) .* ...
                (EstimOpt.jitter1 .* unifrnd(0,ones(2*EstimOpt.NVarA.*EstimOpt.NClass,1))) ; zeros(EstimOpt.NVarS*EstimOpt.NClass,1);
                EstimOpt.jitter2 + unifrnd(-1,ones(EstimOpt.NVarC.*(EstimOpt.NClass-1),1))];
        elseif isfield(Results_old,'MNL') && isfield(Results_old.MNL,'bhat')
            disp('Using MNL results as starting values')
            Results_old.MNL.bhat = Results_old.MNL.bhat(:);
            if EstimOpt.WTP_space > 0
                Results_old.MNL.bhat(end - EstimOpt.WTP_space+1:end) = log(Results_old.MNL.bhat((end - EstimOpt.WTP_space+1:end)));
            end
            b0 = [Results_old.MNL.bhat((1:EstimOpt.NVarA)'*ones(1,EstimOpt.NClass),:) .* ...
                (EstimOpt.jitter1 .* unifrnd(0,ones(EstimOpt.NVarA.*EstimOpt.NClass,1))) ; zeros(EstimOpt.NVarS*EstimOpt.NClass,1); ...
                0.3*ones(EstimOpt.NVarA*EstimOpt.NClass,1); EstimOpt.jitter2 + unifrnd(-1,ones(EstimOpt.NVarC.*(EstimOpt.NClass-1),1))];
        else
            error('No starting values available - run MNL, LC or MXL_d first')
        end
    end
    
else % EstimOpt.FullCov == 1
    if exist('B_backup','var') && ~isempty(B_backup) && size(B_backup,1) == EstimOpt.NClass*(EstimOpt.NVarA + sum(1:EstimOpt.NVarA)+EstimOpt.NVarS) +EstimOpt.NVarC*(EstimOpt.NClass-1)
        b0 = B_backup(:);
        disp('Using the starting values from Backup')
    elseif isfield(Results_old,'LCMXL') && isfield(Results_old.LCMXL,'b0') % starting values provided
        Results_old.LCMXL.b0_old = Results_old.LCMXL.b0(:);
        Results_old.LCMXL = rmfield(Results_old.LCMXL,'b0');
        if length(Results_old.LCMXL.b0_old) ~= EstimOpt.NClass*(EstimOpt.NVarA + sum(1:EstimOpt.NVarA)+EstimOpt.NVarS) +EstimOpt.NVarC*(EstimOpt.NClass-1)
            cprintf(rgb('DarkOrange'), 'WARNING: Incorrect no. of starting values or model specification \n')
            Results_old.LCMXL = rmfield(Results_old.LCMXL,'b0_old');
        else
            b0 = Results_old.LCMXL.b0_old(:);
        end
    end
    if  ~exist('b0','var')
        if isfield(Results_old,'LCMXL_d') && isfield(Results_old.LCMXL_d,'bhat')
            disp('Using LCMXL_d coefficients for starting values')
            Results_old.LCMXL_d.bhat = Results_old.LCMXL_d.bhat(:);
            b0 = zeros(2*(EstimOpt.NVarA + sum(1:EstimOpt.NVarA))+EstimOpt.NVarC*(EstimOpt.NClass-1),1);
            b0(1:EstimOpt.NVarA*EstimOpt.NClass) = Results_old.LCMXL_d.bhat(1:EstimOpt.NVarA*EstimOpt.NClass);
            b0(EstimOpt.NClass*(EstimOpt.NVarA + sum(1:EstimOpt.NVarA))+1:end) = Results_old.LCMXL_d.bhat(2*EstimOpt.NVarA*EstimOpt.NClass+1:end);
            for i = 1:EstimOpt.NClass
                vc_tmp = diag(Results_old.LCMXL_d.bhat(EstimOpt.NVarA*EstimOpt.NClass+1+(i-1)*EstimOpt.NVarA:EstimOpt.NVarA*EstimOpt.NClass+i*EstimOpt.NVarA));
                b0(EstimOpt.NVarA*EstimOpt.NClass+1+(i-1)*sum(1:EstimOpt.NVarA):EstimOpt.NVarA*EstimOpt.NClass+i*sum(1:EstimOpt.NVarA)) = vc_tmp(tril(ones(size(vc_tmp)))==1);
            end
        elseif isfield(Results_old,'LC') && isfield(Results_old.LC,'bhat')
            disp('Using LC coefficients for starting values')
            Results_old.LC.bhat = Results_old.LC.bhat(:);
            b0 = [Results_old.LC.bhat(1:EstimOpt.NVarA*EstimOpt.NClass);zeros(sum(1:EstimOpt.NVarA)*EstimOpt.NClass,1);Results_old.LC.bhat(EstimOpt.NClass*EstimOpt.NVarA+1:end)];
        elseif isfield(Results_old,'MXL') && isfield(Results_old.MXL,'bhat')
            disp('Using MXL coefficients for starting values')
            Results_old.MXL.bhat = Results_old.MXL.bhat(:);
            b0_tmp = [Results_old.MXL.bhat(repmat((1:EstimOpt.NVarA)',EstimOpt.NClass,1)) ;Results_old.MXL.bhat(repmat(((EstimOpt.NVarA+1):(EstimOpt.NVarA+sum(1:EstimOpt.NVarA)))',EstimOpt.NClass,1))];
            b0 = [b0_tmp.* ...
                (EstimOpt.jitter1 .* unifrnd(0,ones((EstimOpt.NVarA+sum(1:EstimOpt.NVarA))*EstimOpt.NClass,1))) ; zeros(EstimOpt.NVarS*EstimOpt.NClass,1); ...
                EstimOpt.jitter2 + unifrnd(-1,ones(EstimOpt.NVarC.*(EstimOpt.NClass-1),1))];
        elseif isfield(Results_old,'MNL') && isfield(Results_old.MNL,'bhat')
            disp('Using MNL results as starting values')
            Results_old.MNL.bhat = Results_old.MNL.bhat(:);
            b0 = [Results_old.MNL.bhat((1:size(Results_old.MNL.bhat,1))'*ones(1,EstimOpt.NClass),:) .* ...
                (EstimOpt.jitter1 .* unifrnd(0,ones(EstimOpt.NVarA.*EstimOpt.NClass,1))) ; zeros(EstimOpt.NVarS*EstimOpt.NClass,1); ...
                zeros(sum(1:EstimOpt.NVarA)*EstimOpt.NClass,1); EstimOpt.jitter2 + unifrnd(-1,ones(EstimOpt.NVarC.*(EstimOpt.NClass-1),1))];
        else
            error('No starting values available - run MNL, LC or MXL first')
        end
    end
end


%% Optimization Options

if isfield(EstimOpt,'BActive')
    EstimOpt.BActive = EstimOpt.BActive(:)';
end

if sum(EstimOpt.Dist == -1) > 0
    if isfield(EstimOpt,'BActive') == 0 || isempty(EstimOpt.BActive)
        EstimOpt.BActive = ones(1,length(b0));
    end
    if EstimOpt.FullCov == 0
        EstimOpt.BActive(EstimOpt.NVarA*EstimOpt.NClass+find(EstimOpt.Dist == -1)) = 0;
    elseif EstimOpt.FullCov == 1
        for i = 1:EstimOpt.NClass
            Vt = tril(ones(EstimOpt.NVarA));
            Vt(EstimOpt.Dist((i-1)*EstimOpt.NVarA+1:i*EstimOpt.NVarA)==-1,:) = 0;
            %             EstimOpt.BActive(EstimOpt.NVarA*EstimOpt.NClass +(i-1)*sum(1:EstimOpt.NVarA)+ 1:EstimOpt.NVarA*EstimOpt.NClass +i*sum(1:EstimOpt.NVarA)) = EstimOpt.BActive(EstimOpt.NVarA*EstimOpt.NClass +(i-1)*sum(1:EstimOpt.NVarA)+ 1:EstimOpt.NVarA*EstimOpt.NClass +i*sum(1:EstimOpt.NVarA)) .* Vt(find(tril(ones(size(Vt)))))';
            EstimOpt.BActive(EstimOpt.NVarA*EstimOpt.NClass +(i-1)*sum(1:EstimOpt.NVarA)+ 1:EstimOpt.NVarA*EstimOpt.NClass +i*sum(1:EstimOpt.NVarA)) = EstimOpt.BActive(EstimOpt.NVarA*EstimOpt.NClass +(i-1)*sum(1:EstimOpt.NVarA)+ 1:EstimOpt.NVarA*EstimOpt.NClass +i*sum(1:EstimOpt.NVarA)) .* Vt(tril(ones(size(Vt)))~=0)';
        end
    end
end

if EstimOpt.ConstVarActive == 1
    if ~isfield(EstimOpt,'BActive') || isempty(EstimOpt.BActive) || sum(EstimOpt.BActive == 0) == 0
        error ('Are there any constraints on model parameters (EstimOpt.ConstVarActive)? Constraints not provided (EstimOpt.BActive).')
    elseif length(b0) ~= length(EstimOpt.BActive)
        error('Check no. of constraints')
    end
    disp(['Initial values: ' mat2str(b0',2)])
    disp(['Parameters with zeros are constrained to their initial values: ' mat2str(EstimOpt.BActive')])
else
    if ~isfield(EstimOpt,'BActive') || isempty(EstimOpt.BActive) || sum(EstimOpt.BActive == 0) == 0
        EstimOpt.BActive = ones(1,length(b0));
        disp(['Initial values: ' mat2str(b0',2)])
    else
        if length(b0) ~= length(EstimOpt.BActive)
            error('Check no. of constraints')
        else
            disp(['Initial values: ' mat2str(b0',2)])
            disp(['Parameters with zeros are constrained to their initial values: ' mat2str(EstimOpt.BActive')])
        end
    end
end

if ~isfield(EstimOpt,'BActiveClass') || isempty(EstimOpt.BActiveClass) || sum(EstimOpt.BActiveClass == 0) == 0
    EstimOpt.BActiveClass = ones(EstimOpt.NVarA,1);
end


%% Generate pseudo-random Draws


if isfield(EstimOpt,'Seed1') == 1
    rng(EstimOpt.Seed1);
end
cprintf('Simulation with ');
cprintf('*blue',[num2str(EstimOpt.NRep) ' ']);

if EstimOpt.Draws == 1
    cprintf('*blue','Pseudo-random '); cprintf('Draws \n');
    err_mtx = randn(EstimOpt.NP*EstimOpt.NRep, EstimOpt.NClass*EstimOpt.NVarA); %to be cut down later
elseif EstimOpt.Draws == 2 % LHS
    cprintf('*blue','Latin Hypercube Sampling '); cprintf('Draws \n');
    err_mtx=lhsnorm(zeros((EstimOpt.NClass*EstimOpt.NVarA)*EstimOpt.NP,1),diag(ones((EstimOpt.NClass*EstimOpt.NVarA)*EstimOpt.NP,1)),EstimOpt.NRep);
    err_mtx = reshape(err_mtx, EstimOpt.NRep*EstimOpt.NP, EstimOpt.NVarA+1);
elseif EstimOpt.Draws >= 3 % Quasi random Draws
    if EstimOpt.Draws == 3
        cprintf('*blue','Halton '); cprintf('Draws (skip = '); cprintf(num2str(EstimOpt.HaltonSkip)); cprintf('; leap = '); cprintf(num2str(EstimOpt.HaltonLeap)); cprintf(') \n')
        hm1 = haltonset(EstimOpt.NClass*EstimOpt.NVarA,'Skip',EstimOpt.HaltonSkip,'Leap',EstimOpt.HaltonLeap); %
    elseif EstimOpt.Draws == 4 % apply reverse-radix scrambling
        cprintf('*blue','Halton '); cprintf('Draws with reverse radix scrambling (skip = '); cprintf(num2str(EstimOpt.HaltonSkip)); cprintf('; leap = '); cprintf(num2str(EstimOpt.HaltonLeap)); cprintf(') \n')
        hm1 = haltonset(EstimOpt.NClass*EstimOpt.NVarA,'Skip',EstimOpt.HaltonSkip,'Leap',EstimOpt.HaltonLeap); %
        hm1 = scramble(hm1,'RR2');
    elseif EstimOpt.Draws == 5
        cprintf('*blue','Sobol '); cprintf('Draws (skip = '); cprintf(num2str(EstimOpt.HaltonSkip)); cprintf('; leap = '); cprintf(num2str(EstimOpt.HaltonLeap)); cprintf(') \n')
        hm1 = sobolset(EstimOpt.NClass*EstimOpt.NVarA,'Skip',EstimOpt.HaltonSkip,'Leap',EstimOpt.HaltonLeap);
    elseif EstimOpt.Draws == 6
        cprintf('*blue','Sobol '); cprintf('Draws with random linear scramble and random digital shift (skip = '); cprintf(num2str(EstimOpt.HaltonSkip)); cprintf('; leap = '); cprintf(num2str(EstimOpt.HaltonLeap)); cprintf(') \n')
        hm1 = sobolset(EstimOpt.NClass*EstimOpt.NVarA,'Skip',EstimOpt.HaltonSkip,'Leap',EstimOpt.HaltonLeap);
        hm1 = scramble(hm1,'MatousekAffineOwen');
    end
    
    err_mtx = net(hm1,EstimOpt.NP*EstimOpt.NRep); % this takes every point:
    clear hm1;
    
    if EstimOpt.NP*EstimOpt.NRep < 3e+7
        err_mtx(:,EstimOpt.Dist < 3) = icdf('Normal',err_mtx(:,EstimOpt.Dist < 2),0,1); %to be cut down later
        
    else % this is for very large number of Draws * variables
        for i=1:EstimOpt.NClass*EstimOpt.NVarA
            if EstimOpt.Dist(i) < 3
                err_mtx(:,i) = icdf('Normal',err_mtx(:,i),0,1); %to be cut down later
            else
                % err_mtx(:,i) = -log(1-err_mtx(:,i)); %to be cut down later
                error('weibull does not work in LCMXL')
            end
        end
    end
    err_mtx(:,EstimOpt.Dist == -1) = 0;
end


%% Display Options


if ((isfield(EstimOpt, 'ConstVarActive') == 1 && EstimOpt.ConstVarActive == 1) || sum(EstimOpt.BActive == 0) > 0) && ~isequal(OptimOpt.GradObj,'on')
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient on - otherwise parameters'' constraints will be ignored - switch to constrained optimization instead (EstimOpt.ConstVarActive = 1) \n')
    OptimOpt.GradObj = 'on';
end

% if any(EstimOpt.MissingNCT(:) == 1) && EstimOpt.NumGrad == 0
%    EstimOpt.NumGrad = 1;
%    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - missing choice tasks not supported by analytical gradient \n')
% end

if any(EstimOpt.MissingAlt(:) == 1) && EstimOpt.NumGrad == 0
    EstimOpt.NumGrad = 1;
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - missing alternatives not supported by analytical gradient \n')
end

% if any(EstimOpt.BActiveClass == 1) && EstimOpt.NumGrad == 0
%    EstimOpt.NumGrad = 1;
%    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - parameters constrained between classes not supported by analytical gradient \n')
% end
if any(EstimOpt.Dist > 1) && EstimOpt.NumGrad == 0
    EstimOpt.NumGrad = 1;
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - analytical gradient available for normally or lognormally distributed parameters only \n')
end

if EstimOpt.WTP_space > 1 && EstimOpt.NumGrad == 0
    EstimOpt.NumGrad = 1;
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - WTP_space > 1 not supported by analytical gradient \n')
end

cond = sum(reshape(EstimOpt.Dist', EstimOpt.NVarA, EstimOpt.NClass),2);
cond = sum((cond >0).*(cond < EstimOpt.NClass));
if cond > 0 && EstimOpt.NumGrad == 0
    EstimOpt.NumGrad = 1;
    disp('Setting user-supplied gradient to numerical - particular random parameter combinations not supported by analytical gradient \n')
end

if (isfield(EstimOpt, 'ConstVarActive') == 0 || EstimOpt.ConstVarActive == 0) && isequal(OptimOpt.Algorithm,'quasi-newton') && isequal(OptimOpt.Hessian,'user-supplied')
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied Hessian off - quasi-newton algorithm does not use it anyway \n')
    OptimOpt.Hessian = 'off';
end

if EstimOpt.RobustStd == 1 && (EstimOpt.HessEstFix == 1 || EstimOpt.HessEstFix == 2)
    EstimOpt.RobustStd = 0;
    cprintf(rgb('DarkOrange'), 'WARNING: Setting off robust standard errors, they do not matter for BHHH aproximation of hessian \n')
end

cprintf('Opmization algorithm: '); cprintf('*Black',[OptimOpt.Algorithm '\n'])

if strcmp(OptimOpt.GradObj,'on')
    if EstimOpt.NumGrad == 0
        cprintf('Gradient: '); cprintf('*Black','user-supplied, analytical \n')
    else
        cprintf('Gradient: '); cprintf('*Black',['user-supplied, numerical, ' OptimOpt.FinDiffType '\n'])
    end
else
    cprintf('Gradient: '); cprintf('*Black',['built-in, ' OptimOpt.FinDiffType '\n'])
end

if isequal(OptimOpt.Algorithm,'quasi-newton')
    cprintf('Hessian: '); cprintf('*Black','off, ')
    switch EstimOpt.HessEstFix
        case 0
            cprintf('*Black','retained from optimization \n')
        case 1
            cprintf('*Black','ex-post calculated using BHHH \n')
        case 2
            cprintf('*Black','ex-post calculated using high-precision BHHH \n')
        case 3
            cprintf('*Black','ex-post calculated numerically \n')
        case 4
            cprintf('*Black','ex-post calculated analytically \n')
    end
else
    if strcmp(OptimOpt.Hessian,'user-supplied')
        if EstimOpt.ApproxHess == 1
            cprintf('Hessian: '); cprintf('*Black','user-supplied, BHHH, ')
        else
            cprintf('Hessian: '); cprintf('*Black','user-supplied, analytical, ')
        end
    else
        cprintf('Hessian: '); cprintf('*Black',['built-in, ' OptimOpt.HessUpdate ', '])
    end
    switch EstimOpt.HessEstFix
        case 0
            cprintf('*Black','retained from optimization \n')
        case 1
            cprintf('*Black','ex-post calculated using BHHH \n')
        case 2
            cprintf('*Black','ex-post calculated using high-precision BHHH \n')
        case 3
            cprintf('*Black','ex-post calculated numerically \n')
        case 4
            cprintf('*Black','ex-post calculated analytically \n')
    end
end


%% Rescructure data


INPUT.XXc = INPUT.Xc(1:EstimOpt.NCT*EstimOpt.NAlt:end,:); % NP x NVarC

%INPUT.YY = reshape(INPUT.Y,EstimOpt.NAlt,EstimOpt.NCT,EstimOpt.NP);...
%INPUT.YY = INPUT.YY(:,:,:,ones(EstimOpt.NRep,1));
%INPUT.YY = permute(INPUT.YY, [1 2 4 3]); %NAlt x NCT x NRep  x NP

INPUT.YYY = reshape(INPUT.Y,EstimOpt.NAlt,EstimOpt.NCT,EstimOpt.NP);
idx = sum(reshape(INPUT.MissingInd,EstimOpt.NAlt,EstimOpt.NCT,EstimOpt.NP)) == EstimOpt.NAlt; ...
    INPUT.YYY(idx(ones(EstimOpt.NAlt,1),:,:) == 1) = NaN; % replace YYY in missing choice-tasks with NaN
INPUT.YY = reshape(INPUT.YYY,EstimOpt.NAlt*EstimOpt.NCT,EstimOpt.NP);

INPUT.Xa(INPUT.MissingInd == 1,:) = NaN;
INPUT.XXa  = reshape(INPUT.Xa, EstimOpt.NAlt*EstimOpt.NCT, EstimOpt.NP, EstimOpt.NVarA);
INPUT.XXa = permute(INPUT.XXa, [1 3 2]); % NAlt*NCT x NVarA  x NP

EstimOpt.Dist = reshape(EstimOpt.Dist, EstimOpt.NVarA, EstimOpt.NClass);

err_sliced = err_mtx'; % NVarA*class x NRep * NP
if isfield(EstimOpt, 'Drawskeep') && ~isempty(EstimOpt.Drawskeep) && EstimOpt.Drawskeep == 1
    Results.err = err_sliced;
end

EstimOpt.indx1 = [];
EstimOpt.indx2 = [];
if EstimOpt.NumGrad == 0 && EstimOpt.FullCov == 1
    for i = 1:EstimOpt.NVarA
        EstimOpt.indx1 = [EstimOpt.indx1, i:EstimOpt.NVarA];
        EstimOpt.indx2 = [EstimOpt.indx2, i*ones(1,EstimOpt.NVarA+1-i)];
    end
    tmp1 = EstimOpt.indx1;
    tmp2 = EstimOpt.indx2;
    for j =1: (EstimOpt.NClass-1)
        tmp1 = tmp1+EstimOpt.NVarA;
        tmp2 = tmp2+EstimOpt.NVarA;
        EstimOpt.indx1 = [EstimOpt.indx1,tmp1];
        EstimOpt.indx2 = [EstimOpt.indx2,tmp2];
    end
end


%% Estimation


LLfun = @(B) LL_lcmxl_MATlike(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs, err_sliced,INPUT.W,EstimOpt,OptimOpt,B);
if EstimOpt.ConstVarActive == 0
    
    if EstimOpt.HessEstFix == 0
        [Results.bhat, LL, Results.exitf, Results.output, Results.g, Results.hess] = fminunc(LLfun, b0, OptimOpt);
    else
        [Results.bhat, LL, Results.exitf, Results.output, Results.g] = fminunc(LLfun, b0, OptimOpt);
    end
    
elseif EstimOpt.ConstVarActive == 1 % equality constraints
    
    EstimOpt.CONS1 = diag(1 - EstimOpt.BActive);
    EstimOpt.CONS1(sum(EstimOpt.CONS1,1)==0,:)=[];
    EstimOpt.CONS2 = zeros(size(EstimOpt.CONS1,1),1);
    %     EstimOpt.CONS1 = sparse(EstimOpt.CONS1);
    %     EstimOpt.CONS2 = sparse(EstimOpt.CONS2);
    if EstimOpt.HessEstFix == 0
        [Results.bhat, LL, Results.exitf, Results.output, Results.lambda, Results.g, Results.hess] = fmincon(LLfun,b0,[],[],EstimOpt.CONS1,EstimOpt.CONS2,[],[],[],OptimOpt);
    else
        [Results.bhat, LL, Results.exitf, Results.output, Results.lambda, Results.g] = fmincon(LLfun,b0,[],[],EstimOpt.CONS1,EstimOpt.CONS2,[],[],[],OptimOpt);
    end
    
end


%% Output


Results.LL = -LL;
Results.LLdetailed = LL_lcmxl(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,Results.bhat);
Results.LLdetailed = Results.LLdetailed.*INPUT.W;

if any(INPUT.MissingInd == 1) % In case of some missing data
    idx = sum(reshape(INPUT.MissingInd,EstimOpt.NAlt,EstimOpt.NCT*EstimOpt.NP)) == EstimOpt.NAlt; ...
        idx = sum(reshape(idx, EstimOpt.NCT, EstimOpt.NP),1)'; % no. of missing NCT for every respondent
    idx = EstimOpt.NCT - idx;
    R2 = mean(exp(-Results.LLdetailed./idx),1);
else
    R2 = mean(exp(-Results.LLdetailed/EstimOpt.NCT),1);
end

% save out_lcmxl

Results.LL = -LL;
if EstimOpt.Scores ~= 0
    [Results.PScores, Results.BScores] = BayesScoresLCMXL(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,Results.bhat);
end

if EstimOpt.HessEstFix == 1
    if isequal(OptimOpt.GradObj,'on') && EstimOpt.NumGrad == 0
        [~, Results.jacobian] = LL_lcmxl(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,Results.bhat);
    else
        f = LL_lcmxl(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,Results.bhat);
        Results.jacobian = numdiff(@(B) LL_lcmxl(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,B), f, Results.bhat,isequal(OptimOpt.FinDiffType, 'central'),EstimOpt.BActive);
    end
    Results.jacobian = INPUT.W(:,ones(size(Results.jacobian,2),1)).*Results.jacobian;
elseif EstimOpt.HessEstFix == 2
    Results.jacobian = jacobianest(@(B) LL_lcmxl(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,B),Results.bhat);
    Results.jacobian = INPUT.W(:,ones(size(Results.jacobian,2),1)).*Results.jacobian;
elseif EstimOpt.HessEstFix == 3
    Results.hess = hessian(@(B)  sum(INPUT.W.*LL_lcmxl(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,B),1), Results.bhat);
end
if EstimOpt.HessEstFix == 1 || EstimOpt.HessEstFix == 2
    Results.hess = Results.jacobian'*Results.jacobian;
end
EstimOpt.BLimit = (sum(Results.hess) == 0 & EstimOpt.BActive == 1);
EstimOpt.BActive(EstimOpt.BLimit == 1) = 0;
Results.hess = Results.hess(EstimOpt.BActive == 1,EstimOpt.BActive == 1);
Results.ihess = inv(Results.hess);
Results.ihess = direcXpnd(Results.ihess,EstimOpt.BActive);
Results.ihess = direcXpnd(Results.ihess',EstimOpt.BActive);
if EstimOpt.RobustStd == 1
    if EstimOpt.NumGrad == 0
        [~, Results.jacobian] = LL_lcmxl(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,Results.bhat);
        Results.jacobian = Results.jacobian.*INPUT.W(:, ones(1,size(Results.jacobian,2)));
    else
        Results.jacobian = numdiff(@(B) INPUT.W.*LL_lcmxl(INPUT.YY,INPUT.XXa,INPUT.XXc,INPUT.Xs,err_sliced,EstimOpt,B),Results.LLdetailed,Results.bhat,isequal(OptimOpt.FinDiffType, 'central'),EstimOpt.BActive);
    end
    RobustHess = Results.jacobian'*Results.jacobian;
    Results.ihess = Results.ihess*RobustHess*Results.ihess;
end

Results.std = sqrt(diag(Results.ihess));
Results.std(EstimOpt.BActive == 0) = NaN;
Results.std(EstimOpt.BLimit == 1) = 0;
Results.std(imag(Results.std) ~= 0) = NaN;

if EstimOpt.FullCov == 0
    std_out = Results.std(EstimOpt.NClass*EstimOpt.NVarA+1:EstimOpt.NClass*EstimOpt.NVarA+EstimOpt.NClass*EstimOpt.NVarA); 
    std_out(imag(Results.std(EstimOpt.NClass*EstimOpt.NVarA+1:EstimOpt.NClass*EstimOpt.NVarA+EstimOpt.NClass*EstimOpt.NVarA)) ~= 0) = NaN;
    for i = 1:EstimOpt.NClass
        Results.DetailsA(1:EstimOpt.NVarA,4*i-3) = Results.bhat((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA);
        Results.DetailsA(1:EstimOpt.NVarA,4*i-1:4*i) = [Results.std((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA),pv(Results.bhat((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA),Results.std((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA))];
    %Results.DetailsA = [Results.bhat(1:EstimOpt.NClass*EstimOpt.NVarA), Results.std(1:EstimOpt.NClass*EstimOpt.NVarA), pv(Results.bhat(1:EstimOpt.NClass*EstimOpt.NVarA), Results.std(1:EstimOpt.NClass*EstimOpt.NVarA))];
        l = EstimOpt.NClass*EstimOpt.NVarA;
%     Results.DetailsV = [Results.bhat(l+1:l+EstimOpt.NClass*EstimOpt.NVarA ).^2, 2*Results.std(l+1:l+EstimOpt.NClass*EstimOpt.NVarA).*abs(Results.bhat(l+1:l+EstimOpt.NClass*EstimOpt.NVarA )), pv(Results.bhat(l+1:l+EstimOpt.NClass*EstimOpt.NVarA), Results.std(l+1:l+EstimOpt.NClass*EstimOpt.NVarA))];
        Results.DetailsV(1:EstimOpt.NVarA,4*i-3) = abs(Results.bhat(l+(i-1)*EstimOpt.NVarA + 1:l+i*EstimOpt.NVarA));
        Results.DetailsV(1:EstimOpt.NVarA,4*i-1:4*i) = [std_out((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA), pv(abs(Results.bhat(l+(i-1)*EstimOpt.NVarA + 1:l+i*EstimOpt.NVarA)),std_out((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA))];
        l = 2*EstimOpt.NClass*EstimOpt.NVarA;
        if EstimOpt.NVarS > 0
            Results.DetailsS(:,4*i-3) = Results.bhat(l+(i-1)*EstimOpt.NVarS+1:l+i*EstimOpt.NVarS);
            Results.DetailsS(:,4*i-1:4*i) = [Results.std(l+(i-1)*EstimOpt.NVarS+1:l+i*EstimOpt.NVarS), pv(Results.bhat(l+(i-1)*EstimOpt.NVarS+1:l+i*EstimOpt.NVarS), Results.std(l+(i-1)*EstimOpt.NVarS+1:l+i*EstimOpt.NVarS))];
            l = l+EstimOpt.NClass*EstimOpt.NVarS;
        end
        if i ~= EstimOpt.NClass
            for j = 1:EstimOpt.NVarC
                Results.DetailsC(j,4*i-3) = Results.bhat(l+j+EstimOpt.NVarC*(i-1));
                Results.DetailsC(j,4*i-1:4*i) = [Results.std(l+j+EstimOpt.NVarC*(i-1)),pv(Results.bhat(l+j+EstimOpt.NVarC*(i-1)), Results.std(l+j+EstimOpt.NVarC*(i-1)))];
            end
        end
    end
    Results.DetailsC = [Results.DetailsC,zeros(EstimOpt.NVarC,1),NaN(EstimOpt.NVarC,3)];
else
    for i = 1:EstimOpt.NClass
        Results.DetailsA(1:EstimOpt.NVarA,4*i-3) = Results.bhat((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA);
        Results.DetailsA(1:EstimOpt.NVarA,4*i-1:4*i) = [Results.std((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA),pv(Results.bhat((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA),Results.std((i-1)*EstimOpt.NVarA + 1:i*EstimOpt.NVarA))];
    l = EstimOpt.NClass*EstimOpt.NVarA;
    Results.DetailsV(1:EstimOpt.NVarA,4*i-3:4*i-1) = sdtri(Results.bhat(l+1:l+sum(1:EstimOpt.NVarA)), Results.ihess(l+1:l+sum(1:EstimOpt.NVarA),l+1:l+sum(1:EstimOpt.NVarA)),EstimOpt);
    Results.DetailsV = [Results.DetailsV(:,1:4*i-3),zeros(EstimOpt.NVarA,1),Results.DetailsV(:,4*i-2:4*i-1)];

    %Results.DetailsV = [];
    %Results.DetailsV = [Results.DetailsV ; sdtri(Results.bhat(l+1:l+sum(1:EstimOpt.NVarA)), Results.ihess(l+1:l+sum(1:EstimOpt.NVarA),l+1:l+sum(1:EstimOpt.NVarA)),EstimOpt)];
    l = l + sum(1:EstimOpt.NVarA);
    if EstimOpt.NVarS > 0
        Results.DetailsS(:,4*i-3) = Results.bhat(l+(i-1)*EstimOpt.NVarS+1:l+i*EstimOpt.NVarS);
        Results.DetailsS(:,4*i-1:4*i) = [Results.std(l+(i-1)*EstimOpt.NVarS+1:l+i*EstimOpt.NVarS), pv(Results.bhat(l+(i-1)*EstimOpt.NVarS+1:l+i*EstimOpt.NVarS), Results.std(l+(i-1)*EstimOpt.NVarS+1:l+i*EstimOpt.NVarS))];
        l = l+EstimOpt.NClass*EstimOpt.NVarS;
    end
    if i ~= EstimOpt.NClass
        for j = 1:EstimOpt.NVarC
            Results.DetailsC(j,4*i-3) = Results.bhat(l+j+EstimOpt.NVarC*(i-1));
            Results.DetailsC(j,4*i-1:4*i) = [Results.std(l+j+EstimOpt.NVarC*(i-1)),pv(Results.bhat(l+j+EstimOpt.NVarC*(i-1)), Results.std(l+j+EstimOpt.NVarC*(i-1)))];
        end
    end
            %Results.DetailsC = [Results.bhat(l+1:l+EstimOpt.NVarC*(EstimOpt.NClass-1)), Results.std(l+1:l+EstimOpt.NVarC*(EstimOpt.NClass-1)), pv(Results.bhat(l+1:l+EstimOpt.NVarC*(EstimOpt.NClass-1)), Results.std(l+1:l+EstimOpt.NVarC*(EstimOpt.NClass-1)))];
    
    end
    Results.DetailsC = [Results.DetailsC,zeros(EstimOpt.NVarC,1),NaN(EstimOpt.NVarC,3)];
end

Results.EstimOpt = EstimOpt;
Results.OptimOpt = OptimOpt;
Results.INPUT = INPUT;


NSdSim = 10000;
bclass = reshape([Results.bhat(end - EstimOpt.NVarC*(EstimOpt.NClass-1) +1 :end); zeros(EstimOpt.NVarC,1)],[EstimOpt.NVarC,EstimOpt.NClass]);
bclass_sim = reshape([mvnrnd(Results.bhat(end - EstimOpt.NVarC*(EstimOpt.NClass-1) +1:end),Results.ihess(end - EstimOpt.NVarC*(EstimOpt.NClass-1) +1:end,end - EstimOpt.NVarC*(EstimOpt.NClass-1) +1:end),NSdSim)';zeros(EstimOpt.NVarC,NSdSim)],[EstimOpt.NVarC,EstimOpt.NClass,NSdSim]);

V = exp(INPUT.XXc*bclass);
Vsum = sum(V,2);
Results.PClass = zeros(1,4*EstimOpt.NClass);
Results.PClass(1,1:4:EstimOpt.NClass*4-3) = mean(V./Vsum(:,ones(EstimOpt.NClass,1)),1);

PClass_mean = zeros(NSdSim,EstimOpt.NClass);
XXc = INPUT.XXc;
parfor i = 1:NSdSim
    bhat_sim_i = bclass_sim(:,:,i);
    V_i = exp(XXc*bhat_sim_i);
    Vsum_i = sum(V_i,2);
    PC_i = V_i./Vsum_i;
    PClass_mean(i,:) = mean(PC_i,1);
end

Results.PClass(1,3:4:EstimOpt.NClass*4-1) = std(PClass_mean);
Results.PClass(1,4:4:EstimOpt.NClass*4) = pv(Results.PClass(1,1:4:EstimOpt.NClass*4-3),Results.PClass(1,3:4:EstimOpt.NClass*4-1));
Results.PClass95ci = [quantile(PClass_mean,0.025);quantile(PClass_mean,0.975)];

EstimOpt.params = length(b0);
if isfield(EstimOpt,'BActive')
    EstimOpt.params = EstimOpt.params - sum(EstimOpt.BActive == 0);
end

%Results.R = [Results.DetailsA; Results.DetailsV; Results.DetailsC; [Results.PClass',zeros(size(Results.PClass')),zeros(size(Results.PClass'))]];
Results.stats = [Results.LL;Results_old.MNL0.LL;1-Results.LL/Results_old.MNL0.LL;R2;((2*EstimOpt.params-2*Results.LL))/EstimOpt.NObs;((log(EstimOpt.NObs)*EstimOpt.params-2*Results.LL))/EstimOpt.NObs;EstimOpt.NObs;EstimOpt.NP;EstimOpt.params];

%% Header

Head = cell(1,2);
if EstimOpt.FullCov == 0
    Head(1,1) = {'LCMXL_d'};
else
    Head(1,1) = {'LCMXL'};
end

if EstimOpt.WTP_space > 0
    Head(1,2) = {'in WTP-space'};
else
    Head(1,2) = {'in preference-space'};
end

%% Results

Results.DetailsAV = [];
for i = 1:EstimOpt.NClass
    Results.DetailsAV = [Results.DetailsAV,Results.DetailsA(:,4*i-3:4*i),Results.DetailsV(:,4*i-3:4*i)];
end

Template1 = {'DetailsAV'};
Template2 = {'DetailsAV'};
Names.DetailsAV = EstimOpt.NamesA;
ST=[];

for i = 1:EstimOpt.NClass
    Heads.DetailsAV{2*i-1,1} = num2str(i, 'Class %1.0f');
    Heads.DetailsAV{2*i,1} = ' ';
    Heads.DetailsAV{2*i-1,2} = 'Means';
    Heads.DetailsAV{2*i,2} = 'Std. Deviations';
end
Heads.DetailsAV(end+1,1) = {'tb'};
Heads.DetailsAV(end,2) = {'tb'};

if EstimOpt.NVarS >0
    Template1 = [Template1;{'DetailsS'}];
    Template2 = [Template2;{'DetailsS'}];
    Names.DetailsS = EstimOpt.NamesS;
    Heads.DetailsS(:,2) = [Heads.DetailsAV(1:2:end-1,1);'tb'];
    Heads.DetailsS(end,2) = {'tb'};
    Heads.DetailsS(1:2,1) = {'Explanatory variables of scale';'lb'};
    ST = [ST,{'DetailsS'}];
end

Template1 = [Template1;{'DetailsC'}];
Template2 = [Template2;{'DetailsC'}];
Names.DetailsC = EstimOpt.NamesC;
Heads.DetailsC(:,2) = [Heads.DetailsAV(1:2:end-1,1);'tb'];
Heads.DetailsC(1:2,1) = {'Probability model';'lb'};
ST = [ST,{'DetailsC'}];

Template1 = [Template1; {'PClass'}];
Template2 = [Template2; {'PClass'}];
Names.PClass = {""};
Heads.PClass(:,2) = [Heads.DetailsAV(1:2:end-1,1);'tb'];
Heads.PClass(1:2,1) = {'Average class probabilities';'lb'};
ST = [ST,{'PClass'}];
%% Footer

Tail = cell(17,2);
Tail(2,1) = {'Model diagnostics'};
Tail(3:17,1) = {'LL at convergence' ;'LL at constant(s) only';  strcat('McFadden''s pseudo-R',char(178));strcat('Ben-Akiva-Lerman''s pseudo-R',char(178))  ;'AIC/n' ;'BIC/n'; 'n (observations)'; 'r (respondents)';'k (parameters)';' ';'Estimation method';'Simulation with';'Optimization method';'Gradient';'Hessian'};

if isfield(Results_old,'MNL0') && isfield(Results_old.MNL0,'LL')
    Tail(3:11,2) = num2cell(Results.stats);
end

if any(INPUT.W ~= 1)
    Tail(13,2) = {'weighted maximum likelihood'};
else
    Tail(13,2) = {'maximum likelihood'};
end

switch EstimOpt.Draws
    case 1
        Tail(14,2) = {[num2str(EstimOpt.NRep),' ','pseudo-random draws']};
    case 2
        Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Latin Hypercube Sampling draws']};
    case  3
        Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Halton draws (skip = ', num2str(EstimOpt.HaltonSkip), '; leap = ', num2str(EstimOpt.HaltonLeap),')']};
    case 4
        Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Halton draws with reverse radix scrambling (skip = ', num2str(EstimOpt.HaltonSkip), '; leap = ', num2str(EstimOpt.HaltonLeap),')']};
    case 5
        Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Sobol draws (skip = ', num2str(EstimOpt.HaltonSkip), '; leap = ', num2str(EstimOpt.HaltonLeap),')']};
    case 6
        Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Sobol draws with random linear scramble and random digital shift (skip = ', num2str(EstimOpt.HaltonSkip), '; leap = ', num2str(EstimOpt.HaltonLeap),')']};
end

Tail(15,2) = {OptimOpt.Algorithm;};

if strcmp(OptimOpt.GradObj,'on')
    if EstimOpt.NumGrad == 0
        Tail(16,2) = {'user-supplied, analytical'};
    else
        Tail(16,2) = {['user-supplied, numerical ',num2str(OptimOpt.FinDiffType)]};
    end
else
    Tail(16,2) = {['built-in, ',num2str(OptimOpt.FinDiffType)]};
    
end

outHessian = [];
if isequal(OptimOpt.Algorithm,'quasi-newton')
    outHessian='off, ';
    switch EstimOpt.HessEstFix
        case 0
            outHessian = [outHessian, 'retained from optimization'];
        case 1
            outHessian = [outHessian, 'ex-post calculated using BHHH'];
        case 2
            outHessian = [outHessian, 'ex-post calculated using high-precision BHHH'];
        case 3
            outHessian = [outHessian, 'ex-post calculated numerically'];
        case 4
            outHessian = [outHessian, 'ex-post calculated analytically'];
    end
else
    if strcmp(OptimOpt.Hessian,'user-supplied')
        if EstimOpt.ApproxHess == 1
            outHessian = 'user-supplied, BHHH, ';
        else
            outHessian = 'user-supplied, analytical, ';
        end
    else
        outHessian = ['built-in, ', num2str(OptimOpt.HessUpdate), ', '];
    end
    switch EstimOpt.HessEstFix
        case 0
            outHessian = [outHessian, 'retained from optimization'];
        case 1
            outHessian = [outHessian, 'ex-post calculated using BHHH'];
        case 2
            outHessian = [outHessian, 'ex-post calculated using high-precision BHHH'];
        case 3
            outHessian = [outHessian, 'ex-post calculated numerically'];
        case 4
            outHessian = [outHessian, 'ex-post calculated analytically'];
    end
end

Tail(17,2) = {outHessian};

%%  Print to screen and .xls

if EstimOpt.Display~=0
    Results.Dist = transpose(EstimOpt.Dist);
    Results.R_out = genOutput(EstimOpt, Results, Head, Tail, Names, Template1, Template2, Heads, ST);
end

end