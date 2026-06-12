use std::collections::{BTreeMap, BTreeSet};

fn read_repo_file(path: &str) -> std::io::Result<String> {
    let repo_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    std::fs::read_to_string(repo_root.join(path))
}

fn expected_detector_docs() -> BTreeMap<&'static str, &'static str> {
    BTreeMap::from([
        ("is_shell", "Shell scripts"),
        ("is_docker", "Dockerfile"),
        ("is_actions", "GitHub Actions"),
        ("is_gitlab", "GitLab CI"),
        ("is_azure", "Azure Pipelines"),
        ("is_circleci", "CircleCI"),
        ("is_makefile", "Makefile"),
        ("is_package_json", "package.json"),
        ("is_terraform", "Terraform"),
        ("is_compose", "Docker Compose"),
    ])
}

fn scan_loop_detectors(scan_rs: &str) -> BTreeSet<String> {
    let start = scan_rs
        .find("// Determine which extractor(s) to use")
        .expect("src/scan.rs must contain the extractor dispatch marker");
    let dispatch = &scan_rs[start..];
    let end = dispatch
        .find("if !is_shell")
        .expect("src/scan.rs must contain the extractor skip guard");

    dispatch[..end]
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            let rest = trimmed.strip_prefix("let is_")?;
            let (name, _) = rest.split_once('=')?;
            Some(format!("is_{}", name.trim()))
        })
        .collect()
}

fn scan_guide_supported_file_types(guide: &str) -> BTreeSet<String> {
    let start = guide
        .find("**orca scan** analyzes files")
        .expect("scan guide must document supported scan file formats");
    let section = &guide[start..];
    let end = section
        .find("The key difference")
        .expect("scan guide must end supported scan file format list");

    section[..end]
        .lines()
        .filter_map(|line| {
            let item = line.trim_start().strip_prefix("- ")?;
            Some(
                item.split(" (`")
                    .next()
                    .unwrap_or(item)
                    .trim_matches('`')
                    .to_string(),
            )
        })
        .collect()
}

#[test]
fn scan_guide_format_list_matches_wired_extractors() -> std::io::Result<()> {
    let scan_rs = read_repo_file("src/scan.rs")?;
    let guide = read_repo_file("docs/scan-precommit-guide.md")?;

    let expected = expected_detector_docs();
    let wired_detectors = scan_loop_detectors(&scan_rs);
    let expected_detectors: BTreeSet<String> = expected.keys().map(ToString::to_string).collect();
    let documented_formats = scan_guide_supported_file_types(&guide);
    let expected_formats: BTreeSet<String> = expected.values().map(ToString::to_string).collect();

    assert_eq!(
        wired_detectors, expected_detectors,
        "update expected_detector_docs when src/scan.rs wires a scan extractor"
    );
    assert_eq!(
        documented_formats, expected_formats,
        "docs/scan-precommit-guide.md supported scan file formats must match wired extractors"
    );
    assert!(
        guide.contains("Azure Pipelines")
            && guide.contains("CircleCI")
            && guide.contains("package.json"),
        "scan guide should name the extractors that previously drifted out of the supported-format list"
    );

    Ok(())
}
