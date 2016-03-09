#!/usr/bin/octave
% PAN-2014 evaluation scrpipt for the author identification task
% for Octave 3.6.4

1;

function [FPrate, TPrate, AUC, thresholds] = pan14authorverificationcomputeroceval(confidence, testClass)
%% Compute ROC curve statistics
%
% Inputs: 
%  confidence(i) is proportional to the probability that  testClass(i) is positive
%  testClass(i) = 0 => target absent, testClass(i) = 1 => target present
%
% Outputs:
% FPrate(i) = False positive rate at threshold i
% TPrate(i) = True positive rate at threshold i
% AUC = area under curve
% thresholds(i) = thresholds used
%
% Based on algorithms 2 and 4 from Tom Fawcett's paper "ROC Graphs: Notes and
% Practical Considerations for Data Mining Researchers" (2003)
% http://www.hpl.hp.com/techreports/2003/HPL-2003-4.pdf"
%
%PMTKdate February 21, 2005
%PMTKauthor Vlad Magdin
% UBC

% This file is from pmtk3.googlecode.com


% break ties in scores
%S = rand('state');
%rand('state',0); 
%confidence = confidence + rand(size(confidence))*10^(-10);
%rand('state',S)
[thresholds order] = sort(confidence, 'descend');
testClass = testClass(order);

%%% -- calculate TP/FP rates and totals -- %%%
AUC = 0;
faCnt = 0;
tpCnt = 0;
falseAlarms = zeros(1,size(thresholds,2));
detections = zeros(1,size(thresholds,2));
fPrev = -inf;
faPrev = 0;
tpPrev = 0;

P = max(size(find(testClass==1)));
N = max(size(find(testClass==0)));

for i=1:length(thresholds)
    if thresholds(i) ~= fPrev
        falseAlarms(i) = faCnt;
        detections(i) = tpCnt;

        AUC = AUC + polyarea([faPrev faPrev faCnt/N faCnt/N],[0 tpPrev tpCnt/P 0]);

        fPrev = thresholds(i);
        faPrev = faCnt/N;
        tpPrev = tpCnt/P;
    end
    
    if testClass(i) == 1
        tpCnt = tpCnt + 1;
    else
        faCnt = faCnt + 1;
    end
end

AUC = AUC + polyarea([faPrev faPrev 1 1],[0 tpPrev 1 0]);

FPrate = falseAlarms/N;
TPrate = detections/P;
endfunction



if nargin~=6
    disp('Usage: -i INPUT-DIR -t TRUTH-FILE -o OUTPUT-FILE')
    return;
end

PARAMS=['-i';'-t';'-o'];
% CODES={'DE','Dutch','Essays';'DR','Dutch','Reviews';'EE','English','Essays';'EN','English','Novels';'GR','Greek','Articles';'SP','Spanish','Articles'};
CODES={'DU','Dutch','xxx';'EN','English','xxx';'GR','Greek','xxx';'SP','Spanish','xxx'};

for i=1:2:nargin
    for j=1:size(PARAMS,1)
        if strcmp(lower(argv(){i}),'-t')==1 && strcmp(PARAMS(j,:),'-t')==1
            TRUTH=argv(){i+1};
            PARAMS(j,:)='  ';
        end
        if strcmp(lower(argv(){i}),'-i')==1 && strcmp(PARAMS(j,:),'-i')==1
            IN=argv(){i+1};
            PARAMS(j,:)='  ';
        end
        if strcmp(lower(argv(){i}),'-o')==1 && strcmp(PARAMS(j,:),'-o')==1
            OUT=argv(){i+1};
            PARAMS(j,:)='  ';
        end
    end
end
disp(PARAMS)
if size(find(PARAMS(:,1)=='-'),1)>0
    disp('Usage: -i INPUT-DIR -t TRUTH-FILE -o OUTPUT-FILE')
    return;
end

% Calculation of ROC-AUC and c@1 scores for the Author Identification task @PAN-2014
% TRUTH: The ground truth file (see format at pan.webis.de)
% ANSWERS: The answers file of a given submission

AUC=0;
C1=0;

% Reading ground truth and answers files
C=dir(TRUTH);
if size(C,1)>0
    GTR=fileread(TRUTH);
else disp(['The given ground truth file (',TRUTH,') does not exist'])
    return;
end
C=dir(IN);
if size(C,1)>0
    ANS=fileread(IN);
    ANS(ANS==13)='';
else disp(['The given input file (',IN,') does not exist'])
    return;
end

% Extracting Problem IDs, True answers, and Given answers
% All unanswered problems are assigned the value 0.5
PROBLEMS=[];
TA_ALL=cell(size(CODES,1)+1,1);
GA_ALL=cell(size(CODES,1)+1,1);
for i=1:size(CODES,1)
        TA=[];
        GA=[];
        PATTERN=CODES{i,:};
        I=strfind(GTR,PATTERN);
        for j=1:size(I,2)
            ProblemID=GTR(I(j):I(j)+4);
            TrueAnswer=GTR(I(j)+6);
            PROBLEMS=[PROBLEMS;ProblemID];
            if TrueAnswer=='Y'
                TA=[TA;1];
            else TA=[TA;0];
            end
            IA=strfind(ANS,ProblemID);
            if size(IA,2)>0
                IE=find(ANS(IA(1):end)==10);
                if size(IE,2)>0
                    GivenAnswer=ANS(IA(1)+6:IA(1)+IE(1)-1)';
                end
                if size(IE,2)==0
                    GivenAnswer=ANS(IA(1)+6:end)';
                end
            else GivenAnswer='0.5';
            end
            GivenAnswer1=GivenAnswer;
            GivenAnswer=str2num(GivenAnswer);
            if size(GivenAnswer,1)==0
                GivenAnswer=0.5;
            end
            if GivenAnswer1=='Y'
                GivenAnswer=1;
            end
            if GivenAnswer1=='N';
                GivenAnswer=0;
            end
            GA=[GA;GivenAnswer];
%            disp([ProblemID,' ',TrueAnswer,' ',num2str(GivenAnswer)])
        end
        GA_ALL{i,1}=GA;
        TA_ALL{i,1}=TA;
        GA_ALL{end,1}=[GA_ALL{end,1};GA];
        TA_ALL{end,1}=[TA_ALL{end,1};TA];
end

RESULTS=zeros(size(CODES,1),2);
for i=1:size(TA_ALL,1)
    if size(TA_ALL{i,1},1)>0
        % Calculation of ROC-AUC
        [~,~,AUC]=pan14authorverificationcomputeroceval(GA_ALL{i,1},TA_ALL{i,1});

        % Calculation of c@1
        B=GA_ALL{i,1};
        B(GA_ALL{i,1}>0.5)=1;
        B(GA_ALL{i,1}<0.5)=0;
        Nc=sum(TA_ALL{i,1}==B);
        N=size(TA_ALL{i,1},1);
        Nu=sum(B==0.5);
        C1=(1/N)*(Nc+(Nu*Nc/N));
        RESULTS(i,1)=AUC;
        RESULTS(i,2)=C1;
    end
end

% Displaying results and saving in the output directory
C=0;
X=['{',10,' "results": [',10];
for i=1:size(CODES,1)
    if size(TA_ALL{i,1})>0
        C=C+1;
        X=[X,'    {"language": "',CODES{i,2},'",',10,'     "genre": "',CODES{i,3},'",',10,'     "AUC": ',num2str(RESULTS(i,1)),',',10,'     "C1": ',num2str(RESULTS(i,2)),',',10,'     "finalScore": ',num2str(RESULTS(i,1)*RESULTS(i,2)),'},',10];
        disp([CODES{i,1},': AUC=',num2str(RESULTS(i,1)),' C@1=',num2str(RESULTS(i,2)),' AUC*C@1=',num2str(RESULTS(i,1)*RESULTS(i,2))])
    else disp([CODES{i,1},': No ground truth problems found'])
    end
end

if C>1
    X=[X,'    {"language": "all",',10,'     "genre": "all",',10,'     "AUC": ',num2str(RESULTS(i,1)),',',10,'     "C1": ',num2str(RESULTS(i,2)),',',10,'     "finalScore": ',num2str(RESULTS(i,1)*RESULTS(i,2)),'}',10,'  ]',10,'}'];
    disp(['ALL: AUC=',num2str(RESULTS(end,1)),' C@1=',num2str(RESULTS(end,2)),' AUC*C@1=',num2str(RESULTS(end,1)*RESULTS(end,2))])
else X=[X(1:end-2),10,'  ]',10,'}'];
end

fid=fopen(OUT,'w');
fprintf(fid,'%s',X);
fclose(fid);
