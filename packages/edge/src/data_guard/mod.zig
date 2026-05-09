pub const data_classification = @import("data_classification.zig");
pub const telemetry_policy = @import("telemetry_policy.zig");
pub const endpoint_policy = @import("endpoint_policy.zig");
pub const egress_evaluator = @import("egress_evaluator.zig");
pub const payload_redaction = @import("payload_redaction.zig");
pub const mission_data_guard = @import("mission_data_guard.zig");
pub const sensor_data_guard = @import("sensor_data_guard.zig");
pub const link_guard = @import("link_guard.zig");
pub const network_finding = @import("network_finding.zig");
pub const network_audit = @import("network_audit.zig");

pub const DataClass = data_classification.DataClass;
pub const Sensitivity = data_classification.Sensitivity;
pub const ChannelKind = data_classification.ChannelKind;
pub const Direction = data_classification.Direction;
pub const TelemetryPayload = data_classification.TelemetryPayload;
pub const Endpoint = endpoint_policy.Endpoint;
pub const EndpointKind = endpoint_policy.EndpointKind;
pub const Policy = telemetry_policy.Policy;
pub const EvaluationContext = egress_evaluator.EvaluationContext;
pub const EgressEvaluation = egress_evaluator.EgressEvaluation;

pub const classifyPayload = data_classification.classifyPayload;
pub const classifyEndpoint = endpoint_policy.classifyEndpoint;
pub const parseEndpointJsonOwned = endpoint_policy.parseEndpointJsonOwned;
pub const loadPolicyFile = telemetry_policy.loadFile;
pub const parsePolicyYaml = telemetry_policy.parseYaml;
pub const defaultSimulationPolicy = telemetry_policy.defaultSimulationPolicy;
pub const evaluateEgress = egress_evaluator.evaluateEgress;
pub const evaluateWithDefaultPolicy = egress_evaluator.evaluateWithDefaultPolicy;
pub const redactPayload = payload_redaction.redactPayload;

test {
    _ = data_classification;
    _ = telemetry_policy;
    _ = endpoint_policy;
    _ = egress_evaluator;
    _ = payload_redaction;
    _ = mission_data_guard;
    _ = sensor_data_guard;
    _ = link_guard;
    _ = network_finding;
    _ = network_audit;
}
