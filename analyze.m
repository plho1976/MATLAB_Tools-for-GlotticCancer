function results = analyze(data, options)
%ANALYZE Reproduce the paired-plan exploratory dosimetry analysis.
% All dose differences are IMRT minus 3DCRT. Uses base MATLAB only.
arguments
    data (1,1) struct
    options.BootstrapResamples (1,1) double {mustBeInteger,mustBePositive} = 20000
    options.BootstrapSeed (1,1) double {mustBeInteger,mustBeNonnegative} = 20261006
end
data = glottic.deriveData(data);
x = data.CRT; y = data.IMRT; keys = string(data.metricKeys(:));
n = numel(data.patient_id);
if n < 4
    error('glottic:CohortTooSmall','At least four complete patient pairs are required.');
end
primary = 'carotid_worse_Dmean_Gy';
results = struct;
results.analysis = data.metadata;
results.analysis.n_paired_patients = n;
results.analysis.matlab_version = version;
results.analysis.code_version = '1.0.0';
results.analysis.primary_endpoint = primary;
results.analysis.delta_definition = 'IMRT minus 3DCRT';
results.analysis.correlation_x_definition = 'Positive carotid reduction = 3DCRT minus IMRT';
results.analysis.mean_definition = 'Arithmetic bilateral mean is not volume weighted';
results.analysis.test_policy = ['Exploratory two-sided analyses. Primary paired t is unadjusted; ' ...
    'Holm families: 15 secondary continuous endpoints and 10 binary thresholds. ' ...
    'Correlations are unadjusted. Nominal confidence intervals are not multiplicity adjusted.'];
results.analysis.exclusions = 'Ambiguous volume columns, year field, Sheet1, DVHs and clinical outcomes are excluded.';
for j = 1:numel(keys)
    k = char(keys(j)); a = x.(k); b = y.(k); d = b-a;
    m = struct;
    m.unit = 'Gy';
    if strcmp(k,'ptv_V66_percent'), m.unit = 'percent'; end
    m.CRT = glottic.inference('describe',a);
    m.IMRT = glottic.inference('describe',b);
    m.delta = glottic.inference('describe',d);
    m.delta_mean_95CI = glottic.inference('meanCI',d);
    m.paired_t = glottic.inference('pairedT',d);
    m.wilcoxon = glottic.inference('wilcoxon',d);
    rel = nan(n,1); valid = a > 0;
    rel(valid) = 100*(a(valid)-b(valid))./a(valid);
    m.patient_relative_reduction_percent = glottic.inference('describe',rel);
    m.patient_relative_reduction_mean_95CI_percent = glottic.inference('meanCI',rel);
    m.relative_reduction_status = 'Defined only for patients with positive 3DCRT baseline';
    m.reduction_of_cohort_means_percent = NaN;
    if mean(a)>0, m.reduction_of_cohort_means_percent = 100*(mean(a)-mean(b))/mean(a); end
    m.IMRT_less_than_3DCRT = sum(b<a);
    m.equal = sum(b==a);
    m.IMRT_greater_than_3DCRT = sum(b>a);
    results.metrics.(k) = m;
end
secondary = keys(keys~=string(primary)); p = zeros(numel(secondary),1);
for j=1:numel(secondary), p(j)=results.metrics.(secondary(j)).paired_t.p_two_sided; end
adj = glottic.inference('holm',p);
for j=1:numel(secondary), results.metrics.(secondary(j)).paired_t.p_holm_secondary_family=adj(j); end
results.multiplicity_adjustment.secondary_continuous = struct('method','Holm', ...
    'family_size',numel(secondary),'keys',secondary);

% Keep these definitions and strict/inclusive operators identical to reference.
names = ["both_carotid_Dmean_less_than_20Gy"; "any_carotid_Dmax_greater_than_50Gy"; ...
    "ptv_D95_at_least_66Gy"; "ptv_D99_9_at_least_62_7Gy"; ...
    "ptv_Dmax_greater_than_72_6Gy"; "ptv_V66_at_least_95percent"; ...
    "carotid_Dmean_under20_and_Dmax_at_most50"; "target_all_three_checks"; ...
    "carotid_mean_under20_and_target_all_three_checks"; ...
    "carotid_mean_under20_max_atmost50_and_target_all_three_checks"];
labels = ["Both carotid Dmean <20 Gy"; "Any carotid Dmax >50 Gy"; ...
    "PTV D95 >=66 Gy"; "PTV D99.9 >=62.7 Gy"; "PTV Dmax >72.6 Gy"; ...
    "PTV V66 >=95%"; "Carotid mean <20 Gy and peak <=50 Gy"; ...
    "All three target checks"; "Carotid mean <20 Gy and all target checks"; ...
    "Carotid mean <20 Gy, peak <=50 Gy and all target checks"];
cx = conditions(x); cy = conditions(y); bp = zeros(10,1);
for j=1:10
    a=cx(:,j); b=cy(:,j);
    item.CRT = glottic.inference('proportion',sum(a),n);
    item.IMRT = glottic.inference('proportion',sum(b),n);
    item.paired_table = struct('both_yes',sum(a&b),'CRT_yes_IMRT_no',sum(a&~b), ...
        'CRT_no_IMRT_yes',sum(~a&b),'both_no',sum(~a&~b));
    item.McNemar_exact_p_two_sided = glottic.inference('mcnemar',sum(a&~b),sum(~a&b));
    item.paired_percent_difference_IMRT_minus_CRT = 100*(mean(b)-mean(a));
    results.thresholds.(names(j)) = item;
    bp(j) = item.McNemar_exact_p_two_sided;
end
adj = glottic.inference('holm',bp);
for j=1:10, results.thresholds.(names(j)).McNemar_exact_p_holm_threshold_family=adj(j); end
results.multiplicity_adjustment.binary_thresholds = struct('method','Holm','family_size',10,'keys',names);
for cutoff=[20 25 30 35]
    k=sprintf('cutoff_%dGy',cutoff);
    results.carotid_mean_threshold_sensitivity.(k).CRT = glottic.inference('proportion',sum(x.carotid_worse_Dmean_Gy<cutoff),n);
    results.carotid_mean_threshold_sensitivity.(k).IMRT = glottic.inference('proportion',sum(y.carotid_worse_Dmean_Gy<cutoff),n);
end
categoryNames=["low_mean_low_max";"low_mean_high_max";"high_mean_low_max";"high_mean_high_max"];
for tech=["CRT" "IMRT"]
    a=data.(tech); low=a.carotid_worse_Dmean_Gy<20; high=a.carotid_worse_Dmax_Gy>50;
    groups=[low&~high low&high ~low&~high ~low&high];
    for j=1:4
        results.carotid_mean_max_joint_categories.(tech).(categoryNames(j))=glottic.inference('proportion',sum(groups(:,j)),n);
    end
    results.arithmetic_bilateral_mean_under20.(tech)=glottic.inference('proportion',sum(a.carotid_arithmetic_bilateral_Dmean_Gy<20),n);
end
grid=zeros(4,3); means=[15 20 25 30]; peaks=[35 50 60];
for i=1:4
    for j=1:3
        grid(i,j)=sum(y.carotid_worse_Dmean_Gy<means(i)&y.carotid_worse_Dmax_Gy<=peaks(j));
    end
end
results.IMRT_joint_threshold_grid = struct('mean_cutoffs_Gy',means,'peak_cutoffs_Gy',peaks,'counts',grid);
reduction=x.carotid_worse_Dmean_Gy-y.carotid_worse_Dmean_Gy;
for key=["ptv_D95_Gy" "ptv_D99_9_Gy" "ptv_Dmax_Gy"]
    results.correlations.(key)=glottic.inference('correlation',reduction,y.(key)-x.(key));
end
bothDecrease=(y.carotid_L_Dmean_Gy<x.carotid_L_Dmean_Gy)&(y.carotid_R_Dmean_Gy<x.carotid_R_Dmean_Gy);
results.both_carotid_means_decreased=glottic.inference('proportion',sum(bothDecrease),n);
low=y.carotid_worse_Dmean_Gy<20; high=y.carotid_worse_Dmax_Gy>50;
results.IMRT_retained_high_max_among_both_mean_under20=glottic.inference('proportion',sum(low&high),sum(low));
% Local stream preserves the caller's global RNG state. NumPy uses PCG64;
% MATLAB uses mt19937ar, so bootstrap draws differ from the Python reference.
stream=RandStream('mt19937ar','Seed',options.BootstrapSeed);
d=y.carotid_worse_Dmean_Gy-x.carotid_worse_Dmean_Gy;
boot=zeros(options.BootstrapResamples,1);
chunk=1000;
for first=1:chunk:numel(boot)
    last=min(first+chunk-1,numel(boot));
    ind=randi(stream,n,last-first+1,n);
    boot(first:last)=mean(reshape(d(ind),size(ind)),2);
end
results.bootstrap=struct('n_resamples',options.BootstrapResamples,'seed',options.BootstrapSeed, ...
    'generator','MATLAB mt19937ar; different draws from NumPy PCG64', ...
    'method','Paired patient bootstrap; linear-interpolated percentile CI on mean IMRT minus 3DCRT delta', ...
    'mean_delta_95CI_Gy',glottic.inference('quantile',boot,[.025 .975]));
results.data_concerns = [ ...
    "Whole workflows used PBC for 3DCRT and AAA for IMRT; technique and algorithm effects are inseparable."; ...
    "20 and 50 Gy carotid cutoffs are exploratory planning descriptors, not validated injury thresholds."; ...
    "Carotid worse-side Dmean and Dmax are selected independently and may refer to different sides."; ...
    "Carotid volumes, D0.03cc, DVHs and spatial exposure extent are unavailable."; ...
    "PTV D99.9 is neither D98 nor D100; PTV mean is not D50."; ...
    "No clinical stroke, local control, toxicity or time-to-event outcomes are analyzed."; ...
    "Primary designation is post hoc; all findings remain exploratory."];
results.tables=buildTables(results,keys,names,labels);
end

function c=conditions(a)
low=a.carotid_worse_Dmean_Gy<20; peak=a.carotid_worse_Dmax_Gy<=50;
t=a.ptv_D95_Gy>=66 & a.ptv_D99_9_Gy>=62.7 & a.ptv_Dmax_Gy<=72.6;
c=[low ~peak a.ptv_D95_Gy>=66 a.ptv_D99_9_Gy>=62.7 a.ptv_Dmax_Gy>72.6 ...
    a.ptv_V66_percent>=95 low&peak t low&t low&peak&t];
end

function tables=buildTables(r,keys,names,labels)
N=numel(keys); Endpoint=keys; Unit=strings(N,1);
CRT_Mean=zeros(N,1); CRT_SD=CRT_Mean; IMRT_Mean=CRT_Mean; IMRT_SD=CRT_Mean;
Delta_Mean=CRT_Mean; CI_Lower=CRT_Mean; CI_Upper=CRT_Mean; PairedT_P=CRT_Mean;
Holm_P=nan(N,1); Wilcoxon_P=CRT_Mean; Wilcoxon_Statistic=CRT_Mean;
CRT_Median=CRT_Mean; CRT_Q1=CRT_Mean; CRT_Q3=CRT_Mean;
IMRT_Median=CRT_Mean; IMRT_Q1=CRT_Mean; IMRT_Q3=CRT_Mean;
RelativeReduction_Mean=CRT_Mean; RelativeReduction_N=CRT_Mean;
CRT_Min=CRT_Mean; CRT_Max=CRT_Mean; IMRT_Min=CRT_Mean; IMRT_Max=CRT_Mean;
Delta_SD=CRT_Mean; RelativeReduction_SD=CRT_Mean;
RelativeReduction_CI_Lower=CRT_Mean; RelativeReduction_CI_Upper=CRT_Mean;
CohortMeansReduction_Percent=CRT_Mean; IMRT_Lower_Count=CRT_Mean;
Equal_Count=CRT_Mean; IMRT_Higher_Count=CRT_Mean;
for i=1:N
    m=r.metrics.(keys(i)); Unit(i)=m.unit;
    CRT_Mean(i)=m.CRT.mean; CRT_SD(i)=m.CRT.sd; IMRT_Mean(i)=m.IMRT.mean; IMRT_SD(i)=m.IMRT.sd;
    CRT_Median(i)=m.CRT.median; CRT_Q1(i)=m.CRT.q1; CRT_Q3(i)=m.CRT.q3;
    IMRT_Median(i)=m.IMRT.median; IMRT_Q1(i)=m.IMRT.q1; IMRT_Q3(i)=m.IMRT.q3;
    CRT_Min(i)=m.CRT.min; CRT_Max(i)=m.CRT.max; IMRT_Min(i)=m.IMRT.min; IMRT_Max(i)=m.IMRT.max;
    Delta_Mean(i)=m.delta.mean; Delta_SD(i)=m.delta.sd;
    CI_Lower(i)=m.delta_mean_95CI(1); CI_Upper(i)=m.delta_mean_95CI(2);
    PairedT_P(i)=m.paired_t.p_two_sided;
    if isfield(m.paired_t,'p_holm_secondary_family'), Holm_P(i)=m.paired_t.p_holm_secondary_family; end
    Wilcoxon_P(i)=m.wilcoxon.p_two_sided; Wilcoxon_Statistic(i)=m.wilcoxon.statistic;
    RelativeReduction_Mean(i)=m.patient_relative_reduction_percent.mean;
    RelativeReduction_SD(i)=m.patient_relative_reduction_percent.sd;
    RelativeReduction_N(i)=m.patient_relative_reduction_percent.n;
    RelativeReduction_CI_Lower(i)=m.patient_relative_reduction_mean_95CI_percent(1);
    RelativeReduction_CI_Upper(i)=m.patient_relative_reduction_mean_95CI_percent(2);
    CohortMeansReduction_Percent(i)=m.reduction_of_cohort_means_percent;
    IMRT_Lower_Count(i)=m.IMRT_less_than_3DCRT; Equal_Count(i)=m.equal; IMRT_Higher_Count(i)=m.IMRT_greater_than_3DCRT;
end
tables.Continuous=table(Endpoint,Unit,CRT_Mean,CRT_SD,IMRT_Mean,IMRT_SD,Delta_Mean,Delta_SD,CI_Lower,CI_Upper, ...
    PairedT_P,Holm_P,Wilcoxon_P,Wilcoxon_Statistic,CRT_Median,CRT_Q1,CRT_Q3,CRT_Min,CRT_Max, ...
    IMRT_Median,IMRT_Q1,IMRT_Q3,IMRT_Min,IMRT_Max,RelativeReduction_Mean,RelativeReduction_SD, ...
    RelativeReduction_N,RelativeReduction_CI_Lower,RelativeReduction_CI_Upper,CohortMeansReduction_Percent, ...
    IMRT_Lower_Count,Equal_Count,IMRT_Higher_Count);
pub=table(keys,strings(N,1),strings(N,1),strings(N,1),strings(N,1),strings(N,1), ...
    'VariableNames',{'Endpoint','CRT_Mean_SD','IMRT_Mean_SD','Delta_95CI','PairedT_P','Holm_P'});
for i=1:N
    pub.Endpoint(i)=endpointLabel(keys(i));
    pub.CRT_Mean_SD(i)=sprintf('%.2f +/- %.2f',CRT_Mean(i),CRT_SD(i));
    pub.IMRT_Mean_SD(i)=sprintf('%.2f +/- %.2f',IMRT_Mean(i),IMRT_SD(i));
    pub.Delta_95CI(i)=sprintf('%.2f (%.2f, %.2f)',Delta_Mean(i),CI_Lower(i),CI_Upper(i));
    pub.PairedT_P(i)=ptext(PairedT_P(i)); pub.Holm_P(i)=ptext(Holm_P(i));
end
oar=["carotid_worse_Dmean_Gy";"carotid_L_Dmean_Gy";"carotid_R_Dmean_Gy"; ...
    "carotid_arithmetic_bilateral_Dmean_Gy";"carotid_worse_Dmax_Gy"; ...
    "carotid_L_Dmax_Gy";"carotid_R_Dmax_Gy";"thyroid_Dmean_Gy"];
[~,ix]=ismember(oar,keys); tables.Table1=pub(ix,:);
target=["ptv_D99_9_Gy";"ptv_D95_Gy";"ptv_V66_percent";"ptv_Dmean_Gy";"ptv_Dmax_Gy"];
[~,ix]=ismember(target,keys); tables.Table2=pub(ix,:);
tables.TableS1=pub; tables.TableS1.Wilcoxon_P=arrayfun(@ptext,Wilcoxon_P);
tables.TableS1.Wilcoxon_Statistic=Wilcoxon_Statistic;

CRT_Count=zeros(10,1); IMRT_Count=CRT_Count; N=repmat(r.analysis.n_paired_patients,10,1);
Both_Yes=CRT_Count; Lost=CRT_Count; Gained=CRT_Count; Both_No=CRT_Count; McNemar_P=CRT_Count; Holm_P=CRT_Count;
for i=1:10
    t=r.thresholds.(names(i)); CRT_Count(i)=t.CRT.count; IMRT_Count(i)=t.IMRT.count;
    Both_Yes(i)=t.paired_table.both_yes; Lost(i)=t.paired_table.CRT_yes_IMRT_no;
    Gained(i)=t.paired_table.CRT_no_IMRT_yes; Both_No(i)=t.paired_table.both_no;
    McNemar_P(i)=t.McNemar_exact_p_two_sided; Holm_P(i)=t.McNemar_exact_p_holm_threshold_family;
end
tables.TableS3=table(labels,CRT_Count,IMRT_Count,N,Both_Yes,Lost,Gained,Both_No,McNemar_P,Holm_P, ...
    'VariableNames',{'Criterion','CRT_Count','IMRT_Count','N','Both_Yes','Lost','Gained','Both_No','McNemar_P','Holm_P'});
tables.Table3=tables.TableS3([1:5 7 8 10],[1:4 6:7 9:10]);
g=r.IMRT_joint_threshold_grid;
tables.TableS2=array2table([g.mean_cutoffs_Gy(:) g.counts], ...
    'VariableNames',{'Mean_StrictlyBelow_Gy','Peak_AtMost35Gy','Peak_AtMost50Gy','Peak_AtMost60Gy'});
rows=cell(20,7); z=0;
for i=1:10
    for tech=["CRT" "IMRT"]
        z=z+1; p=r.thresholds.(names(i)).(tech);
        rows(z,:)={labels(i),tech,p.count,p.denominator,p.percent,p.exact_95CI_percent(1),p.exact_95CI_percent(2)};
    end
end
tables.TableS4=cell2table(rows,'VariableNames',{'Criterion','Technique','Count','Denominator','Percent','CI_Lower_Percent','CI_Upper_Percent'});
categories=string(fieldnames(r.carotid_mean_max_joint_categories.CRT)); rows=cell(8,6); z=0;
for tech=["CRT" "IMRT"]
    for i=1:4
        z=z+1; p=r.carotid_mean_max_joint_categories.(tech).(categories(i));
        rows(z,:)={tech,categories(i),p.count,p.percent,p.exact_95CI_percent(1),p.exact_95CI_percent(2)};
    end
end
tables.TableS5=cell2table(rows,'VariableNames',{'Technique','Category','Count','Percent','CI_Lower_Percent','CI_Upper_Percent'});
ck=string(fieldnames(r.correlations)); rows=cell(3,7);
for i=1:3
    c=r.correlations.(ck(i)); rows(i,:)={endpointLabel(ck(i)),c.spearman_rho,c.spearman_p_two_sided, ...
        c.pearson_r,c.pearson_p_two_sided,c.pearson_fisher_95CI(1),c.pearson_fisher_95CI(2)};
end
tables.TableS6=cell2table(rows,'VariableNames',{'TargetDelta','Spearman_Rho','Spearman_P','Pearson_R','Pearson_P','Pearson_CI_Lower','Pearson_CI_Upper'});
rows=cell(8,7); z=0;
for cutoff=[20 25 30 35]
    for tech=["CRT" "IMRT"]
        z=z+1; p=r.carotid_mean_threshold_sensitivity.(sprintf('cutoff_%dGy',cutoff)).(tech);
        rows(z,:)={cutoff,tech,p.count,p.denominator,p.percent,p.exact_95CI_percent(1),p.exact_95CI_percent(2)};
    end
end
tables.Sensitivity=cell2table(rows,'VariableNames',{'Mean_StrictlyBelow_Gy','Technique','Count','Denominator','Percent','CI_Lower_Percent','CI_Upper_Percent'});
rows=cell(5,7); z=0;
for tech=["CRT" "IMRT"]
    z=z+1; p=r.arithmetic_bilateral_mean_under20.(tech);
    rows(z,:)={"Arithmetic bilateral Dmean <20 Gy",tech,p.count,p.denominator,p.percent,p.exact_95CI_percent(1),p.exact_95CI_percent(2)};
end
extra={"Both carotid means decreased", "IMRT", r.both_carotid_means_decreased; ...
    "High peak >50 Gy among IMRT both-mean <20 Gy", "IMRT", r.IMRT_retained_high_max_among_both_mean_under20};
for i=1:2
    z=z+1; p=extra{i,3}; rows(z,:)={extra{i,1},extra{i,2},p.count,p.denominator,p.percent,p.exact_95CI_percent(1),p.exact_95CI_percent(2)};
end
tables.Descriptive=cell2table(rows(1:z,:),'VariableNames',{'Descriptor','Technique','Count','Denominator','Percent','CI_Lower_Percent','CI_Upper_Percent'});
end

function s=ptext(p)
if isnan(p), s="--"; elseif p<.001, s="<0.001"; else, s=string(sprintf('%.3f',p)); end
end

function s=endpointLabel(key)
s=replace(string(key),'_Gy',' (Gy)'); s=replace(s,'_percent',' (%)');
s=replace(s,'ptv_D99_9','PTV D99.9'); s=replace(s,'ptv_','PTV ');
s=replace(s,'carotid_arithmetic_bilateral_Dmean','Arithmetic bilateral carotid Dmean');
s=replace(s,'carotid_worse_Dmean','Worse-side carotid Dmean');
s=replace(s,'carotid_worse_Dmax','Maximum across both carotids');
s=replace(s,'carotid_L_','Left carotid '); s=replace(s,'carotid_R_','Right carotid ');
s=replace(s,'thyroid_','Thyroid '); s=replace(s,'_',' ');
end
