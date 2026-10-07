function data = importWorkbook(workbookPath, expectedPairs)
%IMPORTWORKBOOK Import and validate the DataLanPhuong SO LIEU paired layout.
%   DATA = glottic.importWorkbook(PATH) requires the reference 30-pair cohort,
%   with current anonymous P01-P30 IDs in sequential order. Pass [] as the
%   second argument to accept a research cohort of 4-99 unique Pxx pairs.
%   Only selected raw values, technique labels, and current anonymous IDs are
%   retained. Legacy identifiers in A:C and the separate Sheet1 are not read.
%   Formulas in selected data, headers, or pair labels are rejected, even if
%   cached numeric values exist. All composites and deltas are recomputed.

if nargin < 2
    expectedPairs = 30;
end
workbookPath = string(workbookPath);
if ~isscalar(workbookPath) || ismissing(workbookPath) || ~isfile(workbookPath)
    error('glottic:importWorkbook:MissingFile', 'Select an existing Excel workbook.');
end
if ~isempty(expectedPairs) && (~isnumeric(expectedPairs) || ~isscalar(expectedPairs) ...
        || ~isfinite(expectedPairs) || expectedPairs ~= fix(expectedPairs) ...
        || expectedPairs < 4 || expectedPairs > 99)
    error('glottic:importWorkbook:InvalidExpectedPairs', 'expectedPairs must be [] or an integer from 4 to 99.');
end
[~, sourceName, extension] = fileparts(workbookPath);
if ~any(strcmpi(extension, [".xlsx", ".xlsm"]))
    error('glottic:importWorkbook:UnsupportedFile', 'Use an OOXML Excel workbook (.xlsx or .xlsm).');
end
sheet = "SO LIEU";
rawKeys = ["ptv_D99_9_Gy"; "ptv_D95_Gy"; "ptv_V66_percent"; ...
    "ptv_Dmean_Gy"; "ptv_Dmin_Gy"; "ptv_Dmax_Gy"; ...
    "carotid_L_Dmean_Gy"; "carotid_L_Dmin_Gy"; "carotid_L_Dmax_Gy"; ...
    "carotid_R_Dmean_Gy"; "carotid_R_Dmin_Gy"; "carotid_R_Dmax_Gy"; ...
    "thyroid_Dmean_Gy"];
metricHeaders = ["D99.9% PTV"; "D95% PTV"; "V66Gy PTV"; ...
    "Mean PTV"; "Min PTV"; "Max PTV"; ...
    "Carotid L Mean"; "Carotid L Min"; "Carotid L Max"; ...
    "Carotid R Mean"; "Carotid R Min"; "Carotid R Max"; "Thyroid Mean"];

% The layout probe uses D only, so no legacy A:C identifier is accessed.
cells = inspectWorksheet(workbookPath, sheet);
rejectFormulas(cells, ["D2"; "D3"]);
probe = readBlock(workbookPath, sheet, 2, 3, 4, 4);
current = normalizedText(probe{1, 1}) == "D99.9% PTV";
legacy = normalizedText(probe{2, 1}) == "Kthuat";
if current && legacy
    error('glottic:importWorkbook:UnknownLayout', 'Conflicting current and legacy SO LIEU layout headers.');
end
if current
    headerRow = 2; firstRow = 3; techniqueColumn = 3;
    metricColumns = [4:12, 15:17, 20];
    selectedColumns = [1, techniqueColumn, metricColumns];
elseif legacy
    headerRow = 3; firstRow = 4; techniqueColumn = 4;
    metricColumns = [5:13, 16:18, 21];
    selectedColumns = [techniqueColumn, metricColumns];
else
    error('glottic:importWorkbook:UnknownLayout', ...
        'SO LIEU does not match the current D2 header or the legacy D3 Kthuat header.');
end

safe = ismember(cells.column, selectedColumns) & cells.row >= (headerRow - double(current));
rejectFormulas(cells, cells.coordinate(safe));
lastRow = max([headerRow; cells.row(safe & cells.hasValue)]);
if lastRow > 10000
    error('glottic:importWorkbook:UnexpectedExtent', 'SO LIEU selected data extend beyond row 10000.');
end

% Separate ranges avoid the year column and unanalysed V35/V50 columns.
raw = cell(lastRow, numel(rawKeys));
raw(:, 1:9) = readBlock(workbookPath, sheet, 1, lastRow, metricColumns(1), metricColumns(9));
raw(:, 10:12) = readBlock(workbookPath, sheet, 1, lastRow, metricColumns(10), metricColumns(12));
raw(:, 13) = readBlock(workbookPath, sheet, 1, lastRow, metricColumns(13), metricColumns(13));
techniques = readBlock(workbookPath, sheet, 1, lastRow, techniqueColumn, techniqueColumn);
if current
    % Validate the Patient header before touching current ID values in A.
    requireHeader(techniques{headerRow}, "Treatment planning", "C2");
    header = readBlock(workbookPath, sheet, headerRow, headerRow, 1, 1);
    requireHeader(header{1}, "Patient", "A2");
    ids = readBlock(workbookPath, sheet, 1, lastRow, 1, 1);
else
    requireHeader(techniques{headerRow}, "Kthuat", "D3");
    ids = cell(lastRow, 1);
end
for j = 1:numel(rawKeys)
    coordinate = excelColumn(metricColumns(j)) + string(headerRow);
    requireHeader(raw{headerRow, j}, metricHeaders(j), coordinate);
    if current
        unit = "Gy";
        if rawKeys(j) == "ptv_V66_percent", unit = "%"; end
        if normalizedText(raw{1, j}) ~= unit
            error('glottic:importWorkbook:UnitMismatch', ...
                'SO LIEU!%s must contain the unit %s.', excelColumn(metricColumns(j)) + "1", unit);
        end
    end
end

crt = zeros(0, numel(rawKeys)); imrt = crt;
patientIDs = strings(0, 1); sourceLabels = strings(0, 1);
r = firstRow;
while r <= lastRow
    active = ~isBlank(techniques{r}) || any(~cellfun(@isBlank, raw(r, :)));
    if current, active = active || ~isBlank(ids{r}); end
    if ~active, r = r + 1; continue; end
    firstLabel = normalizedText(techniques{r});
    if r >= lastRow
        pairError(r, techniqueColumn, 'A second technique row is missing.');
    end
    nextLabel = normalizedText(techniques{r + 1});
    if current
        validFirst = any(firstLabel == ["3DCRT/PCB", "3DCRT/PBC"]);
        validNext = nextLabel == "IMRT/AAA";
    else
        validFirst = firstLabel == "3D"; validNext = nextLabel == "IMRT";
    end
    if ~validFirst || ~validNext
        pairError(r, techniqueColumn, 'Expected adjacent 3DCRT then IMRT technique labels.');
    end
    if current
        pid = normalizedText(ids{r}); nextID = normalizedText(ids{r + 1});
        if isempty(regexp(char(pid), '^P(0[1-9]|[1-9][0-9])$', 'once')) || pid ~= nextID
            error('glottic:importWorkbook:InvalidPairID', ...
                'SO LIEU!A%d:A%d must contain the same anonymous P01-P99 ID.', r, r + 1);
        end
        pid = extractAfter(pid, 1);
        if any(patientIDs == pid)
            error('glottic:importWorkbook:DuplicatePair', 'Duplicate anonymous pair ID at SO LIEU!A%d.', r);
        end
    else
        pid = compose('%02d', numel(patientIDs) + 1);
    end
    pairValues = zeros(2, numel(rawKeys));
    for k = 1:2
        for j = 1:numel(rawKeys)
            coordinate = excelColumn(metricColumns(j)) + string(r + k - 1);
            pairValues(k, j) = measurement(raw{r + k - 1, j}, rawKeys(j), current, coordinate);
        end
    end
    patientIDs(end + 1, 1) = pid; %#ok<AGROW>
    crt(end + 1, :) = pairValues(1, :); %#ok<AGROW>
    imrt(end + 1, :) = pairValues(2, :); %#ok<AGROW>
    sourceLabels = [sourceLabels; firstLabel; nextLabel]; %#ok<AGROW>
    r = r + 2;
end
n = numel(patientIDs);
if n < 4 || n > 99 || (~isempty(expectedPairs) && n ~= expectedPairs)
    if isempty(expectedPairs), expectedDescription = '4-99'; else, expectedDescription = num2str(expectedPairs); end
    error('glottic:importWorkbook:PairCount', 'Expected %s complete pairs; found %d.', expectedDescription, n);
end
if current && ~isempty(expectedPairs) && ~isequal(patientIDs, compose('%02d', (1:n)'))
    error('glottic:importWorkbook:PairOrder', 'Expected sequential anonymous IDs P01-P%02d in workbook order.', n);
end
data = struct('patient_id', patientIDs, 'CRT', struct(), 'IMRT', struct());
for j = 1:numel(rawKeys)
    data.CRT.(char(rawKeys(j))) = crt(:, j);
    data.IMRT.(char(rawKeys(j))) = imrt(:, j);
end
metadata = struct('source_type', 'original workbook', 'source_sheet', char(sheet), ...
    'source_file', char(sourceName + extension), 'source_sha256', sha256File(workbookPath), ...
    'source_technique_labels', unique(sourceLabels), ...
    'formula_cells_in_analyzed_values', strings(0, 1), ...
    'formula_policy', 'Literal source cells required; formulas in selected headers, labels, IDs and measurements rejected.', ...
    'analyzed_raw_cell_count', 2 * n * numel(rawKeys), 'status', 'validated');
if current
    metadata.workbook_layout = 'current: two header rows; V66 already percent';
    metadata.read_columns = 'anonymous pair IDs A; technique C; selected raw metrics D:L, O:Q, T; year B and Sheet1 excluded';
    metadata.algorithm_label_normalization = ...
        'Source 3DCRT/PCB is interpreted as PBC per the planning report; IMRT/AAA is retained.';
else
    metadata.workbook_layout = 'legacy: three header rows; V66 fraction converted to percent';
    metadata.read_columns = 'technique D; selected raw metrics E:M, P:R, U; identifiers A:C and Sheet1 excluded';
    metadata.algorithm_label_normalization = 'Legacy labels 3D and IMRT do not encode dose-calculation algorithms.';
end
data.metadata = metadata;
data = glottic.deriveData(data);
end

function values = readBlock(path, sheet, firstRow, lastRow, firstColumn, lastColumn)
range = excelColumn(firstColumn) + string(firstRow) + ":" + excelColumn(lastColumn) + string(lastRow);
try
    values = readcell(path, 'Sheet', sheet, 'Range', range, 'UseExcel', false);
catch exception
    error('glottic:importWorkbook:ReadFailure', 'Could not read SO LIEU!%s: %s', range, exception.message);
end
expectedSize = [lastRow - firstRow + 1, lastColumn - firstColumn + 1];
if any(size(values) > expectedSize)
    error('glottic:importWorkbook:ReadFailure', 'Unexpected range size for SO LIEU!%s.', range);
end
if ~isequal(size(values), expectedSize)
    padded = cell(expectedSize); padded(1:size(values, 1), 1:size(values, 2)) = values; values = padded;
end
end

function text = normalizedText(value)
text = "";
if (isstring(value) && isscalar(value) && ~ismissing(value)) || ischar(value)
    text = string(strtrim(regexprep(char(value), '\s+', ' ')));
end
end

function yes = isBlank(value)
yes = isempty(value);
if yes, return; end
% readcell can use a scalar MATLAB missing object for an empty Excel cell.
% Check the generic missing predicate before relying on a storage type.
if isscalar(value) && ismissing(value)
    yes = true;
    return;
end
if isstring(value), yes = isscalar(value) && (ismissing(value) || strlength(strtrim(value)) == 0);
elseif ischar(value), yes = isempty(strtrim(value));
elseif isnumeric(value), yes = isscalar(value) && isnan(value);
end
end

function requireHeader(value, expected, coordinate)
if normalizedText(value) ~= expected
    error('glottic:importWorkbook:HeaderMismatch', 'SO LIEU!%s must contain the header "%s".', coordinate, expected);
end
end

function pairError(row, column, explanation)
error('glottic:importWorkbook:IncompletePair', 'SO LIEU!%s%d:%s%d: %s', ...
    excelColumn(column), row, excelColumn(column), row + 1, explanation);
end

function number = measurement(value, key, current, coordinate)
if isBlank(value)
    error('glottic:importWorkbook:MissingMeasurement', 'Missing numeric measurement at SO LIEU!%s.', coordinate);
end
if isnumeric(value) && isreal(value) && isscalar(value) && ~islogical(value)
    number = double(value);
elseif ~current && (ischar(value) || (isstring(value) && isscalar(value)))
    numberPattern = '([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)';
    if key == "ptv_V66_percent"
        pattern = ['^\s*' numberPattern '\s*$'];
    else
        pattern = ['^\s*' numberPattern '\s*Gy\s*$'];
    end
    token = regexp(char(value), pattern, 'tokens', 'once');
    if isempty(token)
        error('glottic:importWorkbook:InvalidMeasurement', ...
            'Invalid legacy measurement at SO LIEU!%s; dose text must include Gy and V66 must be a fraction.', coordinate);
    end
    number = str2double(token{1});
else
    error('glottic:importWorkbook:InvalidMeasurement', 'Expected a numeric literal at SO LIEU!%s.', coordinate);
end
if ~isfinite(number) || number < 0
    error('glottic:importWorkbook:InvalidMeasurement', 'SO LIEU!%s must contain a finite nonnegative measurement.', coordinate);
end
if key == "ptv_V66_percent"
    upper = 100;
    if ~current, upper = 1; end
    if number > upper
        error('glottic:importWorkbook:InvalidV66', 'SO LIEU!%s V66 must be in [0,%g] for this layout.', coordinate, upper);
    end
    if ~current, number = number * 100; end
end
end

function column = excelColumn(number)
column = "";
while number > 0
    digit = mod(number - 1, 26);
    column = string(char(65 + digit)) + column;
    number = floor((number - 1) / 26);
end
end

function result = inspectWorksheet(path, requestedSheet)
% Inspect only OOXML coordinates and formula flags. No cell text is decoded.
try
    archive = javaObject('java.util.zip.ZipFile', char(path));
    archiveCleanup = onCleanup(@() archive.close()); %#ok<NASGU>
    workbook = xmlEntry(archive, 'xl/workbook.xml');
    sheets = workbook.getElementsByTagNameNS('*', 'sheet'); relationID = '';
    for index = 0:sheets.getLength() - 1
        node = sheets.item(index);
        if strcmp(char(node.getAttribute('name')), requestedSheet)
            relationID = char(node.getAttribute('r:id')); break;
        end
    end
    if isempty(relationID)
        error('glottic:importWorkbook:MissingSheet', 'Workbook must contain the SO LIEU worksheet.');
    end
    relationships = xmlEntry(archive, 'xl/_rels/workbook.xml.rels');
    relations = relationships.getElementsByTagNameNS('*', 'Relationship'); target = '';
    for index = 0:relations.getLength() - 1
        node = relations.item(index);
        if strcmp(char(node.getAttribute('Id')), relationID)
            if strcmpi(char(node.getAttribute('TargetMode')), 'External')
                error('glottic:importWorkbook:InvalidArchive', 'SO LIEU must be an internal worksheet.');
            end
            target = char(node.getAttribute('Target')); break;
        end
    end
    if isempty(target)
        error('glottic:importWorkbook:InvalidArchive', 'SO LIEU worksheet relationship is missing.');
    end
    if startsWith(target, '/')
        entryName = extractAfter(string(target), 1);
    else
        uri = javaObject('java.net.URI', 'xl/workbook.xml');
        entryName = string(char(uri.resolve(target).normalize().toString()));
    end
    if isempty(regexp(char(entryName), '^xl/worksheets/[^/]+\.xml$', 'once'))
        error('glottic:importWorkbook:InvalidArchive', 'Unexpected SO LIEU worksheet location.');
    end
    document = xmlEntry(archive, char(entryName));
    nodes = document.getElementsByTagNameNS('*', 'c'); n = double(nodes.getLength());
    coordinate = strings(n, 1); row = zeros(n, 1); column = row;
    hasFormula = false(n, 1); hasValue = hasFormula;
    for index = 1:n
        node = nodes.item(index - 1);
        coordinate(index) = string(char(node.getAttribute('r')));
        token = regexp(char(coordinate(index)), '^([A-Z]+)([1-9]\d*)$', 'tokens', 'once');
        if isempty(token)
            error('glottic:importWorkbook:InvalidArchive', 'Invalid worksheet cell coordinate.');
        end
        row(index) = str2double(token{2});
        letters = double(token{1}) - 64;
        column(index) = sum(letters .* 26 .^ (numel(letters) - 1:-1:0));
        hasFormula(index) = node.getElementsByTagNameNS('*', 'f').getLength() > 0;
        hasValue(index) = hasFormula(index) || node.getElementsByTagNameNS('*', 'v').getLength() > 0 ...
            || node.getElementsByTagNameNS('*', 'is').getLength() > 0;
    end
    result = table(coordinate, row, column, hasFormula, hasValue);
catch exception
    if startsWith(exception.identifier, 'glottic:importWorkbook:')
        rethrow(exception);
    end
    error('glottic:importWorkbook:InvalidArchive', 'Unable to inspect workbook OOXML: %s', exception.message);
end
end

function document = xmlEntry(archive, name)
entry = archive.getEntry(name);
if isempty(entry)
    error('glottic:importWorkbook:InvalidArchive', 'Required workbook OOXML entry is missing: %s.', name);
end
factory = javaMethod('newInstance', 'javax.xml.parsers.DocumentBuilderFactory');
factory.setNamespaceAware(true);
factory.setFeature('http://apache.org/xml/features/disallow-doctype-decl', true);
builder = factory.newDocumentBuilder();
stream = archive.getInputStream(entry);
streamCleanup = onCleanup(@() stream.close()); %#ok<NASGU>
document = builder.parse(stream);
end

function rejectFormulas(cells, selectedCoordinates)
formulaCoordinates = cells.coordinate(cells.hasFormula & ismember(cells.coordinate, selectedCoordinates));
if ~isempty(formulaCoordinates)
    error('glottic:importWorkbook:FormulaCell', ...
        'Formula at SO LIEU!%s. Replace selected formula cells with audited literal values before import.', formulaCoordinates(1));
end
end

function digest = sha256File(path)
handle = fopen(path, 'rb');
if handle < 0
    error('glottic:importWorkbook:ReadFailure', 'Unable to read workbook for its SHA-256 audit hash.');
end
cleanup = onCleanup(@() fclose(handle)); %#ok<NASGU>
engine = javaMethod('getInstance', 'java.security.MessageDigest', 'SHA-256');
while ~feof(handle)
    bytes = fread(handle, 1024 * 1024, '*uint8');
    if ~isempty(bytes), engine.update(typecast(bytes(:), 'int8')); end
end
bytes = typecast(engine.digest(), 'uint8');
digest = lower(reshape(dec2hex(bytes, 2).', 1, []));
end
