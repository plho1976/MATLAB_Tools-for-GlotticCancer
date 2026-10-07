function tests=test_reference
% Meaningful regression tests against all supplied deterministic reference results.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
workspace=fileparts(root);
workbook=fullfile(workspace,'DataLanPhuong.xlsx');
goldFile=fullfile(workspace,'PESM_Manuscript','Analysis','paired_plan_results.json');
assumeTrue(tc,isfile(workbook)&&isfile(goldFile),'Supplied workbook and reference JSON required for regression.');
tc.TestData.data=glottic.importWorkbook(workbook,30);
tc.TestData.r=glottic.analyze(tc.TestData.data,BootstrapResamples=2000);
tc.TestData.gold=jsondecode(fileread(goldFile));
tc.TestData.workbook=workbook;
end

function testRawAndDerivedAgainstCSV(tc)
workspace=fileparts(fileparts(fileparts(mfilename('fullpath'))));
t=readtable(fullfile(workspace,'PESM_Manuscript','Analysis','paired_plan_patient_data.csv'),'TextType','string','VariableNamingRule','preserve');
d=tc.TestData.data;
verifyEqual(tc,height(t),numel(d.patient_id));
for key=string(d.metricKeys(:))'
    verifyEqual(tc,d.CRT.(key),t.('3DCRT_'+key),'AbsTol',2e-12);
    verifyEqual(tc,d.IMRT.(key),t.('IMRT_'+key),'AbsTol',2e-12);
end
end

function testAllContinuousStatistics(tc)
r=tc.TestData.r; gold=tc.TestData.gold; keys=fieldnames(gold.metrics);
% jsondecode uses makeValidName for Python's digit-leading field 3DCRT.
gCRT=matlab.lang.makeValidName('3DCRT');
for i=1:numel(keys)
    k=keys{i}; m=r.metrics.(k); g=gold.metrics.(k);
    fields={'n','mean','sd','median','q1','q3','min','max'};
    for j=1:numel(fields)
        f=fields{j};
        verifyEqual(tc,m.CRT.(f),g.(gCRT).(f),'AbsTol',3e-11);
        verifyEqual(tc,m.IMRT.(f),g.IMRT.(f),'AbsTol',3e-11);
    end
    suffix='Gy'; if strcmp(k,'ptv_V66_percent'), suffix='percentage_points'; end
    gd=g.(['delta_IMRT_minus_3DCRT_' suffix]);
    for j=1:numel(fields), f=fields{j}; verifyEqual(tc,m.delta.(f),gd.(f),'AbsTol',3e-11); end
    verifyEqual(tc,m.delta_mean_95CI,g.(['delta_mean_95CI_' suffix])','AbsTol',3e-10);
    verifyEqual(tc,m.paired_t.t,g.paired_t.t,'AbsTol',3e-10);
    verifyEqual(tc,m.paired_t.p_two_sided,g.paired_t.p_two_sided,'RelTol',3e-9,'AbsTol',1e-25);
    verifyEqual(tc,m.wilcoxon.statistic,g.wilcoxon.statistic);
    verifyEqual(tc,m.wilcoxon.p_two_sided,g.wilcoxon.p_two_sided,'AbsTol',1e-15);
    verifyEqual(tc,m.reduction_of_cohort_means_percent,g.reduction_of_cohort_means_percent,'AbsTol',3e-11);
    verifyEqual(tc,m.patient_relative_reduction_percent.mean,g.patient_relative_reduction_percent.mean,'AbsTol',3e-11);
    verifyEqual(tc,m.patient_relative_reduction_mean_95CI_percent,g.patient_relative_reduction_mean_95CI_percent','AbsTol',3e-10);
    if isfield(g.paired_t,'p_holm_secondary_family')
        verifyEqual(tc,m.paired_t.p_holm_secondary_family,g.paired_t.p_holm_secondary_family,'RelTol',3e-9,'AbsTol',1e-25);
    end
end
end

function testAllThresholdsAndCounts(tc)
r=tc.TestData.r; gold=tc.TestData.gold; keys=fieldnames(gold.thresholds);
gCRT=matlab.lang.makeValidName('3DCRT');
for i=1:numel(keys)
    m=r.thresholds.(keys{i}); g=gold.thresholds.(keys{i});
    for tech=["CRT" "IMRT"]
        gt='IMRT'; if tech=="CRT", gt=gCRT; end
        verifyEqual(tc,m.(tech).count,g.(gt).count);
        verifyEqual(tc,m.(tech).percent,g.(gt).percent,'AbsTol',1e-12);
        verifyEqual(tc,m.(tech).exact_95CI_percent,g.(gt).exact_95CI_percent','AbsTol',2e-9);
    end
    verifyEqual(tc,m.paired_table.both_yes,g.paired_table.both_yes);
    verifyEqual(tc,m.paired_table.both_no,g.paired_table.both_no);
    verifyEqual(tc,m.paired_table.CRT_yes_IMRT_no,g.paired_table.(matlab.lang.makeValidName('3DCRT_yes_IMRT_no')));
    verifyEqual(tc,m.paired_table.CRT_no_IMRT_yes,g.paired_table.(matlab.lang.makeValidName('3DCRT_no_IMRT_yes')));
    verifyEqual(tc,m.McNemar_exact_p_two_sided,g.McNemar_exact_p_two_sided,'AbsTol',1e-14);
    verifyEqual(tc,m.McNemar_exact_p_holm_threshold_family,g.McNemar_exact_p_holm_threshold_family,'AbsTol',1e-14);
end
verifyEqual(tc,r.both_carotid_means_decreased.count,gold.both_carotid_means_decreased.count);
verifyEqual(tc,r.IMRT_retained_high_max_among_both_mean_under20.count,gold.IMRT_retained_high_max_among_both_mean_under20.count);
verifyEqual(tc,r.IMRT_retained_high_max_among_both_mean_under20.denominator,gold.IMRT_retained_high_max_among_both_mean_under20.denominator);
end

function testCorrelations(tc)
keys=fieldnames(tc.TestData.r.correlations);
for i=1:numel(keys)
    m=tc.TestData.r.correlations.(keys{i}); g=tc.TestData.gold.exploratory_correlations_reduction_vs_target_delta.(keys{i});
    verifyEqual(tc,m.spearman_rho,g.spearman_rho,'AbsTol',2e-12);
    verifyEqual(tc,m.spearman_p_two_sided,g.spearman_p_two_sided,'AbsTol',2e-11);
    verifyEqual(tc,m.pearson_r,g.pearson_r,'AbsTol',2e-12);
    verifyEqual(tc,m.pearson_p_two_sided,g.pearson_p_two_sided,'AbsTol',2e-11);
    verifyEqual(tc,m.pearson_fisher_95CI,g.pearson_fisher_95CI','AbsTol',2e-12);
end
end

function testBootstrapRepeatabilityAndRNG(tc)
before=rng;
r1=glottic.analyze(tc.TestData.data,BootstrapResamples=500,BootstrapSeed=77);
r2=glottic.analyze(tc.TestData.data,BootstrapResamples=500,BootstrapSeed=77);
verifyEqual(tc,r1.bootstrap.mean_delta_95CI_Gy,r2.bootstrap.mean_delta_95CI_Gy);
verifyEqual(tc,rng,before);
verifyLessThan(tc,r1.bootstrap.mean_delta_95CI_Gy(1),r1.metrics.carotid_worse_Dmean_Gy.delta.mean);
verifyGreaterThan(tc,r1.bootstrap.mean_delta_95CI_Gy(2),r1.metrics.carotid_worse_Dmean_Gy.delta.mean);
end

function testZeroBaselinesAndEmptyCondition(tc)
d=tc.TestData.data;
d.CRT.thyroid_Dmean_Gy(:)=0;
d.IMRT.carotid_L_Dmean_Gy(:)=20;
d.IMRT.carotid_R_Dmean_Gy(:)=20;
r=glottic.analyze(d,BootstrapResamples=50);
verifyEqual(tc,r.metrics.thyroid_Dmean_Gy.patient_relative_reduction_percent.n,0);
verifyTrue(tc,isnan(r.metrics.thyroid_Dmean_Gy.reduction_of_cohort_means_percent));
verifyEqual(tc,r.IMRT_retained_high_max_among_both_mean_under20.denominator,0);
verifyTrue(tc,isnan(r.IMRT_retained_high_max_among_both_mean_under20.percent));
verifyEqual(tc,r.thresholds.both_carotid_Dmean_less_than_20Gy.IMRT.count,0);
end

function testReportExportAndOverwriteGuard(tc)
folder=string(tempname); guard=onCleanup(@() cleanup(folder)); %#ok<NASGU>
r=run_glottic_analysis(tc.TestData.workbook,folder,MakeFigures=false,BootstrapResamples=50);
verifyTrue(tc,isfile(r.outputFiles.report)); verifyTrue(tc,isfile(r.outputFiles.json));
verifyTrue(tc,isfile(r.outputFiles.workbook)); verifyTrue(tc,isfile(fullfile(folder,'Manifest.json')));
t=readtable(r.outputFiles.workbook,'Sheet','Continuous');
verifyEqual(tc,height(t),16); verifyEqual(tc,t.Delta_Mean,tc.TestData.r.tables.Continuous.Delta_Mean,'AbsTol',1e-10);
verifyError(tc,@() run_glottic_analysis(tc.TestData.workbook,folder,MakeFigures=false),'glottic:OutputExists');
end

function testGUIConstructionAndError(tc)
a=AnalysisDataOfGlotticCancer('file-that-does-not-exist.xlsx',tempdir,Visible='off');
guard=onCleanup(@() delete(a)); %#ok<NASGU>
verifyEqual(tc,a.Name,'Analysis Data of glottic cancer');
s=a.UserData; s.RunButton.ButtonPushedFcn([],[]); s=a.UserData;
verifyNotEmpty(tc,s.LastError);
verifyTrue(tc,startsWith(s.Status.Text,'Analysis stopped:'));
verifyEmpty(tc,s.Results);
end

function cleanup(folder)
if isfolder(folder), rmdir(folder,'s'); end
end
