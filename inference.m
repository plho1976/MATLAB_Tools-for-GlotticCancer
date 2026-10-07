function output = inference(action, varargin)
%INFERENCE Toolbox-free paired-plan inference and descriptive statistics.
%   The dispatch actions are quantile, describe, meanCI, pairedT, wilcoxon,
%   proportion, mcnemar, correlation, and holm. Missing or nonfinite numeric
%   observations are excluded; correlations exclude pairs jointly. Quantiles
%   use NumPy's linear interpolation (h = 1 + (n-1)*p).
%   Paired differences must be IMRT minus 3DCRT. All tests are two-sided.

switch lower(string(action))
    case "quantile"
        output = linearQuantile(varargin{1}, varargin{2});
    case "describe"
        output = describe(varargin{1});
    case "meanci"
        output = meanCI(varargin{1});
    case "pairedt"
        output = pairedT(varargin{1});
    case "wilcoxon"
        output = exactWilcoxon(varargin{1});
    case "proportion"
        output = proportion(varargin{1}, varargin{2});
    case "mcnemar"
        output = exactMcNemar(varargin{1}, varargin{2});
    case "correlation"
        output = correlation(varargin{1}, varargin{2});
    case "holm"
        output = holm(varargin{1});
    otherwise
        error('glottic:UnknownInferenceAction', ...
            'Unknown inference action: %s.', string(action));
end
end

function [x, omitted] = finiteValues(x)
validateattributes(x, {'numeric'}, {'real', 'vector'}, mfilename, 'x');
x = double(x(:));
keep = isfinite(x);
omitted = nnz(~keep);
x = x(keep);
end

function q = linearQuantile(x, p)
[x, ~] = finiteValues(x);
validateattributes(p, {'numeric'}, {'real', 'finite', '>=', 0, '<=', 1}, ...
    mfilename, 'p');
shape = size(p);
p = double(p(:));
if isempty(x)
    q = reshape(nan(size(p)), shape);
    return
end
x = sort(x);
h = 1 + (numel(x)-1)*p;
lo = floor(h);
hi = ceil(h);
q = x(lo) + (h-lo).*(x(hi)-x(lo));
q = reshape(q, shape);
end

function result = describe(values)
[x, omitted] = finiteValues(values);
result = struct('n', numel(x), 'n_undefined', omitted, ...
    'mean', NaN, 'sd', NaN, 'median', NaN, 'q1', NaN, 'q3', NaN, ...
    'min', NaN, 'max', NaN);
if isempty(x)
    return
end
result.mean = mean(x);
if numel(x) > 1
    result.sd = std(x, 0); % Sample SD; denominator n-1.
end
quartiles = linearQuantile(x, [.25 .5 .75]);
result.q1 = quartiles(1);
result.median = quartiles(2);
result.q3 = quartiles(3);
result.min = min(x);
result.max = max(x);
end

function ci = meanCI(values)
[x, ~] = finiteValues(values);
n = numel(x);
if n < 2
    ci = [NaN NaN];
    return
end
margin = tCritical(.975, n-1)*std(x, 0)/sqrt(n);
ci = mean(x) + [-margin margin];
end

function result = pairedT(values)
[d, omitted] = finiteValues(values);
n = numel(d);
result = struct('t', NaN, 'df', n-1, 'p_two_sided', NaN, ...
    'n', n, 'n_undefined', omitted);
if n < 2
    return
end
m = mean(d);
se = std(d, 0)/sqrt(n);
if se == 0
    if m == 0
        result.t = 0;
        result.p_two_sided = 1;
    else
        result.t = sign(m)*Inf;
        result.p_two_sided = 0;
    end
else
    result.t = m/se;
    result.p_two_sided = tTwoSided(result.t, n-1);
end
end

function p = tTwoSided(t, df)
if isnan(t) || df <= 0
    p = NaN;
elseif isinf(t)
    p = 0;
else
    p = betainc(df/(df+t*t), df/2, .5);
end
end

function critical = tCritical(p, df)
if p == .5
    critical = 0;
    return
end
tail = 2*min(p, 1-p);
z = betaincinv(tail, df/2, .5);
critical = sign(p-.5)*sqrt(df*(1-z)/z);
end

function result = exactWilcoxon(values)
[d, omitted] = finiteValues(values);
% Ranking alone removes arithmetic artifacts much finer than source precision.
d = round(d, 8);
d = d(d ~= 0);
n = numel(d);
result = struct('statistic', 0, 'p_two_sided', 1, 'n_nonzero', n, ...
    'n_undefined', omitted, ...
    'method', ['exact random-sign distribution, dynamic programming on ' ...
    'twice the midranks; zeros omitted; differences rounded to 8 decimals']);
if n == 0
    return
end
weights = round(2*midranks(abs(d)));
positiveSum = sum(weights(d > 0));
total = sum(weights);
observed = min(positiveSum, total-positiveSum);
% Probabilities, instead of integer assignment counts, avoid 2^n overflow.
probability = zeros(1, total+1);
probability(1) = 1;
reached = 0;
for i = 1:n
    weight = weights(i);
    next = .5*probability;
    destination = weight+(1:reached+1);
    next(destination) = next(destination) + .5*probability(1:reached+1);
    probability = next;
    reached = reached+weight;
end
result.statistic = observed/2;
result.p_two_sided = min(1, 2*sum(probability(1:observed+1)));
end

function ranks = midranks(x)
[ordered, indices] = sort(x);
ranks = zeros(size(x));
i = 1;
while i <= numel(x)
    j = i;
    while j < numel(x) && ordered(j+1) == ordered(i)
        j = j+1;
    end
    ranks(indices(i:j)) = (i+j)/2;
    i = j+1;
end
end

function result = proportion(k, n)
validateattributes(n, {'numeric'}, {'scalar', 'real', 'finite', ...
    'integer', 'nonnegative'}, mfilename, 'n');
validateattributes(k, {'numeric'}, {'scalar', 'real', 'finite', ...
    'integer', 'nonnegative', '<=', n}, mfilename, 'k');
result = struct('count', double(k), 'denominator', double(n), ...
    'percent', NaN, 'exact_95CI_percent', [NaN NaN], ...
    'status', 'undefined: empty conditional subset');
if n == 0
    return
end
lo = 0;
hi = 1;
if k > 0
    lo = betaincinv(.025, k, n-k+1);
end
if k < n
    hi = betaincinv(.975, k+1, n-k);
end
result.percent = 100*k/n;
result.exact_95CI_percent = 100*[lo hi];
result.status = 'defined';
end

function p = exactMcNemar(b, c)
validateattributes(b, {'numeric'}, {'scalar', 'real', 'finite', ...
    'integer', 'nonnegative'}, mfilename, 'b');
validateattributes(c, {'numeric'}, {'scalar', 'real', 'finite', ...
    'integer', 'nonnegative'}, mfilename, 'c');
n = double(b+c);
if n == 0
    p = 1;
else
    k = double(min(b, c));
    % P(Binomial(n,.5) <= k), evaluated using the regularized beta function.
    p = min(1, 2*betainc(.5, n-k, k+1));
end
end

function result = correlation(x, y)
validateattributes(x, {'numeric'}, {'real', 'vector'}, mfilename, 'x');
validateattributes(y, {'numeric'}, {'real', 'vector', 'numel', numel(x)}, ...
    mfilename, 'y');
x = double(x(:));
y = double(y(:));
keep = isfinite(x) & isfinite(y);
omitted = nnz(~keep);
x = x(keep);
y = y(keep);
n = numel(x);
result = struct('spearman_rho', NaN, 'spearman_p_two_sided', NaN, ...
    'pearson_r', NaN, 'pearson_p_two_sided', NaN, ...
    'pearson_fisher_95CI', [NaN NaN], 'n', n, 'n_undefined', omitted, ...
    'status', 'undefined: fewer than 4 finite pairs');
if n < 4
    return
end
if all(x == x(1)) || all(y == y(1))
    result.status = 'undefined: constant variable';
    return
end
r = pearsonCoefficient(x, y);
rho = pearsonCoefficient(midranks(x), midranks(y));
result.pearson_r = r;
result.spearman_rho = rho;
result.pearson_p_two_sided = correlationP(r, n);
result.spearman_p_two_sided = correlationP(rho, n);
% Match the reference's finite clamp at perfect correlation for Fisher z.
z = atanh(max(-.999999999999999, min(.999999999999999, r)));
normalCritical = sqrt(2)*erfinv(.95);
margin = normalCritical/sqrt(n-3);
result.pearson_fisher_95CI = tanh(z + [-margin margin]);
result.status = ['exploratory, unadjusted; Spearman p uses t approximation; ' ...
    'no causal interpretation'];
end

function r = pearsonCoefficient(x, y)
x = x-mean(x);
y = y-mean(y);
% Scaling first avoids an unnecessary overflow in sum(x.^2)*sum(y.^2).
x = x/norm(x);
y = y/norm(y);
r = max(-1, min(1, sum(x.*y)));
end

function p = correlationP(r, n)
if abs(r) >= 1
    p = 0;
else
    t = r*sqrt((n-2)/(1-r*r));
    p = tTwoSided(t, n-2);
end
end

function adjusted = holm(p)
validateattributes(p, {'numeric'}, {'real', 'vector'}, mfilename, 'p');
shape = size(p);
p = double(p(:));
if any(isinf(p) | (isfinite(p) & (p < 0 | p > 1)))
    error('glottic:InvalidPValue', 'P values must be in [0,1] or NaN.');
end
adjusted = nan(size(p));
valid = find(isfinite(p));
[ordered, order] = sort(p(valid));
m = numel(ordered);
running = 0;
for i = 1:m
    running = max(running, (m-i+1)*ordered(i));
    adjusted(valid(order(i))) = min(1, running);
end
adjusted = reshape(adjusted, shape);
end
