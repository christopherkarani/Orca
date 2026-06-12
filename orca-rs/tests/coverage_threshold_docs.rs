use std::collections::BTreeMap;

fn read_repo_file(path: &str) -> std::io::Result<String> {
    let repo_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    std::fs::read_to_string(repo_root.join(path))
}

fn parse_ci_thresholds(workflow: &str) -> BTreeMap<&'static str, f64> {
    let mut thresholds = BTreeMap::new();
    for line in workflow.lines().map(str::trim) {
        for (env_name, label) in [
            ("OVERALL_MIN", "Overall"),
            ("EVALUATOR_MIN", "src/evaluator.rs"),
            ("HOOK_MIN", "src/hook.rs"),
        ] {
            let prefix = format!("{env_name}=");
            let Some(rest) = line.strip_prefix(&prefix) else {
                continue;
            };
            thresholds.insert(
                label,
                rest.parse()
                    .unwrap_or_else(|err| panic!("{env_name} must be numeric: {err}")),
            );
        }
    }
    thresholds
}

fn parse_documented_thresholds(script: &str) -> BTreeMap<&'static str, f64> {
    let mut thresholds = BTreeMap::new();
    for (label, marker) in [
        ("Overall", "Overall lines             >= "),
        ("src/evaluator.rs", "src/evaluator.rs lines    >= "),
        ("src/hook.rs", "src/hook.rs lines         >= "),
    ] {
        let line = script
            .lines()
            .find(|line| line.trim_start().starts_with(marker))
            .unwrap_or_else(|| {
                panic!("coverage.sh help is missing coverage threshold for {label}")
            });
        let value = line
            .trim_start()
            .strip_prefix(marker)
            .and_then(|rest| rest.split('%').next())
            .unwrap_or_else(|| panic!("coverage.sh threshold for {label} must end with %"));
        thresholds.insert(
            label,
            value.parse().unwrap_or_else(|err| {
                panic!("coverage.sh threshold for {label} must be numeric: {err}")
            }),
        );
    }
    thresholds
}

#[test]
fn coverage_help_thresholds_match_enforced_values() -> std::io::Result<()> {
    let coverage_script = read_repo_file("scripts/coverage.sh")?;

    let enforced_thresholds = parse_ci_thresholds(&coverage_script);
    let documented_thresholds = parse_documented_thresholds(&coverage_script);

    assert_eq!(
        enforced_thresholds, documented_thresholds,
        "coverage.sh help thresholds must match enforced values"
    );
    assert!(
        coverage_script.contains("Coverage thresholds not met"),
        "coverage.sh should fail when enforced thresholds are not met"
    );

    Ok(())
}
