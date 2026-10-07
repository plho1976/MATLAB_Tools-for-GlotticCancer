function tests = test_inference
%TEST_INFERENCE Audited reference checks and missing/degenerate data cases.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
packageRoot = fileparts(fileparts(mfilename('fullpath')));
testCase.TestData.OriginalPath = path;
addpath(packageRoot);
end

function teardownOnce(testCase)
path(testCase.TestData.OriginalPath);
end

function testReferenceTCritical29(testCase)
x = (1:30)';
ci = glottic.inference('meanCI', x);
critical = (ci(2)-mean(x))*sqrt(numel(x))/std(x, 0);
verifyEqual(testCase, critical, 2.045229642132703, 'AbsTol', 1e-10);
end

function testReferenceTCritical1(testCase)
x = [0; 2];
ci = glottic.inference('meanCI', x);
critical = (ci(2)-mean(x))*sqrt(numel(x))/std(x, 0);
verifyEqual(testCase, critical, 12.7062047364321, 'AbsTol', 1e-9);
end

function testReferenceTPHalf(testCase)
result = glottic.inference('pairedT', [0 2]);
verifyEqual(testCase, result.t, 1, 'AbsTol', 1e-14);
verifyEqual(testCase, result.p_two_sided, .5, 'AbsTol', 1e-12);
end

function testReferenceMcNemar0Versus14(testCase)
p = glottic.inference('mcnemar', 0, 14);
verifyEqual(testCase, p, 2/2^14, 'AbsTol', 1e-15);
end

function testReferenceWilcoxonAll30(testCase)
result = glottic.inference('wilcoxon', 1:30);
verifyEqual(testCase, result.p_two_sided, 2/2^30, 'AbsTol', 1e-20);
verifyEqual(testCase, result.statistic, 0);
end

function testReferenceWilcoxonTiedThree(testCase)
result = glottic.inference('wilcoxon', [1 1 1]);
verifyEqual(testCase, result.p_two_sided, .25, 'AbsTol', 1e-15);
end

function testReferenceClopperPearsonZero30(testCase)
result = glottic.inference('proportion', 0, 30);
verifyEqual(testCase, result.exact_95CI_percent, ...
    [0 100*(1-.025^(1/30))], 'AbsTol', 1e-10);
end

function testReferenceClopperPearsonAll30(testCase)
result = glottic.inference('proportion', 30, 30);
verifyEqual(testCase, result.exact_95CI_percent, ...
    [100*.025^(1/30) 100], 'AbsTol', 1e-10);
end

function testLinearQuantileAndOmissions(testCase)
q = glottic.inference('quantile', [1 2 3 4 NaN Inf], [0 .25 .5 .75 1]);
verifyEqual(testCase, q, [1 1.75 2.5 3.25 4], 'AbsTol', 1e-14);
result = glottic.inference('describe', [1 2 3 4 NaN Inf]);
verifyEqual(testCase, result.n, 4);
verifyEqual(testCase, result.n_undefined, 2);
verifyEqual(testCase, result.sd, sqrt(5/3), 'AbsTol', 1e-14);
verifyEqual(testCase, result.q1, 1.75, 'AbsTol', 1e-14);
end

function testEmptyAndSingletonSummary(testCase)
result = glottic.inference('describe', [NaN Inf]);
verifyEqual(testCase, result.n, 0);
verifyEqual(testCase, result.n_undefined, 2);
verifyTrue(testCase, isnan(result.mean));
result = glottic.inference('describe', 7);
verifyEqual(testCase, result.mean, 7);
verifyTrue(testCase, isnan(result.sd));
ci = glottic.inference('meanCI', 7);
verifyTrue(testCase, all(isnan(ci)));
end

function testConstantDifferences(testCase)
zero = glottic.inference('pairedT', zeros(4, 1));
verifyEqual(testCase, zero.t, 0);
verifyEqual(testCase, zero.p_two_sided, 1);
constant = glottic.inference('pairedT', -ones(4, 1));
verifyEqual(testCase, constant.t, -Inf);
verifyEqual(testCase, constant.p_two_sided, 0);
ci = glottic.inference('meanCI', ones(4, 1));
verifyEqual(testCase, ci, [1 1]);
end

function testWilcoxonZerosRoundingAndMixedTies(testCase)
zero = glottic.inference('wilcoxon', [0 0 0 1e-10 NaN]);
verifyEqual(testCase, zero.n_nonzero, 0);
verifyEqual(testCase, zero.p_two_sided, 1);
mixed = glottic.inference('wilcoxon', [1 -1 2 -2]);
verifyEqual(testCase, mixed.statistic, 5);
verifyEqual(testCase, mixed.p_two_sided, 1);
tied = glottic.inference('wilcoxon', [1 1+1e-10 1]);
verifyEqual(testCase, tied.p_two_sided, .25);
end

function testWilcoxonBeyondIntegerCounts(testCase)
result = glottic.inference('wilcoxon', ones(100, 1));
verifyEqual(testCase, result.p_two_sided, 2^(-99), 'RelTol', 1e-14);
end

function testEmptyConditionalProportionAndNoDiscordance(testCase)
result = glottic.inference('proportion', 0, 0);
verifyTrue(testCase, isnan(result.percent));
verifyTrue(testCase, all(isnan(result.exact_95CI_percent)));
verifyEqual(testCase, result.status, 'undefined: empty conditional subset');
verifyEqual(testCase, glottic.inference('mcnemar', 0, 0), 1);
verifyEqual(testCase, glottic.inference('mcnemar', 3, 3), 1);
end

function testCorrelationJointFiltering(testCase)
result = glottic.inference('correlation', [1 2 3 4 NaN 6], ...
    [4 3 2 1 9 Inf]);
verifyEqual(testCase, result.n, 4);
verifyEqual(testCase, result.n_undefined, 2);
verifyEqual(testCase, result.pearson_r, -1, 'AbsTol', 1e-14);
verifyEqual(testCase, result.spearman_rho, -1, 'AbsTol', 1e-14);
verifyLessThan(testCase, result.pearson_p_two_sided, 1e-14);
verifyTrue(testCase, all(isfinite(result.pearson_fisher_95CI)));
end

function testUndefinedCorrelations(testCase)
constant = glottic.inference('correlation', ones(4, 1), (1:4)');
verifyTrue(testCase, isnan(constant.pearson_r));
verifyEqual(testCase, constant.status, 'undefined: constant variable');
small = glottic.inference('correlation', [1 2 3], [1 3 2]);
verifyTrue(testCase, isnan(small.spearman_rho));
verifyEqual(testCase, small.n, 3);
end

function testHolmOrderAndShape(testCase)
adjusted = glottic.inference('holm', [.04 .01 .03 .5]);
verifyEqual(testCase, adjusted, [.09 .04 .09 .5], 'AbsTol', 1e-14);
adjusted = glottic.inference('holm', [.03; NaN; .01]);
verifyEqual(testCase, adjusted([1 3]), [.03; .02], 'AbsTol', 1e-14);
verifyTrue(testCase, isnan(adjusted(2)));
end
