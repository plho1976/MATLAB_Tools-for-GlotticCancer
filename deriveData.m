function data = deriveData(data)
%DERIVEDATA Recompute all composites and patient-level deltas from raw doses.
%   DATA = glottic.deriveData(DATA) never trusts previously stored composites.
%   CRT and IMRT contain numeric column vectors; patient_id contains anonymous
%   two-digit identifiers. The arithmetic bilateral mean is not volume weighted.

rawKeys = ["ptv_D99_9_Gy"; "ptv_D95_Gy"; "ptv_V66_percent"; ...
    "ptv_Dmean_Gy"; "ptv_Dmin_Gy"; "ptv_Dmax_Gy"; ...
    "carotid_L_Dmean_Gy"; "carotid_L_Dmin_Gy"; "carotid_L_Dmax_Gy"; ...
    "carotid_R_Dmean_Gy"; "carotid_R_Dmin_Gy"; "carotid_R_Dmax_Gy"; ...
    "thyroid_Dmean_Gy"];
derivedKeys = ["carotid_worse_Dmean_Gy"; ...
    "carotid_arithmetic_bilateral_Dmean_Gy"; "carotid_worse_Dmax_Gy"];
if ~isstruct(data) || ~isscalar(data) || ~isfield(data, 'patient_id')
    error('glottic:deriveData:InvalidData', 'A scalar data struct with patient_id is required.');
end
ids = string(data.patient_id(:));
if any(ismissing(ids)) || any(cellfun(@isempty, regexp(cellstr(ids), '^\d{2}$', 'once'))) ...
        || numel(unique(ids)) ~= numel(ids)
    error('glottic:deriveData:InvalidIDs', 'patient_id must contain unique two-digit anonymous IDs.');
end
n = numel(ids);
for technique = ["CRT", "IMRT"]
    name = char(technique);
    if ~isfield(data, name) || ~isstruct(data.(name)) || ~isscalar(data.(name))
        error('glottic:deriveData:InvalidData', '%s must be a scalar metric struct.', name);
    end
    for key = rawKeys'
        field = char(key);
        if ~isfield(data.(name), field)
            error('glottic:deriveData:MissingMetric', 'Missing raw metric %s.%s.', name, field);
        end
        values = data.(name).(field);
        if ~isnumeric(values) || ~isreal(values) || numel(values) ~= n ...
                || (~isvector(values) && ~isempty(values)) ...
                || any(~isfinite(values(:)) | values(:) < 0)
            error('glottic:deriveData:InvalidMetric', '%s.%s must contain %d finite nonnegative numbers.', name, field, n);
        end
        values = double(values(:));
        if key == "ptv_V66_percent" && any(values > 100)
            error('glottic:deriveData:InvalidV66', '%s V66 must be in percent [0,100].', name);
        end
        data.(name).(field) = values;
    end
    a = data.(name);
    data.(name).carotid_worse_Dmean_Gy = max(a.carotid_L_Dmean_Gy, a.carotid_R_Dmean_Gy);
    data.(name).carotid_arithmetic_bilateral_Dmean_Gy = ...
        a.carotid_L_Dmean_Gy / 2 + a.carotid_R_Dmean_Gy / 2;
    data.(name).carotid_worse_Dmax_Gy = max(a.carotid_L_Dmax_Gy, a.carotid_R_Dmax_Gy);
end
data.patient_id = ids;
data.n = n;
data.metricKeys = [rawKeys; derivedKeys];
patients = table(ids, 'VariableNames', {'patient_id'});
for technique = ["CRT", "IMRT"]
    for key = data.metricKeys'
        patients.(char(technique + "_" + key)) = data.(char(technique)).(char(key));
    end
end
for key = data.metricKeys'
    patients.(char("delta_" + key)) = data.IMRT.(char(key)) - data.CRT.(char(key));
end
data.patientTable = patients;
end
