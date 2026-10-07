function tests = test_importWorkbook
%TEST_IMPORTWORKBOOK Schema, privacy, pairing and derivation regression tests.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
end

function testCurrentSchemaAndDerivation(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
data = glottic.importWorkbook(path, []);
testCase.verifyEqual(data.patient_id, ["01"; "02"; "03"; "04"]);
testCase.verifyEqual(data.n, 4);
testCase.verifyEqual(numel(data.metricKeys), 16);
testCase.verifySize(data.patientTable, [4, 49]);
testCase.verifyEqual(data.CRT.carotid_worse_Dmean_Gy, ...
    max(data.CRT.carotid_L_Dmean_Gy, data.CRT.carotid_R_Dmean_Gy));
testCase.verifyEqual(data.patientTable.delta_ptv_D95_Gy, ...
    data.IMRT.ptv_D95_Gy - data.CRT.ptv_D95_Gy);
testCase.verifyEqual(data.CRT.ptv_V66_percent, repmat(95.4, 4, 1), 'AbsTol', 1e-12);
testCase.verifyEmpty(data.metadata.formula_cells_in_analyzed_values);
testCase.verifyEqual(strlength(string(data.metadata.source_sha256)), 64);
testCase.verifyEqual(data.metadata.status, 'validated');
end

function testReferenceCohortCountAndOrdering(testCase)
[path, cleanup] = fixture(30, false); %#ok<ASGLU>
data = glottic.importWorkbook(path);
testCase.verifyEqual(data.n, 30);
writecell({'P31'; 'P31'}, path, 'Sheet', 'SO LIEU', 'Range', 'A3:A4', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path), 'glottic:importWorkbook:PairOrder');
end

function testFlexibleCohortPreservesUniqueWorkbookOrder(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
writecell({'P99'; 'P99'}, path, 'Sheet', 'SO LIEU', 'Range', 'A3:A4', 'UseExcel', false);
data = glottic.importWorkbook(path, []);
testCase.verifyEqual(data.patient_id, ["99"; "02"; "03"; "04"]);
testCase.verifyError(@() glottic.importWorkbook(path), 'glottic:importWorkbook:PairCount');
end

function testHeaderMustMatchExactly(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
writecell({'D98% PTV'}, path, 'Sheet', 'SO LIEU', 'Range', 'E2', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:HeaderMismatch');
end

function testCurrentUnitsRequired(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
writecell({'cGy'}, path, 'Sheet', 'SO LIEU', 'Range', 'D1', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:UnitMismatch');
end

function testMissingValueFailsWithCoordinate(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
writecell({''}, path, 'Sheet', 'SO LIEU', 'Range', 'J4', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:MissingMeasurement');
try
    glottic.importWorkbook(path, []);
catch exception
    testCase.verifySubstring(exception.message, 'J4');
end
end

function testDuplicatePairIDRejected(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
writecell({'P01'; 'P01'}, path, 'Sheet', 'SO LIEU', 'Range', 'A5:A6', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:DuplicatePair');
end

function testMismatchedAndIncompletePairsRejected(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
writecell({'P02'}, path, 'Sheet', 'SO LIEU', 'Range', 'A4', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:InvalidPairID');
writecell({'P01'}, path, 'Sheet', 'SO LIEU', 'Range', 'A4', 'UseExcel', false);
writecell({'3DCRT/PCB'}, path, 'Sheet', 'SO LIEU', 'Range', 'C4', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:IncompletePair');
end

function testNegativeNumericAndV66Validation(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
writecell({-1}, path, 'Sheet', 'SO LIEU', 'Range', 'D3', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:InvalidMeasurement');
writecell({62}, path, 'Sheet', 'SO LIEU', 'Range', 'D3', 'UseExcel', false);
writecell({'66 Gy'}, path, 'Sheet', 'SO LIEU', 'Range', 'E3', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:InvalidMeasurement');
writecell({66}, path, 'Sheet', 'SO LIEU', 'Range', 'E3', 'UseExcel', false);
writecell({100.01}, path, 'Sheet', 'SO LIEU', 'Range', 'F3', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:InvalidV66');
end

function testLegacyConversionAndIdentifierExclusion(testCase)
[path, cleanup] = fixture(4, true); %#ok<ASGLU>
data = glottic.importWorkbook(path, []);
testCase.verifyEqual(data.CRT.ptv_V66_percent, repmat(95.4, 4, 1), 'AbsTol', 1e-12);
testCase.verifySubstring(data.metadata.workbook_layout, 'legacy');
testCase.verifyFalse(contains(string(jsonencode(data.metadata)), 'PRIVATE_TEST_IDENTIFIER'));
testCase.verifyFalse(any(contains(string(data.patientTable.Properties.VariableNames), 'PRIVATE_TEST_IDENTIFIER')));
testCase.verifyEqual(data.patient_id, ["01"; "02"; "03"; "04"]);
writecell({1.01}, path, 'Sheet', 'SO LIEU', 'Range', 'G4', 'UseExcel', false);
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:InvalidV66');
end

function testFormulaCachedValueIsRejected(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
injectCachedFormula(path, 'D3');
testCase.verifyError(@() glottic.importWorkbook(path, []), 'glottic:importWorkbook:FormulaCell');
end

function testDerivedValuesAreAlwaysRecomputed(testCase)
[path, cleanup] = fixture(4, false); %#ok<ASGLU>
data = glottic.importWorkbook(path, []);
data.CRT.carotid_worse_Dmean_Gy(:) = -999;
data.patientTable.delta_carotid_worse_Dmean_Gy(:) = -999;
data.CRT.carotid_L_Dmean_Gy(1) = 40;
data.CRT.carotid_R_Dmean_Gy(1) = 10;
data = glottic.deriveData(data);
testCase.verifyEqual(data.CRT.carotid_worse_Dmean_Gy(1), 40);
testCase.verifyEqual(data.CRT.carotid_arithmetic_bilateral_Dmean_Gy(1), 25);
testCase.verifyEqual(data.patientTable.delta_carotid_worse_Dmean_Gy(1), ...
    data.IMRT.carotid_worse_Dmean_Gy(1) - 40);
end

function [path, cleanup] = fixture(n, legacy)
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
path = fullfile(folder, 'synthetic.xlsx');
headers = {'D99.9% PTV', 'D95% PTV', 'V66Gy PTV', 'Mean PTV', 'Min PTV', 'Max PTV', ...
    'Carotid L Mean', 'Carotid L Min', 'Carotid L Max', 'Carotid R Mean', ...
    'Carotid R Min', 'Carotid R Max', 'Thyroid Mean'};
columns = [4:12, 15:17, 20];
headerRow = 2; firstRow = 3; techniqueColumn = 3;
if legacy
    columns = columns + 1; headerRow = 3; firstRow = 4; techniqueColumn = 4;
end
cells = cell(firstRow + 2 * n - 1, max(columns));
if legacy
    cells{3, 4} = 'Kthuat';
else
    cells{2, 1} = 'Patient'; cells{2, 3} = 'Treatment planning';
    cells(1, columns) = repmat({'Gy'}, 1, numel(columns)); cells{1, 6} = '%';
end
cells(headerRow, columns) = headers;
for i = 1:n
    r = firstRow + 2 * (i - 1);
    if legacy
        cells(r:r + 1, 1:3) = repmat({'PRIVATE_TEST_IDENTIFIER'}, 2, 3);
        cells{r, techniqueColumn} = '3D'; cells{r + 1, techniqueColumn} = 'IMRT';
    else
        cells(r:r + 1, 1) = repmat({sprintf('P%02d', i)}, 2, 1);
        cells{r, techniqueColumn} = '3DCRT/PCB'; cells{r + 1, techniqueColumn} = 'IMRT/AAA';
        cells(r:r + 1, 2) = {'IGNORED_YEAR'; 'IGNORED_YEAR'};
    end
    for k = 0:1
        values = [62 + i/10, 66 + i/10, 95.4, 68, 60, 72, ...
            30 + i/10, 2, 66, 35 + i/10, 3, 67, 28] - k;
        values(3) = 95.4;
        for j = 1:numel(columns)
            if legacy && j == 3
                cells{r + k, columns(j)} = values(j) / 100;
            elseif legacy
                cells{r + k, columns(j)} = sprintf('%.6f Gy', values(j));
            else
                cells{r + k, columns(j)} = values(j);
            end
        end
    end
end
writecell(cells, path, 'Sheet', 'SO LIEU', 'UseExcel', false);
writecell({'PRIVATE_TEST_IDENTIFIER'}, path, 'Sheet', 'Sheet1', 'UseExcel', false);
end

function injectCachedFormula(path, coordinate)
% Manipulate only the temporary test fixture, preserving a cached number.
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
unzip(path, folder);
xmlPath = fullfile(folder, 'xl', 'worksheets', 'sheet1.xml');
factory = javaMethod('newInstance', 'javax.xml.parsers.DocumentBuilderFactory');
factory.setNamespaceAware(true);
factory.setFeature('http://apache.org/xml/features/disallow-doctype-decl', true);
builder = factory.newDocumentBuilder();
document = builder.parse(javaObject('java.io.File', xmlPath));
cellNode = findCell(document, coordinate);
assert(~isempty(cellNode), 'Formula fixture cell coordinate was not found.');
while cellNode.hasChildNodes()
    cellNode.removeChild(cellNode.getFirstChild());
end
% The numeric cache must not be interpreted as a shared-string index.
cellNode.removeAttribute('t');
prefix = char(cellNode.getPrefix());
if ~isempty(prefix), prefix = [prefix ':']; end
formula = document.createElementNS(cellNode.getNamespaceURI(), [prefix 'f']);
formula.appendChild(document.createTextNode('60+1'));
cache = document.createElementNS(cellNode.getNamespaceURI(), [prefix 'v']);
cache.appendChild(document.createTextNode('61'));
cellNode.appendChild(formula); cellNode.appendChild(cache);
xmlwrite(xmlPath, document);
% Assert the saved fixture actually contains the formula and its numeric cache.
saved = builder.parse(javaObject('java.io.File', xmlPath));
savedCell = findCell(saved, coordinate);
assert(~isempty(savedCell) && savedCell.getElementsByTagNameNS('*', 'f').getLength() == 1, ...
    'Formula injection did not persist in the fixture.');
assert(strcmp(char(savedCell.getElementsByTagNameNS('*', 'v').item(0).getTextContent()), '61'), ...
    'Formula fixture is missing its cached numeric value.');
archive = [tempname '.zip'];
archiveCleanup = onCleanup(@() deleteIfPresent(archive)); %#ok<NASGU>
entries = dir(folder);
entries = entries(~ismember({entries.name}, {'.', '..'}));
zip(archive, {entries.name}, folder);
movefile(archive, path, 'f');
end

function cellNode = findCell(document, coordinate)
cellNode = [];
nodes = document.getElementsByTagNameNS('*', 'c');
for index = 0:nodes.getLength() - 1
    candidate = nodes.item(index);
    if strcmp(char(candidate.getAttribute('r')), coordinate)
        cellNode = candidate;
        return;
    end
end
end

function deleteIfPresent(path)
if isfile(path), delete(path); end
end
